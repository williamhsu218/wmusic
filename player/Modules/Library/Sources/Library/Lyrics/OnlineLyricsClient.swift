import Foundation
import Metadata

public struct FetchedLyrics: Sendable {
    public let document: LyricsDocument
    public let source: String

    public init(document: LyricsDocument, source: String) {
        self.document = document
        self.source = source
    }
}

public enum LyricsLookupError: Error, Sendable {
    case missingMetadata
    case invalidResponse(String)
    case httpStatus(String, Int)
    case unavailable
}

/// LRClib consent is still the master switch. The additional provider requires
/// a separate opt-in, so an existing LRClib preference never widens sharing.
public actor OnlineLyricsClient: LRClibClientProtocol {
    private let primary: any LRClibClientProtocol
    private let fallback: any LRClibClientProtocol
    private let fallbackEnabled: @Sendable () -> Bool

    public init(
        primary: any LRClibClientProtocol = LRClibClient(),
        fallback: any LRClibClientProtocol = NetEaseLyricsClient(),
        fallbackEnabled: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.bool(forKey: "lyrics.neteaseEnabled")
        }
    ) {
        self.primary = primary
        self.fallback = fallback
        self.fallbackEnabled = fallbackEnabled
    }

    public func fetch(artist: String, title: String, album: String?, duration: TimeInterval) async throws -> FetchedLyrics? {
        var failed = false
        do {
            if let result = try await self.primary.fetch(artist: artist, title: title, album: album, duration: duration) {
                try Task.checkCancellation()
                return result
            }
        } catch {
            try Self.propagateCancellation(error)
            if case LyricsLookupError.missingMetadata = error { throw error }
            failed = true
        }
        if self.fallbackEnabled() {
            try Task.checkCancellation()
            do {
                if let result = try await self.fallback.fetch(artist: artist, title: title, album: album, duration: duration) {
                    try Task.checkCancellation()
                    return result
                }
            } catch {
                try Self.propagateCancellation(error)
                failed = true
            }
        }
        if failed { throw LyricsLookupError.unavailable }
        return nil
    }

    public func get(artist: String, title: String, album: String?, duration: TimeInterval) async throws -> LyricsDocument? {
        try await self.fetch(artist: artist, title: title, album: album, duration: duration)?.document
    }

    public func search(artist: String?, title: String?, album: String?) async throws -> [LyricsDocument] {
        try await self.primary.search(artist: artist, title: title, album: album)
    }

    static func propagateCancellation(_ error: Error) throws {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }
}

/// Only compare catalog identity and timing, never pick the first search hit.
enum LyricsMatch {
    static func normalized(_ text: String) -> String {
        let simplified = text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
        return simplified.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    private static func artistKeys(_ text: String) -> Set<String> {
        var keys: Set<String> = [self.normalized(text)]
        let scalars = text.unicodeScalars
        let han = scalars.filter { (0x4E00 ... 0x9FFF).contains($0.value) }.map(String.init).joined()
        let latin = scalars.filter { (65 ... 90).contains($0.value) || (97 ... 122).contains($0.value) }.map(String.init).joined()
        // Chinese/Latin dual names such as G.E.M.鄧紫棋 and Jay Chou周杰倫.
        if !han.isEmpty, latin.count >= 3 {
            keys.insert(self.normalized(han))
            keys.insert(self.normalized(latin))
        }
        return keys.filter { !$0.isEmpty }
    }

    static func score(
        title: String, artists: [String], duration: TimeInterval?, album: String?,
        queryTitle: String, queryArtist: String, queryDuration: TimeInterval, queryAlbum: String?
    ) -> Double? {
        guard !queryTitle.isEmpty, !queryArtist.isEmpty,
              self.normalized(title) == self.normalized(queryTitle),
              artists.contains(where: { !self.artistKeys($0).isDisjoint(with: self.artistKeys(queryArtist)) }) else { return nil }
        var score = 100.0
        if queryDuration.isFinite, queryDuration > 0 {
            guard let duration, duration.isFinite, duration > 0 else { return nil }
            let delta = abs(duration - queryDuration)
            guard delta <= max(3, min(8, queryDuration * 0.02)) else { return nil }
            score -= delta
        }
        if let album, let queryAlbum, self.normalized(album) == self.normalized(queryAlbum) { score += 2 }
        return score
    }
}
