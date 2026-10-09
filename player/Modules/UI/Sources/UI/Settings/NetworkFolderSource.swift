import Foundation
import Library
import Persistence

/// Uses values embedded in the bookmark so opening Sources never contacts or
/// mounts an offline NAS. Availability is the result of the most recent scan.
public struct NetworkFolderSource: Identifiable, Sendable {
    public let root: LibraryRoot
    public let address: NetworkShareAddress
    public let id: Int64

    public init?(root: LibraryRoot) {
        guard let id = root.id,
              let values = URL.resourceValues(
                  forKeys: [.volumeURLForRemountingKey], fromBookmarkData: root.bookmark
              ),
              let url = values.volumeURLForRemounting,
              let address = NetworkShareAddress.sanitized(url) else { return nil }
        self.root = root
        self.address = address
        self.id = id
    }

    public var name: String { URL(fileURLWithPath: self.root.path).lastPathComponent }
}
