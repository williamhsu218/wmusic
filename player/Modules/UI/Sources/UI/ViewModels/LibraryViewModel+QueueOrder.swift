import Foundation
import Persistence
import Playback

// MARK: - LibraryViewModel + legacy queue order

extension LibraryViewModel {
    /// Sorting must reuse queue-local identities, including separate occurrences
    /// of the same track. Refuse a different browse context instead of rebuilding
    /// the queue from a subset or dropping a repeated user-enqueued item.
    nonisolated static func queueItemsInDisplayOrder(
        tracks: [Track], sourceItems: [QueueItem], activeIDs: Set<QueueItem.ID>
    ) -> [QueueItem]? {
        guard tracks.count == sourceItems.count,
              Set(sourceItems.map(\.id)).count == sourceItems.count,
              activeIDs.isSubset(of: Set(sourceItems.map(\.id))),
              sourceItems.allSatisfy({ item in
                  if case .localBookmark = item.playableSource { return true }
                  return false
              }) else { return nil }

        let byTrackID = Dictionary(grouping: sourceItems, by: \.trackID)
        var usedOccurrences: [Int64: Int] = [:]
        var ordered: [QueueItem] = []
        ordered.reserveCapacity(sourceItems.count)
        for track in tracks {
            guard let trackID = track.id,
                  let occurrences = byTrackID[trackID] else { return nil }
            let offset = usedOccurrences[trackID, default: 0]
            guard occurrences.indices.contains(offset) else { return nil }
            let item = occurrences[offset]
            usedOccurrences[trackID] = offset + 1
            if activeIDs.contains(item.id) {
                ordered.append(item)
            }
        }
        guard ordered.count == activeIDs.count else { return nil }
        return ordered
    }

    /// Old queue blobs stored only the playing order. Recover the visible Songs
    /// order only for an exact, unambiguous match; a playlist, a filtered subset,
    /// duplicate tracks or remote items must retain their existing queue.
    func resolveLegacyQueueOrder(items: [QueueItem], currentIndex: Int?) -> [QueueItem.ID]? {
        guard self.selectedDestination == .songs,
              !self.tracks.isLoading,
              !items.isEmpty,
              let currentIndex,
              items.indices.contains(currentIndex),
              items.allSatisfy({ item in
                  guard case .localBookmark = item.playableSource else { return false }
                  return item.trackID >= 0 && URL(string: item.fileURL)?.isFileURL == true
              }) else { return nil }

        let visibleIDs = self.tracks.tracks.compactMap(\.id)
        let queueTrackIDs = items.map(\.trackID)
        guard visibleIDs.count == self.tracks.tracks.count,
              Set(visibleIDs).count == visibleIDs.count,
              Set(queueTrackIDs).count == queueTrackIDs.count,
              Set(items.map(\.id)).count == items.count,
              Set(visibleIDs) == Set(queueTrackIDs) else { return nil }

        let itemsByTrackID = Dictionary(uniqueKeysWithValues: items.map { ($0.trackID, $0.id) })
        return visibleIDs.compactMap { itemsByTrackID[$0] }
    }
}
