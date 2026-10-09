import AppKit
import Playback
import SwiftUI

// MARK: - QueueView

/// Shows the current playback queue with drag-to-reorder and context menu.
public struct QueueView: View {
    @ObservedObject public var vm: LibraryViewModel
    /// Immersive Mode (ADR-089) drops the genre column so the narrower card
    /// keeps the title and artist readable.
    public var showsGenre: Bool
    /// Larger rows and clearer current/next labels for the full-window player.
    /// The library and Immersive queue keep their existing compact rows.
    public var prominentRows: Bool
    /// The expanded Now Playing view closes before opening the editor.
    /// Other queue surfaces use the root window's normal editor presenter.
    public var onGetInfo: ((Int64) -> Void)?
    /// Called before a context-menu action navigates away from the queue.
    public var onNavigate: (() -> Void)?

    public init(
        vm: LibraryViewModel,
        showsGenre: Bool = true,
        prominentRows: Bool = false,
        onGetInfo: ((Int64) -> Void)? = nil,
        onNavigate: (() -> Void)? = nil
    ) {
        self.vm = vm
        self.showsGenre = showsGenre
        self.prominentRows = prominentRows
        self.onGetInfo = onGetInfo
        self.onNavigate = onNavigate
    }

    public var body: some View {
        QueueContentView(
            vm: self.vm,
            showsGenre: self.showsGenre,
            prominentRows: self.prominentRows,
            onGetInfo: self.onGetInfo,
            onNavigate: self.onNavigate
        )
    }
}

// MARK: - QueueContentView

/// Inner view that observes queue state via the `QueuePlayer`.
private struct QueueContentView: View {
    private struct QueueSnapshot {
        var items: [QueueItem] = []
        var currentIndex: Int?
        var unavailableIDs: Set<QueueItem.ID> = []
        var hasLoadedQueue = false
    }

    @ObservedObject var vm: LibraryViewModel
    /// Observed separately so the animated row indicator pauses when playback pauses.
    var nowPlaying: NowPlayingViewModel
    var showsGenre = true
    var prominentRows = false
    var onGetInfo: ((Int64) -> Void)?
    var onNavigate: (() -> Void)?
    @State private var queueSnapshot = QueueSnapshot()
    @State private var refreshGeneration = 0

    private var items: [QueueItem] { self.queueSnapshot.items }
    private var currentIndex: Int? { self.queueSnapshot.currentIndex }
    private var unavailableIDs: Set<QueueItem.ID> { self.queueSnapshot.unavailableIDs }
    private var hasLoadedQueue: Bool { self.queueSnapshot.hasLoadedQueue }

    init(
        vm: LibraryViewModel,
        showsGenre: Bool = true,
        prominentRows: Bool = false,
        onGetInfo: ((Int64) -> Void)? = nil,
        onNavigate: (() -> Void)? = nil
    ) {
        self.vm = vm
        self.nowPlaying = vm.nowPlaying
        self.showsGenre = showsGenre
        self.prominentRows = prominentRows
        self.onGetInfo = onGetInfo
        self.onNavigate = onNavigate
    }

    /// The slice of the queue shown in Up Next: the now-playing track followed by
    /// everything queued after it. Tracks *behind* the playhead are reachable via
    /// Previous and are intentionally hidden so the current track is pinned to the
    /// top. Each entry keeps its absolute queue index so the row actions (play
    /// from here, reorder, remove) keep operating on real queue positions. Falls
    /// back to the whole queue when nothing is currently playing.
    private var upcoming: [UpNextEntry] {
        let start = self.currentIndex.flatMap { self.items.indices.contains($0) ? $0 : nil } ?? 0
        let nextSlot = (self.currentIndex ?? -1) + 1
        return (start ..< self.items.count).map { idx in
            let item = self.items[idx]
            return UpNextEntry(
                index: idx,
                item: item,
                isCurrent: idx == self.currentIndex,
                isUnavailable: self.unavailableIDs.contains(item.id),
                isAlreadyNext: idx == nextSlot,
                albumName: item.albumID.flatMap { self.vm.tracks.albumNames[$0] }
            )
        }
    }

