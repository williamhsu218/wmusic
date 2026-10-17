// swiftlint:disable file_length
import AppKit
import AudioEngine
import Foundation
import Observability
import Persistence
import Playback
import Scrobble
import Subsonic
import UserNotifications

// MARK: - NowPlayingViewModel

/// Drives the `NowPlayingStrip` at the bottom of every screen.
///
/// Subscribes to `Transport.state` on init and updates its observable
/// properties on `@MainActor`.
@Observable
@MainActor
public final class NowPlayingViewModel {
    // MARK: - Observable state

    /// Cover art for the current track, or `nil` when nothing is playing.
    public private(set) var artwork: NSImage? {
        didSet { self.syncDisplay() }
    }
    /// Track title of the current item, or empty string when idle.
    public private(set) var title = "" {
        didSet { self.syncDisplay() }
    }
    /// Primary artist of the current item.
    public private(set) var artist = "" {
        didSet { self.syncDisplay() }
    }
    /// Album name of the current item.
    public private(set) var album = "" {
        didSet { self.syncDisplay() }
    }
    /// Total duration of the current track in seconds.
    public private(set) var duration: TimeInterval = 0
    /// Current playback position in seconds.
    public private(set) var position: TimeInterval = 0
    /// `true` while the engine is actively playing.
    public private(set) var isPlaying = false
    /// Output volume in the range 0.0–1.0.
    public var volume: Float = 1.0
    /// `true` when shuffle mode is active.
    public private(set) var shuffleOn = false
    /// Current repeat mode (.off / .one / .all).
    public private(set) var repeatMode: RepeatMode = .off
    /// `true` when "stop after current track" is armed.
    public private(set) var stopAfterCurrent = false
    /// The database ID of the track currently loaded into the engine, or `nil`.
    public private(set) var nowPlayingTrackID: Int64?
    /// The album ID of the track currently loaded into the engine, or `nil`.
    public private(set) var nowPlayingAlbumID: Int64?
    /// The artist ID of the track currently loaded into the engine, or `nil`.
    public private(set) var nowPlayingArtistID: Int64?
    /// The Subsonic server ID of the stream currently loaded into the engine, or
    /// `nil` when the current item is not a Subsonic stream.
    public private(set) var nowPlayingSubsonicServerID: UUID?
    /// The Subsonic song ID of the stream currently loaded into the engine, or
    /// `nil` when the current item is not a Subsonic stream. Together with
    /// `nowPlayingSubsonicServerID` this lets per-server Songs lists move their
    /// selection onto the playing row, mirroring the local library.
    public private(set) var nowPlayingSubsonicSongID: String?
    /// `true` only while playback is paused mid-song (not stopped, idle, or ended).
    /// Used by `playPause()` to decide whether to resume or reload the library.
    public private(set) var isPaused = false
    /// Current playback rate (0.5×–2.0×). Default 1.0×.
    public private(set) var playbackRate: Float = 1.0
    /// `true` when the output is muted (volume forced to 0 without forgetting the real level).
    public private(set) var isMuted = false
    /// Seconds remaining on the sleep timer, or `nil` when off.
    public private(set) var sleepTimerRemaining: TimeInterval?
    /// Whether the sleep timer's fade-out option is active.
    public private(set) var sleepTimerFadeOut = false
    /// The number of minutes the active sleep timer was set to, or `nil` when off.
    /// Used by the Playback menu to show a checkmark next to the active preset.
    public private(set) var sleepTimerActiveMinutes: Int?
    /// Number of scrobbles pending submission. Sourced from `ScrobbleQueueRepository.observeStats()`.
    /// Zero when scrobbling is not configured. Used to drive the strip indicator.
    public private(set) var pendingScrobbleCount = 0
    /// `true` when the currently-playing (or paused) track is marked as loved.
    public private(set) var nowPlayingIsLoved = false
    /// `true` when the current item is a podcast episode.
    public private(set) var isPodcast = false
    /// The `podcasts.id` of the current show when `isPodcast` is `true`. `nil` otherwise.
    public private(set) var podcastID: Int64?
    /// The feed URL of the current podcast show.
    public private(set) var podcastFeedURL: URL?
    /// The episode GUID of the currently playing episode.
    public private(set) var podcastGUID: String?

    // MARK: - Callbacks

    /// Called when play is pressed but the queue is empty; set by `LibraryViewModel`.
    public var onPlayFromEmptyQueue: (@MainActor () -> Void)?

    /// Called when playback fails terminally — e.g. a streamed source dropped and
    /// the engine exhausted its reconnect attempts. Set by `LibraryViewModel` to
    /// surface a toast. The transport has already stopped by the time this fires.
    public var onPlaybackError: (@MainActor () -> Void)?

    /// Supplies a source order for a legacy queue only when the visible library
    /// can account for every existing item. New queues already own their order.
    public var onResolveLegacyQueueOrder: (@MainActor ([QueueItem], Int?) -> [QueueItem.ID]?)?

    // MARK: - Internal

    private let engine: any Transport
    private let database: Database
    private let subsonicCoverArtProvider: SubsonicCoverArtProvider?
    // nonisolated(unsafe): assigned only from @MainActor methods and read once
    // from the nonisolated `deinit`, which has exclusive access, never
    // concurrently. Task handles are themselves Sendable. See #279.
    // @ObservationIgnored keeps them stored properties: `@Observable` would
    // otherwise rewrite them as computed, where the annotation has no effect
    // and the compiler says so on every build (#458).
    @ObservationIgnored private nonisolated(unsafe) var stateTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var positionTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var sleepTimerTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var scrobbleStatsTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var currentTrackTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var initialItemSyncTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var queueChangesTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var streamTitleTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var markerTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var metadataTask: Task<Void, Never>?

