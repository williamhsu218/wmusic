import AppKit
import SwiftUI

// MARK: - NowPlayingStrip

/// The 72pt-tall transport bar anchored at the bottom of every main view.
///
/// Shows current track artwork, title/artist/album, play/pause and scrubber,
/// and a volume slider.
public struct NowPlayingStrip: View {
    public var vm: NowPlayingViewModel
    @EnvironmentObject private var library: LibraryViewModel

    /// While dragging the scrubber, the fraction is held locally so the Slider
    /// doesn't fight live `vm.position` updates; seeking happens on release.
    @AppStorage("appearance.accentColor") private var accentColorKey = "system"
    @State private var scrubDragFraction: Double?
    /// Menu-to-strip signal (BocanCommands sets it); cleared at launch by BocanApp.
    @AppStorage("scrobble.showRecentSheet") private var showRecentScrobbles = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Optional — only the main window injects a `ScrobbleSettingsViewModel`.
    /// When non-nil and `vm.pendingScrobbleCount > 0`, a pending-scrobbles
    /// indicator is shown in the panel-buttons area.
    var scrobbleSettingsVM: ScrobbleSettingsViewModel?
    var openExpandedNowPlaying: () -> Void
    var prewarmExpandedNowPlaying: () -> Void

    public init(
        vm: NowPlayingViewModel,
        scrobbleSettingsVM: ScrobbleSettingsViewModel? = nil,
        openExpandedNowPlaying: @escaping () -> Void = {},
        prewarmExpandedNowPlaying: @escaping () -> Void = {}
    ) {
        self.vm = vm
        self.scrobbleSettingsVM = scrobbleSettingsVM
        self.openExpandedNowPlaying = openExpandedNowPlaying
        self.prewarmExpandedNowPlaying = prewarmExpandedNowPlaying
    }

