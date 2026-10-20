import AudioEngine
@preconcurrency import AVFoundation
import Foundation
import Persistence
import Testing
@testable import Playback

// MARK: - Stubs

/// Records every resolver call and returns canned values, so tests can assert
/// the player consulted the seam without decoding real audio.
private actor StubPodcastResolver: PodcastEpisodeResolving {
    var audioURLToReturn: URL
    let resumePositionToReturn: TimeInterval

    private(set) var audioURLCalls: [(feedURL: URL, guid: String)] = []
    private(set) var resumeCalls: [(feedURL: URL, guid: String)] = []
    private(set) var persistCalls:
        [(feedURL: URL, guid: String, position: TimeInterval, duration: TimeInterval)] = []
    private(set) var markPlayedCalls: [(feedURL: URL, guid: String)] = []

    init(audioURL: URL, resumePosition: TimeInterval = 0) {
        self.audioURLToReturn = audioURL
        self.resumePositionToReturn = resumePosition
    }

    func setAudioURL(_ url: URL) {
        self.audioURLToReturn = url
    }

    func audioURL(feedURL: URL, episodeGUID: String) async throws -> URL {
        self.audioURLCalls.append((feedURL, episodeGUID))
        return self.audioURLToReturn
    }

    func resumePosition(feedURL: URL, episodeGUID: String) async -> TimeInterval {
        self.resumeCalls.append((feedURL, episodeGUID))
        return self.resumePositionToReturn
    }

    func persistPosition(
        feedURL: URL,
        episodeGUID: String,
        position: TimeInterval,
        duration: TimeInterval
    ) async {
        self.persistCalls.append((feedURL, episodeGUID, position, duration))
    }

    func markPlayed(feedURL: URL, episodeGUID: String) async {
        self.markPlayedCalls.append((feedURL, episodeGUID))
    }
}

/// Captures scrobble dispatch so a test can prove a podcast never scrobbles.
private actor CapturingScrobbleSink: ScrobbleSink {
    private(set) var recordPlayCalls = 0
    private(set) var recordSubsonicCalls = 0

    func recordPlay(trackID _: Int64, playedAt _: Date, durationPlayed _: TimeInterval) async {
        self.recordPlayCalls += 1
    }

    func recordSubsonicPlay(
        context _: SubsonicPlayContext,
        playedAt _: Date,
        durationPlayed _: TimeInterval
    ) async {
        self.recordSubsonicCalls += 1
    }
}

// MARK: - PodcastPlaybackTests

