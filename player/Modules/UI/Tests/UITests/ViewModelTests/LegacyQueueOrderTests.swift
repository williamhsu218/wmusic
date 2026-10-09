import AudioEngine
import Foundation
import Playback
import Testing
@testable import Persistence
@testable import UI

@Suite("Legacy queue Songs order recovery")
@MainActor
struct LegacyQueueOrderTests {
    private func tracks() -> [Track] {
        [3, 1, 2].map { id in
            Track(
                id: Int64(id), fileURL: "file:///tmp/wmusic-queue-order-\(id).flac",
                fileSize: 1024, fileMtime: 0, fileFormat: "flac", duration: 60,
                title: "Track \(id)", addedAt: 0, updatedAt: 0
            )
        }
    }

    private func makeLibrary() async throws -> LibraryViewModel {
        let db = try await Database(location: .inMemory)
        let library = LibraryViewModel(database: db, engine: MockTransport())
        library.tracks.setTracks(self.tracks(), preserveOrder: true)
        return library
    }

    private func items() -> [QueueItem] {
        self.tracks().map { QueueItem.make(from: $0, artistName: nil) }
    }

    @Test("exact Songs membership follows displayed order and reuses queue IDs")
    func exactSongsMatch() async throws {
        let library = try await self.makeLibrary()
        let original = self.items()
        let shuffled = [original[1], original[2], original[0]]

        let resolved = library.resolveLegacyQueueOrder(items: shuffled, currentIndex: 1)

        #expect(library.tracks.tracks.map(\.id) == [3, 1, 2])
        #expect(resolved == original.map(\.id))
        #expect(shuffled[1].id == original[2].id)
    }

    @Test("missing or added queue tracks cannot replace a custom queue")
    func nonMatchingMembership() async throws {
        let library = try await self.makeLibrary()
        let items = self.items()
        #expect(library.resolveLegacyQueueOrder(items: Array(items.prefix(2)), currentIndex: 0) == nil)
        library.tracks.setTracks(Array(self.tracks().prefix(2)), preserveOrder: true)
        #expect(library.resolveLegacyQueueOrder(items: items, currentIndex: 0) == nil)
    }

    @Test("a repeated track makes legacy source recovery ambiguous")
    func duplicateTracksAreRejected() async throws {
        let library = try await self.makeLibrary()
        let original = self.items()
        let duplicated = original + [QueueItem.make(from: self.tracks()[0], artistName: nil)]
        #expect(library.resolveLegacyQueueOrder(items: duplicated, currentIndex: 0) == nil)
        library.tracks.setTracks(self.tracks() + [self.tracks()[0]], preserveOrder: true)
        #expect(library.resolveLegacyQueueOrder(items: original, currentIndex: 0) == nil)
    }

    @Test("other destinations cannot supply the Songs baseline", arguments: [
        SidebarDestination.upNext, .album(7), .playlist(9), .history,
    ])
    func otherDestinationsAreRejected(destination: SidebarDestination) async throws {
        let library = try await self.makeLibrary()
        library.selectedDestination = destination
        #expect(library.resolveLegacyQueueOrder(items: self.items(), currentIndex: 1) == nil)
    }

    @Test("a loading or empty Songs list cannot supply the baseline")
    func unloadedRowsAreRejected() async throws {
        let library = try await self.makeLibrary()
        library.tracks.beginSmartFolderLoading()
        #expect(library.resolveLegacyQueueOrder(items: self.items(), currentIndex: 0) == nil)
        library.tracks.finishSmartFolderRows([])
        #expect(library.resolveLegacyQueueOrder(items: self.items(), currentIndex: 0) == nil)
    }

    @Test("recovery requires a valid current item", arguments: [nil, -1, 3])
    func invalidCurrentIndexIsRejected(index: Int?) async throws {
        let library = try await self.makeLibrary()
        #expect(library.resolveLegacyQueueOrder(items: self.items(), currentIndex: index) == nil)
    }

    @Test("a remote item cannot be mistaken for the local Songs context")
    func remoteItemsAreRejected() async throws {
        let library = try await self.makeLibrary()
        let original = self.items()
        let track = original[0]
        let remote = QueueItem(
            id: track.id, trackID: track.trackID, bookmark: nil, fileURL: track.fileURL,
            duration: track.duration, sourceFormat: track.sourceFormat,
            playableSource: .subsonic(serverID: UUID(), songID: "remote")
        )
        #expect(library.resolveLegacyQueueOrder(items: [remote] + original.dropFirst(), currentIndex: 1) == nil)
    }

    @Test("a legacy already-off queue recovers before enabling and disables from the same track")
    func alreadyOffLegacyToggle() async throws {
        let db = try await Database(location: .inMemory)
        let engine = AudioEngine()
        let player = QueuePlayer(engine: engine, database: db)
        await player.waitUntilActivated()
        let library = LibraryViewModel(database: db, engine: player)
        library.tracks.setTracks(self.tracks(), preserveOrder: true)
        let canonical = self.items()
        let legacy = [canonical[1], canonical[2], canonical[0]]
        await player.queue.restore(
            items: legacy, currentIndex: 1, repeatMode: .all,
            shuffleState: .off, sourceItems: nil
        )
        #expect(!(await player.queue.hasKnownSourceOrder))

        await library.nowPlaying.setShuffle(true)
        #expect(await player.queue.hasKnownSourceOrder)
        #expect(await player.queue.currentItem?.id == canonical[2].id)
        await library.nowPlaying.setShuffle(false)

        let after = await player.queue.snapshot()
        #expect(after.items.map(\.id) == canonical.map(\.id))
        #expect(after.currentIndex == 2)
        #expect(await player.queue.currentItem?.id == canonical[2].id)
        #expect(await engine.currentTime == 0)
        #expect(await engine.duration == 0)
        #expect(!(await engine.isPlaying))
        #expect(await player.queue.history.isEmpty)
    }