    var body: some View {
        Group {
            if !self.prominentRows, self.items.isEmpty {
                self.emptyQueueState
            } else {
                // The expanded player keeps this List mounted as the queue loads
                // or becomes empty. Replacing a List while a window is being
                // resized can make SwiftUI dismantle its backing outline view
                // during AppKit's live-resize row update.
                List {
                    ForEach(self.upcoming) { entry in
                        QueueRow(
                            item: entry.item,
                            albumName: entry.albumName,
                            isCurrent: entry.isCurrent,
                            isPlaying: self.nowPlaying.isPlaying,
                            isUnavailable: entry.isUnavailable,
                            isAlreadyNext: entry.isAlreadyNext,
                            position: entry.index,
                            showsGenre: self.showsGenre,
                            prominentRows: self.prominentRows
                        )
                        .listRowBackground(entry.isCurrent ? Color.accentColor.opacity(0.15) : Color.clear)
                        .contextMenu {
                            Button(L10n.string("Play From Here")) {
                                Task {
                                    await self.vm.playFromQueueIndex(entry.index)
                                    await self.refreshQueue()
                                }
                            }
                            .disabled(entry.isCurrent || entry.isUnavailable)

                            Divider()

                            Button(L10n.string("Play Next")) {
                                Task {
                                    await self.vm.playQueueItemNext(id: entry.item.id)
                                    await self.refreshQueue()
                                }
                            }
                            .disabled(entry.isCurrent || entry.isAlreadyNext)

                            Button(L10n.string("Move to Bottom")) {
                                Task {
                                    await self.vm.moveQueueItemToBottom(id: entry.item.id)
                                    await self.refreshQueue()
                                }
                            }
                            .disabled(entry.index == self.items.count - 1)

                            Divider()

                            Button(L10n.string("Show in Finder")) {
                                if let url = URL(string: entry.item.fileURL) {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            }
                            .disabled(entry.isUnavailable)

                            if entry.item.trackID >= 0 {
                                Button(L10n.string("Get Info")) {
                                    if let onGetInfo = self.onGetInfo {
                                        onGetInfo(entry.item.trackID)
                                    } else {
                                        self.vm.tagEditorTrackIDs = [entry.item.trackID]
                                    }
                                }
                            }

                            if let albumID = entry.item.albumID {
                                Button(L10n.string("Go to Album")) {
                                    self.onNavigate?()
                                    Task { await self.vm.selectDestination(.album(albumID)) }
                                }
                            }

                            if let artistID = entry.item.artistID {
                                Button(L10n.string("Go to Artist")) {
                                    self.onNavigate?()
                                    Task { await self.vm.selectDestination(.artist(artistID)) }
                                }
                            }

                            Divider()

                            Button(L10n.string("Remove from Queue")) {
                                Task {
                                    await self.vm.queuePlayer?.queue.remove(ids: Set([entry.item.id]))
                                    await self.refreshQueue()
                                }
                            }
                        }
                        // Double-click row → play from this item. Mirrors the
                        // accessibilityHint on QueueRow so VoiceOver and pointer
                        // users get the same primary action. Skipped when the
                        // file is missing so we don't no-op silently.
                        .onTapGesture(count: 2) {
                            guard !entry.isUnavailable else { return }
                            Task {
                                await self.vm.playFromQueueIndex(entry.index)
                                await self.refreshQueue()
                            }
                        }
                    }
                    .onMove { from, to in
                        Task { await self.moveItems(from: from, to: to) }
                    }
                }
                .listStyle(.inset)
                .overlay {
                    if self.prominentRows, self.hasLoadedQueue, self.items.isEmpty {
                        self.emptyQueueState
                    } else if self.prominentRows, self.hasLoadedQueue,
                       self.upcoming.count == 1,
                       self.upcoming.first?.isCurrent == true {
                        VStack(spacing: 9) {
                            Image(systemName: "list.bullet.indent")
                                .font(.title2)
                            Text(L10n.string("Nothing else in the queue"))
                                .font(.headline)
                            Text(L10n.string("Choose another song to keep listening."))
                                .font(.subheadline)
                        }
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 70)
                        .accessibilityElement(children: .combine)
                        .allowsHitTesting(false)
                    }
                }
                // Keep the backing List mounted while loading; reveal the
                // finished queue snapshot without a spinner-to-list swap.
                .opacity(self.prominentRows && !self.hasLoadedQueue ? 0 : 1)
                .animation(
                    self.prominentRows ? .easeOut(duration: 0.2) : nil,
                    value: self.hasLoadedQueue
                )
            }
        }
        .navigationTitle(L10n.string("Up Next"))
        // Accept streamed Subsonic songs dragged in from a server's song list (#332).
        .overlay(SubsonicSongDropTarget { payloads in
            Task {
                await self.vm.addSubsonicSongsToQueue(payloads)
                await self.refreshQueue()
            }
        })
        .task { await self.observeQueueChanges() }
        .task { await self.observeUnavailableChanges() }
    }

