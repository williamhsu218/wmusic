import AudioEngine
import Foundation
import Persistence
import Testing
@testable import Playback

private func shuffleItem(_ id: Int64, excluded: Bool = false) -> QueueItem {
    QueueItem(
        trackID: id, bookmark: nil, fileURL: "/tmp/shuffle-regression-\(id).flac", duration: 200,
        sourceFormat: AudioSourceFormat(
            sampleRate: 44100, bitDepth: 16, channelCount: 2, isInterleaved: false, codec: "flac"
        ),
        excludedFromShuffle: excluded
    )
}

@Suite("Shuffle original order regression")
struct ShuffleOrderRegressionTests {
    @Test("shuffle off follows the current item in its original source position")
    func offResumesOriginalPosition() async throws {
        let queue = PlaybackQueue()
        let original = (1 ... 10).map { shuffleItem(Int64($0)) }
        await queue.replace(with: original, startAt: 6)
        await queue.setShuffle(true, seed: 42)
        await queue.setShuffle(false)
        #expect(await queue.items.map(\.id) == original.map(\.id))
        #expect(await queue.currentIndex == 6)
        #expect(await queue.currentItem?.id == original[6].id)
        #expect(await queue.advanceManual()?.id == original[7].id)
    }

    @Test("reenabling shuffle uses the whole source pool with current item pinned")
    func reenableUsesWholePool() async {
        let queue = PlaybackQueue()
        let original = (1 ... 20).map { shuffleItem(Int64($0)) }
        await queue.replace(with: original, startAt: 8)
        await queue.setShuffle(true, seed: 100)
        let firstOrder = await queue.items.map(\.id)
        await queue.setShuffle(false)
        await queue.setShuffle(true, seed: 200)
        let secondOrder = await queue.items.map(\.id)
        #expect(secondOrder.first == original[8].id)
        #expect(Set(secondOrder) == Set(original.map(\.id)))
        #expect(firstOrder != secondOrder)
    }

    @Test("excluded tracks return to sequential order and remain excluded next shuffle")
    func excludedSourceItemsSurvive() async {
        let queue = PlaybackQueue()
        let original = [shuffleItem(1), shuffleItem(2, excluded: true), shuffleItem(3), shuffleItem(4)]
        await queue.replace(with: original, startAt: 2)
        await queue.setShuffle(true, seed: 7)
        #expect(await queue.items.count == 3)
        await queue.setShuffle(false)
        #expect(await queue.items.map(\.id) == original.map(\.id))
        #expect(await queue.currentIndex == 2)
        await queue.setShuffle(true, seed: 19)
        #expect(await queue.items.count == 3)
        #expect(await queue.items.contains { $0.id == original[1].id } == false)
    }

    @Test("play from here and shuffled manual reorder preserve the source baseline")
    func cursorAndReorderPreserveSource() async {
        let queue = PlaybackQueue()
        let original = (1 ... 10).map { shuffleItem(Int64($0)) }
        await queue.replace(with: original)
        await queue.setShuffle(true, seed: 42)
        await queue.seekToIndex(4)
        let selected = await queue.currentItem
        let reversed = await Array(queue.items.reversed())
        await queue.reorder(to: reversed)
        #expect(await queue.currentItem?.id == selected?.id)
        await queue.setShuffle(false)
        #expect(await queue.items.map(\.id) == original.map(\.id))
        #expect(await queue.currentItem?.id == selected?.id)
    }

    @Test("play-next while shuffled inserts beside current in original order")
    func playNextKeepsOriginalOrder() async {
        let queue = PlaybackQueue()
        let original = (1 ... 5).map { shuffleItem(Int64($0)) }
        let next = shuffleItem(99)
        await queue.replace(with: original, startAt: 2)
        await queue.setShuffle(true, seed: 42)
        await queue.appendNext([next])
        #expect(await queue.peekNext()?.id == next.id)
        await queue.setShuffle(false)
        #expect(await queue.items.map(\.trackID) == [1, 2, 3, 99, 4, 5])
        #expect(await queue.currentItem?.id == original[2].id)
    }

    @Test("restore preserves active shuffle order and exact current cursor")
    func restoreWithoutReshuffle() async {
        let queue = PlaybackQueue()
        let original = (1 ... 8).map { shuffleItem(Int64($0)) }
        await queue.replace(with: original, startAt: 3)
        await queue.setShuffle(true, seed: 99)
        await queue.seekToIndex(2)
        let saved = await queue.persistenceSnapshot()
        let restored = PlaybackQueue()
        await restored.restore(
            items: saved.items, currentIndex: saved.currentIndex,
            repeatMode: saved.repeatMode, shuffleState: saved.shuffleState, sourceItems: saved.sourceItems
        )
        #expect(await restored.items.map(\.id) == saved.items.map(\.id))
        #expect(await restored.currentIndex == 2)
        #expect(await restored.hasKnownSourceOrder)
        let selected = await restored.currentItem
        await restored.setShuffle(false)
        #expect(await restored.items.map(\.id) == original.map(\.id))
        #expect(await restored.currentItem?.id == selected?.id)
    }

    @Test("legacy baseline recovery validates exact IDs and survives a toggle")
    func legacyRecovery() async {
        let queue = PlaybackQueue()
        let original = (1 ... 6).map { shuffleItem(Int64($0)) }
        let legacy = Array(original.reversed())
        await queue.restore(items: legacy, currentIndex: 2, repeatMode: .all, shuffleState: .off, sourceItems: nil)
        #expect(await queue.hasKnownSourceOrder == false)
        #expect(await queue.persistenceSnapshot().sourceItems == nil)
        #expect(await queue.rebaseSourceOrder(Array(original.dropFirst()).map(\.id)) == false)
        #expect(await queue.rebaseSourceOrder(original.map(\.id)))
        let current = await queue.currentItem
        await queue.setShuffle(true, seed: 1)
        await queue.setShuffle(false)
        #expect(await queue.currentItem?.id == current?.id)
        #expect(await queue.items.map(\.id) == original.map(\.id))
    }

