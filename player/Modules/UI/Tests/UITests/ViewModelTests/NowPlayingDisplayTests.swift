import AudioEngine
import Foundation
import Playback
import Testing
@testable import Persistence
@testable import UI

/// A local track change reaches the now-playing surfaces as one snapshot:
/// the previous track stays drawn until the new one's database metadata and
/// decoder facts are both in, or the hold limit passes.
@Suite("NowPlayingDisplay snapshot")
@MainActor
struct NowPlayingDisplayTests {
    private var decoderFixture: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ViewModelTests/
            .deletingLastPathComponent() // UITests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // UI/
            .deletingLastPathComponent() // Modules/
            .appendingPathComponent("AudioEngine/Tests/AudioEngineTests/Fixtures/sine-1s-44100-24-stereo.flac")
    }

    private func makeTrack(_ title: String) -> Track {
        let now = Int64(Date().timeIntervalSince1970)
        return Track(
            fileURL: "file:///tmp/\(title).flac",
            fileSize: 1024,
            fileMtime: now,
            fileFormat: "flac",
            duration: 180,
            title: title,
            addedAt: now,
            updatedAt: now
        )
    }

    /// Polls until `condition` holds or `timeout` passes.
    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: @MainActor () async -> Bool
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    @Test("The first track after idle draws at once")
    func firstTrackDrawsImmediately() async throws {
        let db = try await Database(location: .inMemory)
        let vm = NowPlayingViewModel(engine: MockTransport(), database: db)
        vm.setCurrentTrack(self.makeTrack("First"))
        #expect(vm.display.title == "First")
    }

    @Test("A track change keeps the previous snapshot until the decoder is ready")
    func changeWaitsForReady() async throws {
        let engine = MockTransport()
        let db = try await Database(location: .inMemory)
        let vm = NowPlayingViewModel(engine: engine, database: db)
        vm.setCurrentTrack(self.makeTrack("First"))
        #expect(vm.display.title == "First")

        vm.setCurrentTrack(self.makeTrack("Second"))
        // The live field moves on at once; the drawn snapshot does not.
        #expect(vm.title == "Second")
        #expect(vm.display.title == "First")

        // Let the metadata resolve (no artist/album rows: it finishes at once),
        // then report the new decoder.
        try await Task.sleep(for: .milliseconds(30))
        #expect(vm.display.title == "First")
        engine.emit(.ready)
        let switched = try await self.waitUntil(timeout: .milliseconds(200)) { vm.display.title == "Second" }
        #expect(switched)
    }

    @Test("A change without .ready (gapless) still lands within the hold limit")
    func changeReleasesAfterLimit() async throws {
        let db = try await Database(location: .inMemory)
        let vm = NowPlayingViewModel(engine: MockTransport(), database: db)
        vm.setCurrentTrack(self.makeTrack("First"))
        vm.setCurrentTrack(self.makeTrack("Second"))
        #expect(vm.display.title == "First")
        let switched = try await self.waitUntil { vm.display.title == "Second" }
        #expect(switched)
    }

    @Test(
        "An older ready read cannot publish facts or release the next track's hold",
        arguments: [DeferredDecoderRead.details, .codec], [false, true]
    )
    func delayedReadyDoesNotCrossSkip(read: DeferredDecoderRead, repeatsSameTrack: Bool) async throws {
        let engine = DeferredFactsTransport()
        let db = try await Database(location: .inMemory)
        let vm = NowPlayingViewModel(engine: engine, database: db)
        defer { engine.finishState() }
        let first = self.makeTrack("First")
        vm.setCurrentTrack(first)
        await engine.deferNextRead(read)
        engine.emit(.ready)
        try #require(await self.waitUntil { await engine.hasPendingRead })

        // Repeat-one reloads the same Track value: identity alone is insufficient.
        let next = repeatsSameTrack ? first : self.makeTrack("Second")
        vm.setCurrentTrack(next)
        await engine.setCodec("opus")
        await engine.resumeRead()
        // This state is processed after the suspended .ready branch, so the
        // assertions do not depend on a guessed task scheduling delay.
        engine.emit(.paused)
        try #require(await self.waitUntil { vm.isPaused })
        #expect(vm.display.title == "First")
        #expect(vm.display.sourceFacts?.codec == nil)
        #expect(vm.sourceFacts?.codec == nil)

        engine.emit(.ready)
        try #require(await self.waitUntil { vm.display.sourceFacts?.codec == "opus" })
        #expect(vm.display.title == next.title)
    }

    @Test("An older ready read cannot restore facts after clear or radio selection", arguments: [false, true])
    func delayedReadyDoesNotCrossSourceChange(selectRadio: Bool) async throws {
        let engine = DeferredFactsTransport()
        let db = try await Database(location: .inMemory)
        let vm = NowPlayingViewModel(engine: engine, database: db)
        defer { engine.finishState() }
        vm.setCurrentTrack(self.makeTrack("Local"))
        await engine.deferNextRead(.codec)
        engine.emit(.ready)
        try #require(await self.waitUntil { await engine.hasPendingRead })

        if selectRadio {
            let url = try #require(URL(string: "http://127.0.0.1:9/never"))
            await vm.applyStreamItem(.makeInternetRadio(name: "Test FM", streamURL: url, homePage: nil))
        } else {
            vm.clearNowPlayingDisplay()
        }
        await engine.resumeRead()
        engine.emit(.paused)
        try #require(await self.waitUntil { vm.isPaused })
        #expect(vm.display.title == (selectRadio ? "Test FM" : ""))
        #expect(vm.display.sourceFacts == nil)
        #expect(vm.sourceFacts == nil)
    }

    @Test("A buffered ready event must not adopt a newer track or clear", arguments: [false, true])
    func bufferedReadyDoesNotCrossSourceChange(clearsDisplay: Bool) async throws {
        let decoder = AudioEngine()
        try await decoder.load(self.decoderFixture)
        let oldCodec = try #require(await decoder.currentCodec)
        #expect(oldCodec == "flac")
        let engine = BufferedDecoderFactsTransport(engine: decoder)
        let db = try await Database(location: .inMemory)
        let vm = NowPlayingViewModel(engine: engine, database: db)
        defer { engine.finishState() }
        vm.setCurrentTrack(self.makeTrack("First"))

        // QueuePlayer forwards the engine's bare .ready into its own buffered
        // stream. A current-track change is emitted before load(B), with a
        // marker DB await in between, while decoder A is still installed.
        engine.emit(.ready)
        if clearsDisplay {
            vm.clearNowPlayingDisplay()
        } else {
            vm.setCurrentTrack(self.makeTrack("Second"))
        }
        engine.emit(.paused)
        try #require(await self.waitUntil { vm.isPaused })

        // The read is from a real installed decoder, not a mock's stale cache.
        #expect(await decoder.currentCodec == oldCodec)
        #expect(vm.sourceFacts?.codec == nil)
        #expect(vm.display.sourceFacts?.codec == nil)
        #expect(vm.display.title == (clearsDisplay ? "" : "First"))
    }

    @Test("A ready snapshot of the matching real decoder publishes its codec")
    func matchingRealDecoderPublishesFacts() async throws {
        let decoder = AudioEngine()
        try await decoder.load(self.decoderFixture)
        let engine = BufferedDecoderFactsTransport(engine: decoder)
        let db = try await Database(location: .inMemory)
        let vm = NowPlayingViewModel(engine: engine, database: db)
        defer { engine.finishState() }
        var track = self.makeTrack("Matching")
        track.fileURL = self.decoderFixture.absoluteString
        vm.setCurrentTrack(track)
        engine.emit(.ready)
        engine.emit(.paused)
        try #require(await self.waitUntil { vm.isPaused })
        #expect(vm.display.title == "Matching")
        #expect(vm.display.sourceFacts?.codec == "flac")
    }

    @Test("A decoder URL mismatch releases the display at its limit with scanned columns")
    func mismatchedDecoderFallsBackToScannedFacts() async throws {
        let decoder = AudioEngine()
        try await decoder.load(self.decoderFixture)
        let engine = BufferedDecoderFactsTransport(engine: decoder)
        let db = try await Database(location: .inMemory)
        let vm = NowPlayingViewModel(engine: engine, database: db)
        defer { engine.finishState() }
        vm.setCurrentTrack(self.makeTrack("First"))
        var track = self.makeTrack("Second")
        track.sampleRate = 48000
        track.bitDepth = 24
        vm.setCurrentTrack(track)
        engine.emit(.ready)
        engine.emit(.paused)
        try #require(await self.waitUntil { vm.isPaused })
        #expect(vm.display.title == "First")
        try #require(await self.waitUntil { vm.display.title == "Second" })
        #expect(vm.display.sourceFacts?.codec == nil)
        #expect(vm.display.sourceFacts?.sampleRateHz == 48000)
        #expect(vm.display.sourceFacts?.bitDepth == 24)
    }
}