    /// The current track's CUE markers (ADR-087), position-sorted; empty for
    /// tracks without them. Fed by `QueuePlayer.markerUpdates` per load.
    public private(set) var markers: [TrackMarker] = []

    /// The marker playback is currently inside, from the live position.
    public var currentMarker: TrackMarker? {
        self.markers.last { Double($0.positionMs) / 1000.0 <= self.position + 0.1 }
    }

    /// The full `Track` record for the currently-playing item, or `nil` when idle.
    /// Populated by `setCurrentTrack(_:)` and used by `TrackInfoPanel`.
    public private(set) var currentTrack: Track?

    /// Codec, bitrate, sample rate, bit depth and channels of what is
    /// playing, for the strip's badges (ADR-092). Nil when nothing plays, and
    /// when neither the track nor the decoder can say anything at all.
    public private(set) var sourceFacts: NowPlayingSourceFacts? {
        didSet { self.syncDisplay() }
    }

    /// The title, subtitle, cover and badges the now-playing surfaces draw.
    /// Follows the fields above, except while a local track change is being
    /// resolved: then it keeps the previous track until the new one is
    /// complete, so the change lands as one update (see `NowPlayingDisplay`).
    public private(set) var display = NowPlayingDisplay()

    /// The local track whose display is still being resolved, and which of
    /// its two late parts (database metadata, decoder facts) have arrived.
    @ObservationIgnored private var displayHold: DisplayHold?
    @ObservationIgnored private nonisolated(unsafe) var displayHoldTimeoutTask: Task<Void, Never>?
    /// Invalidates decoder reads that finish after a skip, source change or clear.
    @ObservationIgnored private var sourceGeneration = 0
    @ObservationIgnored private var sourceForFacts: FactsSource?

    /// Upper bound on how long a track change may keep showing the previous
    /// track. A gapless transition emits no `.ready`, and a slow volume can
    /// delay the database or cover read; neither may leave the old title up.
    static let displayHoldLimit: Duration = .milliseconds(350)

    /// The current item's own contribution to `sourceFacts`: the scanned
    /// columns of a local track, nothing for a stream. Kept aside so each
    /// refresh re-merges from it rather than accumulating the last decoder's
    /// answers onto the next track.
    @ObservationIgnored private var trackSourceFacts: NowPlayingSourceFacts?

    /// Stream URL of the playing internet radio station, nil for every other
    /// source (ADR-078 slice 5). Drives the strip's info button in radio mode.
    public private(set) var nowPlayingRadioStreamURL: String?
    /// The station's display name, kept aside so live ICY titles can take
    /// over `title` while the station moves to the artist line.
    public private(set) var nowPlayingRadioStationName: String?

    /// True when the queue has a current item of any source (library
    /// track, radio, Subsonic stream, podcast). Menu commands that act on
    /// "whatever is current" (Clear Queue) key off this rather than the
    /// library-track ID, which is nil for streams (ADR-081).
    public var hasCurrentItem: Bool {
        self.nowPlayingTrackID != nil
            || self.nowPlayingRadioStreamURL != nil
            || self.nowPlayingSubsonicSongID != nil
            || self.isPodcast
    }

    private let log = AppLogger.make(.ui)

    // MARK: - Init

    /// Creates a new `NowPlayingViewModel` bound to the given transport and database.
    /// Pass `scrobbleRepository` to show the pending-scrobbles indicator in the strip.
    public init(
        engine: any Transport,
        database: Database,
        scrobbleRepository: ScrobbleQueueRepository? = nil,
        subsonicCoverArtProvider: SubsonicCoverArtProvider? = nil
    ) {
        self.engine = engine
        self.database = database
        self.subsonicCoverArtProvider = subsonicCoverArtProvider
        self.startObservingState()
        if let qp = engine as? QueuePlayer {
            self.startObservingCurrentTrack(qp)
            self.startObservingSleepTimer(qp)
        }
        if let storedRate = UserDefaults.standard.object(forKey: "playback.rate") as? Double {
            let r = max(0.5, min(2.0, Float(storedRate)))
            self.playbackRate = r
            Task { await self.setRate(r) }
        }
        if let repo = scrobbleRepository {
            self.startObservingScrobbleStats(repo)
        }
    }

    deinit {
        // Cancel every long-lived observation loop. These closures all capture
        // [weak self] so they no-op once the VM is gone, but leaving the tasks
        // running is untidy and a real leak should the VM ever become per-window
        // rather than app-lifetime. Task.cancel() is safe from a nonisolated
        // deinit; the stored handles are Sendable. See #279.
        self.stateTask?.cancel()
        self.positionTask?.cancel()
        self.sleepTimerTask?.cancel()
        self.scrobbleStatsTask?.cancel()
        self.currentTrackTask?.cancel()
        self.initialItemSyncTask?.cancel()
        self.queueChangesTask?.cancel()
        self.streamTitleTask?.cancel()
        self.markerTask?.cancel()
        self.metadataTask?.cancel()
        self.displayHoldTimeoutTask?.cancel()
    }

    private func startObservingScrobbleStats(_ repo: ScrobbleQueueRepository) {
        self.scrobbleStatsTask = Task { [weak self] in
            do {
                for try await stats in repo.observeStats() {
                    self?.pendingScrobbleCount = stats.pending
                }
            } catch {
                AppLogger.make(.scrobble).warning(
                    "scrobble.nowPlaying.stats.failed",
                    ["error": String(reflecting: error)]
                )
            }
        }
    }

    // MARK: - Public API

