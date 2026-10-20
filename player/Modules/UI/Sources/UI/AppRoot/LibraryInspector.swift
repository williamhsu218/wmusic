import SwiftUI

/// One persistent trailing slot, sharing the existing queue and lyric editor.
struct LibraryInspector: View {
    let library: LibraryViewModel
    let lyricsVM: LyricsViewModel
    @Binding var selection: String
    @Binding var isVisible: Bool
    @AppStorage("lyrics.paneWidth") private var width: Double = 300
    @State private var resizeStart: Double?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker(L10n.string("Inspector"), selection: self.$selection) {
                    Text(L10n.string("Lyrics")).tag("lyrics")
                    Text(L10n.string("Queue")).tag("queue")
                    Text(L10n.string("Track Info")).tag("info")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("inspector.selection")
                Button {
                    self.isVisible = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help(L10n.string("Close"))
                .accessibilityLabel(L10n.string("Close Inspector"))
                .accessibilityIdentifier("inspector.close")
            }
            .padding(10)
            Divider()
            switch self.selection {
            case "queue":
                QueueView(vm: self.library, showsGenre: false)
                    .scrollContentBackground(.hidden)
            case "info":
                NowPlayingInspectorInfo(library: self.library)
            default:
                LyricsPane(vm: self.lyricsVM, nowPlaying: self.library.nowPlaying, embedded: true) {
                    position in
                    Task { await self.library.nowPlaying.scrub(to: position) }
                }
            }
        }
        .frame(width: min(420, max(260, self.width)))
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.separatorAdaptive).frame(width: 1)
            Color.clear.frame(width: 6).contentShape(Rectangle())
                .gesture(
                    DragGesture().onChanged { value in
                        if self.resizeStart == nil { self.resizeStart = min(420, max(260, self.width)) }
                        self.width = min(
                            420, max(260, (self.resizeStart ?? self.width) - value.translation.width))
                    }.onEnded { _ in self.resizeStart = nil })
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.inspector")
    }
}

private struct NowPlayingInspectorInfo: View {
    let library: LibraryViewModel
    private var np: NowPlayingViewModel { self.library.nowPlaying }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let image = self.np.display.artwork {
                    Image(nsImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                }
                Text(self.np.display.title.isEmpty ? L10n.string("Not playing") : self.np.display.title)
                    .font(.title3.bold()).textSelection(.enabled)
                Text(self.np.display.artist).foregroundStyle(.secondary).textSelection(.enabled)
                Text(self.np.display.album).foregroundStyle(.secondary).textSelection(.enabled)
                if let facts = self.np.display.sourceFacts {
                    ForEach(SourceBadgeModel.badges(for: facts)) { badge in
                        SourceBadge(model: badge)
                    }
                }
                if self.np.nowPlayingTrackID != nil {
                    Button(L10n.string("Get Info")) { self.library.showTagEditorForNowPlaying() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .accessibilityIdentifier("inspector.trackInfo")
    }
}
