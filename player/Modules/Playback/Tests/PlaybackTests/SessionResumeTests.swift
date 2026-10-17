@preconcurrency import AVFoundation
import AudioEngine
import Foundation
import Persistence
import Testing
@testable import Playback

@Suite("Session resume", .serialized)
struct SessionResumeTests {
    private func writeFixture(to url: URL) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100))
        buffer.frameLength = 44100
        for channel in 0 ..< 2 {
            buffer.floatChannelData?[channel].initialize(repeating: 0, count: 44100)
        }
        for _ in 0 ..< 30 { try file.write(from: buffer) }
    }

    private func item(url: URL) -> QueueItem {
        QueueItem(
            trackID: 1, bookmark: nil, fileURL: url.absoluteString, duration: 30,
            sourceFormat: AudioSourceFormat(
                sampleRate: 44100, bitDepth: 16, channelCount: 2, isInterleaved: false, codec: "flac"
            ), title: "Resume fixture"
        )
    }

    @Test("restore defers file opening and Play retries a file that became available")
    func unavailableFileCanBeRetriedWithoutSkipping() async throws {
        let db = try await Database(location: .inMemory)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("late-mounted.wav")
        let item = self.item(url: url)
        let suite = "wmusic.resume-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0.35, forKey: "playback.resumePosition")
        let persistence = QueuePersistence(database: db)
        await persistence.saveImmediately(items: [item], currentIndex: 0, repeatMode: .off, shuffleState: .off)

        let engine = AudioEngine()
        let player = QueuePlayer(engine: engine, database: db, resumeDefaultsSuiteName: suite)
        await player.waitUntilActivated()
        #expect(await engine.playbackState == .idle, "launch must not open an unavailable file")
        #expect(await player.currentTime == 0.35)
        await #expect(throws: (any Error).self) { try await player.play() }

        try self.writeFixture(to: url)
        try await player.play()
        #expect(await engine.isPlaying, "Play must reload after the previous decoder failed")
        #expect(await player.queue.currentItem?.id == item.id, "no Next/Previous workaround")
        let resumedPosition = await engine.currentTime
        #expect(abs(resumedPosition - 0.35) < 0.1, "retain the deferred resume point after a failed load")
        await player.stop()
    }

    @Test("quitting within the debounce flushes order, selection and position")
    func immediateQuitPreservesSession() async throws {
        let db = try await Database(location: .inMemory)
        let suite = "wmusic.resume-tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = AudioEngine()
        let player = QueuePlayer(engine: engine, database: db, resumeDefaultsSuiteName: suite)
        await player.waitUntilActivated()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("resume.wav")
        try self.writeFixture(to: fixture)
        let items = [self.item(url: fixture), self.item(url: fixture)]
        await player.queue.replace(with: items, startAt: 1)
        try await player.play()
        try await player.seek(to: 0.4)
        await player.prepareForTermination()
        #expect(await engine.playbackState == .paused)

        let saved = try #require(await QueuePersistence(database: db).restore())
        #expect(saved.items.map(\.id) == items.map(\.id))
        #expect(saved.currentIndex == 1)
        #expect(defaults.string(forKey: "playback.resumeItemID") == items[1].id.uuidString)
        let savedPosition = defaults.double(forKey: "playback.resumePosition")
        #expect(abs(savedPosition - 0.4) < 0.1)

        let restoredEngine = AudioEngine()
        let restored = QueuePlayer(engine: restoredEngine, database: db, resumeDefaultsSuiteName: suite)
        await restored.waitUntilActivated()
        #expect(await restoredEngine.playbackState == .idle)
        let restoredPosition = await restored.currentTime
        #expect(restoredPosition == savedPosition)
        try await restored.play()
        #expect(await restoredEngine.isPlaying)
        let playingPosition = await restoredEngine.currentTime
        #expect(abs(playingPosition - savedPosition) < 0.1)
        await restored.stop()
        await player.stop()
    }
}