    @Test("duplicate tracks retain the actual queue item, not the first matching track")
    func duplicateTrackCurrentItem() async {
        let queue = PlaybackQueue()
        let original = [shuffleItem(1), shuffleItem(2), shuffleItem(1), shuffleItem(3)]
        await queue.replace(with: original, startAt: 2)
        await queue.setShuffle(true, seed: 42)
        await queue.reorder(to: Array(queue.items.reversed()))
        #expect(await queue.currentItem?.id == original[2].id)
        await queue.setShuffle(false)
        #expect(await queue.currentIndex == 2)
    }

    @Test("nil restore cursor remains exhausted")
    func restoreExhaustedQueue() async {
        let queue = PlaybackQueue()
        let original = [shuffleItem(1), shuffleItem(2)]
        await queue.restore(items: original, currentIndex: nil, repeatMode: .off, shuffleState: .off, sourceItems: original)
        #expect(await queue.currentIndex == nil)
        await queue.setShuffle(false)
        #expect(await queue.currentIndex == nil)
    }

    @Test("an irrevocable handover follows the actual incoming item after shuffle-off")
    func lateHandoverUsesActualIncoming() async {
        let queue = PlaybackQueue()
        let original = (1 ... 10).map { shuffleItem(Int64($0)) }
        await queue.replace(with: original, startAt: 3)
        await queue.setRepeatMode(.all)
        await queue.setShuffle(true, seed: 123)
        let incoming = await queue.items[5]
        await queue.setShuffle(false)
        #expect(await queue.advanceToItem(id: incoming.id)?.id == incoming.id)
        #expect(await queue.currentItem?.id == incoming.id)
        #expect(await queue.items.map(\.id) == original.map(\.id))
        #expect(await queue.history.last?.id == original[3].id)
        #expect(await queue.repeatMode == .all)
        #expect(await queue.advanceToItem(id: UUID()) == nil)
        #expect(await queue.currentItem?.id == incoming.id)
    }

    @Test("an excluded audible incoming item survives shuffle-on without losing baseline")
    func lateHandoverKeepsExcludedIncoming() async {
        let queue = PlaybackQueue()
        let original = [shuffleItem(1), shuffleItem(2, excluded: true), shuffleItem(3)]
        await queue.replace(with: original)
        await queue.setRepeatMode(.one)
        await queue.setShuffle(true, seed: 123)
        #expect(await queue.items.contains { $0.id == original[1].id } == false)
        #expect(await queue.advanceToItem(id: original[1].id)?.id == original[1].id)
        #expect(await queue.currentItem?.id == original[1].id)
        #expect(await queue.history.last?.id == original[0].id)
        #expect(await queue.repeatMode == .one)
        await queue.setShuffle(false)
        #expect(await queue.items.map(\.id) == original.map(\.id))
        #expect(await queue.currentIndex == 1)
    }
}

@Suite("QueuePlayer shuffle source regression")
struct QueuePlayerShuffleSourceTests {
    @Test("selected-item playback preserves source order before decoder error")
    func selectedPlaybackSourceOrder() async throws {
        let db = try await Database(location: .inMemory)
        let engine = AudioEngine()
        let player = QueuePlayer(engine: engine, database: db)
        await player.waitUntilActivated()
        let original = (1 ... 12).map { shuffleItem(Int64($0)) }
        do {
            try await player.play(items: original, startingAt: 5, shuffle: true)
            Issue.record("Expected nonexistent fixture load to fail")
        } catch {}
        #expect(await player.queue.currentItem?.id == original[5].id)
        await player.setShuffle(false)
        #expect(await player.queue.items.map(\.id) == original.map(\.id))
        #expect(await player.queue.currentIndex == 5)
        await player.stop()
    }

    @Test("playAt moves the cursor without replacing shuffled source order")
    func playAtKeepsSourceOrder() async throws {
        let db = try await Database(location: .inMemory)
        let player = QueuePlayer(engine: AudioEngine(), database: db)
        await player.waitUntilActivated()
        let original = (1 ... 12).map { shuffleItem(Int64($0)) }
        await player.queue.replace(with: original, startAt: 1)
        await player.queue.setShuffle(true, seed: 8)
        let chosen = await player.queue.items[4]
        do {
            try await player.playAt(index: 4)
            Issue.record("Expected nonexistent fixture load to fail")
        } catch {}
        await player.setShuffle(false)
        #expect(await player.queue.items.map(\.id) == original.map(\.id))
        #expect(await player.queue.currentItem?.id == chosen.id)
        await player.stop()
    }

    @Test("player restores saved random rows and source baseline without reshuffle")
    func playerRestorePreservesOrder() async throws {
        let db = try await Database(location: .inMemory)
        let original = (1 ... 12).map { shuffleItem(Int64($0)) }
        let active = Array(original.reversed())
        let persistence = QueuePersistence(database: db, debounce: .zero)
        await persistence.saveImmediately(
            items: active, currentIndex: 4, repeatMode: .all,
            shuffleState: .on(seed: 123), sourceItems: original
        )
        let player = QueuePlayer(engine: AudioEngine(), database: db)
        await player.waitUntilActivated()
        #expect(await player.queue.items.map(\.id) == active.map(\.id))
        #expect(await player.queue.currentIndex == 4)
        await player.setShuffle(false)
        #expect(await player.queue.items.map(\.id) == original.map(\.id))
        #expect(await player.queue.currentItem?.id == active[4].id)
        await player.stop()
    }
}