    /// Set by the TracksView/AlbumsView when a track is selected and played.
    public func setCurrentTrack(_ track: Track) {
        self.metadataTask?.cancel()
        self.sourceGeneration &+= 1
        let generation = self.sourceGeneration
        self.sourceForFacts = .local(URL(string: track.fileURL))
        self.beginDisplayHold(for: track)
        self.log.info("playback.track", ["id": track.id ?? -1, "title": track.title ?? "?"])
        if self.isPodcast {
            // Switching from podcast to local track -- restore music rate and reset remote commands.
            if let qp = self.engine as? QueuePlayer {
                Task {
                    await qp.configureRemoteCommandsForMusic()
                    let musicRate = UserDefaults.standard.double(forKey: "playback.rate")
                    if musicRate > 0 {
                        let r = Float(max(0.5, min(2.0, musicRate)))
                        await qp.setRate(r)
                        self.playbackRate = r
                    }
                }
            }
        }
        self.isPodcast = false
        self.podcastID = nil
        self.podcastFeedURL = nil
        self.podcastGUID = nil
        self.currentTrack = track
        self.nowPlayingTrackID = track.id
        self.nowPlayingAlbumID = track.albumID
        self.nowPlayingArtistID = track.artistID
        // A local track is not a Subsonic stream; drop any stale stream identity.
        self.nowPlayingSubsonicServerID = nil
        self.nowPlayingSubsonicSongID = nil
        self.nowPlayingRadioStreamURL = nil
        self.nowPlayingRadioStationName = nil
        self.nowPlayingIsLoved = track.loved
        // The scanned columns are what the badges have until the decoder is
        // open; the codec only ever comes from the decoder.
        self.trackSourceFacts = NowPlayingSourceFacts(track: track)
        self.applySourceFacts(NowPlayingSourceFacts())
        self.title = track.title ?? L10n.string("Unknown Track")
        self.artist = ""
        self.album = ""
        self.duration = track.duration
        self.artwork = nil

        self.metadataTask = Task { [weak self] in
            await self?.resolveMetadata(for: track, generation: generation)
        }
    }

    /// Updates the loved state for the currently-playing track.
    /// Called by `LibraryViewModel.applyLoved` when the now-playing track is in the updated set.
    public func updateNowPlayingLoved(_ loved: Bool) {
        self.nowPlayingIsLoved = loved
    }

    // MARK: - Transport commands: the `NowPlayingViewModel` transport extension below

    /// Streams are never engine-preloaded, so a restored queue whose
    /// current item is a stream emits no current-track change at launch
    /// and the display (and everything keyed off it: the strip, the Clear
    /// Queue menu gate) would sit on "Not playing" forever (ADR-079
    /// flag). Called once after activation; engine-driven emissions
    /// overwrite the seeded display the moment anything actually loads.
    private func seedDisplayFromRestoredQueue(_ qp: QueuePlayer) async {
        guard let item = await qp.queue.currentItem else { return }
        if self.currentTrack == nil, !self.hasCurrentItem {
            await self.applyRestoredItem(item, player: qp)
        }
        // The queue stream may have seeded metadata before activation finished
        // restoring the position. Read that position after the activation gate.
        self.position = await qp.currentTime
    }

    /// Re-derives the display from the queue after a mutation that never
    /// reaches the engine (nothing loaded, nothing playing). An
    /// engine-loaded track owns the display, so this backs off then.
    private func syncDisplayWithQueueIfIdle(_ qp: QueuePlayer) async {
        guard self.currentTrack == nil else { return }
        guard let item = await qp.queue.currentItem else {
            if self.hasCurrentItem {
                self.clearNowPlayingDisplay()
            }
            return
        }
        await self.applyRestoredItem(item, player: qp)
    }

    /// Seed from SQLite metadata without opening the audio file at launch.
    private func applyRestoredItem(_ item: QueueItem, player: QueuePlayer) async {
        if case .localBookmark = item.playableSource {
            do {
                let track = try await TrackRepository(database: self.database).fetch(id: item.trackID)
                guard await player.queue.currentItem?.id == item.id else { return }
                self.setCurrentTrack(track)
            } catch {
                self.log.warning("nowplaying.restore.metadataFailed", ["error": String(reflecting: error)])
            }
        } else {
            await self.applyStreamItem(item)
        }
        self.position = await player.currentTime
    }

    /// Populates the now-playing display from a queue item that has no local
    /// `Track` row (e.g. a Subsonic stream or podcast), using the item's snapshot metadata.
    @discardableResult
    func applyStreamItem(_ item: QueueItem) async -> Int {
        self.metadataTask?.cancel()
        self.sourceGeneration &+= 1
        let generation = self.sourceGeneration
        self.sourceForFacts = .stream
        self.releaseDisplayHold()
        self.nowPlayingTrackID = nil
        self.nowPlayingAlbumID = nil
        self.nowPlayingArtistID = nil
        // A stream has no scanned columns: every badge it shows comes from
        // the decoder, and there is nothing to show until it is open.
        self.trackSourceFacts = nil
        self.sourceFacts = nil
        self.title = item.title ?? L10n.string("Unknown Track")
        self.artist = item.artistName ?? ""
        self.album = item.albumName ?? ""
        self.duration = item.duration
        self.artwork = nil

        if case let .podcast(feedURL, episodeGUID) = item.playableSource {
            self.nowPlayingRadioStreamURL = nil
            self.nowPlayingRadioStationName = nil
            await self.applyPodcastItem(feedURL: feedURL, episodeGUID: episodeGUID)
        } else if case let .subsonic(serverID, songID) = item.playableSource {
            self.isPodcast = false
            self.podcastID = nil
            self.podcastFeedURL = nil
            self.podcastGUID = nil
            self.nowPlayingSubsonicServerID = serverID
            self.nowPlayingSubsonicSongID = songID
            self.nowPlayingRadioStreamURL = nil
            self.nowPlayingRadioStationName = nil
            await self.loadSubsonicArtwork(serverID: serverID, songID: songID)
        } else if case let .internetRadio(streamURL) = item.playableSource {
            self.isPodcast = false
            self.podcastID = nil
            self.podcastFeedURL = nil
            self.podcastGUID = nil
            self.nowPlayingSubsonicServerID = nil
            self.nowPlayingSubsonicSongID = nil
            self.nowPlayingRadioStreamURL = streamURL.absoluteString
            self.nowPlayingRadioStationName = item.title
        } else {
            self.isPodcast = false
            self.podcastID = nil
            self.podcastFeedURL = nil
            self.podcastGUID = nil
            self.nowPlayingSubsonicServerID = nil
            self.nowPlayingSubsonicSongID = nil
            self.nowPlayingRadioStreamURL = nil
            self.nowPlayingRadioStationName = nil
        }
        return generation
    }

