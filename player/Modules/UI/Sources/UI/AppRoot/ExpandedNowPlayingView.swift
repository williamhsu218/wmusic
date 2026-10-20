import SwiftUI

/// A full-window listening surface presented inside the main window. Keeping
/// the library browser alive underneath preserves its navigation and scroll
/// position while the cover, transport and queue take the whole content area.
struct ExpandedNowPlayingView: View {
    let library: LibraryViewModel
    let lyricsVM: LyricsViewModel
    var visualizerVM: VisualizerViewModel? = nil
    var artworkNamespace: Namespace.ID? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The parent keeps this surface mounted behind the browser between visits.
    /// Gate its window-level commands while it is hidden.
    let isPresented: Bool
    let onClose: () -> Void
    let onGetInfo: (Int64) -> Void
    let onNavigate: () -> Void

    @AppStorage("ui.expandedNowPlaying.panel") private var selection: ExpandedNowPlayingPanel.Selection = .queue

    private var nowPlaying: NowPlayingViewModel { self.library.nowPlaying }

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 620 || geometry.size.width < 920
            let controlHeight: CGFloat = 58
            let contentWidth = isCompact
                ? geometry.size.width
                : min(max(0, geometry.size.width - 64), 2100)
            let contentHeight = isCompact
                ? max(0, geometry.size.height - controlHeight)
                : min(max(0, geometry.size.height - controlHeight), 1160)
            let playerWidth = min(contentWidth * 0.43, 760)
            let heroHeight = min(250, max(230, contentHeight * 0.46))
            let layout = isCompact
                ? AnyLayout(VStackLayout(spacing: 0))
                : AnyLayout(HStackLayout(spacing: 28))

            VStack(spacing: 0) {
                self.playbackControls
                    .frame(height: controlHeight)

                // Only the layout changes at the compact breakpoint. Keep the
                // queue List in one stable child slot while the window resizes.
                layout {
                    self.playerContent(
                        size: geometry.size,
                        isCompact: isCompact,
                        width: playerWidth,
                        height: contentHeight
                    )
                    .frame(width: isCompact ? nil : playerWidth,
                           height: isCompact ? heroHeight : contentHeight)

                    ExpandedNowPlayingPanel(
                        library: self.library,
                        lyricsVM: self.lyricsVM,
                        selection: self.selection,
                        isPresented: self.isPresented,
                        onGetInfo: self.onGetInfo,
                        onNavigate: self.onNavigate,
                        visualizerVM: self.visualizerVM
                    )
                        .frame(maxWidth: .infinity, maxHeight: isCompact ? .infinity : nil)
                        .frame(height: isCompact ? nil : contentHeight)
                        .padding(.horizontal, isCompact ? 24 : 0)
                        .padding(.bottom, isCompact ? 16 : 0)
                }
                .frame(width: contentWidth, height: contentHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background {
                ArtworkAmbientBackground(image: self.nowPlaying.display.artwork)
                    .ignoresSafeArea()
            }
        }
        // The listening surface fills the space released by the hidden
        // library toolbar instead of retaining an empty titlebar-sized gap.
        .ignoresSafeArea(.container, edges: .top)
        .onExitCommand(perform: self.isPresented ? self.onClose : nil)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(self.isPresented ? .isModal : [])
        .accessibilityLabel(L10n.string("Now Playing"))
        .accessibilityIdentifier(A11y.NowPlaying.expandedRoot)
    }