@Suite("QueuePlayer podcast playback")
struct PodcastPlaybackTests {
    @Test("quit without playing a restored episode never overwrites its saved position with zero")
    func unloadedRestoredEpisodePreservesPosition() async throws {
        let db = try await Database(location: .inMemory)
        let stub = StubPodcastResolver(audioURL: Self.enclosure, resumePosition: 42)
        let item = self.makePodcastItem(duration: 300)
        await QueuePersistence(database: db).saveImmediately(
            items: [item], currentIndex: 0, repeatMode: .off, shuffleState: .off
        )
        let suite = "wmusic.podcast-restore.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let player = QueuePlayer(
            engine: AudioEngine(), database: db, podcastResolver: stub, resumeDefaultsSuiteName: suite
        )
        await player.waitUntilActivated()
        await player.prepareForTermination()
        #expect(await stub.persistCalls.isEmpty)
        #expect(await stub.audioURLCalls.isEmpty)
    }

    // swiftlint:disable:next force_unwrapping
    private static let feed = URL(string: "https://example.invalid/feed.xml")!
    private static let guid = "episode-guid-1"
    // swiftlint:disable:next force_unwrapping
    private static let enclosure = URL(string: "https://example.invalid/ep1.mp3")!

    private func makeFormat() -> AudioSourceFormat {
        AudioSourceFormat(
            sampleRate: 44100, bitDepth: 16, channelCount: 2,
            isInterleaved: false, codec: "mp3"
        )
    }

    private func makePodcastItem(duration: TimeInterval = 0) -> QueueItem {
        QueueItem(
            trackID: -1,
            bookmark: nil,
            fileURL: "",
            duration: duration,
            sourceFormat: self.makeFormat(),
            title: "Episode Title",
            artistName: "Show Name",
            playableSource: .podcast(feedURL: Self.feed, episodeGUID: Self.guid)
        )
    }

    private func makeLocalItem() -> QueueItem {
        QueueItem(
            trackID: 1,
            bookmark: nil,
            fileURL: "/tmp/local.flac",
            duration: 100,
            sourceFormat: self.makeFormat()
        )
    }

    private func makePlayer(
        db: Database,
        resolver: StubPodcastResolver?,
        sink: CapturingScrobbleSink? = nil
    ) -> QueuePlayer {
        QueuePlayer(
            engine: AudioEngine(),
            database: db,
            scrobbleSink: sink,
            podcastResolver: resolver
        )
    }

    // MARK: - No resolver

    @Test("A .podcast item with no resolver fails the load cleanly with PlaybackError")
    func noResolverFailsCleanly() async throws {
        let db = try await Database(location: .inMemory)
        let player = self.makePlayer(db: db, resolver: nil)
        await #expect(throws: PlaybackError.self) {
            try await player.play(items: [self.makePodcastItem()])
        }
    }

    // MARK: - Resume on load

    @Test("Resume on load consults the resolver and seeks to the returned position")
    func resumeOnLoadConsultsResolver() async throws {
        let db = try await Database(location: .inMemory)
        let stub = StubPodcastResolver(audioURL: Self.enclosure, resumePosition: 42)
        let player = self.makePlayer(db: db, resolver: stub)

        let sought = await player.applyPodcastResumeIfNeeded(for: self.makePodcastItem())

        #expect(sought == 42)
        let calls = await stub.resumeCalls
        #expect(calls.count == 1)
        #expect(calls.first?.feedURL == Self.feed)
        #expect(calls.first?.guid == Self.guid)
    }

    @Test("A resume position of <= 1 does not seek")
    func resumeOfOneOrLessDoesNotSeek() async throws {
        let db = try await Database(location: .inMemory)
        for resume in [TimeInterval(0), 1] {
            let stub = StubPodcastResolver(audioURL: Self.enclosure, resumePosition: resume)
            let player = self.makePlayer(db: db, resolver: stub)
            let sought = await player.applyPodcastResumeIfNeeded(for: self.makePodcastItem())
            #expect(sought == nil, "resume \(resume) should not seek")
        }
    }

    @Test("Resume is a no-op for a non-podcast item (resolver not consulted)")
    func resumeIgnoresNonPodcast() async throws {
        let db = try await Database(location: .inMemory)
        let stub = StubPodcastResolver(audioURL: Self.enclosure, resumePosition: 42)
        let player = self.makePlayer(db: db, resolver: stub)

        let sought = await player.applyPodcastResumeIfNeeded(for: self.makeLocalItem())

        #expect(sought == nil)
        let calls = await stub.resumeCalls
        #expect(calls.isEmpty)
    }

    /// Load actual synthetic audio so position-writeback tests do not mistake an
    /// idle engine's zero for a played episode's position.
    private func loadPodcastFixture(player: QueuePlayer, resolver: StubPodcastResolver) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("podcast-\(UUID()).wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100))
            buffer.frameLength = 44100
            for channel in 0 ..< 2 {
                buffer.floatChannelData?[channel].initialize(repeating: 0, count: 44100)
            }
            for _ in 0 ..< 3 {
                try file.write(from: buffer)
            }
        }
        await resolver.setAudioURL(url)
        await player.waitUntilActivated()
        try await player.play(items: [self.makePodcastItem(duration: 3)])
        try await player.seek(to: 0.5)
        return url
    }

    // MARK: - Position write-back

    @Test("persistPodcastPositionIfNeeded writes back when the current item is a podcast")
    func writeBackForPodcast() async throws {
        let db = try await Database(location: .inMemory)
        let stub = StubPodcastResolver(audioURL: Self.enclosure)
        let player = self.makePlayer(db: db, resolver: stub)
        let fixture = try await self.loadPodcastFixture(player: player, resolver: stub)
        defer { try? FileManager.default.removeItem(at: fixture) }

        await player.persistPodcastPositionIfNeeded()

        let calls = await stub.persistCalls
        #expect(calls.count == 1)
        #expect((calls.first?.position ?? 0) > 0.4)
        await player.stop()
        #expect(calls.first?.feedURL == Self.feed)
        #expect(calls.first?.guid == Self.guid)
    }

    @Test("persistPodcastPositionIfNeeded is a no-op for a non-podcast current item")
    func writeBackSkipsNonPodcast() async throws {
        let db = try await Database(location: .inMemory)
        let stub = StubPodcastResolver(audioURL: Self.enclosure)
        let player = self.makePlayer(db: db, resolver: stub)
        await player.queue.replace(with: [self.makeLocalItem()], startAt: 0)

        await player.persistPodcastPositionIfNeeded()

        let calls = await stub.persistCalls
        #expect(calls.isEmpty)
    }

    @Test("pause() persists a podcast position once")
    func pausePersistsPodcast() async throws {
        let db = try await Database(location: .inMemory)
        let stub = StubPodcastResolver(audioURL: Self.enclosure)
        let player = self.makePlayer(db: db, resolver: stub)
        let fixture = try await self.loadPodcastFixture(player: player, resolver: stub)
        defer { try? FileManager.default.removeItem(at: fixture) }

        await player.pause()

        let calls = await stub.persistCalls
        #expect(calls.count == 1)
        #expect((calls.first?.position ?? 0) > 0.4)
        await player.stop()
    }

    @Test("stop() persists a podcast position once")
    func stopPersistsPodcast() async throws {
        let db = try await Database(location: .inMemory)
        let stub = StubPodcastResolver(audioURL: Self.enclosure)
        let player = self.makePlayer(db: db, resolver: stub)
        let fixture = try await self.loadPodcastFixture(player: player, resolver: stub)
        defer { try? FileManager.default.removeItem(at: fixture) }

        await player.stop()

        let calls = await stub.persistCalls
        #expect(calls.count == 1)
        #expect((calls.first?.position ?? 0) > 0.4)
        await player.stop()
    }

    @Test("savePositionForSuspend persists a loaded podcast position")
    func suspendPersistsPodcast() async throws {
        let db = try await Database(location: .inMemory)
        let stub = StubPodcastResolver(audioURL: Self.enclosure)
        let player = self.makePlayer(db: db, resolver: stub)
        let fixture = try await self.loadPodcastFixture(player: player, resolver: stub)
        defer { try? FileManager.default.removeItem(at: fixture) }

        await player.savePositionForSuspend()

        let calls = await stub.persistCalls
        #expect(calls.count == 1)
        #expect((calls.first?.position ?? 0) > 0.4)
        await player.stop()
    }

    @Test("pause() does not persist for a non-podcast current item")
    func pauseSkipsNonPodcast() async throws {
        let db = try await Database(location: .inMemory)
        let stub = StubPodcastResolver(audioURL: Self.enclosure)
        let player = self.makePlayer(db: db, resolver: stub)
        await player.queue.replace(with: [self.makeLocalItem()], startAt: 0)

        await player.pause()

        let calls = await stub.persistCalls
        #expect(calls.isEmpty)
    }

    // MARK: - Mark played

    @Test("A podcast item reaching end is marked played exactly once")
    func markPlayedOnEnd() async throws {
        let db = try await Database(location: .inMemory)
        let stub = StubPodcastResolver(audioURL: Self.enclosure)
        let player = self.makePlayer(db: db, resolver: stub)
        await player.queue.replace(with: [self.makePodcastItem()], startAt: 0)

        await player.handleTrackEnded()

        let calls = await stub.markPlayedCalls
        #expect(calls.count == 1)
        #expect(calls.first?.guid == Self.guid)
    }

    @Test("A non-podcast item reaching end does not call markPlayed")
    func markPlayedSkipsNonPodcast() async throws {
        let db = try await Database(location: .inMemory)
        let stub = StubPodcastResolver(audioURL: Self.enclosure)
        let player = self.makePlayer(db: db, resolver: stub)
        await player.queue.replace(with: [self.makeLocalItem()], startAt: 0)

        await player.handleTrackEnded()

        let calls = await stub.markPlayedCalls
        #expect(calls.isEmpty)
    }

    // MARK: - Scrobble skip

    @Test("A completed podcast item is marked played but never scrobbles")
    func podcastDoesNotScrobble() async throws {
        let db = try await Database(location: .inMemory)
        let stub = StubPodcastResolver(audioURL: Self.enclosure)
        let sink = CapturingScrobbleSink()
        let player = self.makePlayer(db: db, resolver: stub, sink: sink)
        await player.queue.replace(with: [self.makePodcastItem()], startAt: 0)

        await player.handleTrackEnded()

        let markPlayed = await stub.markPlayedCalls
        #expect(markPlayed.count == 1, "podcast end should mark played")
        let scrobbles = await sink.recordPlayCalls
        let subsonicScrobbles = await sink.recordSubsonicCalls
        #expect(scrobbles == 0, "podcasts must never scrobble to Last.fm / ListenBrainz")
        #expect(subsonicScrobbles == 0)
    }
}
