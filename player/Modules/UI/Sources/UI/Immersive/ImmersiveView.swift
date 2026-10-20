import SwiftUI

/// Full screen hosts the same listening surface as the main-window player.
/// The scene, Escape key and saved visibility retain their existing contract.
public struct ImmersiveView: View {
    private let library: LibraryViewModel
    private let lyricsVM: LyricsViewModel
    private let visualizerVM: VisualizerViewModel
    private let onClose: () -> Void
    public nonisolated static let preferenceKey = "ui.immersive.visible"

    public init(
        library: LibraryViewModel,
        lyricsVM: LyricsViewModel,
        visualizerVM: VisualizerViewModel,
        onClose: @escaping () -> Void
    ) {
        self.library = library
        self.lyricsVM = lyricsVM
        self.visualizerVM = visualizerVM
        self.onClose = onClose
    }

    public var body: some View {
        ExpandedNowPlayingView(
            library: self.library, lyricsVM: self.lyricsVM,
            visualizerVM: self.visualizerVM, presentation: .immersive, isPresented: true,
            onClose: self.onClose,
            onGetInfo: { id in
                self.onClose()
                self.library.tagEditorTrackIDs = [id]
            },
            onNavigate: self.onClose
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11y.Immersive.root)
    }
}
