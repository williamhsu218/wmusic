import AudioEngine
import Foundation
import Persistence
import Playback
import Testing
@testable import UI

@Suite("Now-playing local restore")
@MainActor
struct NowPlayingLocalRestoreTests {
    @Test("the bottom Play button keeps a restored queue even before metadata arrives")
    func playUsesRestoredQueue() async throws {
        let db = try await Database(location: .inMemory)
        let now = Int64(Date().timeIntervalSince1970)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unmounted-\(UUID()).wav").absoluteString
        let trackID = try await TrackRepository(database: db).insert(Track(
            fileURL: fileURL, fileSize: 1, fileMtime: now, fileFormat: "wav",
            duration: 30, title: "Restored song", addedAt: now, updatedAt: now
        ))
        let item = QueueItem(
            trackID: trackID, bookmark: nil, fileURL: fileURL, duration: 30,
            sourceFormat: AudioSourceFormat(
                sampleRate: 44100, bitDepth: 16, channelCount: 2, isInterleaved: false, codec: "wav"
            ), title: "Restored song"
        )
        await QueuePersistence(database: db).saveImmediately(
            items: [item], currentIndex: 0, repeatMode: .all, shuffleState: .on(seed: 42)
        )
        let engine = AudioEngine()
        let player = QueuePlayer(engine: engine, database: db)
        let vm = NowPlayingViewModel(engine: player, database: db)
        var replacedQueue = false
        vm.onPlayFromEmptyQueue = { replacedQueue = true }
        // No waiting for the display observer: Play itself must await activation
        // and consult the queue rather than a possibly stale track-ID field.
        await vm.playPause()
        #expect(!replacedQueue)
        #expect(await player.queue.currentItem?.id == item.id)
        #expect(await player.queue.shuffleState == .on(seed: 42))
        if case .failed = await engine.playbackState {} else {
            Issue.record("Play must attempt the selected file, even when that file is offline")
        }
        for _ in 0 ..< 1000 where vm.nowPlayingTrackID == nil { await Task.yield() }
        #expect(vm.nowPlayingTrackID == trackID)
        #expect(vm.title == "Restored song")
    }
}