    /// The player owns its controls above both columns. Empty header space is
    /// draggable without taking gestures away from the lyrics or the buttons.
    private var playbackControls: some View {
        HStack {
            Button(action: self.onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.bgSecondary.opacity(0.72), in: Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.string("Close"))
            .accessibilityLabel(L10n.string("Close"))
            .accessibilityIdentifier(A11y.NowPlaying.expandedClose)
            .keyboardShortcut(self.isPresented ? .cancelAction : nil)
            .disabled(!self.isPresented)

            Spacer()

            Picker(L10n.string("Now Playing"), selection: self.$selection) {
                Label(L10n.string("Queue"), systemImage: "list.bullet")
                    .tag(ExpandedNowPlayingPanel.Selection.queue)
                Label(L10n.string("Lyrics"), systemImage: "quote.bubble")
                    .tag(ExpandedNowPlayingPanel.Selection.lyrics)
                if self.visualizerVM != nil {
                    Label(L10n.string("Visualizer"), systemImage: "waveform")
                        .tag(ExpandedNowPlayingPanel.Selection.visualizer)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier(A11y.NowPlaying.expandedPanelPicker)
        }
        .padding(.leading, 24)
        .padding(.trailing, 24)
        .frame(maxHeight: .infinity)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func playerContent(size: CGSize, isCompact: Bool, width: CGFloat, height: CGFloat) -> some View {
        if isCompact {
            self.compactPlayerContent(size: size, height: height)
        } else {
            self.playerColumn(width: width, height: height)
        }
    }

    private func playerColumn(width: CGFloat, height: CGFloat) -> some View {
        // Reserve the real height needed by the title, source badges and
        // transport, including a two-line title at the column breakpoint.
        let coverSize = min(max(180, height - 312), width - 32, 700)

        return VStack(spacing: 0) {
            Spacer(minLength: 0)

            self.artwork(size: coverSize)
                .padding(.bottom, 18)

            self.metadata(compact: false)

            if let facts = self.nowPlaying.display.sourceFacts {
                SourceBadgesRow(facts: facts)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }

            ImmersiveTransport(np: self.nowPlaying, library: self.library, prominent: true)
                .padding(.top, 20)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    private func compactPlayerContent(size: CGSize, height: CGFloat) -> some View {
        let heroHeight = min(250, max(230, height * 0.46))
        let coverSize = min(190, heroHeight - 32)

        return HStack(spacing: 24) {
            self.artwork(size: coverSize)

            VStack(alignment: .leading, spacing: 0) {
                self.metadata(compact: true)

                if size.height >= 736, let facts = self.nowPlaying.display.sourceFacts {
                    SourceBadgesRow(facts: facts)
                        .padding(.top, 8)
                }

                Spacer(minLength: 8)

                ImmersiveTransport(np: self.nowPlaying, library: self.library)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 28)
        .frame(height: heroHeight)
    }

    private func metadata(compact: Bool) -> some View {
        VStack(alignment: compact ? .leading : .center, spacing: 4) {
            Text(self.nowPlaying.display.title.isEmpty ? L10n.string("Not playing") : self.nowPlaying.display.title)
                .font(.system(size: compact ? 23 : 28, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)

            if !self.nowPlaying.display.artist.isEmpty {
                Text(self.nowPlaying.display.artist)
                    .font(compact ? .body : .title3)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            let album = self.nowPlaying.nowPlayingRadioStationName ?? self.nowPlaying.display.album
            if !album.isEmpty {
                Text(album)
                    .font(.subheadline)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(compact ? .leading : .center)
        .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
    }

    private func artwork(size: CGFloat) -> some View {
        Group {
            if let image = self.nowPlaying.display.artwork {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                GradientPlaceholder(seed: Int(truncatingIfNeeded: self.nowPlaying.nowPlayingAlbumID ?? 0))
            }
        }
        .frame(width: size, height: size)
        .modifier(PlaybackArtworkMatch(namespace: self.artworkNamespace, isSource: self.isPresented, enabled: !self.reduceMotion))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.23), radius: 24, y: 14)
        .accessibilityLabel(
            self.nowPlaying.display.title.isEmpty
                ? L10n.string("No artwork")
                : L10n.string("Artwork for \(self.nowPlaying.display.title)")
        )
        .accessibilityIdentifier(A11y.Immersive.artwork)
    }

}
