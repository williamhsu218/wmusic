import Observability
import Persistence
import SwiftUI

// MARK: - AlbumDetailView

/// Header (cover + metadata + play button) + track list for one album.
///
/// The track list reuses `TracksView` but hides the Album column since
/// context is already known.
public struct AlbumDetailView: View {
    public let albumID: Int64
    public var library: LibraryViewModel

    @State private var album: Album?
    @State private var artistName = ""
    @State private var artwork: NSImage?
    @State private var collapsed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(albumID: Int64, library: LibraryViewModel) {
        self.albumID = albumID
        self.library = library
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Header
                self.header(compact: self.collapsed || geometry.size.height < 460)

                Divider()

                // Track list
                TracksView(
                    vm: self.library.tracks, library: self.library,
                    onScroll: { offset in
                        let next = self.collapsed ? offset > 4 : offset > 64
                        if next != self.collapsed {
                            withAnimation(self.reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                                self.collapsed = next
                            }
                        }
                    })
            }
        }
        // task(id:), not task: switching .album(A) -> .album(B) keeps this
        // view's identity (same switch arm in ContentPane), so a plain task
        // never re-fires and the header shows album A over album B's tracks.
        .task(id: self.albumID) {
            self.collapsed = false
            self.album = nil
            self.artistName = ""
            self.artwork = nil
            await self.load()
        }
        .navigationTitle(self.album?.title ?? L10n.string("Album"))
    }

    // MARK: - Header

    @ViewBuilder
    private func header(compact: Bool) -> some View {
        if compact {
            HStack(spacing: 12) {
                self.artworkView(size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(self.album?.title ?? "").font(.headline).lineLimit(1)
                    Text(self.artistName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    Task { await self.library.playAlbum(albumID: self.albumID) }
                } label: {
                    Label(L10n.string("Play"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(L10n.string("Play Album"))
                Button {
                    Task { await self.playShuffled() }
                } label: {
                    Image(systemName: "shuffle")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(L10n.string("Shuffle Album"))
            }
            .padding(12)
            .background { ArtworkAmbientBackground(image: self.artwork) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("album.header.compact")
        } else {
            HStack(alignment: .bottom, spacing: 20) {
                self.artworkView(size: 180)

                VStack(alignment: .leading, spacing: 6) {
                    if let year = album?.year {
                        Text(verbatim: String(year))
                            .font(Typography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .textCase(.uppercase)
                    }

                    Text(self.album?.title ?? "")
                        .font(Typography.largeTitle)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)

                    if !self.artistName.isEmpty {
                        Button {
                            if let artistID = album?.albumArtistID {
                                Task { await self.library.selectDestination(.artist(artistID)) }
                            }
                        } label: {
                            Text(self.artistName)
                                .font(Typography.title)
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.string("Artist: \(self.artistName)"))
                        .help(L10n.string("Opens this artist's page."))
                    }

                    HStack(spacing: 8) {
                        // Release kind from the tags (#403); plain albums carry no badge.
                        if let kind = album?.releaseType, kind != "album" {
                            Text(ReleaseKindLabel.string(for: kind))
                                .font(Typography.footnote.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.bgTertiary, in: Capsule())
                                .accessibilityLabel(
                                    L10n.string("Release kind: \(ReleaseKindLabel.string(for: kind))"))
                        }
                        if let total = album?.totalTracks {
                            Text(localized: "\(total) songs")
                                .font(Typography.footnote)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    // Play / Shuffle buttons (ADR-005 audit H4).
                    HStack(spacing: 8) {
                        Button {
                            Task {
                                if let first = library.tracks.tracks.first {
                                    await self.library.play(track: first)
                                }
                            }
                        } label: {
                            Label(L10n.string("Play"), systemImage: "play.fill")
                                .font(Typography.body)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityLabel(L10n.string("Play Album"))
                        .help(L10n.string("Play this album from the first track"))

                        Button {
                            Task { await self.playShuffled() }
                        } label: {
                            Label(L10n.string("Shuffle"), systemImage: "shuffle")
                                .font(Typography.body)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityLabel(L10n.string("Shuffle Album"))
                        .help(L10n.string("Play this album in shuffled order"))
                        .disabled(self.library.tracks.tracks.isEmpty)
                    }
                    .padding(.top, 4)
                }

                Spacer()
            }
            .padding(20)
            .background { ArtworkAmbientBackground(image: self.artwork) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("album.header.expanded")
        }
    }

    private func artworkView(size: CGFloat) -> some View {
        Group {
            if let img = artwork {
                // Base colour drives layout; the image is an overlay so a
                // non-square source can't stretch the 180×180 frame.
                Color.bgTertiary
                    .overlay {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                    }
                    .accessibilityLabel(L10n.string("\(self.album?.title ?? L10n.string("Album")) artwork"))
            } else if let path = album?.coverArtPath {
                Artwork(artPath: path, seed: Int(self.albumID), size: 180)
                    .accessibilityLabel(L10n.string("\(self.album?.title ?? L10n.string("Album")) artwork"))
            } else {
                GradientPlaceholder(seed: Int(self.albumID))
                    .accessibilityLabel(
                        L10n.string("\(self.album?.title ?? L10n.string("Album")) artwork placeholder"))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.artworkCornerRadius * 2, style: .continuous))
        .shadow(radius: 8, y: 4)
    }

    // MARK: - Data loading

    private func playShuffled() async {
        let tracks = self.library.tracks.tracks
        guard !tracks.isEmpty else { return }
        await self.library.play(tracks: tracks, shuffle: true)
    }

    private func load() async {
        await self.library.tracks.load(albumID: self.albumID)
        guard !Task.isCancelled else { return }

        // Resolve album record
        do {
            let repo = AlbumRepository(database: library.database)
            let rec = try await repo.fetch(id: self.albumID)
            guard !Task.isCancelled else { return }
            self.album = rec
            // Resolve artist
            if let artistID = rec.albumArtistID {
                let artistRepo = ArtistRepository(database: library.database)
                if let name = await recoveredRead(
                    "albumDetail.artist.failed",
                    {
                        try await artistRepo.fetch(id: artistID).name
                    })
                {
                    self.artistName = name
                }
            }
            // Load artwork
            if let hash = rec.coverArtHash {
                let artRepo = CoverArtRepository(database: library.database)
                // Double optional: the read can fail, and the hash can have no
                // row. Both mean "no artwork", so flatten the two together.
                let artRec = await recoveredRead("albumDetail.coverArt.failed") {
                    try await artRepo.fetch(hash: hash)
                }.flatMap(\.self)
                if let artRec {
                    self.artwork = await ArtworkLoader.shared.image(at: artRec.path)
                }
            }
        } catch {
            // The page renders with empty fields, which reads as an album with
            // no metadata rather than one that could not be loaded. Same fault
            // as the two reads above and invisible to a `try?` search (#491).
            AppLogger.make(.ui).warning(
                "albumDetail.load.failed",
                [
                    "albumID": self.albumID,
                    "error": String(reflecting: error),
                ])
        }
    }
}
