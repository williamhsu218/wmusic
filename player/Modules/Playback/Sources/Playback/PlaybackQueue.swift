import Foundation
import Observability

// MARK: - PlaybackQueue

/// Actor that owns and manages the playback queue.
///
/// All mutating operations are serialised by actor isolation.
/// The `changes` stream emits incremental `QueueChange` events to UI consumers.
///
/// **Invariants maintained at all times:**
/// - `currentIndex` is `nil` or in `0..<items.count`.
/// - `history` is bounded to `historyLimit` items (oldest dropped first).
/// - Bulk operations (append 5k items) complete in < 50ms.
public actor PlaybackQueue {
    // MARK: - Types

    private static let historyLimit = 256

    // MARK: - State

    public private(set) var items: [QueueItem] = []
    public private(set) var history: [QueueItem] = []
    public private(set) var currentIndex: Int?
    public private(set) var repeatMode: RepeatMode = .off
    public private(set) var shuffleState: ShuffleState = .off
    public private(set) var stopAfterCurrent = false

    /// Read the rows and playhead in one actor turn so a queue mutation
    /// cannot leave the UI with a position from a different item array.
    public func snapshot() -> (items: [QueueItem], currentIndex: Int?) {
        (self.items, self.currentIndex)
    }

    /// The original (un-shuffled) source order, used to restore on shuffle-off.
    private var sourceOrder: [QueueItem] = []
    public private(set) var hasKnownSourceOrder = true

    /// Capture all persisted queue state together, including a known original order.
    public func persistenceSnapshot() -> (
        items: [QueueItem], currentIndex: Int?, repeatMode: RepeatMode,
        shuffleState: ShuffleState, sourceItems: [QueueItem]?
    ) {
        (self.items, self.currentIndex, self.repeatMode, self.shuffleState,
         self.hasKnownSourceOrder ? self.sourceOrder : nil)
    }

    // MARK: - Change stream

    /// Per-subscriber continuations: a single shared AsyncStream races between consumers.
    private var subscribers: [UUID: AsyncStream<QueueChange>.Continuation] = [:]

    /// Subscribe to queue change events. Each call returns an independent stream.
    /// The subscriber is registered synchronously before the stream is returned, so any
    /// emit that occurs after `await queue.changes()` returns is guaranteed to be delivered.
    public func changes() -> AsyncStream<QueueChange> {
        let (stream, continuation) = AsyncStream.makeStream(of: QueueChange.self)
        let id = UUID()
        self.subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeSubscriber(id: id) }
        }
        return stream
    }

    private func removeSubscriber(id: UUID) {
        self.subscribers.removeValue(forKey: id)
    }

    private let log = AppLogger.make(.playback)

    // MARK: - Init

    public init() {}

    // MARK: - Queue mutations

    /// Append items to the end of the queue.
    public func append(_ newItems: [QueueItem]) {
        guard !newItems.isEmpty else { return }
        self.items.append(contentsOf: newItems)
        self.sourceOrder.append(contentsOf: newItems)
        self.emit(.appended(items: newItems))
        self.log.debug("queue.append", ["count": newItems.count, "total": self.items.count])
    }

    /// Insert items to play immediately after the current item (or at position 0 if nothing playing).
    public func appendNext(_ newItems: [QueueItem]) {
        guard !newItems.isEmpty else { return }
        let insertIdx = (currentIndex ?? -1) + 1
        let sourceIdx = self.currentItem.flatMap { current in
            self.sourceOrder.firstIndex { $0.id == current.id }
        }.map { $0 + 1 } ?? 0
        self.items.insert(contentsOf: newItems, at: insertIdx)
        self.sourceOrder.insert(contentsOf: newItems, at: sourceIdx)
        self.emit(.insertedNext(items: newItems))
        self.log.debug("queue.appendNext", ["count": newItems.count])
    }

    /// Insert items at a specific index.
    public func insert(_ newItems: [QueueItem], at index: Int) {
        guard !newItems.isEmpty else { return }
        let clampedIdx = max(0, min(index, items.count))
        let sourceIdx = self.items.indices.contains(clampedIdx)
            ? self.sourceOrder.firstIndex { $0.id == self.items[clampedIdx].id } ?? self.sourceOrder.count
            : self.sourceOrder.count
        self.items.insert(contentsOf: newItems, at: clampedIdx)
        if let ci = currentIndex, clampedIdx <= ci {
            self.currentIndex = ci + newItems.count
        }
        self.sourceOrder.insert(contentsOf: newItems, at: sourceIdx)
        self.emit(.appended(items: newItems))
    }

    /// Remove items by their queue-local IDs.
    /// If the current item is removed, advances to the next surviving item (or stops if none remain).
    public func remove(ids: Set<QueueItem.ID>) {
        guard !ids.isEmpty else { return }
        let removedIDs = Array(ids)

        let oldCurrentIndex = self.currentIndex
        let removingCurrent = oldCurrentIndex.map { ids.contains(self.items[$0].id) } ?? false

        // Only items removed *before* the current position shift the index leftward;
        // removals after it leave the current track exactly where it is.
        let removedBeforeCurrent = oldCurrentIndex.map { ci in
            self.items[..<ci].lazy.count(where: { ids.contains($0.id) })
        } ?? 0

        let originalCount = self.items.count
        self.items.removeAll { ids.contains($0.id) }
        self.sourceOrder.removeAll { ids.contains($0.id) }

        // Recompute currentIndex against the new array.
        var newCurrentIndex = oldCurrentIndex
        if let ci = oldCurrentIndex {
            if self.items.isEmpty {
                newCurrentIndex = nil
            } else if removingCurrent {
                // Current item gone: keep its slot (now the next surviving item),
                // clamped to the last index when it had been at the tail.
                newCurrentIndex = min(ci - removedBeforeCurrent, self.items.count - 1)
            } else {
                // Current item survived: it only shifts by the removals ahead of it.
                newCurrentIndex = ci - removedBeforeCurrent
            }
        }

        let previousIndex = self.currentIndex
        self.currentIndex = newCurrentIndex

        self.emit(.removed(ids: removedIDs))
        if previousIndex != self.currentIndex {
            self.emit(.currentChanged(newIndex: self.currentIndex, previousIndex: previousIndex))
        }
        self.log.debug("queue.remove", ["count": originalCount - self.items.count])
    }

    /// Move a single item from one position to another.
    public func move(fromIndex: Int, toIndex: Int) {
        guard fromIndex != toIndex,
              self.items.indices.contains(fromIndex),
              self.items.indices.contains(toIndex) else { return }
        let item = self.items.remove(at: fromIndex)
        self.items.insert(item, at: toIndex)
        if self.shuffleState == .off {
            self.sourceOrder = self.items
        }

        // Adjust currentIndex after the move
        if let ci = currentIndex {
            if ci == fromIndex {
                self.currentIndex = toIndex
            } else if fromIndex < ci, toIndex >= ci {
                self.currentIndex = ci - 1
            } else if fromIndex > ci, toIndex <= ci {
                self.currentIndex = ci + 1
            }
        }
        self.emit(.moved(fromIndex: fromIndex, toIndex: toIndex))
    }

    /// Clear the entire queue and history.
    public func clear() {
        self.items.removeAll()
        self.sourceOrder.removeAll()
        self.hasKnownSourceOrder = true
        let previous = self.currentIndex
        self.currentIndex = nil
        self.emit(.cleared)
        if previous != nil {
            self.emit(.currentChanged(newIndex: nil, previousIndex: previous))
        }
        self.log.debug("queue.clear")
    }

    /// Replace the entire queue with `newItems`, starting playback at `startAt`.
    public func replace(with newItems: [QueueItem], startAt index: Int = 0) {
        self.items = newItems
        self.sourceOrder = newItems
        self.hasKnownSourceOrder = true
        let newIndex: Int? = newItems.isEmpty ? nil : max(0, min(index, newItems.count - 1))
        self.currentIndex = newIndex
        self.emit(.reset(items: self.items, currentIndex: self.currentIndex))
        self.log.debug("queue.replace", ["count": newItems.count, "startAt": index])
    }

    /// Reorder the queue to match `newItems` while keeping the currently-playing
    /// track at the correct position.  If the current track isn't in the new list,
    /// currentIndex is set to 0.  Does nothing if the queue is empty.
    public func reorder(to newItems: [QueueItem]) {
        guard !newItems.isEmpty else { return }
        let current = self.currentItem
        self.items = newItems
        if self.shuffleState == .off {
            self.sourceOrder = newItems
        }
        if let current,
           let idx = newItems.firstIndex(where: { $0.id == current.id }) {
            self.currentIndex = idx
        } else {
            self.currentIndex = 0
        }
        self.emit(.reset(items: self.items, currentIndex: self.currentIndex))
        self.log.debug("queue.reorder", ["count": newItems.count])
    }

    /// Restore an already ordered queue without running shuffle a second time.
    public func restore(
        items: [QueueItem], currentIndex: Int?, repeatMode: RepeatMode,
        shuffleState: ShuffleState, sourceItems: [QueueItem]?
    ) {
        self.items = items
        self.currentIndex = currentIndex.flatMap { items.indices.contains($0) ? $0 : nil }
        self.repeatMode = repeatMode
        self.shuffleState = shuffleState
        if let sourceItems,
           Set(sourceItems.map(\.id)).count == sourceItems.count,
           Set(items.map(\.id)).isSubset(of: Set(sourceItems.map(\.id))) {
            self.sourceOrder = sourceItems
            self.hasKnownSourceOrder = true
        } else {
            self.sourceOrder = items
            self.hasKnownSourceOrder = false
        }
        self.emit(.repeatChanged(repeatMode))
        self.emit(.shuffleChanged(shuffleState))
        self.emit(.reset(items: self.items, currentIndex: self.currentIndex))
    }

    /// Recover a legacy baseline only by reordering the exact existing queue IDs.
    /// The current shuffled play order and playing item remain untouched.
    @discardableResult
    public func rebaseSourceOrder(_ orderedIDs: [QueueItem.ID]) -> Bool {
        guard !self.hasKnownSourceOrder,
              orderedIDs.count == self.sourceOrder.count,
              Set(orderedIDs).count == orderedIDs.count,
              Set(orderedIDs) == Set(self.sourceOrder.map(\.id)) else { return false }
        let byID = Dictionary(uniqueKeysWithValues: self.sourceOrder.map { ($0.id, $0) })
        self.sourceOrder = orderedIDs.compactMap { byID[$0] }
        self.hasKnownSourceOrder = true
        self.emit(.reset(items: self.items, currentIndex: self.currentIndex))
        return true
    }

    // MARK: - Navigation

    /// Move the current position to `index` without replacing items.
    /// Used to restart a exhausted queue from the beginning.
    public func seekToIndex(_ index: Int) {
        guard self.items.indices.contains(index) else { return }
        let prev = self.currentIndex
        self.currentIndex = index
        self.emit(.currentChanged(newIndex: index, previousIndex: prev))
        self.log.debug("queue.seekToIndex", ["index": index])
    }

    /// Advance to the next item according to repeatMode, returning it or nil if stopped.
    public func advance() -> QueueItem? {
        switch self.repeatMode {
        case .one:
            // Don't advance — caller repeats the current item
            return self.currentItem

        case .all:
            guard !self.items.isEmpty else { return nil }
            let next = ((currentIndex ?? -1) + 1) % self.items.count
            return self.advance(to: next)

        case .off:
            // When currentIndex is nil the queue is already exhausted; don't wrap.
            guard let ci = currentIndex else { return nil }
            let next = ci + 1
            guard next < self.items.count else {
                let prev = self.currentIndex
                self.currentIndex = nil
                self.emit(.currentChanged(newIndex: nil, previousIndex: prev))
                return nil
            }
            return self.advance(to: next)
        }
    }

    /// Follow the item the engine has already made audible. A shuffle toggle
    /// can reorder the queue after a handover has passed its cancellation point.
    public func advanceToItem(id: QueueItem.ID) -> QueueItem? {
        if let index = self.items.firstIndex(where: { $0.id == id }) {
            return self.advance(to: index)
        }
        // A shuffle toggle may hide an excluded item whose boundary already
        // started. Keep that audible item while retaining the original baseline.
        guard let item = self.sourceOrder.first(where: { $0.id == id }) else { return nil }
        let index = (self.currentIndex ?? -1) + 1
        self.items.insert(item, at: index)
        self.emit(.insertedNext(items: [item]))
        return self.advance(to: index)
    }

    /// Advance as if the user pressed Next manually.
    ///
    /// Differs from `advance()` in that `repeatMode == .one` is treated as `.all`:
    /// repeat-one only governs automatic end-of-track advance, not explicit user
    /// skips.  This matches standard transport-bar UX (Apple Music, Spotify, etc.).
    public func advanceManual() -> QueueItem? {
        switch self.repeatMode {
        case .one, .all:
            guard !self.items.isEmpty else { return nil }
            let next = ((currentIndex ?? -1) + 1) % self.items.count
            return self.advance(to: next)

        case .off:
            guard let ci = currentIndex else { return nil }
            let next = ci + 1
            guard next < self.items.count else {
                let prev = self.currentIndex
                self.currentIndex = nil
                self.emit(.currentChanged(newIndex: nil, previousIndex: prev))
                return nil
            }
            return self.advance(to: next)
        }
    }

    /// Navigate backwards. If near the start of the current item, go to previous; otherwise stays.
    public func retreat() -> QueueItem? {
        // Pop from history if available, otherwise go to start of current
        if !self.history.isEmpty {
            let prev = self.history.removeLast()
            // Find prev in items and set as current
            if let idx = items.firstIndex(where: { $0.id == prev.id }) {
                let previousIndex = self.currentIndex
                self.currentIndex = idx
                self.emit(.currentChanged(newIndex: idx, previousIndex: previousIndex))
                self.log.debug("queue.retreat", ["to": idx])
                return self.items[idx]
            }
        }
        // No history — go to previous index
        let targetIdx = (currentIndex ?? 1) - 1
        guard targetIdx >= 0, targetIdx < self.items.count else {
            return self.currentItem
        }
        return self.advance(to: targetIdx)
    }

    /// Peek at the item that would play after the current one (without advancing).
    public func peekNext() -> QueueItem? {
        switch self.repeatMode {
        case .one:
            return self.currentItem
        case .all:
            guard !self.items.isEmpty else { return nil }
            let next = ((currentIndex ?? -1) + 1) % self.items.count
            return self.items[next]
        case .off:
            let next = (currentIndex ?? -1) + 1
            return next < self.items.count ? self.items[next] : nil
        }
    }

    /// Like `peekNext()` but treats `.one` the same as `.off` — never returns
    /// the current item. Used by the missing-file skip logic so repeat-one mode
    /// advances past an unloadable track instead of re-queuing it.
    public func peekNextIgnoringRepeatOne() -> QueueItem? {
        let next = (currentIndex ?? -1) + 1
        switch self.repeatMode {
        case .one, .off:
            return next < self.items.count ? self.items[next] : nil
        case .all:
            guard !self.items.isEmpty else { return nil }
            return self.items[next % self.items.count]
        }
    }

    /// The currently playing item, or `nil` if nothing is loaded.
    public var currentItem: QueueItem? {
        self.currentIndex.map { self.items[$0] }
    }

    // MARK: - Repeat / shuffle

    public func setRepeatMode(_ mode: RepeatMode) {
        self.repeatMode = mode
        self.emit(.repeatChanged(mode))
        self.log.debug("queue.repeat", ["mode": mode.rawValue])
    }

    public func setStopAfterCurrent(_ enabled: Bool) {
        self.stopAfterCurrent = enabled
        self.emit(.stopAfterCurrentChanged(enabled))
        self.log.debug("queue.stopAfterCurrent", ["enabled": enabled])
    }

    /// Enable or disable shuffle.
    /// When enabling: shuffles using `seed`, preserving current item at front.
    /// When disabling: restores the original source order starting from the current item.
    public func setShuffle(
        _ on: Bool, seed: UInt64 = UInt64.random(in: .min ... .max),
        preservingCurrent: Bool = true
    ) {
        if on {
            self.shuffleState = .on(seed: seed)
            let strategy = FisherYatesShuffle()
            let current = preservingCurrent ? self.currentItem : nil

            // Exclude excluded tracks and shuffle the rest; current item stays first
            var toShuffle = self.sourceOrder.filter { !$0.excludedFromShuffle }
            // Explicit album/artist playback still works when all tracks are excluded.
            if !preservingCurrent, toShuffle.isEmpty {
                toShuffle = self.sourceOrder
            }
            if let cur = current {
                toShuffle.removeAll { $0.id == cur.id }
            }
            var shuffled = strategy.shuffled(toShuffle, seed: seed)
            if let cur = current {
                shuffled.insert(cur, at: 0)
            }

            self.items = shuffled
            self.currentIndex = shuffled.isEmpty ? nil : 0
        } else {
            self.shuffleState = .off
            // Restore source order, keeping current item as the active index
            let current = self.currentItem
            self.items = self.sourceOrder
            if let cur = current, let idx = items.firstIndex(where: { $0.id == cur.id }) {
                self.currentIndex = idx
            } else {
                self.currentIndex = nil
            }
        }
        self.emit(.shuffleChanged(self.shuffleState))
        self.emit(.reset(items: self.items, currentIndex: self.currentIndex))
        self.log.debug("queue.shuffle", ["on": on])
    }

    // MARK: - Private helpers

    private func advance(to index: Int) -> QueueItem? {
        guard self.items.indices.contains(index) else { return nil }

        // Push current to history
        if let ci = currentIndex {
            self.pushHistory(self.items[ci])
        }

        let previousIndex = self.currentIndex
        self.currentIndex = index
        self.emit(.currentChanged(newIndex: index, previousIndex: previousIndex))
        self.log.debug("queue.advance", ["to": index])
        return self.items[index]
    }

    private func pushHistory(_ item: QueueItem) {
        self.history.append(item)
        if self.history.count > Self.historyLimit {
            self.history.removeFirst()
        }
    }

    private func emit(_ change: QueueChange) {
        for continuation in self.subscribers.values {
            continuation.yield(change)
        }
    }
}
