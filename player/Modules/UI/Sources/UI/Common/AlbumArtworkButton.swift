import Persistence
import SwiftUI

/// Independent open and play targets: opening never waits for a double click.
struct AlbumArtworkButton: View {
    let album: Album
    let onOpen: () -> Void
    let onPlay: () -> Void
    var isActive = false
    private enum Action: Hashable { case open, play }
    @FocusState private var focusedAction: Action?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let revealed = self.isActive || self.focusedAction != nil
        ZStack(alignment: .bottomTrailing) {
            Button(action: self.onOpen) {
                Artwork(
                    artPath: self.album.coverArtPath, seed: Int(self.album.id ?? 0),
                    size: Theme.albumGridMinWidth
                )
            }
            .buttonStyle(.plain)
            .focused(self.$focusedAction, equals: .open)
            .accessibilityLabel(L10n.string("View Album") + ": " + self.album.title)
            .accessibilityIdentifier("album.open.\(self.album.id ?? 0)")

            Button(action: self.onPlay) {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.primary.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .focused(self.$focusedAction, equals: .play)
            .padding(10)
            .opacity(revealed ? 1 : 0)
            .scaleEffect(revealed || self.reduceMotion ? 1 : 0.88)
            .allowsHitTesting(revealed)
            .accessibilityHidden(!revealed)
            .help(L10n.string("Play Album"))
            .accessibilityLabel(L10n.string("Play Album") + ": " + self.album.title)
            .accessibilityIdentifier("album.play.\(self.album.id ?? 0)")
        }
        .animation(self.reduceMotion ? nil : .easeOut(duration: 0.15), value: revealed)
    }
}
