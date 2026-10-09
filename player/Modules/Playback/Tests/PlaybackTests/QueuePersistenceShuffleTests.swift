import Foundation
import Persistence
import Testing
@testable import Playback

@Suite("Queue persistence shuffle source order")
struct QueuePersistenceShuffleTests {
    private func item(_ trackID: Int64, excluded: Bool = false) -> QueueItem {
        QueueItem(
            trackID: trackID,
            bookmark: BookmarkBlob(data: Data(repeating: 0xA5, count: 4096)),
            fileURL: "file:///tmp/shuffle-test-\(trackID).flac",
            duration: 60,
            sourceFormat: AudioSourceFormat(
                sampleRate: 44100, bitDepth: 16, channelCount: 2,
                isInterleaved: false, codec: "flac"
            ),
            title: "Track \(trackID)",
            excludedFromShuffle: excluded,
            playableSource: .localBookmark(Data())
        )
    }

    @Test("Immediate save preserves active order, current item and original order")
    func immediateRoundTrip() async throws {
        let database = try await Database(location: .inMemory)
        let persistence = QueuePersistence(database: database)
        let source = [self.item(1), self.item(2, excluded: true), self.item(3), self.item(4)]
        let active = [source[2], source[0], source[3]]

        await persistence.saveImmediately(
            items: active, currentIndex: 1,
            repeatMode: .all, shuffleState: .on(seed: 71), sourceItems: source
        )

        let restored = try #require(await persistence.restore())
        #expect(restored.items.map(\.id) == active.map(\.id))
        #expect(restored.currentIndex == 1)
        #expect(restored.items[1].id == source[0].id)
        #expect(restored.repeatMode == .all)
        #expect(restored.shuffleState == .on(seed: 71))
        #expect(restored.sourceItems?.map(\.id) == source.map(\.id))
        #expect(restored.sourceItems?[1].excludedFromShuffle == true)
        #expect(restored.items.allSatisfy { $0.bookmark == nil })
        #expect(restored.sourceItems?.allSatisfy { $0.bookmark == nil } == true)

        // Both lists use the bookmark-free DTO, and the additive optional
        // field retains schema 2 compatibility.
        struct Entry: Codable, Sendable {
            let bookmark: Data?
        }
        struct Payload: Codable, Sendable {
            let version: Int
            let items: [Entry]
            let sourceItems: [Entry]?
        }
        let payload = try #require(
            await SettingsRepository(database: database).get(Payload.self, for: QueuePersistence.settingsKeyV2)
        )
        #expect(payload.version == 2)
        #expect(payload.items.allSatisfy { $0.bookmark == nil })
        #expect(payload.sourceItems?.allSatisfy { $0.bookmark == nil } == true)
    }

    @Test("Debounced save retains source order separately from shuffled order")
    func debouncedRoundTrip() async throws {
        let database = try await Database(location: .inMemory)
        let persistence = QueuePersistence(database: database, debounce: .milliseconds(1))
        let source = [self.item(1), self.item(2), self.item(3)]
        let active = [source[2], source[0], source[1]]
        await persistence.scheduleSave(
            items: active, currentIndex: 2,
            repeatMode: .off, shuffleState: .on(seed: 15), sourceItems: source
        )
        await persistence._awaitPendingSaveForTesting()

        let restored = try #require(await persistence.restore())
        #expect(restored.items.map(\.id) == active.map(\.id))
        #expect(restored.sourceItems?.map(\.id) == source.map(\.id))
        #expect(restored.currentIndex == 2)
        #expect(restored.shuffleState == .on(seed: 15))
    }

    @Test("Older v2 blobs keep original order unknown", arguments: [nil, 2] as [Int?])
    func missingSourceOrder(version: Int?) async throws {
        struct LegacyPayload: Codable, Sendable {
            let version: Int?
            let items: [QueueItem]
            let currentIndex: Int?
            let repeatMode: RepeatMode
            let shuffleState: ShuffleState
        }
        let database = try await Database(location: .inMemory)
        let persistence = QueuePersistence(database: database)
        let active = [self.item(8), self.item(2), self.item(5)]
        try await SettingsRepository(database: database).set(
            LegacyPayload(
                version: version, items: active, currentIndex: 1,
                repeatMode: .all, shuffleState: .on(seed: 88)
            ),
            for: QueuePersistence.settingsKeyV2
        )

        let restored = try #require(await persistence.restore())
        #expect(restored.items.map(\.id) == active.map(\.id))
        #expect(restored.currentIndex == 1)
        #expect(restored.shuffleState == .on(seed: 88))
        #expect(restored.sourceItems == nil)

        // Re-saving an unknown source order must not invent a known baseline.
        await persistence.saveImmediately(
            items: restored.items, currentIndex: restored.currentIndex,
            repeatMode: restored.repeatMode, shuffleState: restored.shuffleState,
            sourceItems: restored.sourceItems
        )
        let secondRestore = try #require(await persistence.restore())
        #expect(secondRestore.sourceItems == nil)
    }

    @Test("Legacy v1 migration does not invent the original order of a shuffled queue")
    func legacyMigrationKeepsSourceUnknown() async throws {
        struct LegacyPayload: Codable, Sendable {
            let items: [QueueItem]
            let currentIndex: Int?
            let repeatMode: RepeatMode
            let shuffleState: ShuffleState
        }
        let database = try await Database(location: .inMemory)
        let persistence = QueuePersistence(database: database)
        let active = [self.item(9), self.item(3), self.item(6)]
        try await SettingsRepository(database: database).set(
            LegacyPayload(
                items: active, currentIndex: 2,
                repeatMode: .all, shuffleState: .on(seed: 63)
            ),
            for: QueuePersistence.settingsKeyV1
        )

        let restored = try #require(await persistence.restore())
        #expect(restored.items.map(\.id) == active.map(\.id))
        #expect(restored.currentIndex == 2)
        #expect(restored.shuffleState == .on(seed: 63))
        #expect(restored.sourceItems == nil)
        let migrated = try #require(await persistence.restore())
        #expect(migrated.items.map(\.id) == active.map(\.id))
        #expect(migrated.sourceItems == nil)
    }

    @Test("Immediate snapshot replaces a pending older shuffle snapshot")
    func immediateReplacesPending() async throws {
        let database = try await Database(location: .inMemory)
        let persistence = QueuePersistence(database: database, debounce: .seconds(3600))
        let source = [self.item(1), self.item(2), self.item(3)]
        await persistence.scheduleSave(
            items: [source[2], source[0], source[1]], currentIndex: 0,
            repeatMode: .off, shuffleState: .on(seed: 44), sourceItems: source
        )
        await persistence.saveImmediately(
            items: source, currentIndex: 2,
            repeatMode: .off, shuffleState: .off, sourceItems: source
        )

        let restored = try #require(await persistence.restore())
        #expect(restored.items.map(\.id) == source.map(\.id))
        #expect(restored.currentIndex == 2)
        #expect(restored.shuffleState == .off)
        #expect(restored.sourceItems?.map(\.id) == source.map(\.id))
    }
}
