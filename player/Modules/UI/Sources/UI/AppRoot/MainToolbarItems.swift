import SwiftUI

// MARK: - MainToolbarItems

/// The main window's navigation-placement toolbar group: history, the view
/// toggles (mini player, playback panel, visualizer, Immersive Mode) and Identify
/// Track. Split out of ``BocanRootView`` to keep that file under the length
/// cap. A plain struct: the root re-evaluates on every value it passes in,
/// so the labels and enablement stay live without wrappers here.
struct MainToolbarItems: ToolbarContent {
    let vm: LibraryViewModel
    let miniPlayerOpen: Bool
    let toggleMiniPlayer: () -> Void
    let lyricsPaneVisible: Binding<Bool>
    let visualizerPaneVisible: Binding<Bool>
    /// Immersive Mode (ADR-089) is its own window; the root opens or
    /// dismisses it, and `immersiveOpen` mirrors the window's state.
    let immersiveOpen: Bool
    let toggleImmersive: () -> Void
    let reduceMotion: Bool
    private var inspectorShown: Bool {
        self.lyricsPaneVisible.wrappedValue || self.visualizerPaneVisible.wrappedValue
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(L10n.string("Back"), systemImage: "chevron.left") {
                Task { await self.vm.goBack() }
            }
            .disabled(!self.vm.canGoBack)
            .help(L10n.string("Back (⌘[)"))
            .keyboardShortcut("[", modifiers: .command)
            .accessibilityIdentifier(A11y.Toolbar.back)

            Button(L10n.string("Forward"), systemImage: "chevron.right") {
                Task { await self.vm.goForward() }
            }
            .disabled(!self.vm.canGoForward)
            .help(L10n.string("Forward (⌘])"))
            .keyboardShortcut("]", modifiers: .command)
            .accessibilityIdentifier(A11y.Toolbar.forward)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(
                self.miniPlayerOpen ? L10n.string("Hide Mini Player") : L10n.string("Show Mini Player"),
                systemImage: "pip.enter"
            ) {
                self.toggleMiniPlayer()
            }
            .help(L10n.string("Toggle mini player (⌥⌘M)"))
            .accessibilityIdentifier(A11y.Toolbar.miniPlayerToggle)
            .foregroundStyle(self.miniPlayerOpen ? Color.accentColor : Color.primary)
            .accessibilityValue(self.miniPlayerOpen ? L10n.string("on") : L10n.string("off"))

            Button(
                self.inspectorShown ? L10n.string("Hide Playback Panel") : L10n.string("Show Playback Panel"),
                systemImage: "sidebar.right"
            ) {
                let visible = self.inspectorShown
                self.visualizerPaneVisible.wrappedValue = false
                self.lyricsPaneVisible.wrappedValue = !visible
            }
            .help(L10n.string("Queue, lyrics, and track information"))
            .accessibilityIdentifier("toolbar.inspector")
            .foregroundStyle(self.inspectorShown ? Color.accentColor : Color.primary)
            .accessibilityValue(self.inspectorShown ? L10n.string("on") : L10n.string("off"))

            Button(
                self.visualizerPaneVisible.wrappedValue ? L10n.string("Hide Visualizer") : L10n.string("Show Visualizer"),
                // Spectrum-bars glyph, distinct from the waveform +
                // magnifier used by Identify Track right beside it.
                systemImage: "chart.bar.xaxis"
            ) {
                if !self.visualizerPaneVisible.wrappedValue {
                    self.lyricsPaneVisible.wrappedValue = false
                }
                self.toggleAnimated(self.visualizerPaneVisible)
            }
            .help(L10n.string("Toggle visualizer pane (⇧⌘V)"))
            .accessibilityIdentifier(A11y.Toolbar.visualizerToggle)
            .foregroundStyle(self.visualizerPaneVisible.wrappedValue ? Color.accentColor : Color.primary)
            .accessibilityValue(self.visualizerPaneVisible.wrappedValue ? L10n.string("on") : L10n.string("off"))

            Button(
                self.immersiveOpen ? L10n.string("Exit Immersive Mode") : L10n.string("Enter Immersive Mode"),
                systemImage: "arrow.up.left.and.arrow.down.right"
            ) {
                self.toggleImmersive()
            }
            .help(L10n.string("Toggle Immersive Mode (⇧⌘I)"))
            .accessibilityIdentifier(A11y.Toolbar.immersiveToggle)
            .foregroundStyle(self.immersiveOpen ? Color.accentColor : Color.primary)
            .accessibilityValue(self.immersiveOpen ? L10n.string("on") : L10n.string("off"))

            Button(L10n.string("Identify Track"), systemImage: "waveform.badge.magnifyingglass") {
                self.vm.showIdentifyTrackForCurrentSelection()
            }
            .disabled(!self.vm.hasSingleTrackSelection)
            .help(L10n.string("Identify track using AcoustID (⌘⌥I)"))
            .accessibilityIdentifier(A11y.Toolbar.identifyTrack)
        }
    }

    /// Flips a pane flag with the same short fade the panes always used,
    /// unless Reduce Motion is on.
    private func toggleAnimated(_ flag: Binding<Bool>) {
        if self.reduceMotion {
            flag.wrappedValue.toggle()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                flag.wrappedValue.toggle()
            }
        }
    }
}