enum DeferredDecoderRead: Sendable {
    case details
    case codec
}

/// Suspends one decoder read while retaining the answer from its old source.
/// Actor isolation keeps this gate deterministic under concurrent test runs.
private actor DeferredFactsTransport: Transport {
    nonisolated let state: AsyncStream<PlaybackState>
    private nonisolated let continuation: AsyncStream<PlaybackState>.Continuation
    private var deferredRead: DeferredDecoderRead?
    private var pendingRead: CheckedContinuation<Void, Never>?
    private var codec = "flac"

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: PlaybackState.self)
        self.state = stream
        self.continuation = continuation
    }

    var currentTime: TimeInterval { 0 }
    var duration: TimeInterval { 180 }
    var hasPendingRead: Bool { self.pendingRead != nil }

    var currentStreamDetails: StreamDetails? {
        get async {
            await self.suspendReadIfNeeded(.details)
            return nil
        }
    }

    var currentCodec: String? {
        get async {
            let codec = self.codec
            await self.suspendReadIfNeeded(.codec)
            return codec
        }
    }

    func deferNextRead(_ read: DeferredDecoderRead) { self.deferredRead = read }
    func setCodec(_ codec: String) { self.codec = codec }

    func resumeRead() {
        self.pendingRead?.resume()
        self.pendingRead = nil
    }

    private func suspendReadIfNeeded(_ read: DeferredDecoderRead) async {
        guard self.deferredRead == read else { return }
        self.deferredRead = nil
        await withCheckedContinuation { self.pendingRead = $0 }
    }

    nonisolated func emit(_ state: PlaybackState) { self.continuation.yield(state) }
    nonisolated func finishState() { self.continuation.finish() }
    func load(_: URL) async throws {}
    func play() async throws {}
    func pause() async {}
    func stop() async {}
    func seek(to _: TimeInterval) async throws {}
    func setVolume(_: Float) async {}
}

