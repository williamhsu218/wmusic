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

/// LRClib consent is still the master switch. Both fallback providers require
/// separate opt-ins, so an existing preference never widens sharing.
public actor OnlineLyricsClient: LRClibClientProtocol {
    private let primary: any LRClibClientProtocol
    private let fallback: any LRClibClientProtocol
    private let fallbackEnabled: @Sendable () -> Bool
    private let additional: any LRClibClientProtocol
    private let additionalEnabled: @Sendable () -> Bool

    public init(
        primary: any LRClibClientProtocol = LRClibClient(),
        fallback: any LRClibClientProtocol = NetEaseLyricsClient(),
        fallbackEnabled: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.bool(forKey: "lyrics.neteaseEnabled")
        },
        additional: any LRClibClientProtocol = KugouLyricsClient(),
        additionalEnabled: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.bool(forKey: "lyrics.kugouEnabled")
        }
    ) {
        self.primary = primary
        self.fallback = fallback
        self.fallbackEnabled = fallbackEnabled
        self.additional = additional
        self.additionalEnabled = additionalEnabled
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
        if self.additionalEnabled() {
            try Task.checkCancellation()
            do {
                if let result = try await self.additional.fetch(artist: artist, title: title, album: album, duration: duration) {
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

    static func artistKeys(_ text: String) -> Set<String> {
        var keys: Set<String> = [self.normalized(text)]
        let scalars = text.unicodeScalars
        let han = scalars.filter { (0x4E00 ... 0x9FFF).contains($0.value) }.map(String.init).joined()
        let latin = scalars.filter { (65 ... 90).contains($0.value) || (97 ... 122).contains($0.value) }.map(String.init).joined()
        // Chinese/Latin dual names such as G.E.M.鄧紫棋 and Jay Chou周杰倫.
        if !han.isEmpty, latin.count >= 3 {
            keys.insert(self.normalized(han))
            keys.insert(self.normalized(latin))
        }
        // Multi-artist tags often join names with separators rather than
        // matching the catalog's array representation. Keep the full key too.
        let separated = text.replacingOccurrences(of: #"\s+(?:feat\.?|ft\.?|featuring)\s+"#, with: ";", options: .regularExpression)
        for part in separated.components(separatedBy: CharacterSet(charactersIn: ";；、&")) {
            keys.insert(self.normalized(part))
        }
        return keys.filter { !$0.isEmpty }
    }

    private static func artistComponents(_ text: String) -> [String] {
        let separated = text.replacingOccurrences(of: #"(?i)\s+(?:feat\.?|ft\.?|featuring|/)\s+"#, with: ";", options: .regularExpression)
        return separated.components(separatedBy: CharacterSet(charactersIn: ";；、&"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Remove catalog decoration, while retaining recording identities such
    /// as Live, Remix, acoustic, instrumental, and unknown parenthetical text.
    static func cleanTitle(_ text: String, artist: String = "") -> String {
        var title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.replacingOccurrences(of: #"^\d{1,3}[.、]\s*|^\d{1,3}\s+-\s+"#, with: "", options: .regularExpression)
        if let range = title.range(of: " - "), artistKeys(artist).contains(normalized(String(title[..<range.lowerBound]))) {
            title = String(title[range.upperBound...])
        }
        let pattern = #"[\(（\[【]([^\)）\]】]*)[\)）\]】]"#
        if let expression = try? NSRegularExpression(pattern: pattern) {
            for match in expression.matches(in: title, range: NSRange(title.startIndex..., in: title)).reversed() {
                guard let inner = Range(match.range(at: 1), in: title), let whole = Range(match.range, in: title) else { continue }
                let label = normalized(String(title[inner]))
                let promotional = ["主题曲", "片尾曲", "片头曲", "插曲", "remaster"].contains { label.contains($0) }
                let recording = ["live", "现场", "remix", "混音", "伴奏", "instrumental", "acoustic", "cover", "翻唱"].contains { label.contains($0) }
                if promotional, !recording { title.removeSubrange(whole) }
            }
        }
        let cleaned = title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—")))
        return cleaned.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
    }

    static func searchTitles(_ title: String, artist: String) -> [String] {
        let cleaned = cleanTitle(title, artist: artist)
        let variants = [cleaned, cleaned.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? cleaned,
                        cleaned.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? cleaned]
        var seen = Set<String>()
        return variants.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func searchArtist(_ artist: String) -> String {
        let simplified = artist.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? artist
        let han = simplified.unicodeScalars.filter { (0x4E00 ... 0x9FFF).contains($0.value) }.map(String.init).joined()
        // A bilingual single name can be searched using its Chinese portion.
        // Do not concatenate separate collaborating artists into a new name.
        if !han.isEmpty, !simplified.contains(where: { ";；、&".contains($0) }) { return han }
        return simplified.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func score(
        title: String, artists: [String], duration: TimeInterval?, album: String?,
        queryTitle: String, queryArtist: String, queryDuration: TimeInterval, queryAlbum: String?
    ) -> Double? {
        guard !queryTitle.isEmpty, !queryArtist.isEmpty,
              self.normalized(self.cleanTitle(title)) == self.normalized(self.cleanTitle(queryTitle, artist: queryArtist)),
              self.artistComponents(queryArtist).allSatisfy({ component in
                  artists.contains { !self.artistKeys($0).isDisjoint(with: self.artistKeys(component)) }
              }) else { return nil }
        var score = 100.0
        if queryDuration.isFinite, queryDuration > 0 {
            guard let duration, duration.isFinite, duration > 0 else { return nil }
            let delta = abs(duration - queryDuration)
            guard delta <= max(4, min(12, queryDuration * 0.03)) else { return nil }
            score -= delta
        }
        if let album, let queryAlbum, self.normalized(album) == self.normalized(queryAlbum) { score += 2 }
        return score
    }
}
