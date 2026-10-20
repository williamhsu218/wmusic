import Acoustics
import Library
import Observability
import Scrobble
import SwiftUI
import UniformTypeIdentifiers

// MARK: - BocanRootView

/// The top-level view for the app window.
///
/// Composes a `NavigationSplitView` (sidebar | content) with a
/// `NowPlayingStrip` overlay at the bottom.  The optional detail column
/// is reserved for `AlbumDetailView` and `ArtistDetailView` — those are
/// pushed via `NavigationLink` rather than swapped here to avoid macOS
/// bugs with dynamic detail swapping.
///
/// `LibraryViewModel` is injected by the app and also placed in the
/// environment so deeply nested views can reach it directly.
public struct BocanRootView: View {
    @StateObject private var vm: LibraryViewModel
    /// Plain reference (not @ObservedObject): the root only hands the model
    /// to the lyrics pane, the playback driver and the environment. Observing
    /// it re-ran this whole body, and every child that could not prove itself
    /// unchanged, on each synced lyric line (#456). The pane toggle reads the
    /// same preference key through `lyricsPaneVisible` below.
    private let startupScanDefaults: UserDefaults
    private let lyricsVM: LyricsViewModel
    @ObservedObject private var visualizerVM: VisualizerViewModel
    /// Plain reference (not @ObservedObject) so `BocanRootView` skips
    /// scrobble-settings re-renders; only `RecentScrobblesView` subscribes.
    private let scrobbleSettingsVM: ScrobbleSettingsViewModel?
    @EnvironmentObject private var windowMode: WindowModeController
    @FocusState private var searchFocused: Bool
    /// Restored on sheet close so keyboard focus is never stranded.
    @FocusState private var mainContentFocused: Bool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var tagEditorVM: TagEditorViewModel?
    @State private var identifyVM: IdentifyTrackViewModel?
    @State private var batchCoverArtVM: BatchCoverArtViewModel?
    @State private var duplicateReviewVM: DuplicateReviewViewModel?
    /// Per-window state: the main browser stays mounted behind its player.
    @AppStorage("ui.inspector.selection") private var inspectorSelection = "lyrics"
    @State private var showExpandedNowPlaying = false
    @State private var expandedPrewarmed = false
    @State private var expandedTransitionGeneration = 0
    @State private var browserInputBlocked = false
    @State private var pendingExpandedInfoTrackID: Int64?
    @State private var pendingSearchFocus = false
    @AppStorage("appearance.colorScheme") private var colorSchemeKey = "system"
    @AppStorage("appearance.accentColor") private var accentColorKey = "system"
    /// Observed so the FSEvents watcher follows the Settings toggle live (M8).
    @AppStorage("library.watchForChanges") private var watchForChanges = true
    /// Show the first-launch consent banner until the user responds (issue #209).
    @AppStorage(MetricKitListener.consentAskedKey) private var diagnosticsConsentAsked = false
    /// Show the crash-recovery banner when the previous session ended abnormally (issue #208).
    @AppStorage("launch.didCrashPreviously") private var didCrashPreviously = false
    /// Mirrors whether the Immersive Mode window is open (ADR-089); the
    /// window content keeps it current. Read for the toolbar label and to
    /// reopen the window after bootstrap when it was left open.
    @AppStorage(ImmersiveView.preferenceKey) private var immersiveOpen = false
    /// Mirrors `LyricsViewModel.paneVisible` (`@AppStorage("lyrics.paneVisible")`)
    /// for the toolbar toggle, the same way the View menu does, so the root
    /// re-renders when the pane opens or closes and not when a lyric line
    /// changes (#456). Both sides read and write one UserDefaults key.
    @AppStorage("lyrics.paneVisible") private var lyricsPaneVisible = false
    @AppStorage("lyrics.paneWidth") private var inspectorWidth: Double = 340
    @AppStorage("visualizer.paneVisible") private var visualizerVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        vm: LibraryViewModel,
        lyricsVM: LyricsViewModel,
        visualizerVM: VisualizerViewModel,
        scrobbleSettingsVM: ScrobbleSettingsViewModel? = nil,
        startupScanDefaults: UserDefaults = .standard
    ) {
        _vm = StateObject(wrappedValue: vm)
        self.lyricsVM = lyricsVM
        self.visualizerVM = visualizerVM
        self.scrobbleSettingsVM = scrobbleSettingsVM
        self.startupScanDefaults = startupScanDefaults
    }

    /// `true` once any music source exists (local folder or Subsonic server,
    /// hidden included). Holds the diagnostics consent banner back until the
    /// first-launch "Add Music" call to action is satisfied (issue #310).
    private var libraryHasContent: Bool {
        !self.vm.libraryRoots.isEmpty
            || !self.vm.subsonicServers.isEmpty
            || !self.vm.hiddenSubsonicServers.isEmpty
    }

    /// `true` while any modal sheet is presented over the main window.
    private var anySheetOpen: Bool {
        self.tagEditorVM != nil
            || self.identifyVM != nil
            || self.vm.isPlaylistImportSheetPresented
            || self.vm.playlistExportRequest != nil
            || self.vm.isBatchCoverArtSheetPresented
            || self.vm.isDuplicateReviewSheetPresented
    }

    /// Main window chrome, split from `body` to keep the modifier chain
    /// within the Swift type-checker's limits.
    private var windowContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                NavigationSplitView {
                    Sidebar(vm: self.vm)
                } detail: {
                    ContentPane(vm: self.vm)
                }

                if self.visualizerVisible || self.lyricsPaneVisible {
                    self.playbackInspector
                        .frame(width: min(420, max(300, self.inspectorWidth)))
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .leading) {
                            PlaybackPanelResizeHandle(width: self.$inspectorWidth)
                        }
                }
            }
            NowPlayingStrip(
                vm: self.vm.nowPlaying,
                scrobbleSettingsVM: self.scrobbleSettingsVM,
                openExpandedNowPlaying: { self.setExpandedNowPlaying(true) },
                prewarmExpandedNowPlaying: { self.prewarmExpandedNowPlaying() }
            )
            .environmentObject(self.visualizerVM)
        }
        // Routed: the library query everywhere, History's own query
        // on History (ADR-094 slice 2).
        .searchable(text: self.$vm.searchText, placement: .toolbar, prompt: Text(localized: "Search"))
        .searchFocused(self.$searchFocused)
        .toolbar {
            MainToolbarItems(
                vm: self.vm,
                miniPlayerOpen: self.windowMode.miniPlayerOpen,
                toggleMiniPlayer: { self.windowMode.toggleMiniPlayer() },
                lyricsPaneVisible: self.$lyricsPaneVisible,
                visualizerPaneVisible: self.$visualizerVisible,
                immersiveOpen: self.immersiveOpen,
                toggleImmersive: {
                    if self.immersiveOpen {
                        self.dismissWindow(id: ImmersiveWindowView.windowID)
                    } else {
                        self.openWindow(id: ImmersiveWindowView.windowID)
                    }
                },
                reduceMotion: self.reduceMotion
            )
        }
        // AppStorage on a model is not a View invalidation source. Observe
        // pane routing here too, then publish the model change for its host.
        .onChange(of: self.visualizerVisible, initial: true) { _, visible in
            self.visualizerVM.objectWillChange.send()
            self.visualizerVM.paneVisible = visible
        }
        .modifier(LyricsPlaybackDriver(lyricsVM: self.lyricsVM, nowPlaying: self.vm.nowPlaying))
        .safeAreaInset(edge: .top, spacing: 0) {
            if self.didCrashPreviously {
                CrashRecoveryBanner()
            } else if !self.diagnosticsConsentAsked, self.libraryHasContent {
                DiagnosticsConsentBanner()
            }
        }
        .environmentObject(self.vm)
        .environment(\.lyricsViewModel, self.lyricsVM)
        .task {
            // Wire window openers before any UI loads.
            let ow = self.openWindow
            let dw = self.dismissWindow
            self.windowMode.openWindow = { id in ow(id: id) }
            self.windowMode.dismissWindow = { id in dw(id: id) }
            // Load the playlist sidebar BEFORE restoring UI state so that a
            // saved .folder destination doesn't briefly show "Folder Not Found"
            // while playlistSidebar.nodes is still empty. Per-phase timing comes
            // from Telemetry.timer signposts inside the called methods.
            await self.vm.playlistSidebar.reload()
            // Bootstrap Subsonic clients before restoring navigation state.
            // This ensures that any persisted Subsonic destination (e.g.
            // .subsonicSongs) can load immediately without racing against the
            // background hydration task that calls reloadClients() in BocanApp.
            await self.vm.bootstrapSubsonic()
            await self.vm.restoreUIState()
            self.windowMode.restoreIfNeeded()
            // Immersive Mode left open last time reopens after bootstrap
            // (ADR-089), the same point the mini player restores; its scene
            // restoration is disabled so it can never open before this.
            if self.immersiveOpen {
                self.openWindow(id: ImmersiveWindowView.windowID)
            }
            await self.vm.refreshRoots()
            await self.vm.loadCurrentDestination()
            self.prewarmExpandedNowPlaying()
            await self.vm.triggerStartupScanIfNeeded(userDefaults: self.startupScanDefaults)
            await self.vm.startOrStopWatcher()
        }
        .onDisappear {
            Task { await self.vm.saveUIState() }
        }
        .overlay {
            // Drop-target highlight border
            if self.vm.isDragTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: [UTType.fileURL, UTType.folder],
            isTargeted: self.$vm.isDragTargeted
        ) { providers in
            guard !self.browserInputBlocked else { return false }
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    if let url = await Self.loadURL(from: provider) {
                        urls.append(url)
                    }
                }
                if !urls.isEmpty {
                    await self.vm.addDroppedURLs(urls)
                }
            }
            return true
        }
    }

    public var body: some View {
        self.windowContent
            .accessibilityHidden(self.browserInputBlocked)
            // Keep the browser mounted so returning preserves navigation and
            // selection, while the player owns the window's visible controls.
            .toolbarVisibility(self.browserInputBlocked ? .hidden : .visible, for: .windowToolbar)
            .toolbarBackgroundVisibility(self.browserInputBlocked ? .hidden : .automatic, for: .windowToolbar)
            .overlay {
                if self.expandedPrewarmed {
                    ZStack {
                        // Block pointer input until the player has finished fading
                        // out, then restore the browser and its native toolbar.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {}
                            .allowsHitTesting(self.browserInputBlocked)
                            .accessibilityHidden(true)

                        ExpandedNowPlayingView(
                            library: self.vm,
                            lyricsVM: self.lyricsVM,
                            visualizerVM: self.visualizerVM,
                            isPresented: self.showExpandedNowPlaying,
                            onClose: { self.setExpandedNowPlaying(false) },
                            onGetInfo: { trackID in
                                self.pendingExpandedInfoTrackID = trackID
                                self.setExpandedNowPlaying(false)
                            },
                            onNavigate: { self.setExpandedNowPlaying(false) }
                        )
                        .opacity(self.showExpandedNowPlaying ? 1 : 0)
                        .allowsHitTesting(self.showExpandedNowPlaying)
                        .disabled(!self.showExpandedNowPlaying)
                        .accessibilityHidden(!self.showExpandedNowPlaying)
                    }
                }
            }
            .focused(self.$mainContentFocused)
            .frame(minWidth: 900, minHeight: 550)
            // No root .accessibilityIdentifier: an unused "BocanMainWindow" one masked a child's own identifier (ADR-084).
            .background(MainWindowGrabber().frame(width: 0, height: 0).allowsHitTesting(false))
            .background(
                // ADR-005 audit H2: sidebar divider via NSSplitView autosave + a settings fallback.
                SidebarWidthAutosave(initialWidth: self.vm.sidebarWidth) { width in
                    self.vm.sidebarWidth = width
                }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            )
            // Type-to-search (#369): the first printable keypress anywhere in
            // the main window starts a fresh search seeded with it.
            .background(TypeToSearchBackground(vm: self.vm, isSuspended: self.browserInputBlocked))
            .background(NavigationInputBackground(vm: self.vm, isSuspended: self.browserInputBlocked))
            .onChange(of: self.vm.selectedDestination) { _, _ in
                // Menu navigation should reveal the destination it just chose.
                if self.browserInputBlocked {
                    self.setExpandedNowPlaying(false)
                }
            }
            .onChange(of: self.vm.searchFocusRequestID) { _, _ in
                // ADR-005 audit H5: ⌘F (Find) focuses the search field.
                if self.browserInputBlocked {
                    self.pendingSearchFocus = true
                    self.setExpandedNowPlaying(false)
                } else {
                    self.searchFocused = true
                }
            }
            .onChange(of: self.anySheetOpen) { _, isOpen in
                // Keyboard focus phase: return focus to the main content area when
                // any modal sheet closes so Tab / arrow keys remain reachable.
                if isOpen {
                    self.setExpandedNowPlaying(false)
                } else {
                    self.mainContentFocused = true
                }
            }
            .onChange(of: self.watchForChanges) { _, _ in
                // ADR-005 audit M8: live-toggle the FSEvents watcher when the
                // Settings switch flips, instead of waiting for next launch.
                Task { await self.vm.startOrStopWatcher() }
            }
            .alert(
                L10n.string("Playback Error"),
                isPresented: self.playbackErrorBinding
            ) {
                Button(L10n.string("OK")) { self.vm.playbackErrorMessage = nil }
            } message: {
                Text(self.vm.playbackErrorMessage ?? "")
            }
            .alert(
                L10n.string("Re-scan Failed"),
                isPresented: self.rescanErrorBinding
            ) {
                Button(L10n.string("OK")) { self.vm.rescanErrorMessage = nil }
            } message: {
                Text(self.vm.rescanErrorMessage ?? "")
            }
            .modifier(ClearQueueConfirmationModifier(
                isPresented: self.$vm.clearQueueConfirmationPresented,
                itemCount: self.vm.clearQueueItemCount
            ) {
                Task { await self.vm.clearQueue() }
            })
            .overlay(alignment: .top) {
                // ADR-007 audit M2: lightweight toast surface for transient
                // confirmations (e.g. "Re-scanned «Title»"). Auto-dismisses
                // via LibraryViewModel.showToast after 2 seconds.
                ZStack {
                    if let toast = self.vm.toast {
                        ToastBanner(message: toast)
                            .padding(.top, 12)
                            .transition(self.reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                            .accessibilityAddTraits(.isStaticText)
                            .accessibilityLabel(toast.text)
                    }
                }
                // Animate only the toast. Applying the transaction to the root
                // also animated the browser and transport on unrelated updates.
                .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.18), value: self.vm.toast)
            }
            .onChange(of: self.vm.tagEditorTrackIDs) { _, _ in
                self.tagEditorVM = self.vm.makeTagEditorViewModel()
            }
            .sheet(isPresented: self.tagEditorBinding) {
                if let tagVM = self.tagEditorVM {
                    TagEditorSheet(vm: tagVM, isPresented: self.tagEditorBinding)
                }
            }
            .sheet(item: self.$vm.artistInfo) { ArtistInfoSheet(artistID: $0.id, library: self.vm) { self.vm.artistInfo = nil } }
            .onChange(of: self.vm.identifyTrack?.id) { _, _ in
                if let track = self.vm.identifyTrack,
                   let queue = self.vm.fingerprintQueue,
                   let svc = self.vm.metadataEditService {
                    self.identifyVM = IdentifyTrackViewModel(
                        track: track,
                        queue: queue,
                        editService: svc,
                        artistRepo: self.vm.artistRepo,
                        albumRepo: self.vm.albumRepo
                    )
                } else {
                    self.identifyVM = nil
                }
            }
            .sheet(item: self.$identifyVM) { identVM in
                IdentifyTrackSheet(vm: identVM)
                    .onDisappear {
                        let didApply = identVM.didApply
                        let openTagEditor = identVM.openTagEditorAfterDismiss
                        // Capture the track ID before clearing identifyTrack.
                        let trackID = self.vm.identifyTrack?.id
                        self.vm.identifyTrack = nil
                        if didApply, let id = trackID {
                            Task { await self.vm.refreshTracks(ids: [id]) }
                        }
                        if openTagEditor, let id = trackID {
                            self.vm.tagEditorTrackIDs = [id]
                        }
                    }
            }
            .sheet(isPresented: self.$vm.isPlaylistImportSheetPresented) {
                PlaylistImportSheet(
                    isPresented: self.$vm.isPlaylistImportSheetPresented,
                    importer: self.vm.playlistImporter
                ) { playlistID, stationsAdded in
                    self.vm.handlePlaylistImportCompletion(playlistID: playlistID, stationsAdded: stationsAdded)
                }
            }
            .sheet(item: self.$vm.playlistExportRequest) { req in
                PlaylistExportSheet(
                    isPresented: Binding(
                        get: { self.vm.playlistExportRequest != nil },
                        set: {
                            if !$0 {
                                self.vm.playlistExportRequest = nil
                            }
                        }
                    ),
                    exporter: self.vm.playlistExporter,
                    playlistID: req.id,
                    playlistName: req.name
                )
            }
            .onChange(of: self.vm.isBatchCoverArtSheetPresented) { _, presented in
                if presented {
                    self.batchCoverArtVM = BatchCoverArtViewModel(
                        database: self.vm.database,
                        albumRepo: self.vm.albumRepo,
                        artistRepo: self.vm.artistRepo
                    )
                } else {
                    self.batchCoverArtVM = nil
                }
            }
            .sheet(isPresented: self.$vm.isBatchCoverArtSheetPresented) {
                if let batchVM = self.batchCoverArtVM {
                    BatchCoverArtSheet(
                        vm: batchVM,
                        isPresented: self.$vm.isBatchCoverArtSheetPresented
                    )
                }
            }
            .onChange(of: self.vm.isDuplicateReviewSheetPresented) { _, presented in
                if presented {
                    self.duplicateReviewVM = DuplicateReviewViewModel(
                        database: self.vm.database,
                        library: self.vm
                    )
                } else {
                    self.duplicateReviewVM = nil
                }
            }
            .sheet(isPresented: self.$vm.isDuplicateReviewSheetPresented) {
                if let dupVM = self.duplicateReviewVM {
                    DuplicateReviewSheet(
                        vm: dupVM,
                        isPresented: self.$vm.isDuplicateReviewSheetPresented
                    )
                }
            }
            .onKeyPress(.init("i"), phases: .down) { event in
                guard event.modifiers == [.command, .option] else { return .ignored }
                self.vm.showIdentifyTrackForCurrentSelection()
                return .handled
            }
            .onAppear { self.applyAppearance(self.colorSchemeKey) }
            .onChange(of: self.colorSchemeKey) { _, newKey in self.applyAppearance(newKey) }
            .tint(AccentPalette.color(for: self.accentColorKey))
    }

    // MARK: - Helpers

    /// Build the player and its queue before the artwork is clicked. Its
    /// invisible view keeps its layout identity through every open and close.
    private func prewarmExpandedNowPlaying() {
        guard !self.expandedPrewarmed else { return }
        withTransaction(Transaction(animation: nil)) {
            self.expandedPrewarmed = true
        }
    }

    @ViewBuilder
    private var playbackInspector: some View {
        if self.visualizerVisible {
            VisualizerPane(vm: self.visualizerVM, nowPlayingVM: self.vm.nowPlaying, usesInspectorSizing: true)
        } else {
            LibraryInspector(
                library: self.vm,
                lyricsVM: self.lyricsVM,
                selection: self.$inspectorSelection,
                isVisible: self.$lyricsPaneVisible
            )
        }
    }

    /// Fade the player while keeping the browser alive. Its toolbar stays
    /// hidden until closing completes, before restoring browser input/focus.
    private func setExpandedNowPlaying(_ expanded: Bool) {
        guard expanded != self.showExpandedNowPlaying else { return }
        self.expandedTransitionGeneration &+= 1
        let generation = self.expandedTransitionGeneration
        let fade: Animation? = self.reduceMotion ? nil : .smooth(duration: 0.28)
        if expanded {
            self.prewarmExpandedNowPlaying()
            withTransaction(Transaction(animation: nil)) {
                // A focused toolbar search field consumes Escape before the
                // player's cancel shortcut. Release it as the player opens.
                self.searchFocused = false
                self.browserInputBlocked = true
            }
            withAnimation(fade) {
                self.showExpandedNowPlaying = true
            }
            return
        }
        withAnimation(fade, completionCriteria: .logicallyComplete) {
            self.showExpandedNowPlaying = false
        } completion: {
            guard generation == self.expandedTransitionGeneration else { return }
            guard !self.showExpandedNowPlaying else { return }
            self.finishExpandedClose()
        }
    }

    private func finishExpandedClose() {
        withTransaction(Transaction(animation: nil)) {
            self.browserInputBlocked = false
        }
        if self.pendingSearchFocus {
            self.pendingSearchFocus = false
            self.pendingExpandedInfoTrackID = nil
            self.searchFocused = true
        } else if let trackID = self.pendingExpandedInfoTrackID {
            self.pendingExpandedInfoTrackID = nil
            self.vm.tagEditorTrackIDs = [trackID]
        }
    }

    /// Sets `NSApp.appearance` so every window updates immediately, avoiding
    /// the half-repainted artefact `.preferredColorScheme` can leave when
    /// returning from a forced scheme to System.
    private func applyAppearance(_ key: String) {
        switch key {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)

        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)

        default:
            NSApp.appearance = nil // follow System
        }
    }

    private var playbackErrorBinding: Binding<Bool> {
        Binding(
            get: { self.vm.playbackErrorMessage != nil },
            set: {
                if !$0 {
                    self.vm.playbackErrorMessage = nil
                }
            }
        )
    }

    private var rescanErrorBinding: Binding<Bool> {
        Binding(
            get: { self.vm.rescanErrorMessage != nil },
            set: {
                if !$0 {
                    self.vm.rescanErrorMessage = nil
                }
            }
        )
    }

    private var tagEditorBinding: Binding<Bool> {
        Binding(
            get: { self.tagEditorVM != nil },
            set: {
                if !$0 {
                    let didSave = self.tagEditorVM?.didSave == true
                    // Capture IDs before clearing state.
                    let editedIDs = self.vm.tagEditorTrackIDs ?? []
                    self.tagEditorVM = nil
                    self.vm.tagEditorTrackIDs = nil
                    if didSave {
                        // Refresh only the affected rows — preserves scroll position.
                        Task { await self.vm.refreshTracks(ids: editedIDs) }
                    }
                }
            }
        )
    }

    // MARK: - Drop helper

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}

// MARK: - Clear-queue confirmation (issue #260)

/// Hosts the "Clear the queue?" confirmation as a standalone modifier so the
/// large `BocanRootView.body` modifier chain stays within the Swift
/// type-checker's complexity budget.
private struct ClearQueueConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let itemCount: Int
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert(L10n.string("Clear the queue?"), isPresented: self.$isPresented) {
            Button(L10n.string("Clear Queue"), role: .destructive, action: self.onConfirm)
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: {
            Text(localized: "This removes the \(self.itemCount) tracks in your queue and stops playback.")
        }
    }
}
