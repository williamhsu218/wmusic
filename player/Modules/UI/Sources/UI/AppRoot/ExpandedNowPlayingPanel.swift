import SwiftUI

/// Keeps lyric observation inside the right column, away from the library and
/// artwork. The two surfaces share the existing queue and playback driver.
struct ExpandedNowPlayingPanel: View {
    let library: LibraryViewModel
    let lyricsVM: LyricsViewModel
    let isPresented: Bool
    let onGetInfo: (Int64) -> Void
    let onNavigate: () -> Void

    @AppStorage("ui.expandedNowPlaying.panel") private var selection: Panel = .queue

    private enum Panel: String {
        case queue, lyrics
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(L10n.string(self.selection == .queue ? "Playing Queue" : "Lyrics"))
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(self.selection == .queue
                        ? A11y.NowPlaying.expandedQueueTitle : "nowPlaying.expanded.lyricsTitle")

                Spacer(minLength: 0)

                Picker(L10n.string("Now Playing"), selection: self.$selection) {
                    Label(L10n.string("Queue"), systemImage: "list.bullet").tag(Panel.queue)
                    Label(L10n.string("Lyrics"), systemImage: "quote.bubble").tag(Panel.lyrics)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier(A11y.NowPlaying.expandedPanelPicker)
            }
            .padding(.horizontal, 22)
            .frame(height: 60)

            if self.selection == .queue {
                Divider()
                QueueView(
                    vm: self.library,
                    showsGenre: false,
                    prominentRows: true,
                    onGetInfo: self.onGetInfo,
                    onNavigate: self.onNavigate
                )
                .scrollContentBackground(.hidden)
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
        .background {
            if self.selection == .lyrics {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.07), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}