    @Test("a legacy mismatched queue retains every item when disabling")
    func mismatchRemainsUntouched() async throws {
        let db = try await Database(location: .inMemory)
        let player = QueuePlayer(engine: AudioEngine(), database: db)
        await player.waitUntilActivated()
        let library = LibraryViewModel(database: db, engine: player)
        library.tracks.setTracks(Array(self.tracks().prefix(2)), preserveOrder: true)
        let original = self.items()
        await player.queue.restore(
            items: original, currentIndex: 1, repeatMode: .off,
            shuffleState: .on(seed: 42), sourceItems: nil
        )

        await library.nowPlaying.setShuffle(false)

        let after = await player.queue.snapshot()
        #expect(after.items.map(\.id) == original.map(\.id))
        #expect(after.currentIndex == 1)
        #expect(!(await player.queue.hasKnownSourceOrder))
    }

    @Test("known source order never invokes legacy recovery")
    func knownSourceIsPreserved() async throws {
        let db = try await Database(location: .inMemory)
        let player = QueuePlayer(engine: AudioEngine(), database: db)
        await player.waitUntilActivated()
        let vm = NowPlayingViewModel(engine: player, database: db)
        let original = self.items()
        await player.queue.replace(with: original, startAt: 1)
        var recoveryCalls = 0
        vm.onResolveLegacyQueueOrder = { _, _ in
            recoveryCalls += 1
            return original.reversed().map(\.id)
        }

        await vm.setShuffle(true)
        await vm.setShuffle(false)

        #expect(recoveryCalls == 0)
        #expect(await player.queue.items.map(\.id) == original.map(\.id))
        #expect(await player.queue.currentItem?.id == original[1].id)
    }

    @Test("sorting Songs during shuffle keeps the playing UUID when shuffle turns off")
    func sortDuringShuffleKeepsCurrentIdentity() async throws {
        let db = try await Database(location: .inMemory)
        let engine = AudioEngine()
        let player = QueuePlayer(engine: engine, database: db)
        await player.waitUntilActivated()
        let library = LibraryViewModel(database: db, engine: player)
        let canonical = self.items()
        library.tracks.setTracks(Array(self.tracks().reversed()), preserveOrder: true)
        await player.queue.restore(
            items: [canonical[1], canonical[2], canonical[0]], currentIndex: 1,
            repeatMode: .all, shuffleState: .on(seed: 42), sourceItems: canonical
        )

        await library.reorderQueue()
        #expect(await player.queue.items.map(\.id) == canonical.reversed().map(\.id))
        #expect(await player.queue.currentItem?.id == canonical[2].id)
        await library.nowPlaying.setShuffle(false)

        #expect(await player.queue.items.map(\.id) == canonical.map(\.id))
        #expect(await player.queue.currentIndex == 2)
        #expect(await player.queue.currentItem?.id == canonical[2].id)
        #expect(!(await engine.isPlaying))
        #expect(await engine.currentTime == 0)
    }

    @Test("sorting keeps the exact playing occurrence of a repeated track")
    func sortKeepsDuplicateOccurrence() async throws {
        let db = try await Database(location: .inMemory)
        let player = QueuePlayer(engine: AudioEngine(), database: db)
        await player.waitUntilActivated()
        let library = LibraryViewModel(database: db, engine: player)
        let tracks = self.tracks()
        let first = QueueItem.make(from: tracks[0], artistName: nil)
        let second = QueueItem.make(from: tracks[0], artistName: nil)
        let other = QueueItem.make(from: tracks[1], artistName: nil)
        let source = [first, second, other]
        library.tracks.setTracks([tracks[1], tracks[0], tracks[0]], preserveOrder: true)
        await player.queue.restore(
            items: [second, other, first], currentIndex: 0,
            repeatMode: .off, shuffleState: .on(seed: 42), sourceItems: source
        )

        await library.reorderQueue()
        #expect(await player.queue.items.map(\.id) == [other.id, first.id, second.id])
        #expect(await player.queue.currentItem?.id == second.id)
        await library.nowPlaying.setShuffle(false)
        #expect(await player.queue.items.map(\.id) == source.map(\.id))
        #expect(await player.queue.currentIndex == 1)
        #expect(await player.queue.currentItem?.id == second.id)
    }

    @Test("sorting during shuffle retains the active membership and refuses partial contexts")
    func sortKeepsActiveMembership() async throws {
        let db = try await Database(location: .inMemory)
        let player = QueuePlayer(engine: AudioEngine(), database: db)
        await player.waitUntilActivated()
        let library = LibraryViewModel(database: db, engine: player)
        var tracks = self.tracks()
        tracks[0].excludedFromShuffle = true
        let source = tracks.map { QueueItem.make(from: $0, artistName: nil) }
        library.tracks.setTracks(Array(tracks.reversed()), preserveOrder: true)
        await player.queue.restore(
            items: [source[1], source[2]], currentIndex: 1,
            repeatMode: .off, shuffleState: .on(seed: 42), sourceItems: source
        )

        await library.reorderQueue()
        #expect(await player.queue.items.map(\.id) == [source[2].id, source[1].id])
        #expect(await player.queue.currentItem?.id == source[2].id)
        library.tracks.setTracks(Array(tracks.prefix(2)), preserveOrder: true)
        await library.reorderQueue()
        #expect(await player.queue.items.map(\.id) == [source[2].id, source[1].id])
        await library.nowPlaying.setShuffle(false)
        #expect(await player.queue.items.map(\.id) == source.map(\.id))
        #expect(await player.queue.currentItem?.id == source[2].id)
    }
}