    /// Resets every now-playing display field; called when the queue is empty.
    func clearNowPlayingDisplay() {
        self.metadataTask?.cancel()
        self.sourceGeneration &+= 1
        self.sourceForFacts = nil
        self.releaseDisplayHold()
        self.nowPlayingTrackID = nil
        self.nowPlayingAlbumID = nil
        self.nowPlayingArtistID = nil
        self.nowPlayingSubsonicServerID = nil
        self.nowPlayingSubsonicSongID = nil
        self.nowPlayingRadioStreamURL = nil
        self.nowPlayingRadioStationName = nil
        self.isPodcast = false
        self.podcastID = nil
        self.podcastFeedURL = nil
        self.podcastGUID = nil
        self.title = ""
        self.artist = ""
        self.album = ""
        self.artwork = nil
        self.trackSourceFacts = nil
        self.sourceFacts = nil
    }

    private func startObservingSleepTimer(_ qp: QueuePlayer) {
        let timer = qp.sleepTimer
        self.sleepTimerTask = Task { [weak self] in
            // Poll the actor's remaining value at 1 s intervals to update the badge.
            while !Task.isCancelled {
                guard let self else { return }
                async let rem = timer.remaining
                async let fade = timer.fadeOut
                let (remaining, fadeOut) = await (rem, fade)
                self.sleepTimerRemaining = remaining
                self.sleepTimerFadeOut = fadeOut
                if remaining == nil {
                    self.sleepTimerActiveMinutes = nil
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func startObservingState() {
        self.stateTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.engine.state {
                guard !Task.isCancelled else { break }
                switch state {
                case .playing:
                    self.log.info("transport.state", ["state": "playing"])
                    self.isPlaying = true
                    self.isPaused = false
                    self.startPollingPosition()

                case .paused:
                    self.log.info("transport.state", ["state": "paused"])
                    self.isPlaying = false
                    self.isPaused = true
                    self.stopPollingPosition()
                    // The 500 ms polling cadence can leave `position` stale (or
                    // still at zero for a quick play/pause). Capture the engine's
                    // banked pause position so the scrubber freezes exactly where
                    // playback will resume.
                    self.position = await self.engine.currentTime

                // `.failed` shares the not-playing teardown; the engine has already
                // stopped and frozen the position, so we only add the user-facing alert.
                case .stopped, .idle, .ended, .failed:
                    self.log.info("transport.state", ["state": String(describing: state)])
                    self.isPlaying = false
                    self.isPaused = false
                    self.stopPollingPosition()
                    if state == .ended {
                        self.position = 0
                        // Queue played through to its end (#330).
                        Haptics.stateChange()
                    }
                    if case .failed = state {
                        self.onPlaybackError?()
                    }

                case .ready:
                    self.isPlaying = false
                    // The decoder is installed by the time `.ready` emits, so
                    // this is the first moment the codec can be read.
                    let generation = self.sourceGeneration
                    if await self.refreshSourceFacts(for: generation) {
                        self.noteDisplayDecoderReady(for: generation)
                    }

                case .loading:
                    break
                }
            }
        }
    }
}

// MARK: - NowPlayingViewModel transport

/// The transport commands the strip, the menus and the media keys call.
/// Same-file extension, so the private engine and log stay reachable, and
/// the class body stays inside the lint length limit (extensions do not
/// count toward it).
public extension NowPlayingViewModel {
    /// Toggles play/pause on the engine.
    func playPause() async {
        let start = Date()
        defer { self.log.debug("transport.playPause.end", ["ms": -start.timeIntervalSinceNow * 1000]) }
        do {
            let player = self.engine as? QueuePlayer
            if let player { await player.waitUntilActivated() }
            let playing = if let player { await player.isPlaying } else { self.isPlaying }
            let hasQueue = if let player { await !player.queue.items.isEmpty } else { false }
            self.log.debug("transport.playPause.start", ["action": playing ? "pause" : "play"])
            if playing {
                await self.engine.pause()
            } else if hasQueue || self.isPaused || self.hasCurrentItem {
                // Resume: either explicitly paused mid-playback, or stopped after a
                // session restore (engine loaded a track but never called play()).
                // QueuePlayer.play() handles the stopped-with-queue case internally,
                // so this correctly resumes the restored (possibly shuffled) queue
                // without discarding it.
                try await self.engine.play()
            } else {
                // Nothing is playing, nothing was paused, and no track has ever been
                // loaded, so hand off to the library callback so it queues the full
                // current browse view.  Covers first launch and cleared queues.
                self.onPlayFromEmptyQueue?()
            }
        } catch {
            self.log.error("transport.playPause.failed", ["error": String(reflecting: error)])
        }
    }

    /// Seek to an absolute position.
    func scrub(to time: TimeInterval) async {
        Haptics.positionCommit()
        let trackID = self.nowPlayingTrackID
        do {
            try await self.engine.seek(to: time)
            // Position polling stops while paused. Read the engine back so a
            // lyric click updates both the scrubber and highlight immediately.
            let position = await self.engine.currentTime
            guard self.nowPlayingTrackID == trackID else { return }
            self.position = position
        } catch {
            self.log.error("transport.seek.failed", ["error": String(reflecting: error)])
        }
    }

    /// Clamps and applies volume to the engine; preserves mute state.
    func setVolume(_ newVolume: Float) async {
        self.volume = min(1, max(0, newVolume))
        if !self.isMuted {
            await self.engine.setVolume(self.volume)
        }
    }

    /// Toggles mute; preserves stored volume so unmuting restores the previous level.
    func toggleMute() async {
        if self.isMuted {
            self.isMuted = false
            await self.engine.setVolume(self.volume)
        } else {
            self.isMuted = true
            await self.engine.setVolume(0)
        }
    }

    /// Steps volume up by 10%, clamped to 1.0.
    func increaseVolume() async {
        await self.setVolume(min(1.0, self.volume + 0.1))
    }

    /// Steps volume down by 10%, clamped to 0.0.
    func decreaseVolume() async {
        await self.setVolume(max(0.0, self.volume - 0.1))
    }

    /// Skips to previous. Delegates to `QueuePlayer.previous()`, which owns
    /// the restart threshold AND the CUE-marker semantics (ADR-087); a
    /// local shortcut here would make the strip's button disagree with media
    /// keys. Falls back to a plain restart for non-QueuePlayer engines.
    func previous() async {
        guard let qp = self.engine as? QueuePlayer else {
            let pos = await self.engine.currentTime
            if pos > 3.0 {
                await self.scrub(to: 0)
            }
            return
        }
        do { try await qp.previous() } catch {
            self.log.error("transport.previous.failed", ["error": String(reflecting: error)])
        }
    }

    /// Restarts the current track from position 0, regardless of position.
    func restartTrack() async {
        await self.scrub(to: 0)
    }

    /// Skips to the next track (no-op if engine is not a QueuePlayer).
    func next() async {
        let end = Telemetry.timer("playback.next")
        defer { end() }
        guard let qp = engine as? QueuePlayer else { return }
        do { try await qp.next() } catch {
            self.log.error("transport.next.failed", ["error": String(reflecting: error)])
        }
    }

    /// Toggles shuffle on the queue player.
    func toggleShuffle() async {
        await self.setShuffle(!self.shuffleOn)
    }

    /// Sets shuffle to an explicit value on the queue player.
    func setShuffle(_ on: Bool) async {
        guard let qp = engine as? QueuePlayer else { return }
        if !(await qp.queue.hasKnownSourceOrder) {
            let snapshot = await qp.queue.snapshot()
            if let orderedIDs = self.onResolveLegacyQueueOrder?(snapshot.items, snapshot.currentIndex) {
                await qp.queue.rebaseSourceOrder(orderedIDs)
            }
        }
        await qp.setShuffle(on)
        self.shuffleOn = on
    }

    /// Cycles to the next repeat mode (off → all → one → off).
    func cycleRepeat() async {
        guard let qp = engine as? QueuePlayer else { return }
        let next: RepeatMode = switch self.repeatMode {
        case .off:
            .all

        case .all:
            .one

        case .one:
            .off
        }
        await qp.setRepeat(next)
        self.repeatMode = next
    }

    /// Toggles the stop-after-current flag on the queue player.
    func toggleStopAfterCurrent() async {
        guard let qp = engine as? QueuePlayer else { return }
        let new = !self.stopAfterCurrent
        await qp.setStopAfterCurrent(new)
        self.stopAfterCurrent = new
    }

    /// Set playback rate (0.5x-2.0x) with pitch correction.
    /// Saves to `podcast.playback.rate` when a podcast is playing, `playback.rate` otherwise.
    func setRate(_ rate: Float) async {
        guard let qp = engine as? QueuePlayer else { return }
        await qp.setRate(rate)
        self.playbackRate = max(0.5, min(2.0, rate))
        if self.isPodcast {
            UserDefaults.standard.set(Double(self.playbackRate), forKey: "podcast.playback.rate")
        } else {
            UserDefaults.standard.set(Double(self.playbackRate), forKey: "playback.rate")
        }
    }

    /// Steps up to the next quick rate above the current rate.
    func increaseSpeed() async {
        let next = Self.quickRates.first { $0 > self.playbackRate + 0.01 }
        await self.setRate(next ?? 2.0)
    }

    /// Steps down to the next quick rate below the current rate.
    func decreaseSpeed() async {
        let prev = Self.quickRates.last { $0 < self.playbackRate - 0.01 }
        await self.setRate(prev ?? 0.75)
    }

    /// Resets playback speed to 1.0x.
    func resetSpeed() async {
        await self.setRate(1.0)
    }

    /// Quick-pick rates shared with `SpeedPickerView` and the Playback menu.
    static let quickRates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    /// Sleep timer presets shared with the Playback menu.
    static let sleepPresets: [(label: String, minutes: Int?)] = [
        (L10n.string("Off"), nil),
        (L10n.string("15 min"), 15),
        (L10n.string("30 min"), 30),
        (L10n.string("45 min"), 45),
        (L10n.string("1 hr"), 60),
        (L10n.string("1 hr 30 min"), 90),
        (L10n.string("2 hr"), 120),
    ]

    /// Configure the sleep timer.  Pass `nil` minutes to cancel.
    func setSleepTimer(minutes: Int?, fadeOut: Bool = false) async {
        guard let qp = engine as? QueuePlayer else { return }
        await qp.sleepTimer.set(minutes: minutes, fadeOut: fadeOut)
        self.sleepTimerFadeOut = fadeOut
        self.sleepTimerActiveMinutes = minutes
        if minutes == nil {
            self.sleepTimerRemaining = nil
        }
    }
}

// MARK: - NowPlayingViewModel podcast transport

/// Podcast skip-interval transport actions.
public extension NowPlayingViewModel {
    /// Skip backward by the configured podcast skip-back interval (default 15 s).
    func skipBack() async {
        let interval = UserDefaults.standard.double(forKey: "podcasts.skipBackInterval")
        let secs = interval > 0 ? interval : 15
        await self.scrub(to: max(0, self.position - secs))
    }

    /// Skip forward by the configured podcast skip-forward interval (default 30 s).
    func skipForward() async {
        let interval = UserDefaults.standard.double(forKey: "podcasts.skipForwardInterval")
        let secs = interval > 0 ? interval : 30
        await self.scrub(to: min(self.duration, self.position + secs))
    }
}

// MARK: - NowPlayingViewModel private helpers

extension NowPlayingViewModel {
    /// Resolves the starting podcast rate when an episode begins: a per-show
    /// override wins, else the global `podcast.playback.rate` default, else 1.0;
    /// clamped to [0.5, 2.0]. A manual `SpeedPickerView` change overrides live and
    /// is not written back to the per-show value.
    nonisolated static func resolvePodcastRate(showSpeed: Double?, globalRate: Double) -> Float {
        let effective = showSpeed ?? (globalRate > 0 ? globalRate : 1.0)
        return Float(max(0.5, min(2.0, effective)))
    }
}

private extension NowPlayingViewModel {
    func startPollingPosition() {
        self.stopPollingPosition()
        self.positionTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let pos = await engine.currentTime
                let dur = await engine.duration
                // Cancellation can happen while either actor read is suspended.
                // Do not let that stale tick overwrite the final position captured
                // by the paused-state handler.
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.position = pos
                    if dur > 0 {
                        self.duration = dur
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 s
            }
        }
    }

    func stopPollingPosition() {
        self.positionTask?.cancel()
        self.positionTask = nil
    }

    /// Prefers the episode's own cached art over the show's; with `retry`,
    /// looks again after a short delay for art still being fetched.
    private func applyEpisodeArtwork(podcastID: Int64, guid: String, retry: Bool) async {
        let repo = EpisodeRepository(database: self.database)
        // Qualified: the Subsonic client exports a `PodcastEpisode` too.
        let episode: Persistence.PodcastEpisode?
        do {
            episode = try await repo.fetchByGUID(podcastID: podcastID, guid: guid)
        } catch {
            // Now Playing falls back to the show's art, which looks like a feed
            // that supplied no episode art rather than a failed read (#491).
            self.log.warning("nowplaying.episodeArt.lookupFailed", [
                "guid": guid,
                "error": String(reflecting: error),
            ])
            episode = nil
        }
        if let path = episode?.artworkPath {
            self.artwork = await ArtworkLoader.shared.image(at: path)
            return
        }
        guard retry, episode?.artworkURL != nil else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.podcastGUID == guid else { return }
            await self.applyEpisodeArtwork(podcastID: podcastID, guid: guid, retry: false)
        }
    }

    /// Fills podcast-specific now-playing state when the current queue item is a podcast episode.
    func applyPodcastItem(feedURL: URL, episodeGUID: String) async {
        self.isPodcast = true
        self.podcastFeedURL = feedURL
        self.podcastGUID = episodeGUID
        self.nowPlayingSubsonicServerID = nil
        self.nowPlayingSubsonicSongID = nil
        let repo = PodcastRepository(database: self.database)
        // Qualified: the Subsonic client exports a `Podcast` too.
        let podcast: Persistence.Podcast?
        do {
            podcast = try await repo.fetchByFeedURLIgnoringScheme(feedURL.absoluteString)
        } catch {
            // Without the show row there is no podcast ID and no show artwork,
            // so Now Playing quietly loses its podcast detail (#491).
            self.log.warning("nowplaying.podcastLookup.failed", ["error": String(reflecting: error)])
            podcast = nil
        }
        self.podcastID = podcast?.id
        if let path = podcast?.artworkPath {
            self.artwork = await ArtworkLoader.shared.image(at: path)
        }
        // Episode art overrides the show's when the feed supplies it (ADR-047,
        // #410). It is cached lazily when playback resolves the episode, so on
        // a first play it may land a moment after this runs: re-check once.
        if let podcastID = podcast?.id {
            await self.applyEpisodeArtwork(podcastID: podcastID, guid: episodeGUID, retry: true)
        }
        if let qp = self.engine as? QueuePlayer {
            let back = UserDefaults.standard.double(forKey: "podcasts.skipBackInterval")
            let fwd = UserDefaults.standard.double(forKey: "podcasts.skipForwardInterval")
            await qp.configureRemoteCommandsForPodcast(
                backInterval: back > 0 ? back : 15,
                forwardInterval: fwd > 0 ? fwd : 30
            )
            let savedRate = UserDefaults.standard.double(forKey: "podcast.playback.rate")
            let r = Self.resolvePodcastRate(showSpeed: podcast?.playbackSpeed, globalRate: savedRate)
            await qp.setRate(r)
            self.playbackRate = r
        }
    }

    func loadSubsonicArtwork(serverID: UUID, songID: String) async {
        guard let provider = self.subsonicCoverArtProvider else { return }
        do {
            guard let url = try await provider.coverArtURL(serverID: serverID, entityID: songID) else {
                return
            }
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = NSImage(data: data) else { return }
            // Only apply if the same Subsonic song is still current.
            if let qp = self.engine as? QueuePlayer,
               let item = await qp.queue.currentItem,
               case let .subsonic(_, currentSongID) = item.playableSource,
               currentSongID == songID {
                self.artwork = image
            }
        } catch {
            self.log.warning(
                "nowplaying.subsonic.artwork.failed",
                ["songID": songID, "error": String(reflecting: error)]
            )
        }
    }

    func resolveMetadata(for track: Track, generation: Int) async {
        guard !Task.isCancelled else { return }
        let trackID = track.id
        var resolvedArtist = ""
        var resolvedAlbum = ""
        var resolvedArtwork: NSImage?
        var artworkPath: String?
        do {
            // Resolve artist name
            if let artistID = track.artistID {
                let artistRecord = try await database.read { db in
                    try Artist.fetchOne(db, key: artistID)
                }
                guard !Task.isCancelled else { return }
                resolvedArtist = artistRecord?.name ?? ""
            }

            // Resolve album name
            if let albumID = track.albumID {
                let albumRecord = try await database.read { db in
                    try Album.fetchOne(db, key: albumID)
                }
                guard !Task.isCancelled else { return }
                resolvedAlbum = albumRecord?.title ?? ""

                // Resolve cover art
                if let hash = track.coverArtHash ?? albumRecord?.coverArtHash {
                    let artRecord = try await database.read { db in
                        try CoverArt.fetchOne(db, key: hash)
                    }
                    guard !Task.isCancelled else { return }
                    if let path = artRecord?.path {
                        artworkPath = path
                        resolvedArtwork = await ArtworkLoader.shared.image(at: path)
                    }
                }
            }

            // A quick skip may finish an older database/artwork read after the
            // next track starts. Publish related fields together, once, only
            // for the task and track that still own the display.
            guard !Task.isCancelled,
                  generation == self.sourceGeneration,
                  self.nowPlayingTrackID == trackID,
                  self.currentTrack == track else { return }
            self.artist = resolvedArtist
            self.album = resolvedAlbum
            self.artwork = resolvedArtwork
            self.noteDisplayMetadataReady(for: track, generation: generation)
            await self.postTrackChangeNotification(
                title: self.title,
                artist: resolvedArtist,
                artworkPath: artworkPath
            )
        } catch {
            if !Task.isCancelled {
                self.log.error("nowplaying.resolve.failed", ["error": String(reflecting: error)])
                self.noteDisplayMetadataReady(for: track, generation: generation)
            }
        }
    }

    /// Posts a `UNNotification` banner when a new track starts (if enabled and app is not frontmost).
    func postTrackChangeNotification(title: String, artist: String, artworkPath: String?) async {
        let settingOn = UserDefaults.standard.bool(forKey: "general.showNotifications")
        let appActive = NSApp?.isActive ?? true
        self.log.debug("notifications.attempt", ["settingOn": settingOn, "appActive": appActive, "title": title])
        guard settingOn else { return }
        guard !appActive else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            self.log.warning(
                "notifications.skipped",
                ["reason": "not authorized", "authStatus": String(describing: settings.authorizationStatus)]
            )
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        if !artist.isEmpty {
            content.subtitle = artist
        }
        content.sound = nil

        if let path = artworkPath {
            let sourceURL = URL(fileURLWithPath: path)
            // UNNotificationAttachment moves the file into its own data store, which
            // fails when the source is inside the app sandbox container (daemon
            // cross-process access is denied). Copy to a world-readable temp location first.
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(sourceURL.pathExtension)
            if (try? FileManager.default.copyItem(at: sourceURL, to: tempURL)) != nil,
               let attachment = try? UNNotificationAttachment(identifier: "artwork", url: tempURL) {
                content.attachments = [attachment]
            }
        }

        // Re-using the same identifier replaces any still-visible previous banner.
        let request = UNNotificationRequest(
            identifier: "bocan.trackChange",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            self.log.info("notifications.posted", ["title": title])
        } catch {
            self.log.error("notifications.add.failed", ["error": String(reflecting: error)])
        }
    }
}

// MARK: - Current-item observation

/// Split out of the class body to stay inside the `type_body_length` lint
/// limit; same-file extension so the private task handles stay reachable.
private extension NowPlayingViewModel {
    func startObservingCurrentTrack(_ qp: QueuePlayer) {
        self.currentTrackTask = Task { [weak self] in
            guard let self else { return }
            for await track in qp.currentTrackChanges {
                if let track {
                    self.setCurrentTrack(track)
                    let generation = self.sourceGeneration
                    _ = await self.refreshSourceFacts(for: generation)
                } else if let item = await qp.queue.currentItem {
                    let generation = await self.applyStreamItem(item)
                    _ = await self.refreshSourceFacts(for: generation)
                } else {
                    // Stopping leaves the last decoder installed, so the
                    // cleared display must not ask it anything.
                    self.clearNowPlayingDisplay()
                }
            }
        }
        self.initialItemSyncTask = Task { [weak self] in
            await qp.waitUntilActivated()
            await self?.seedDisplayFromRestoredQueue(qp)
        }
        self.startObservingStreamExtras(qp)
        // Observe queue changes to keep UI state (shuffle, repeat, stop-after-current) in sync.
        self.queueChangesTask = Task { [weak self] in
            guard let self else { return }
            // Subscribe before any other read. The queue registers the
            // subscriber synchronously, so nothing emitted after this line
            // can be missed; the three reads below each hop to the queue
            // actor, and a replace landing in that window used to go unseen
            // by both this loop and the one-shot seed above (#451).
            let changes = await qp.queue.changes()
            let initialRepeat = await qp.queue.repeatMode
            let initialShuffle = await qp.queue.shuffleState
            let initialStopAfter = await qp.queue.stopAfterCurrent
            self.repeatMode = initialRepeat
            self.shuffleOn = initialShuffle != .off
            self.stopAfterCurrent = initialStopAfter
            // Whatever the queue held before the subscription is not on the
            // stream: derive the display from it once, then follow the stream.
            await self.syncDisplayWithQueueIfIdle(qp)

            for await change in changes {
                switch change {
                case let .stopAfterCurrentChanged(enabled):
                    self.stopAfterCurrent = enabled

                case let .repeatChanged(mode):
                    self.repeatMode = mode

                case let .shuffleChanged(state):
                    self.shuffleOn = state != .off

                case .reset, .cleared, .currentChanged:
                    // Queue mutations that swap the current item touch the
                    // engine only while something is playing; a replaced or
                    // cleared queue at rest (the seeded E2E radio queue, a
                    // stopped queue being cleared) emits no current-track
                    // change, so re-derive the display from the queue.
                    await self.syncDisplayWithQueueIfIdle(qp)

                default:
                    break
                }
            }
        }
    }
}

// MARK: - Source facts (ADR-092)

/// Same-file extension so the private engine and the seeded columns stay
/// reachable, and the class body stays inside the `type_body_length` limit.
private extension NowPlayingViewModel {
    /// Re-derives `sourceFacts` from the open decoder over the current item's
    /// own columns. Called where the engine has just taken on a source: the
    /// current-item stream (the only signal a gapless transition gives) and
    /// the `.ready` that follows every load.
    ///
    /// The engine is asked rather than cached: it is the only place that
    /// knows which decoder is installed right now.
    func refreshSourceFacts(for generation: Int) async -> Bool {
        guard let source = self.sourceForFacts,
              generation == self.sourceGeneration else { return false }
        if let snapshot = await self.engine.currentSourceFactsSnapshot {
            guard !Task.isCancelled, generation == self.sourceGeneration else { return false }
            if case let .local(expectedURL) = source {
                guard let expectedURL, let actualURL = snapshot.sourceURL,
                      expectedURL.standardizedFileURL.resolvingSymlinksInPath()
                      == actualURL.standardizedFileURL.resolvingSymlinksInPath() else { return false }
            }
            self.applySourceFacts(NowPlayingSourceFacts(details: snapshot.streamDetails, codec: snapshot.codec))
            return true
        }
        // Simple transports without identity retain the generation-checked
        // legacy path; a real engine's empty snapshot never falls through.
        let details = await self.engine.currentStreamDetails
        guard !Task.isCancelled, generation == self.sourceGeneration else { return false }
        let codec = await self.engine.currentCodec
        guard !Task.isCancelled, generation == self.sourceGeneration else { return false }
        self.applySourceFacts(NowPlayingSourceFacts(details: details, codec: codec))
        return true
    }

