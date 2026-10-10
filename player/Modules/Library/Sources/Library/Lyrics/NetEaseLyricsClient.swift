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
        let titles = LyricsMatch.searchTitles(title, artist: artist)
        let searchArtist = LyricsMatch.searchArtist(artist)
        let queries = ["\(titles[0]) \(searchArtist)", titles[0]] + titles.dropFirst().map { "\($0) \(searchArtist)" }
        var attempted = Set<Int64>()
        var failure: (any Error)?
        for (index, query) in queries.prefix(4).enumerated() {
            do {
                let songs = try await self.catalog(query: query, path: index == 1 ? "cloudsearch/pc" : "search/get/web")
                let ranked = songs.compactMap { song -> (Song, Double)? in
                    guard let score = LyricsMatch.score(
                        title: song.name, artists: song.artists.flatMap { [$0.name] + ($0.alias ?? []) },
                        duration: song.duration.map { $0 / 1000 }, album: song.album?.name,
                        queryTitle: title, queryArtist: artist, queryDuration: duration, queryAlbum: album
                    ) else { return nil }
                    return (song, score - Double(max(0, song.artists.count - 1)) * 5)
                }.sorted { $0.1 > $1.1 }
                for (song, _) in ranked.prefix(3) {
                    guard attempted.insert(song.id).inserted else { continue }
                    try Task.checkCancellation()
                    do {
                        let data = try await self.request("song/lyric", items: [
                            .init(name: "id", value: String(song.id)), .init(name: "lv", value: "-1"),
                            .init(name: "kv", value: "-1"), .init(name: "tv", value: "-1"),
                        ])
                        let result: LyricResponse = try self.decode(data)
                        guard result.code == 200 else { throw LyricsLookupError.httpStatus("NetEase", result.code) }
                        if let text = result.lrc?.lyric, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return LRCParser.parseDocument(text)
                        }
                    } catch {
                        try OnlineLyricsClient.propagateCancellation(error)
                        failure = error
                    }
                }
            } catch {
                try OnlineLyricsClient.propagateCancellation(error)
                failure = error
            }
        }
        if let failure { throw failure }
        return nil
    }

    public func search(artist: String?, title: String?, album: String?) async throws -> [LyricsDocument] {
        guard let artist, let title, let doc = try await self.get(artist: artist, title: title, album: album, duration: 0) else { return [] }
        return [doc]
    }

    private func catalog(query: String, path: String) async throws -> [Song] {
        let data = try await self.request(path, items: [
            .init(name: "s", value: query), .init(name: "type", value: "1"),
            .init(name: "limit", value: "100"), .init(name: "offset", value: "0"),
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
        enum CodingKeys: String, CodingKey { case id, name, artists, ar, duration, dt, album, al }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try values.decode(Int64.self, forKey: .id)
            self.name = try values.decode(String.self, forKey: .name)
            self.artists = try values.decodeIfPresent([Artist].self, forKey: .artists) ?? values.decodeIfPresent([Artist].self, forKey: .ar) ?? []
            self.duration = try values.decodeIfPresent(Double.self, forKey: .duration) ?? values.decodeIfPresent(Double.self, forKey: .dt)
            self.album = try values.decodeIfPresent(Album.self, forKey: .album) ?? values.decodeIfPresent(Album.self, forKey: .al)
        }
        struct Artist: Decodable { let name: String; let alias: [String]? }
        struct Album: Decodable { let name: String }
    }
    private struct LyricResponse: Decodable {
        let code: Int
        let lrc: Lyric?
        struct Lyric: Decodable { let lyric: String? }
    }
}