/// Models QueuePlayer's buffered state forwarding while every fact read still
/// comes from the real decoder currently installed in its AudioEngine actor.
private final class BufferedDecoderFactsTransport: Transport {
    let state: AsyncStream<PlaybackState>
    private let continuation: AsyncStream<PlaybackState>.Continuation
    private let engine: AudioEngine

    init(engine: AudioEngine) {
        self.engine = engine
        let (stream, continuation) = AsyncStream.makeStream(of: PlaybackState.self)
        self.state = stream
        self.continuation = continuation
    }

    var currentTime: TimeInterval { get async { await self.engine.currentTime } }
    var duration: TimeInterval { get async { await self.engine.duration } }
    var currentStreamDetails: StreamDetails? { get async { await self.engine.currentStreamDetails } }
    var currentCodec: String? { get async { await self.engine.currentCodec } }
    var currentSourceFactsSnapshot: TransportSourceFacts? {
        get async { await self.engine.currentSourceFactsSnapshot }
    }
    func emit(_ state: PlaybackState) { self.continuation.yield(state) }
    func finishState() { self.continuation.finish() }
    func load(_ url: URL) async throws { try await self.engine.load(url) }
    func play() async throws { try await self.engine.play() }
    func pause() async { await self.engine.pause() }
    func stop() async { await self.engine.stop() }
    func seek(to time: TimeInterval) async throws { try await self.engine.seek(to: time) }
    func setVolume(_ volume: Float) async { await self.engine.setVolume(volume) }
}
