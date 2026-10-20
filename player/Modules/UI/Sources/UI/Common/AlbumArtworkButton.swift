import Persistence
import SwiftUI

/// Independent open and play targets: opening never waits for a double click.
struct AlbumArtworkButton: View {
    let album: Album
    let onOpen: () -> Void
    let onPlay: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button(action: self.onOpen) {
                Artwork(
                    artPath: self.album.coverArtPath, seed: Int(self.album.id ?? 0),
                    size: Theme.albumGridMinWidth)
            }
            .buttonStyle(.plain)
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
            .padding(10)
            // Keep a visible affordance and a keyboard/VoiceOver target at rest.
            .opacity(self.hovered ? 1 : 0.65)
            .help(L10n.string("Play Album"))
            .accessibilityLabel(L10n.string("Play Album") + ": " + self.album.title)
            .accessibilityIdentifier("album.play.\(self.album.id ?? 0)")
        }
        .onHover { self.hovered = $0 }
        .animation(self.reduceMotion ? nil : .easeOut(duration: 0.15), value: self.hovered)
    }
}
