import Foundation
import Metadata
import Persistence
import Testing
@testable import Library

@Suite("Online lyrics matching and fallback", .serialized)
struct LyricsNetworkTests {
    @Test("404 falls back to title search and matches traditional artist plus timing")
    func searchFallback() async throws {
        let session = Self.session { request in
            if request.url!.path.hasSuffix("/get") { return (404, "{}") }
            #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "album_name" }) == false)
            return (200, #"[{"trackName":"自由的你","artistName":"G.E.M. 鄧紫棋","albumName":"Different edition","duration":297,"syncedLyrics":"[00:01.00]Original test line"}]"#)
        }
        let doc = try await LRClibClient(session: session).get(artist: "G.E.M.邓紫棋", title: "自由的你", album: "Local tag", duration: 296)
        #expect(doc?.testSyncedLineCount == 1)
    }

    @Test("Search ignores covers, live titles, missing timing, and different recordings")
    func rejectsWrongRecordings() async throws {
        let session = Self.session { request in
            if request.url!.path.hasSuffix("/get") { return (404, "{}") }
            return (200, #"[{"trackName":"Song","artistName":"Cover artist","duration":180,"plainLyrics":"Wrong artist"},{"trackName":"Song (Live)","artistName":"Artist","duration":180,"plainLyrics":"Wrong version"},{"trackName":"Song","artistName":"Artist","duration":220,"plainLyrics":"Wrong timing"},{"trackName":"Song","artistName":"Artist","plainLyrics":"No duration"},{"trackName":"Song","artistName":"Artist","duration":181,"plainLyrics":"Correct original fixture"}]"#)
        }
        let doc = try await LRClibClient(session: session).get(artist: "Artist", title: "Song", album: nil, duration: 180)
        #expect(doc == .unsynced("Correct original fixture"))
    }

    @Test("A real no-match differs from service failure")
    func noMatchAndInvalidJSON() async throws {
        let empty = Self.session { request in request.url!.path.hasSuffix("/get") ? (404, "{}") : (200, "[]") }
        #expect(try await LRClibClient(session: empty).get(artist: "A", title: "T", album: nil, duration: 180) == nil)
        let bad = Self.session { _ in (200, "<html>Gateway error</html>") }
        await #expect(throws: LyricsLookupError.self) {
            _ = try await LRClibClient(session: bad).get(artist: "A", title: "T", album: nil, duration: 180)
        }
    }

    @Test("NetEase verifies catalog metadata before requesting lyrics and reports its own source")
    func netease() async throws {
        let session = Self.session { request in
            #expect(request.url?.scheme == "https")
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://music.163.com/")
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            if request.url!.path.contains("search") {
                return (200, #"{"code":200,"result":{"songs":[{"id":99,"name":"Song","artists":[{"name":"Cover"}],"duration":180000},{"id":7,"name":"Song","artists":[{"name":"Artist"}],"duration":181000}]}}"#)
            }
            #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(name: "id", value: "7")) == true)
            return (200, #"{"code":200,"lrc":{"lyric":"[00:01.00]Original fixture"}}"#)
        }
        let result = try await NetEaseLyricsClient(session: session).fetch(artist: "Artist", title: "Song", album: nil, duration: 180)
        #expect(result?.source == "netease")
        #expect(result?.document.testSyncedLineCount == 1)
    }

    @Test("NetEase rejects a provider business error rather than treating it as no lyrics")
    func providerBusinessError() async throws {
        let session = Self.session { _ in (200, #"{"code":500}"#) }
        await #expect(throws: LyricsLookupError.self) {
            _ = try await NetEaseLyricsClient(session: session).get(artist: "Artist", title: "Song", album: nil, duration: 180)
        }
    }

    @Test("Fallback is used after primary failures, only with its separate opt-in")
    func fallbackConsent() async throws {
        let primary = FixtureClient(failure: URLError(.notConnectedToInternet))
        let backup = FixtureClient(result: FetchedLyrics(document: .unsynced("Original backup"), source: "netease"))
        let disabled = OnlineLyricsClient(primary: primary, fallback: backup, fallbackEnabled: { false })
        await #expect(throws: LyricsLookupError.self) {
            _ = try await disabled.fetch(artist: "A", title: "T", album: nil, duration: 180)
        }
        #expect(await backup.calls == 0)
        let enabled = OnlineLyricsClient(primary: primary, fallback: backup, fallbackEnabled: { true })
        #expect(try await enabled.fetch(artist: "A", title: "T", album: nil, duration: 180)?.source == "netease")
        #expect(await backup.calls == 1)
    }

    @Test("No primary match falls back, while two successful empty responses stay a no-match")
    func fallbackNoMatch() async throws {
        let backup = FixtureClient(result: FetchedLyrics(document: .unsynced("Original fallback fixture"), source: "netease"))
        let client = OnlineLyricsClient(primary: FixtureClient(), fallback: backup, fallbackEnabled: { true })
        #expect(try await client.fetch(artist: "A", title: "T", album: nil, duration: 180)?.source == "netease")
        let empty = OnlineLyricsClient(primary: FixtureClient(), fallback: FixtureClient(), fallbackEnabled: { true })
        #expect(try await empty.fetch(artist: "A", title: "T", album: nil, duration: 180) == nil)
    }

    @Test("Primary hit makes no backup request; cancellation never starts backup")
    func primaryAndCancellation() async throws {
        let primary = FixtureClient(result: FetchedLyrics(document: .unsynced("Original primary"), source: "lrclib"))
        let backup = FixtureClient(result: FetchedLyrics(document: .unsynced("Original backup"), source: "netease"))
        let client = OnlineLyricsClient(primary: primary, fallback: backup, fallbackEnabled: { true })
        #expect(try await client.get(artist: "A", title: "T", album: nil, duration: 180) == .unsynced("Original primary"))
        let cancelled = OnlineLyricsClient(primary: FixtureClient(failure: URLError(.cancelled)), fallback: backup, fallbackEnabled: { true })
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.get(artist: "A", title: "T", album: nil, duration: 180)
        }
        #expect(await backup.calls == 0)
    }

    @Test("A fetched backup keeps its source when saved, observed and cached")
    func sourcePersistence() async throws {
        let db = try await Database(location: .inMemory)
        let now = Int64(Date().timeIntervalSince1970)
        let id = try await TrackRepository(database: db).upsert(Track(
            fileURL: "/tmp/original-fixture.wav", duration: 180, title: "Song", addedAt: now, updatedAt: now
        ))
        let client = FixtureClient(result: FetchedLyrics(document: .unsynced("Original cached"), source: "netease"))
        let service = LyricsService(database: db, fetcher: client)
        let result = try await service.forceFetchWithSource(for: id)
        #expect(result?.source == "netease")
        let resolved = try await service.lyricsWithSource(for: id)
        #expect(resolved.1 == "netease")
        UserDefaults.standard.set(true, forKey: "lyrics.lrclibEnabled")
        defer { UserDefaults.standard.removeObject(forKey: "lyrics.lrclibEnabled") }
        #expect(try await service.autoFetchIfMissing(for: id) == .unsynced("Original cached"))
        #expect(await client.calls == 1)
    }

    @Test("Traditional/simplified metadata and dual artist names match without matching other songs")
    func normalizedIdentity() {
        #expect(LyricsMatch.normalized("周杰倫") == LyricsMatch.normalized("周杰伦"))
        #expect(LyricsMatch.score(title: "青花瓷", artists: ["Jay Chou 周杰倫"], duration: 239, album: nil, queryTitle: "青花瓷", queryArtist: "周杰伦", queryDuration: 240, queryAlbum: nil) != nil)
        #expect(LyricsMatch.score(title: "青花瓷 (Live)", artists: ["周杰伦"], duration: 239, album: nil, queryTitle: "青花瓷", queryArtist: "周杰伦", queryDuration: 240, queryAlbum: nil) == nil)
    }

    private static func session(_ handler: @escaping (URLRequest) -> (Int, String)) -> URLSession {
        LyricsFixtureProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsFixtureProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class LyricsFixtureProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let (status, text) = Self.handler?(self.request) else { return }
        let response = HTTPURLResponse(url: self.request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: Data(text.utf8))
        self.client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private actor FixtureClient: LRClibClientProtocol {
    let result: FetchedLyrics?
    let failure: (any Error)?
    var calls = 0
    init(result: FetchedLyrics? = nil, failure: (any Error)? = nil) { self.result = result; self.failure = failure }
    func fetch(artist: String, title: String, album: String?, duration: TimeInterval) async throws -> FetchedLyrics? {
        self.calls += 1
        if let failure { throw failure }
        return self.result
    }
    func get(artist: String, title: String, album: String?, duration: TimeInterval) async throws -> LyricsDocument? {
        try await self.fetch(artist: artist, title: title, album: album, duration: duration)?.document
    }
    func search(artist: String?, title: String?, album: String?) async throws -> [LyricsDocument] { [] }
}

@Suite("Live lyrics channels")
struct LyricsLiveChannelTests {
    @Test("NetEase and the aggregate client retrieve verified synced lyrics", .enabled(if: ProcessInfo.processInfo.environment["WMUSIC_LYRICS_LIVE"] == "1"))
    func liveChannels() async throws {
        let direct = try await NetEaseLyricsClient().fetch(artist: "G.E.M.邓紫棋", title: "自由的你", album: "自由的你", duration: 296)
        #expect(direct?.source == "netease")
        #expect((direct?.document.testSyncedLineCount ?? 0) > 5)
        // The old provider can be temporarily unavailable. This gate measures
        // the shipped retrieval chain, not that external service's uptime.
        let second = try await OnlineLyricsClient(fallbackEnabled: { true }).fetch(artist: "G.E.M.邓紫棋", title: "自由的你", album: "自由的你", duration: 296)
        #expect((second?.document.testSyncedLineCount ?? 0) > 5)
    }

    @Test("A failed primary switches to the real NetEase endpoint", .enabled(if: ProcessInfo.processInfo.environment["WMUSIC_LYRICS_LIVE"] == "1"))
    func liveFallback() async throws {
        let client = OnlineLyricsClient(primary: FixtureClient(failure: URLError(.cannotConnectToHost)), fallbackEnabled: { true })
        let second = try await client.fetch(artist: "G.E.M.邓紫棋", title: "自由的你", album: "自由的你", duration: 296)
        #expect(second?.source == "netease")
        #expect((second?.document.testSyncedLineCount ?? 0) > 5)
    }
}

private extension LyricsDocument {
    var testSyncedLineCount: Int {
        guard case let .synced(lines, _) = self else { return 0 }
        return lines.count
    }
}
