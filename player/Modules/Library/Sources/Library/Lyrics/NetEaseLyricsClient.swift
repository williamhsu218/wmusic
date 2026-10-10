import Acoustics
import Foundation
import Metadata
import Observability

/// An optional fallback using the public HTTPS catalog and lyric endpoints.
/// No account, cookie, proxy, or audio-download endpoint is used.
public actor NetEaseLyricsClient: LRClibClientProtocol {
    private let session: URLSession
    private let limiter = RateLimiter(maxRequests: 1, per: 1)

    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(artist: String, title: String, album: String?, duration: TimeInterval) async throws -> FetchedLyrics? {
        guard let doc = try await self.get(artist: artist, title: title, album: album, duration: duration) else { return nil }
        return FetchedLyrics(document: doc, source: "netease")
    }

    public func get(artist: String, title: String, album: String?, duration: TimeInterval) async throws -> LyricsDocument? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LyricsLookupError.missingMetadata }
        let songs = try await self.catalog(artist: artist, title: title)
        let ranked = songs.compactMap { song -> (Song, Double)? in
            guard let score = LyricsMatch.score(
                title: song.name, artists: song.artists.map(\.name), duration: song.duration.map { $0 / 1000 }, album: song.album?.name,
                queryTitle: title, queryArtist: artist, queryDuration: duration, queryAlbum: album
            ) else { return nil }
            return (song, score)
        }.sorted { $0.1 > $1.1 }
        for (song, _) in ranked.prefix(3) {
            try Task.checkCancellation()
            let data = try await self.request("song/lyric", items: [
                .init(name: "id", value: String(song.id)), .init(name: "lv", value: "-1"),
                .init(name: "kv", value: "-1"), .init(name: "tv", value: "-1"),
            ])
            let result: LyricResponse = try self.decode(data)
            guard result.code == 200 else { throw LyricsLookupError.httpStatus("NetEase", result.code) }
            if let text = result.lrc?.lyric, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return LRCParser.parseDocument(text)
            }
        }
        return nil
    }

    public func search(artist: String?, title: String?, album: String?) async throws -> [LyricsDocument] {
        guard let artist, let title, let doc = try await self.get(artist: artist, title: title, album: album, duration: 0) else { return [] }
        return [doc]
    }

    private func catalog(artist: String, title: String) async throws -> [Song] {
        let data = try await self.request("search/get/web", items: [
            .init(name: "s", value: "\(title) \(artist)"), .init(name: "type", value: "1"),
            .init(name: "limit", value: "20"), .init(name: "offset", value: "0"),
        ])
        let response: SearchResponse = try self.decode(data)
        guard response.code == 200 else { throw LyricsLookupError.httpStatus("NetEase", response.code) }
        return response.result?.songs ?? []
    }

    private func request(_ path: String, items: [URLQueryItem]) async throws -> Data {
        try Task.checkCancellation()
        try await self.limiter.wait()
        var components = URLComponents(string: "https://music.163.com/api/\(path)")!
        components.queryItems = items
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpShouldHandleCookies = false
        request.setValue(UserAgent.string, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await self.session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw LyricsLookupError.invalidResponse("NetEase") }
        guard http.statusCode == 200 else { throw LyricsLookupError.httpStatus("NetEase", http.statusCode) }
        guard data.count <= 2_000_000 else { throw LyricsLookupError.invalidResponse("NetEase") }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw LyricsLookupError.invalidResponse("NetEase") }
    }

    private struct SearchResponse: Decodable {
        let code: Int
        let result: Result?
        struct Result: Decodable { let songs: [Song]? }
    }
    private struct Song: Decodable {
        let id: Int64
        let name: String
        let artists: [Artist]
        let duration: Double?
        let album: Album?
        struct Artist: Decodable { let name: String }
        struct Album: Decodable { let name: String }
    }
    private struct LyricResponse: Decodable {
        let code: Int
        let lrc: Lyric?
        struct Lyric: Decodable { let lyric: String? }
    }
}