    @ViewBuilder
    private var emptyQueueState: some View {
        if self.prominentRows, !self.nowPlaying.title.isEmpty {
            EmptyState(
                symbol: "list.bullet.indent",
                title: L10n.string("Nothing else in the queue"),
                message: L10n.string("Choose another song to keep listening.")
            )
        } else if self.vm.libraryRoots.isEmpty {
            // Fresh install / no music folders configured: mirror the Albums
            // and Artists empty states with an Add-Music-Folder CTA.
            EmptyState(
                symbol: "list.bullet.indent",
                title: L10n.string("Queue is Empty"),
                message: L10n.string("Add a music folder to start building your library."),
                actionLabel: L10n.string("Add Music Folder")
            ) {
                Task { await self.vm.addFolderByPicker() }
            }
        } else {
            EmptyState(
                symbol: "list.bullet.indent",
                title: L10n.string("Queue is Empty"),
                message: L10n.string("Double-click a track, or right-click to add to queue.")
            )
        }
    }

    private func refreshQueue() async {
        self.refreshGeneration &+= 1
        let generation = self.refreshGeneration
        guard let qp = vm.queuePlayer else {
            self.queueSnapshot.hasLoadedQueue = true
            return
        }
        let queue = await qp.queue.snapshot()
        guard generation == self.refreshGeneration else { return }
        // The availability stream owns unavailableIDs. Publish the queue's
        // rows and playhead together, preserving any newer availability event.
        self.queueSnapshot = QueueSnapshot(
            items: queue.items,
            currentIndex: queue.currentIndex,
            unavailableIDs: self.queueSnapshot.unavailableIDs,
            hasLoadedQueue: true
        )
    }

    private func observeQueueChanges() async {
        guard let queue = vm.queuePlayer?.queue else { return }
        let changes = await queue.changes()
        await self.refreshQueue()
        for await _ in changes {
            await self.refreshQueue()
        }
    }

    private func observeUnavailableChanges() async {
        guard let qp = vm.queuePlayer else { return }
        for await ids in await qp.unavailableItemUpdates() {
            self.queueSnapshot.unavailableIDs = ids
        }
    }

    private func moveItems(from source: IndexSet, to destination: Int) async {
        guard let queue = vm.queuePlayer?.queue else { return }
        // Up Next shows a contiguous slice starting at the playhead, so map the
        // slice-relative move offsets back onto absolute queue positions.
        let start = self.upcoming.first?.index ?? 0
        var newItems = self.items
        guard source.allSatisfy({ newItems.indices.contains($0 + start) }),
              (0...newItems.count).contains(destination + start) else { return }
        newItems.move(fromOffsets: IndexSet(source.map { $0 + start }), toOffset: destination + start)
        // Preserve the playing item and the source order held behind shuffle.
        await queue.reorder(to: newItems)
        await self.refreshQueue()
    }
}

// MARK: - UpNextEntry

/// One row in the Up Next list: a queue item plus its absolute queue index and
/// the derived flags the row and its context menu need. Carrying the absolute
/// index lets the view render only the current-and-after slice while still
/// driving actions (play-from, reorder, remove) against real queue positions.
private struct UpNextEntry: Identifiable {
    let index: Int
    let item: QueueItem
    let isCurrent: Bool
    let isUnavailable: Bool
    let isAlreadyNext: Bool
    let albumName: String?
    var id: QueueItem.ID {
        self.item.id
    }
}

// MARK: - QueueRow

private struct QueueRow: View {
    let item: QueueItem
    let albumName: String?
    let isCurrent: Bool
    let isPlaying: Bool
    let isUnavailable: Bool
    let isAlreadyNext: Bool
    let position: Int
    var showsGenre = true
    var prominentRows = false
    @State private var isHovered = false

