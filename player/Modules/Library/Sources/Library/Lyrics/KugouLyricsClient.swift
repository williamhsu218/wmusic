import Acoustics
import Foundation
import Metadata
import Observability

/// Searches the lyric catalog directly, independently of streaming rights and
/// music-search ranking. Requires its own opt-in; requests never include audio,
/// local paths, account credentials, or cookies.
public actor KugouLyricsClient: LRClibClientProtocol {
    private let session: URLSession
    private let limiter = RateLimiter(maxRequests: 1, per: 1)

    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(artist: String, title: String, album: String?, duration: TimeInterval) async throws -> FetchedLyrics? {
        guard let document = try await self.get(artist: artist, title: title, album: album, duration: duration) else { return nil }
        return FetchedLyrics(document: document, source: "kugou")
    }

    public func get(artist: String, title: String, album: String?, duration: TimeInterval) async throws -> LyricsDocument? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LyricsLookupError.missingMetadata }
        var attempted = Set<String>()
        var failure: (any Error)?
        for queryTitle in LyricsMatch.searchTitles(title, artist: artist) {
            do {
                var items: [URLQueryItem] = [.init(name: "keyword", value: "\(LyricsMatch.searchArtist(artist)) - \(queryTitle)"), .init(name: "man", value: "yes")]
                if duration.isFinite, duration > 0, duration < 86_400 {
                    items.append(.init(name: "duration", value: String(Int((duration * 1000).rounded()))))
                }
                let result: SearchResponse = try self.decode(await self.request("search", items: items))
                guard result.status == 200 else { throw LyricsLookupError.httpStatus("Kugou", result.status) }
                let ranked = (result.candidates ?? []).compactMap { candidate -> (Candidate, Double)? in
                    guard let score = LyricsMatch.score(title: candidate.song, artists: [candidate.singer], duration: candidate.duration / 1000, album: nil,
                        queryTitle: title, queryArtist: artist, queryDuration: duration, queryAlbum: album) else { return nil }
                    return (candidate, score)
                }.sorted { $0.1 > $1.1 }
                for (candidate, _) in ranked.prefix(3) {
                    guard attempted.insert(candidate.id).inserted else { continue }
                    do {
                        let lyric: LyricResponse = try self.decode(await self.request("download", items: [
                            .init(name: "id", value: candidate.id), .init(name: "accesskey", value: candidate.accesskey),
                            .init(name: "fmt", value: "lrc"), .init(name: "charset", value: "utf8"),
                        ]))
                        guard lyric.status == 200, let content = lyric.content, let data = Data(base64Encoded: content),
                              let text = String(data: data, encoding: .utf8) else { throw LyricsLookupError.invalidResponse("Kugou") }
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                        let doc = LRCParser.parseDocument(text)
                        // Tag-only responses are not lyrics.
                        if case let .synced(lines, _) = doc, !lines.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
                        return doc
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

    private func request(_ path: String, items: [URLQueryItem]) async throws -> Data {
        try Task.checkCancellation()
        try await self.limiter.wait()
        var components = URLComponents(string: "https://lyrics.kugou.com/\(path)")!
        components.queryItems = items + [.init(name: "client", value: "pc"), .init(name: "ver", value: "1")]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpShouldHandleCookies = false
        request.setValue(UserAgent.string, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await self.session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, data.count <= 2_000_000 else { throw LyricsLookupError.invalidResponse("Kugou") }
        guard http.statusCode == 200 else { throw LyricsLookupError.httpStatus("Kugou", http.statusCode) }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw LyricsLookupError.invalidResponse("Kugou") }
    }

    private struct SearchResponse: Decodable { let status: Int; let candidates: [Candidate]? }
    private struct Candidate: Decodable {
        let id: String
        let accesskey: String
        let song: String
        let singer: String
        let duration: Double
    }
    private struct LyricResponse: Decodable { let status: Int; let content: String? }
}
