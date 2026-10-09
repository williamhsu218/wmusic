import Foundation
import Library
import Persistence
import Testing
@testable import UI

@Suite("Music folder navigation")
@MainActor
struct MusicFolderNavigationTests {
    private func addRoot(_ path: String, database: Database) async throws -> Int64 {
        let root = try await LibraryRootRepository(database: database).upsert(
            LibraryRoot(path: path, bookmark: Data(), addedAt: 0)
        )
        return try #require(root.id)
    }

    private func addTrack(
        _ path: String,
        title: String,
        disabled: Bool = false,
        database: Database
    ) async throws -> Int64 {
        var track = Track(
            fileURL: URL(fileURLWithPath: path, isDirectory: false).absoluteString,
            title: title,
            addedAt: 0,
            updatedAt: 0
        )
        track.disabled = disabled
        return try await TrackRepository(database: database).insert(track)
    }

    @Test("a source route shows only active songs inside its exact Unicode folder boundary")
    func sourceBoundary() async throws {
        let db = try await Database(location: .inMemory)
        let path = "/Volumes/音乐 100%_mix"
        let rootID = try await self.addRoot(path, database: db)
        let ownID = try await self.addTrack(path + "/Album/Song.flac", title: "Own Song", database: db)
        _ = try await self.addTrack(path + "/Removed.flac", title: "Disabled Song", disabled: true, database: db)
        _ = try await self.addTrack(path + "_other/Song.flac", title: "Sibling Song", database: db)
        _ = try await self.addTrack("/Users/test/Music/Song.flac", title: "Local Song", database: db)

        let vm = LibraryViewModel(database: db, engine: MockTransport())
        await vm.selectDestination(.musicFolder(rootID))

        #expect(vm.selectedDestination == .musicFolder(rootID))
        #expect(vm.tracks.tracks.compactMap(\.id) == [ownID])
        #expect(LibraryViewModel.destinationRendersSharedTrackList(.musicFolder(rootID)))
    }

    @Test("source search and scan reload stay scoped while preserving the selected song")
    func searchAndReload() async throws {
        let db = try await Database(location: .inMemory)
        let path = "/Volumes/Music"
        let rootID = try await self.addRoot(path, database: db)
        let firstID = try await self.addTrack(path + "/First.flac", title: "Shared First", database: db)
        _ = try await self.addTrack(path + "/Unmatched.flac", title: "Another Song", database: db)
        _ = try await self.addTrack("/Volumes/Other/Shared.flac", title: "Shared Elsewhere", database: db)
        let vm = LibraryViewModel(database: db, engine: MockTransport())
        vm.searchQuery = "Shared"
        await vm.selectDestination(.musicFolder(rootID))
        #expect(vm.tracks.tracks.compactMap(\.id) == [firstID])
        vm.tracks.selection = [firstID]

        // Scanning writes imported rows before reloading the current destination.
        let newID = try await self.addTrack(path + "/New.flac", title: "Shared New", database: db)
        await vm.loadCurrentDestination()
        #expect(Set(vm.tracks.tracks.compactMap(\.id)) == [firstID, newID])
        #expect(vm.tracks.selection == [firstID])
    }

    @Test("bookmark-style private paths and decomposed Unicode still belong to their saved source")
    func canonicalAliases() async throws {
        let db = try await Database(location: .inMemory)
        let path = "/var/tmp/Björk_100%"
        let rootID = try await self.addRoot(path, database: db)
        let importedPath = "/private/var/tmp/Björk_100%/Song.flac".decomposedStringWithCanonicalMapping
        let ownID = try await self.addTrack(importedPath, title: "Own Song", database: db)
        _ = try await self.addTrack("/private/var/tmp/Björk_100%_other/Song.flac", title: "Sibling Song", database: db)
        let fetched = try await TrackRepository(database: db).fetchAll(libraryRootID: rootID)
        #expect(fetched.compactMap(\.id) == [ownID])
    }

    @Test("a real bookmarked scan remains browsable from its original source path")
    func bookmarkedScanRoute() async throws {
        let base = URL(fileURLWithPath: "/var/tmp", isDirectory: true)
            .appendingPathComponent("wmusic-source-route-\(UUID().uuidString)", isDirectory: true)
        let source = base.appendingPathComponent("音乐_%", isDirectory: true)
        let sibling = base.appendingPathComponent("音乐_%_other", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Library/Tests/LibraryTests/Fixtures/sample-library/Artist A/Album One/01 - First Track.mp3")
        let db = try await Database(location: .inMemory)
        let scanner = LibraryScanner(database: db)
        for (folder, filename) in [(source, "own.mp3"), (sibling, "other.mp3")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fixture, to: folder.appendingPathComponent(filename))
            try await scanner.addRoot(folder)
        }
        for await _ in await scanner.scan(mode: .full) {}
        #expect(try await TrackRepository(database: db).fetchAll().count == 2)
        let rootID = try #require(try await scanner.roots().first { $0.path == source.path }?.id)
        let vm = LibraryViewModel(database: db, engine: MockTransport(), scanner: scanner)
        await vm.refreshRoots()
        await vm.selectDestination(.musicFolder(rootID))
        #expect(vm.tracks.rows.count == 1)
        let fileURL = try #require(vm.tracks.tracks.first?.fileURL)
        #expect(URL(string: fileURL)?.lastPathComponent == "own.mp3")
        await scanner.stopWatching()
    }

    @Test("a single-file source does not include similarly named files")
    func fileRoot() async throws {
        let db = try await Database(location: .inMemory)
        let path = "/tmp/One.flac"
        let rootID = try await self.addRoot(path, database: db)
        let ownID = try await self.addTrack("/private/tmp/One.flac", title: "One", database: db)
        _ = try await self.addTrack("/private/tmp/One.flac.bak", title: "Other", database: db)
        let fetched = try await TrackRepository(database: db).fetchAll(libraryRootID: rootID)
        #expect(fetched.compactMap(\.id) == [ownID])
    }

    @Test("removing the active source falls back to Songs on reload")
    func removedRootFallback() async throws {
        let db = try await Database(location: .inMemory)
        let rootID = try await self.addRoot("/Volumes/Music", database: db)
        let localID = try await self.addTrack("/Users/test/Music/Local.flac", title: "Local", database: db)
        let vm = LibraryViewModel(database: db, engine: MockTransport())
        await vm.selectDestination(.musicFolder(rootID))
        try await LibraryRootRepository(database: db).delete(id: rootID)
        await vm.loadCurrentDestination()
        #expect(vm.selectedDestination == .songs)
        #expect(vm.tracks.tracks.compactMap(\.id) == [localID])
    }

    @Test("state restoration preserves a live music source and rejects a removed one")
    func restoredRootValidation() async throws {
        let db = try await Database(location: .inMemory)
        let rootID = try await self.addRoot("/Volumes/Music", database: db)
        let vm = LibraryViewModel(database: db, engine: MockTransport())
        vm.selectedDestination = .musicFolder(rootID)
        await vm.saveUIState()
        let restored = LibraryViewModel(database: db, engine: MockTransport())
        await restored.restoreUIState()
        #expect(restored.selectedDestination == .musicFolder(rootID))

        try await LibraryRootRepository(database: db).delete(id: rootID)
        let afterRemoval = LibraryViewModel(database: db, engine: MockTransport())
        await afterRemoval.restoreUIState()
        #expect(afterRemoval.selectedDestination == .songs)
    }
}
