import Foundation
import Library
import Metadata
import Persistence
import Testing
@testable import UI

@Suite("Lyrics lookup presentation", .serialized)
@MainActor
struct LyricsFetchTests {
    @Test("No match and connection failure have distinct messages; retry clears the error")
    func failureAndRetry() async throws {
        let db = try await Database(location: .inMemory)
        let id = try await self.seed(db, name: "failure")
        let client = PresentationFetcher()
        let vm = LyricsViewModel(service: LyricsService(database: db, fetcher: client))
        vm.trackDidChange(trackID: id)
        await self.wait { !vm.isFetching }
        vm.forceFetch(for: id)
        await self.wait { !vm.isFetching }
        #expect(vm.fetchMessage == L10n.string("No matching lyrics were found. Check the song title and artist."))

        await client.configure(failure: URLError(.notConnectedToInternet))
        vm.forceFetch(for: id)
        await self.wait { !vm.isFetching }
        #expect(vm.fetchMessage == L10n.string("Online lyrics could not be retrieved. Check your connection or try again."))

        await client.configure(result: FetchedLyrics(document: .unsynced("Original retry fixture"), source: "netease"))
        vm.forceFetch(for: id)
        await self.wait { !vm.isFetching && vm.document != nil }
        #expect(vm.fetchMessage == nil)
        #expect(vm.document == .unsynced("Original retry fixture"))
        #expect(vm.documentSource == "netease")
        #expect(vm.documentSourceLabel == L10n.string("NetEase Cloud Music"))
        vm.trackDidChange(trackID: nil)
    }

    @Test("A track change cancels old lookup and prevents stale lyrics from being saved")
    func trackChange() async throws {
        let db = try await Database(location: .inMemory)
        let first = try await self.seed(db, name: "first")
        let second = try await self.seed(db, name: "second")
        let client = PresentationFetcher()
        let service = LyricsService(database: db, fetcher: client)
        let vm = LyricsViewModel(service: service)
        vm.trackDidChange(trackID: first)
        await self.wait { !vm.isFetching }
        await client.configure(result: FetchedLyrics(document: .unsynced("Stale fixture"), source: "netease"), delay: true)
        vm.forceFetch(for: first)
        for _ in 0..<100 {
            if await client.startedDelayedRequest { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await client.startedDelayedRequest)
        vm.trackDidChange(trackID: second)
        try await Task.sleep(for: .milliseconds(300))
        #expect(vm.document == nil)
        #expect(vm.fetchMessage == nil)
        #expect(try await LyricsRepository(database: db).fetch(trackID: first) == nil)
        vm.trackDidChange(trackID: nil)
    }

    private func seed(_ db: Database, name: String) async throws -> Int64 {
        let now = Int64(Date().timeIntervalSince1970)
        return try await TrackRepository(database: db).upsert(Track(
            fileURL: "/tmp/lyrics-\(name).wav", duration: 180, title: name,
            addedAt: now, updatedAt: now
        ))
    }

    private func wait(_ condition: @escaping () -> Bool) async {
        for _ in 0..<100 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(condition(), "Async lyrics operation finished")
    }
}

private actor PresentationFetcher: LRClibClientProtocol {
    var result: FetchedLyrics?
    var failure: (any Error)?
    var delay = false
    var startedDelayedRequest = false

    func configure(result: FetchedLyrics? = nil, failure: (any Error)? = nil, delay: Bool = false) {
        self.result = result
        self.failure = failure
        self.delay = delay
    }

    func fetch(artist: String, title: String, album: String?, duration: TimeInterval) async throws -> FetchedLyrics? {
        if self.delay {
            self.startedDelayedRequest = true
            // Simulate a provider returning despite cancellation; the service
            // must check cancellation before it persists that stale response.
            try? await Task.sleep(for: .milliseconds(200))
        }
        if let failure { throw failure }
        return self.result
    }

    func get(artist: String, title: String, album: String?, duration: TimeInterval) async throws -> LyricsDocument? {
        try await self.fetch(artist: artist, title: title, album: album, duration: duration)?.document
    }

    func search(artist: String?, title: String?, album: String?) async throws -> [LyricsDocument] { [] }
}
