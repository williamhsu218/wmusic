import AppKit
import Persistence
import SwiftUI
import Testing
@testable import UI

@Suite("Album header and table stability")
@MainActor
struct AlbumHeaderStabilityTests {
    @Test("viewport growth cannot immediately undo a collapse", arguments: [CGFloat(140), 220, 320])
    func collapseSurvivesClamping(heightDelta: CGFloat) {
        // Worst case: the old viewport is scrolled to the bottom. Growing it
        // clamps the offset by exactly the header reduction.
        let offset = heightDelta + 65
        #expect(AlbumHeaderCollapsePolicy.isCollapsed(
            after: offset,
            wasCollapsed: false,
            expandedHeight: heightDelta + 80,
            compactHeight: 80
        ))
        #expect(AlbumHeaderCollapsePolicy.isCollapsed(
            after: offset - heightDelta,
            wasCollapsed: true,
            expandedHeight: heightDelta + 80,
            compactHeight: 80
        ))
        #expect(!AlbumHeaderCollapsePolicy.isCollapsed(
            after: 0,
            wasCollapsed: true,
            expandedHeight: heightDelta + 80,
            compactHeight: 80
        ))
    }

    @Test("short albums do not enter a collapse and clamp feedback loop", arguments: [8, 12, 15])
    func shortAlbumsStayStable(tracks: Int) {
        let maximumOffset = max(0, CGFloat(tracks) * 28 - 300)
        #expect(!AlbumHeaderCollapsePolicy.isCollapsed(
            after: maximumOffset,
            wasCollapsed: false,
            expandedHeight: 220,
            compactHeight: 80
        ))
    }

    @Test("layout, horizontal scrolling and stale bounds do not act as vertical input")
    func geometryIsNotScrolling() {
        var observation = TrackScrollObservation()
        #expect(observation.verticalOffset(after: CGRect(x: 0, y: 0, width: 600, height: 300)) == nil)
        #expect(observation.verticalOffset(after: CGRect(x: 0, y: 205, width: 600, height: 300)) == 205)
        #expect(observation.verticalOffset(after: CGRect(x: 0, y: 0, width: 600, height: 440)) == nil)
        #expect(observation.verticalOffset(after: CGRect(x: 40, y: 0, width: 600, height: 440)) == nil)
        #expect(observation.verticalOffset(after: CGRect(x: 40, y: -10, width: 600, height: 440)) == -10)
        #expect(
            observation.verticalOffset(after: CGRect(x: 40, y: 250, width: 585, height: 440)) == 250,
            "An appearing vertical scroller must not swallow the first wheel input"
        )
        var firstInput = TrackScrollObservation()
        #expect(firstInput.verticalOffset(after: CGRect(x: 0, y: 250, width: 600, height: 300)) == 250)
    }

    @Test("reused title cells stop hidden indicators and reflect pause state")
    func reusedPlaybackIndicator() {
        let cell = TrackTitleCell()
        cell.updatePlaybackIndicator(isCurrent: false, isPlaying: true)
        #expect(cell.indicator.isHidden)
        #expect(!cell.indicator.rootView.isPlaying)
        cell.updatePlaybackIndicator(isCurrent: true, isPlaying: true)
        #expect(!cell.indicator.isHidden)
        #expect(cell.indicator.rootView.isPlaying)
        cell.updatePlaybackIndicator(isCurrent: true, isPlaying: false)
        #expect(!cell.indicator.rootView.isPlaying)
        cell.updatePlaybackIndicator(isCurrent: false, isPlaying: true)
        #expect(cell.indicator.isHidden)
        #expect(!cell.indicator.rootView.isPlaying)
        #expect(cell.playbackState == nil)
    }

    @Test("coalesced native bounds callbacks retain genuine vertical input")
    func coalescedNativeScroll() async {
        let noop: (Track) -> Void = { _ in }
        let actions = TrackContextMenuActions(
            playNow: noop, playSingle: noop, playAlbum: noop, shuffleAlbum: noop, playArtist: noop,
            playNext: { _ in }, addToQueue: { _ in }, addToPlaylist: { _, _ in }, newPlaylistFromSelection: { _ in },
            love: { _ in }, goToArtist: { _ in }, goToAlbum: { _ in }, showInFinder: noop, rescanFile: noop,
            getInfo: { _ in }, identify: noop, removeFromLibrary: { _ in }, deleteFromDisk: { _ in },
            copy: { _ in }, toggleShuffle: { _, _ in }, computeReplayGain: { _ in }, rate: { _, _ in },
            removeFromPlaylist: nil, editLyrics: nil, fetchLyricsFromLRClib: nil
        )
        var callbacks: [CGFloat] = []
        let table = TrackTable(
            rows: [],
            rowsVersion: 0,
            selection: .constant([]),
            sortOrder: .constant([]),
            nowPlayingTrackID: nil,
            sortable: false,
            emphasizesPlayCount: false,
            playlistNodes: [],
            actions: actions,
            scrollRequest: 0,
            scrollTargetTrackID: nil,
            onMove: nil,
            onScroll: { callbacks.append($0) }
        )
        let coordinator = TrackTableCoordinator(parent: table)
        let clip = NSClipView(frame: CGRect(x: 0, y: 0, width: 600, height: 300))
        func notify() {
            coordinator.didScroll(Notification(name: NSView.boundsDidChangeNotification, object: clip))
        }
        notify()
        clip.bounds.origin.y = 250
        notify()
        // Native scrolling can advance again before the queued SwiftUI update.
        clip.bounds.origin.y = 251
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(callbacks == [250], "A newer native offset must not discard the only scroll callback")
        clip.bounds = CGRect(x: 0, y: 0, width: 600, height: 440)
        notify()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(callbacks == [250], "Viewport clamping must not feed back into header state")
    }
}
