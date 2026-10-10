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
        let client = FixtureClient(result: FetchedLyrics(document: .unsynced("Original cached"), source: "kugou"))
        let service = LyricsService(database: db, fetcher: client)
        let result = try await service.forceFetchWithSource(for: id)
        #expect(result?.source == "kugou")
        let resolved = try await service.lyricsWithSource(for: id)
        #expect(resolved.1 == "kugou")
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

    @Test("NetEase finds an original beyond the first twenty search results")
    func deepCatalog() async throws {
        let session = Self.session { request in
            if request.url!.path.contains("search") {
                let limit = Int(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "limit" }!.value!)!
                let covers = (0..<76).map { i in ["id": i + 100, "name": "画心", "artists": [["name": "Cover artist"]], "duration": 432000] as [String: Any] }
                let original: [String: Any] = ["id": 327089, "name": "画心", "artists": [["name": "张靓颖"]], "duration": 432293]
                let data = try! JSONSerialization.data(withJSONObject: ["code": 200, "result": ["songs": Array((covers + [original]).prefix(limit))]])
                return (200, String(decoding: data, as: UTF8.self))
            }
            #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.contains(.init(name: "id", value: "327089")))
            return (200, #"{"code":200,"lrc":{"lyric":"[00:01.00]Original deep catalog fixture"}}"#)
        }
        #expect(try await NetEaseLyricsClient(session: session).get(artist: "张靓颖", title: "画心", album: nil, duration: 432)?.testSyncedLineCount == 1)
    }

    @Test("NetEase recovers from catalog failure using the alternate response shape and aliases")
    func alternateCatalog() async throws {
        let session = Self.session { request in
            if request.url!.path.hasSuffix("search/get/web") { return (503, "{}") }
            if request.url!.path.contains("cloudsearch") {
                return (200, #"{"code":200,"result":{"songs":[{"id":7,"name":"画心","ar":[{"name":"张靓颖","alias":["Jane Zhang"]}],"dt":432293,"al":{"name":"Album"}}]}}"#)
            }
            return (200, #"{"code":200,"lrc":{"lyric":"[00:01.00]Original alternate fixture"}}"#)
        }
        #expect(try await NetEaseLyricsClient(session: session).get(artist: "Jane Zhang", title: "画心", album: nil, duration: 432)?.testSyncedLineCount == 1)
    }

    @Test("A broken lyric candidate does not prevent another valid recording")
    func candidateFailure() async throws {
        let session = Self.session { request in
            if request.url!.path.contains("search") {
                return (200, #"{"code":200,"result":{"songs":[{"id":1,"name":"Song","artists":[{"name":"Artist"}],"duration":180000},{"id":2,"name":"Song","artists":[{"name":"Artist"}],"duration":181000}]}}"#)
            }
            if URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.contains(.init(name: "id", value: "1")) { return (500, "{}") }
            return (200, #"{"code":200,"lrc":{"lyric":"[00:01.00]Original second candidate"}}"#)
        }
        #expect(try await NetEaseLyricsClient(session: session).get(artist: "Artist", title: "Song", album: nil, duration: 180)?.testSyncedLineCount == 1)
    }

    @Test("Kugou decodes verified LRC, rejects covers and tries another broken candidate")
    func kugou() async throws {
        let session = Self.session { request in
            #expect(request.url!.scheme == "https")
            #expect(request.httpShouldHandleCookies == false)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            if request.url!.path == "/search" {
                #expect(items.contains(.init(name: "keyword", value: "张靓颖 - 画心")))
                #expect(items.contains(.init(name: "duration", value: "432000")))
                return (200, #"{"status":200,"candidates":[{"id":"99","accesskey":"fixture","song":"画心","singer":"Cover","duration":432000},{"id":"1","accesskey":"fixture","song":"画心","singer":"张靓颖","duration":432000},{"id":"2","accesskey":"fixture","song":"画心","singer":"张靓颖","duration":432100}]}"#)
            }
            #expect(items.contains(.init(name: "fmt", value: "lrc")))
            #expect(!items.contains(.init(name: "id", value: "99")))
            if items.contains(.init(name: "id", value: "1")) { return (200, #"{"status":200,"content":"not base64"}"#) }
            let content = Data("[00:01.00]Original Kugou fixture".utf8).base64EncodedString()
            return (200, "{\"status\":200,\"content\":\"\(content)\"}")
        }
        let result = try await KugouLyricsClient(session: session).fetch(artist: "张靓颖", title: "画心", album: nil, duration: 432)
        #expect(result?.source == "kugou")
        #expect(result?.document.testSyncedLineCount == 1)
    }

    @Test("Kugou has independent consent and is skipped on cancellation")
    func additionalConsent() async throws {
        let third = FixtureClient(result: FetchedLyrics(document: .unsynced("Original third provider"), source: "kugou"))
        let disabled = OnlineLyricsClient(primary: FixtureClient(), fallback: FixtureClient(), fallbackEnabled: { false }, additional: third, additionalEnabled: { false })
        #expect(try await disabled.fetch(artist: "A", title: "T", album: nil, duration: 180) == nil)
        #expect(await third.calls == 0)
        let enabled = OnlineLyricsClient(primary: FixtureClient(failure: URLError(.cannotConnectToHost)), fallback: FixtureClient(), fallbackEnabled: { true }, additional: third, additionalEnabled: { true })
        #expect(try await enabled.fetch(artist: "A", title: "T", album: nil, duration: 180)?.source == "kugou")
        let cancelled = OnlineLyricsClient(primary: FixtureClient(failure: CancellationError()), additional: third, additionalEnabled: { true })
        await #expect(throws: CancellationError.self) { _ = try await cancelled.fetch(artist: "A", title: "T", album: nil, duration: 180) }
        #expect(await third.calls == 1)
    }

    @Test("Promotional decorations and remasters match, while recording versions stay distinct")
    func titleDecoration() {
        #expect(LyricsMatch.score(title: "小幸运 (电影《我的少女时代》主题曲)", artists: ["田馥甄"], duration: 265, album: nil, queryTitle: "小幸运", queryArtist: "田馥甄", queryDuration: 265, queryAlbum: nil) != nil)
        #expect(LyricsMatch.cleanTitle("07. Artist - Song (2020 Remastered)", artist: "Artist") == "Song")
        #expect(LyricsMatch.score(title: "Song", artists: ["A", "B"], duration: 180, album: nil, queryTitle: "Song", queryArtist: "A & B", queryDuration: 180, queryAlbum: nil) != nil)
        #expect(LyricsMatch.score(title: "Song", artists: ["A"], duration: 180, album: nil, queryTitle: "Song", queryArtist: "A & B", queryDuration: 180, queryAlbum: nil) == nil)
        for version in ["Live", "现场版", "Remix", "伴奏", "Acoustic", "Taylor's Version"] {
            #expect(LyricsMatch.score(title: "Song (\(version))", artists: ["Artist"], duration: 180, album: nil, queryTitle: "Song", queryArtist: "Artist", queryDuration: 180, queryAlbum: nil) == nil)
        }
        #expect(LyricsMatch.score(title: "Song", artists: ["Someone Else"], duration: 180, album: nil, queryTitle: "Song", queryArtist: "Artist", queryDuration: 180, queryAlbum: nil) == nil)
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

    @Test("Common songs and the two reported failures work through actual providers", .enabled(if: ProcessInfo.processInfo.environment["WMUSIC_LYRICS_LIVE"] == "1"))
    func commonSongs() async throws {
        let samples: [(String, String, Double)] = [
            ("张靓颖", "画心", 432), ("张靓颖", "如果爱下去", 242),
            ("周杰伦", "青花瓷", 239), ("田馥甄", "小幸运", 265),
            ("陈奕迅", "十年", 205), ("孙燕姿", "遇见", 210),
            ("Adele", "Hello", 295.5), ("Taylor Swift", "Love Story", 235.3),
        ]
        let netease = NetEaseLyricsClient()
        let kugou = KugouLyricsClient()
        for (artist, title, duration) in samples {
            let first = try await netease.fetch(artist: artist, title: title, album: nil, duration: duration)
            let second = try await kugou.fetch(artist: artist, title: title, album: nil, duration: duration)
            print("LYRICS_LIVE \(artist) / \(title): netease=\(first?.document.testSyncedLineCount ?? 0), kugou=\(second?.document.testSyncedLineCount ?? 0)")
            #expect((first?.document.testSyncedLineCount ?? 0) > 5 || (second?.document.testSyncedLineCount ?? 0) > 5, "\(artist) / \(title)")
            if title == "画心" || title == "如果爱下去" {
                #expect((first?.document.testSyncedLineCount ?? 0) > 5)
                #expect((second?.document.testSyncedLineCount ?? 0) > 5)
                let aggregate = try await OnlineLyricsClient(fallbackEnabled: { true }, additionalEnabled: { true }).fetch(artist: artist, title: title, album: nil, duration: duration)
                #expect((aggregate?.document.testSyncedLineCount ?? 0) > 5)
            }
        }
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
