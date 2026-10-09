import AppKit

// MARK: - NowPlayingDisplay

/// What the now-playing surfaces draw for the current item: the strip, the
/// full-window player, Immersive Mode and the mini player.
///
/// `NowPlayingViewModel` resolves a local track in stages: the title is known
/// at once, the artist, album and cover come from the database a moment later,
/// and the codec only once the decoder is open. Drawing each stage as it lands
/// made every track change flash through a blank subtitle, a placeholder cover
/// and a badge row that reflowed when the codec arrived. The view model keeps
/// the previous track's snapshot on screen until the new one is complete (or
/// a short limit passes) and then publishes it in one assignment.
public struct NowPlayingDisplay: Equatable {
    public var title = ""
    public var artist = ""
    public var album = ""
    public var artwork: NSImage?
    public var sourceFacts: NowPlayingSourceFacts?

    public init(
        title: String = "",
        artist: String = "",
        album: String = "",
        artwork: NSImage? = nil,
        sourceFacts: NowPlayingSourceFacts? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.sourceFacts = sourceFacts
    }

    /// Stable identity of the drawn cover. Consecutive tracks of one album
    /// share the cached `NSImage`, so the cover does not cross-fade between
    /// them.
    public var artworkIdentity: ObjectIdentifier? {
        self.artwork.map { ObjectIdentifier($0) }
    }
}