    /// Best-effort display title: metadata title → decoded filename stem → raw last path component.
    private var displayTitle: String {
        if let t = item.title, !t.isEmpty {
            return t
        }
        let raw = self.item.fileURL.split(separator: "/").last.map(String.init) ?? self.item.fileURL
        return raw.removingPercentEncoding.map { url in
            // Strip extension for cleaner display.
            if let dot = url.lastIndex(of: ".") {
                return String(url[url.startIndex ..< dot])
            }
            return url
        } ?? raw
    }

    private var displaySubtitle: String? {
        let parts = [item.artistName, self.albumName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }

    var body: some View {
        HStack(spacing: 0) {
            // Playing indicator — animated bars for the current track, warning glyph for
            // unavailable rows. Opacity-hidden otherwise; always hidden from VoiceOver.
            Group {
                if self.isUnavailable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                } else {
                    PlayingBarsIndicator(isPlaying: self.isPlaying)
                }
            }
            .frame(width: 20)
            .opacity((self.isCurrent || self.isUnavailable) ? 1 : 0)
            .accessibilityHidden(true)

            // Title + artist/album
            VStack(alignment: .leading, spacing: self.prominentRows ? 4 : 1) {
                if self.prominentRows, self.isCurrent || self.isAlreadyNext {
                    Text(self.isCurrent ? L10n.string("Now Playing") : L10n.string("Up Next"))
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.textSecondary)
                }
                Text(self.titleWithSuffix)
                    .font(self.prominentRows
                        ? .system(size: 16, weight: self.isCurrent ? .semibold : .medium)
                        : (self.isCurrent ? Typography.body.weight(.semibold) : Typography.body))
                    .foregroundStyle(self.titleColor)
                    .lineLimit(self.prominentRows ? 2 : 1)
                if let subtitle = self.displaySubtitle {
                    Text(subtitle)
                        .font(self.prominentRows ? .subheadline : Typography.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(self.prominentRows ? 2 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)

            // Genre
            if !self.showsGenre {
                Spacer().frame(width: 8)
            } else if let genre = item.genre, !genre.isEmpty {
                Text(genre)
                    .font(Typography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .frame(width: 80, alignment: .leading)
            } else {
                Spacer().frame(width: 80)
            }

            // Duration
            Text(Formatters.duration(self.item.duration))
                .font(Typography.caption.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: 44, alignment: .trailing)

            // Drag-reorder grip — revealed on hover so the row's reorder
            // affordance is discoverable (the whole row is already draggable
            // via the List's .onMove). Space is always reserved so the layout
            // doesn't shift when the grip appears (#313).
            Image(systemName: "line.3.horizontal")
                .font(Typography.caption)
                .foregroundStyle(Color.textTertiary)
                .frame(width: 18)
                .opacity(self.isHovered ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.vertical, self.prominentRows ? 10 : 3)
        .padding(.horizontal, self.prominentRows ? 8 : 0)
        .opacity(self.isUnavailable ? 0.55 : 1.0)
        .help(self.isUnavailable ? L10n.string("File missing — original location no longer exists") : "")
        .onHover { self.isHovered = $0 }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.rowLabel)
        .accessibilityHint(self.isUnavailable
            ? L10n.string("File is missing. Use the context menu to remove it from the queue.")
            : L10n.string(
                "Double-tap to play from this item. Use the context menu to reorder, jump to album or artist, or remove from the queue."
            ))
        .accessibilityAddTraits(self.isCurrent ? .isSelected : [])
    }

    private var titleWithSuffix: String {
        self.isUnavailable ? L10n.string("\(self.displayTitle) (missing)") : self.displayTitle
    }

    private var titleColor: Color {
        if self.isUnavailable {
            return Color.textSecondary
        }
        return self.isCurrent ? Color.accentColor : Color.textPrimary
    }

    private var rowLabel: String {
        var parts = [self.isCurrent ? L10n.string("Now playing: \(self.displayTitle)") : self.displayTitle]
        if self.isUnavailable {
            parts.append(L10n.string("file missing"))
        }
        if let sub = self.displaySubtitle {
            parts.append(sub)
        }
        if let genre = item.genre, !genre.isEmpty {
            parts.append(genre)
        }
        parts.append(Formatters.duration(self.item.duration))
        return parts.joined(separator: ", ")
    }
}