    /// Merges live decoder facts over the current item's columns, and leaves
    /// `sourceFacts` nil when the two together say nothing.
    func applySourceFacts(_ live: NowPlayingSourceFacts) {
        let merged = (self.trackSourceFacts ?? NowPlayingSourceFacts()).merging(live)
        self.sourceFacts = merged.isEmpty ? nil : merged
    }
}

// MARK: - Stream extras (ICY titles + CUE markers)

private extension NowPlayingViewModel {
    /// Live ICY titles (ADR-078 slice 5) and CUE markers (ADR-087). While a
    /// station plays, the stream title takes the title line and the station
    /// name moves to the artist line; junk or absent titles never emit.
    /// Markers arrive on every load — empty for tracks without them — so the
    /// strip's ticks and marker line follow the current track.
    func startObservingStreamExtras(_ qp: QueuePlayer) {
        self.streamTitleTask = Task { [weak self] in
            guard let self else { return }
            for await streamTitle in qp.streamTitleUpdates {
                guard self.nowPlayingRadioStreamURL != nil else { continue }
                self.title = streamTitle
                if let station = self.nowPlayingRadioStationName, !station.isEmpty {
                    self.artist = station
                }
            }
        }
        self.markerTask = Task { [weak self] in
            guard let self else { return }
            for await markers in qp.markerUpdates {
                self.markers = markers
            }
        }
    }
}

// MARK: - Display snapshot

/// Same-file extension so the private hold state stays reachable, and the
/// class body stays inside the `type_body_length` limit.
extension NowPlayingViewModel {
    enum FactsSource {
        case local(URL?)
        case stream
    }

