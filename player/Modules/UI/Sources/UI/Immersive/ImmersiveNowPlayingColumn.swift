import SwiftUI

// MARK: - ImmersiveNowPlayingColumn

/// The leading Immersive Mode column (ADR-089): the artwork as a square that
/// fills the column width, then the title, artist and album beneath it.
/// Podcasts show the episode title and the show name; radio shows the live
/// stream title and the station name. Nothing playing shows the same idle
/// copy as the transport strip.
struct ImmersiveNowPlayingColumn: View {
    /// `@Observable`, so a plain property is the correct binding.
    var vm: NowPlayingViewModel
    var library: LibraryViewModel

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            self.artwork

            VStack(alignment: .center, spacing: 4) {
                Text(self.titleText)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(self.vm.display.title.isEmpty ? Color.textSecondary : Color.textPrimary)
                    .lineLimit(1)
                    .accessibilityIdentifier(A11y.Immersive.title)

                if !self.vm.display.artist.isEmpty {
                    Text(self.vm.display.artist)
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .accessibilityIdentifier(A11y.Immersive.artist)
                }

                if let detail = self.detailText {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                        .accessibilityIdentifier(A11y.Immersive.album)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            // The player controls sit under everything else in this column.
            // The strip is covered while Immersive Mode is on.
            ImmersiveTransport(np: self.vm, library: self.library)
        }
        .padding(16)
    }

    // MARK: - Text

    private var titleText: String {
        self.vm.display.title.isEmpty ? L10n.string("Not playing") : self.vm.display.title
    }

    /// The third line: the album for music, the station for radio. Podcasts
    /// carry the show in `artist` and nothing here.
    private var detailText: String? {
        if let station = self.vm.nowPlayingRadioStationName, !station.isEmpty {
            return station
        }
        return self.vm.display.album.isEmpty ? nil : self.vm.display.album
    }

    // MARK: - Artwork

    /// A fixed-aspect base with the image in an overlay, the same trick as
    /// ``Artwork``, so a non-square embedded cover cannot distort the column.
    private var artwork: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = self.vm.display.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    GradientPlaceholder(seed: Int(truncatingIfNeeded: self.vm.nowPlayingAlbumID ?? 0))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium, style: .continuous))
            // Lifts the cover off the visualizer now that no card frames it.
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
            .accessibilityLabel(
                self.vm.display.title.isEmpty ? L10n.string("No artwork") : L10n.string("Artwork for \(self.vm.display.title)")
            )
            .accessibilityIdentifier(A11y.Immersive.artwork)
    }
}
