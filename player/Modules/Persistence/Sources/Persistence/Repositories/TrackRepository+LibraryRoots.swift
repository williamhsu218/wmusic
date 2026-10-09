import Foundation
import GRDB

extension TrackRepository {
    /// Fetches active tracks belonging to a registered music folder or file.
    /// Root IDs resolve to existing paths: older libraries do not persist a
    /// per-track root foreign key, and nested roots intentionally share songs.
    public func fetchAll(libraryRootID: Int64, query: String = "") async throws -> [Track] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await self.database.read { db in
            guard let root = try LibraryRoot.fetchOne(db, key: libraryRootID) else {
                throw PersistenceError.notFound(entity: "library_roots", id: libraryRootID)
            }
            let rootURLs = Self.sourceURLVariants(root.path)
            let predicate = rootURLs.map { _ in
                "(file_url = ? OR substr(file_url, 1, length(?)) = ?)"
            }.joined(separator: " OR ")
            let arguments = rootURLs.flatMap { url in
                let prefix = url.hasSuffix("/") ? url : url + "/"
                return [url, prefix, prefix]
            }
            // Exact substr equality respects case and treats %, _ and other
            // characters literally while excluding similarly named siblings.
            var request = Track
                .filter(Column("disabled") == false)
                .filter(sql: predicate, arguments: StatementArguments(arguments))
            if !trimmed.isEmpty {
                request = request.filter(
                    sql: "id IN (SELECT rowid FROM tracks_fts WHERE tracks_fts MATCH ?)",
                    arguments: [SQL.escapeFTSTerm(trimmed)]
                )
            }
            return try request.order(Column("added_at").desc).fetchAll(db)
        }
    }

    private static func sourceURLVariants(_ path: String) -> Set<String> {
        var paths: Set<String> = [path]
        // Bookmarks and FSEvents can use the /private form of these standard
        // macOS aliases. Derive both lexically; browsing the saved index must
        // never stat, mount, or resolve symlinks on an unavailable NAS.
        let aliases = [("/var", "/private/var"), ("/tmp", "/private/tmp"), ("/etc", "/private/etc")]
        for (alias, canonical) in aliases {
            if path == alias || path.hasPrefix(alias + "/") {
                paths.insert(canonical + path.dropFirst(alias.count))
            } else if path == canonical || path.hasPrefix(canonical + "/") {
                paths.insert(alias + path.dropFirst(canonical.count))
            }
        }
        // Normalize before URI encoding, where accents become ASCII escapes.
        return Set(paths.flatMap { path in
            [path, path.precomposedStringWithCanonicalMapping, path.decomposedStringWithCanonicalMapping]
                .map { URL(fileURLWithPath: $0, isDirectory: false).absoluteString }
        })
    }
}