    struct DisplayHold {
        let track: Track
        let generation: Int
        var metadataReady = false
        var decoderReady = false
    }

    /// Copies the live fields into `display` unless a track change is still
    /// being resolved. Skips identical values so observers are not woken.
    func syncDisplay() {
        guard self.displayHold == nil else { return }
        let next = NowPlayingDisplay(
            title: self.title,
            artist: self.artist,
            album: self.album,
            artwork: self.artwork,
            sourceFacts: self.sourceFacts
        )
        if next != self.display {
            self.display = next
        }
    }

    /// Keeps the previous track on screen while `track` resolves. The first
    /// track after idle has nothing to keep, so it draws at once.
    func beginDisplayHold(for track: Track) {
        self.displayHoldTimeoutTask?.cancel()
        self.displayHoldTimeoutTask = nil
        guard !self.display.title.isEmpty else {
            self.displayHold = nil
            return
        }
        let generation = self.sourceGeneration
        self.displayHold = DisplayHold(track: track, generation: generation)
        self.displayHoldTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.displayHoldLimit)
            guard !Task.isCancelled, self?.sourceGeneration == generation else { return }
            self?.releaseDisplayHold()
        }
    }

    func noteDisplayMetadataReady(for track: Track, generation: Int) {
        guard var hold = self.displayHold,
              hold.track == track,
              hold.generation == generation,
              self.sourceGeneration == generation else { return }
        hold.metadataReady = true
        self.advanceDisplayHold(hold)
    }

    /// `.ready` follows every engine load, after the new decoder is
    /// installed; the facts refreshed at the track-change event may still
    /// describe the outgoing decoder.
    func noteDisplayDecoderReady(for generation: Int) {
        guard var hold = self.displayHold,
              hold.generation == generation,
              self.sourceGeneration == generation else { return }
        hold.decoderReady = true
        self.advanceDisplayHold(hold)
    }

    private func advanceDisplayHold(_ hold: DisplayHold) {
        if hold.metadataReady, hold.decoderReady {
            self.releaseDisplayHold()
        } else {
            self.displayHold = hold
        }
    }

    /// Ends any hold and publishes the live fields in one assignment.
    func releaseDisplayHold() {
        self.displayHoldTimeoutTask?.cancel()
        self.displayHoldTimeoutTask = nil
        self.displayHold = nil
        self.syncDisplay()
    }
}
