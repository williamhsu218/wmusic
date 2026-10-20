import SwiftUI

/// Keeps lyric observation inside the right column, away from the library and
/// artwork. The two surfaces share the existing queue and playback driver.
struct ExpandedNowPlayingPanel: View {
    let library: LibraryViewModel
    let lyricsVM: LyricsViewModel
    let selection: Selection
    let isPresented: Bool
    let onGetInfo: (Int64) -> Void
    let onNavigate: () -> Void
    var visualizerVM: VisualizerViewModel? = nil

    enum Selection: String {
        case queue, lyrics, visualizer
    }

    var body: some View {
        VStack(spacing: 0) {
            if self.selection == .queue {
                Text(L10n.string("Playing Queue"))
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .frame(height: 48)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(A11y.NowPlaying.expandedQueueTitle)
                QueueView(
                    vm: self.library,
                    showsGenre: false,
                    prominentRows: true,
                    onGetInfo: self.onGetInfo,
                    onNavigate: self.onNavigate
                )
                .scrollContentBackground(.hidden)
            } else if self.selection == .visualizer, let visualizerVM {
                if self.isPresented {
                    VisualizerPane(vm: visualizerVM, nowPlayingVM: self.library.nowPlaying, embedded: true)
                }
            } else {
                ExpandedLyricsView(
                    vm: self.lyricsVM,
                    isPresented: self.isPresented,
                    trackID: self.library.nowPlaying.nowPlayingTrackID
                ) { position in
                    Task { await self.library.nowPlaying.scrub(to: position) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