    public var body: some View {
        HStack(spacing: 6) {
            self.trackIdentity
            Spacer(minLength: 0)
            self.transport
            Spacer(minLength: 0)
            self.volumeAndScrubber
            Spacer(minLength: 0)
            Divider()
                .frame(height: 32)
                .padding(.horizontal, 4)
            self.panelButtons
        }
        .frame(height: Theme.nowPlayingStripHeight)
        .padding(.horizontal, 16)
        .adaptiveMaterial()
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11y.NowPlaying.strip)
        .sheet(isPresented: self.$showRecentScrobbles) {
            if let ssvm = self.scrobbleSettingsVM {
                RecentScrobblesView(viewModel: ssvm)
            }
        }
    }

    // MARK: - Sub-views

    /// The drawn snapshot of the current item. It changes once per track,
    /// after the title, subtitle, cover and badges are all known.
    private var display: NowPlayingDisplay { self.vm.display }

    /// The cover and text keep their view identity across track changes:
    /// the text is replaced in place and only a different cover cross-fades.
    /// Rebuilding the whole block per track (`.id` + an offset transition)
    /// faded it out and in even when only the title changed.
    private var trackIdentity: some View {
        HStack(spacing: 12) {
            self.artwork
            self.trackInfo
        }
        // Fill the width offered by the outer frame so a short/long title
        // cannot shift the controls beside this region on each track change.
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minWidth: 220, maxWidth: 440, alignment: .leading)
        .clipped()
    }

    private var artwork: some View {
        Button {
            self.openExpandedNowPlaying()
        } label: {
            ZStack {
                Group {
                    if let img = self.display.artwork {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        GradientPlaceholder(seed: 0)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: Theme.artworkCornerRadius, style: .continuous))
                // Keyed on the image object, not the track: the same album's
                // next song reuses the cached cover and does not fade.
                .id(self.display.artworkIdentity)
                .transition(.opacity)
            }
            .frame(width: 48, height: 48)
            .animation(self.reduceMotion ? nil : .easeOut(duration: 0.15), value: self.display.artworkIdentity)
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .disabled(self.display.title.isEmpty)
        .help(L10n.string("Now Playing"))
        .accessibilityLabel(L10n.string("Now Playing"))
        .accessibilityIdentifier(A11y.NowPlaying.artworkButton)
        .onHover { isHovering in
            if isHovering { self.prewarmExpandedNowPlaying() }
        }
    }

    /// The title line, shared by the jump-button and plain-text renderings so
    /// both stay pixel-identical: full-strength while something plays, dimmed
    /// only for the idle "Not playing" placeholder.
    private var titleText: some View {
        Text(self.display.title.isEmpty ? L10n.string("Not playing") : self.display.title)
            .font(Typography.body)
            .foregroundStyle(self.display.title.isEmpty ? Color.textSecondary : Color.textPrimary)
            .lineLimit(1)
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Title — click to jump to current track in the track list. Radio
            // and podcast items have no tracks row to jump to; render plain
            // text there instead of a permanently disabled button, whose
            // plain-style dimming greyed the title down to subtitle strength.
            if self.vm.nowPlayingTrackID != nil {
                Button {
                    Task { await self.library.scrollToNowPlayingTrack() }
                } label: {
                    self.titleText
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .help(L10n.string("Jump to \"\(self.display.title)\" in track list"))
                .keyboardShortcut(KeyBindings.jumpToCurrentTrack)
                .accessibilityLabel(L10n.string("Jump to \(self.display.title) in track list"))
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier(A11y.NowPlaying.titleButton)
            } else {
                self.titleText
                    .accessibilityLabel(self.display.title.isEmpty ? L10n.string("Not playing") : self.display.title)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier(A11y.NowPlaying.titleButton)
            }

            // Artist/show — click to navigate to the artist or podcast show.
            if !self.display.artist.isEmpty {
                Button {
                    if self.vm.isPodcast, let id = self.vm.podcastID {
                        Task { await self.library.selectDestination(.podcastShow(id)) }
                    } else {
                        Task { await self.library.goToCurrentArtist() }
                    }
                } label: {
                    Text(self.vm.isPodcast ? self.display.artist : (self.trackSubtitle ?? self.display.artist))
                        .font(Typography.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .disabled(self.vm.isPodcast ? self.vm.podcastID == nil : self.vm.nowPlayingArtistID == nil)
                .help(self.vm.isPodcast
                    ? (self.vm.podcastID != nil ? L10n.string("Go to podcast show") : self.display.artist)
                    : (self.vm.nowPlayingArtistID != nil ? L10n.string("Go to artist: \(self.display.artist)") : self.display.artist))
                .keyboardShortcut(KeyBindings.goToCurrentArtist)
                .accessibilityLabel(self.vm.isPodcast
                    ? L10n.string("Go to podcast show")
                    : L10n.string("Go to artist \(self.display.artist)"))
                .accessibilityIdentifier(A11y.NowPlaying.subtitleButton)
            } else if !self.display.title.isEmpty {
                // Keep the line's height so a track without an artist does
                // not move the title and badges.
                Text(verbatim: " ")
                    .font(Typography.subheadline)
                    .accessibilityHidden(true)
            }

            if let chapter = self.currentChapter {
                Text(verbatim: chapter.title)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            } else if let marker = self.currentMarkerText {
                // CUE marker line (ADR-087): cue content renders verbatim,
                // same as podcast chapter titles.
                Text(verbatim: marker)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier(A11y.NowPlaying.markerLine)
            }

            // Codec, bitrate, sample rate, bit depth and channels (ADR-092).
            // The line is reserved while anything is loaded, so badges that
            // are absent for one item cannot change the block's height.
            if !self.display.title.isEmpty {
                ZStack(alignment: .leading) {
                    Text(verbatim: "0")
                        .font(Typography.mini)
                        .padding(.vertical, 1)
                        .hidden()
                        .accessibilityHidden(true)
                    if let facts = self.display.sourceFacts {
                        SourceBadgesRow(facts: facts)
                    }
                }
                .padding(.top, 2)
            }
        }
        // Centred in the bar, and 160...380 rather than 120...300 (#536).
        //
        // Measured: everything else on the strip costs 668 pt before this
        // block and the scrubber divide what is left, and the transport alone
        // is 317 of it. The floor is what pays at a narrow window: at 900 pt
        // the block is pinned to it, and 160 shows appreciably more title than
        // 120 did. The ceiling only bites above about 1300 pt, where a long
        // title now gets the room instead of stopping at 300. In between, at
        // the 1100 pt default window, the block already takes close to its
        // ideal width and neither bound moves it; a longer title still
        // truncates there, and only a narrower transport or a minimum window
        // width would change that.
        .frame(minWidth: 160, maxWidth: 380, alignment: .leading)
        // Announce the completed snapshot, so the artist is included.
        .onChange(of: self.display.title) { _, title in
            guard self.vm.nowPlayingTrackID != nil, !title.isEmpty else { return }
            let msg = self.display.artist.isEmpty
                ? self.display.title
                : L10n.string("\(self.display.title) by \(self.display.artist)")
            NSAccessibility.post(
                element: NSApplication.shared,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: msg,
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                ]
            )
        }
    }

    private var trackSubtitle: String? {
        let parts = [self.display.artist, self.display.album]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }

    private var currentChapter: UIChapter? {
        guard self.vm.isPodcast else { return nil }
        return self.library.podcasts.nowPlayingChapters.current(at: self.vm.position)
    }

    /// "Title - Performer" for the CUE marker playback is inside (ADR-087).
    private var currentMarkerText: String? {
        guard let marker = self.vm.currentMarker else { return nil }
        let parts = [marker.title, marker.performer]
            .compactMap(\.self)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }

    @ViewBuilder
    private var transport: some View {
        if self.vm.isPodcast {
            PodcastTransportControls(
                vm: self.vm,
                loadTranscript: {
                    guard let podcastID = self.vm.podcastID, let guid = self.vm.podcastGUID else { return nil }
                    return await self.library.podcasts.loadTranscript(podcastID: podcastID, guid: guid)
                },
                chapters: self.library.podcasts.nowPlayingChapters,
                episode: self.library.podcasts.nowPlayingEpisode,
                showPersons: self.library.podcasts.nowPlayingShowPersons,
                podrollContext: PodrollContext(
                    items: self.library.podcasts.nowPlayingPodroll,
                    resolve: { await self.library.podcasts.resolvePodroll($0) },
                    onSelect: { self.library.openPodcastRecommendation($0) }
                )
            )
            // Key on podcastID *and* GUID: applyPodcastItem sets the GUID first and
            // resolves podcastID a beat later, so keying on the GUID alone can fire
            // while podcastID is still nil, bail, and never re-run -- leaving the
            // Show Notes button greyed even though chapters/notes are loadable.
            .task(id: "\(self.vm.podcastID ?? -1)|\(self.vm.podcastGUID ?? "")") {
                guard let podcastID = self.vm.podcastID, let guid = self.vm.podcastGUID else {
                    self.library.podcasts.clearNowPlayingChapters()
                    return
                }
                await self.library.podcasts.loadChapters(podcastID: podcastID, guid: guid)
                await self.library.podcasts.loadNowPlayingShowNotes(podcastID: podcastID, guid: guid)
            }
        } else {
            MusicTransportControls(vm: self.vm, library: self.library)
        }
    }

    /// Speed, sleep timer, pending scrobbles, DSP and Immersive Mode; see
    /// `NowPlayingPanelButtons`.
    private var panelButtons: some View {
        NowPlayingPanelButtons(vm: self.vm, scrobbleSettingsVM: self.scrobbleSettingsVM)
    }

    private var volumeAndScrubber: some View {
        VStack(spacing: 4) {
            self.scrubber
            self.volumeRow
        }
        // 300 rather than 340. At a narrow window the scrubber is squeezed
        // well below either figure, and asking for 340 made it worse: the
        // 0:00 and 5:00 labels closed on the thumb until they touched it at
        // 900 pt. Asking for less leaves the slider a legible track.
        .frame(maxWidth: 300)
    }

    private var scrubber: some View {
        HStack(spacing: 6) {
            Text(Formatters.duration(self.displayPosition))
                .font(Typography.caption)
                .foregroundStyle(Color.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: self.timeLabelWidth, alignment: .trailing)

            Slider(
                value: Binding(
                    get: {
                        if let drag = self.scrubDragFraction {
                            return drag
                        }
                        return self.vm.duration > 0 ? self.vm.position / self.vm.duration : 0
                    },
                    set: { fraction in
                        // Hold the drag locally; seek once on release, not per move.
                        self.scrubDragFraction = fraction
                    }
                ),
                in: 0 ... 1
            ) { editing in
                if !editing, let fraction = self.scrubDragFraction {
                    let target = fraction * self.vm.duration
                    self.scrubDragFraction = nil
                    Task { await self.vm.scrub(to: target) }
                }
            }
            .controlSize(.mini)
            .disabled(self.vm.duration == 0)
            .id(self.accentColorKey)
            .help(L10n.string("Scrub to position"))
            .accessibilityLabel(L10n.string("Playback position"))
            .accessibilityValue(
                L10n.string("\(Formatters.duration(self.displayPosition)) of \(Formatters.duration(self.vm.duration))")
            )
            .accessibilityAdjustableAction { direction in
                guard direction == .increment || direction == .decrement else { return }
                let step = max(self.vm.duration * 0.05, 5)
                let pos = direction == .increment ? min(self.vm.position + step, self.vm.duration) : max(self.vm.position - step, 0)
                Task { await self.vm.scrub(to: pos) }
            }
            .accessibilityIdentifier(A11y.NowPlaying.scrubber)
            // CUE marker ticks (ADR-087): |------|-----|-|---- along the
            // slider's bottom edge. Hidden below two markers (inert sets
            // never load, but the guard keeps the rule in one place).
            .overlay(alignment: .bottom) {
                if self.vm.markers.count >= 2, self.vm.duration > 0 {
                    GeometryReader { geo in
                        ForEach(self.vm.markers) { marker in
                            Rectangle()
                                .fill(Color.textTertiary)
                                .frame(width: 1, height: 4)
                                .offset(
                                    x: geo.size.width * min(1, Double(marker.positionMs) / 1000.0 / self.vm.duration),
                                    y: geo.size.height - 3
                                )
                        }
                    }
                    .allowsHitTesting(false)
                }
            }

            Text(Formatters.duration(self.vm.duration))
                .font(Typography.caption)
                .foregroundStyle(Color.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: self.timeLabelWidth, alignment: .leading)
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 4) {
            Button {
                Task { await self.vm.toggleMute() }
            } label: {
                Image(systemName: self.vm.isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(Typography.caption)
                    .foregroundStyle(self.vm.isMuted ? Color.primary : Color.textTertiary)
            }
            .buttonStyle(.plain)
            .help(self.vm.isMuted ? L10n.string("Unmute") : L10n.string("Mute"))
            .accessibilityLabel(self.vm.isMuted ? L10n.string("Unmute") : L10n.string("Mute"))
            .accessibilityIdentifier(A11y.NowPlaying.muteButton)
            .keyboardShortcut(KeyBindings.mute)

            Slider(value: Binding(
                get: { Double(self.vm.volume) },
                set: { newVolume in Task { await self.vm.setVolume(Float(newVolume)) } }
            ), in: 0 ... 1) { editing in
                if !editing {
                    Haptics.positionCommit()
                }
            }
            .controlSize(.mini)
            .frame(maxWidth: 100)
            .id(self.accentColorKey)
            .help(L10n.string("Volume: \(Int(self.vm.volume * 100))%"))
            .accessibilityLabel(L10n.string("Volume"))
            .accessibilityValue(L10n.string("\(Int(self.vm.volume * 100)) percent"))
            .accessibilityAdjustableAction { direction in
                guard direction == .increment || direction == .decrement else { return }
                let vol = direction == .increment ? min(self.vm.volume + 0.1, 1) : max(self.vm.volume - 0.1, 0)
                Task { await self.vm.setVolume(vol) }
            }
            .accessibilityIdentifier(A11y.NowPlaying.volumeSlider)

            Image(systemName: "speaker.wave.3.fill")
                .font(Typography.caption)
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Helpers

    /// Position shown under the scrubber — live engine position normally,
    /// but tracks the drag fraction while the user is scrubbing so the
    /// time readout mirrors where the thumb currently sits.
    private var displayPosition: TimeInterval {
        if let drag = self.scrubDragFraction {
            return drag * self.vm.duration
        }
        return self.vm.position
    }

    /// The width of both labels either side of the scrubber. Sized on the
    /// longer of the total and the elapsed time, so an hour-long podcast gets
    /// its wide slot from the first frame, and a live stream (which reports no
    /// duration) widens once when its clock passes an hour (#563).
    private var timeLabelWidth: Double {
        Formatters.timeLabelWidth(longest: max(self.vm.duration, self.displayPosition))
    }
}
