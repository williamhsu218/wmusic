import SwiftUI

/// One persistent trailing slot, sharing the existing queue and lyric editor.
struct LibraryInspector: View {
    let library: LibraryViewModel
    let lyricsVM: LyricsViewModel
    @Binding var selection: String
    @Binding var isVisible: Bool
    @AppStorage("lyrics.paneWidth") private var width: Double = 300
    @State private var resizeStart: Double?
    @State private var resizeCursorPushed = false

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
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button(L10n.string("Clear Queue")) {
                            Task { await self.library.requestClearQueue() }
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("inspector.clearQueue")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    QueueView(vm: self.library, showsGenre: false)
                        .scrollContentBackground(.hidden)
                }
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
                    DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { value in
                        if self.resizeStart == nil {
                            self.resizeStart = min(420, max(260, self.width))
                        }
                        self.width = min(
                            420, max(260, (self.resizeStart ?? self.width) - value.translation.width)
                        )
                    }.onEnded { _ in self.resizeStart = nil }
                )
                .onHover { hovering in
                    if hovering, !self.resizeCursorPushed {
                        NSCursor.resizeLeftRight.push()
                        self.resizeCursorPushed = true
                    } else if !hovering, self.resizeCursorPushed {
                        NSCursor.pop()
                        self.resizeCursorPushed = false
                    }
                }
                .onDisappear {
                    if self.resizeCursorPushed {
                        NSCursor.pop()
                        self.resizeCursorPushed = false
                    }
                    self.resizeStart = nil
                }
                .accessibilityLabel(L10n.string("Resize Inspector"))
                .accessibilityValue(L10n.string("\(Int(self.width)) points"))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: self.width = min(420, max(260, self.width) + 20)
                    case .decrement: self.width = max(260, min(420, self.width) - 20)
                    @unknown default: break
                    }
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.inspector")
    }
}

private struct NowPlayingInspectorInfo: View {
    let library: LibraryViewModel
    private var np: NowPlayingViewModel {
        self.library.nowPlaying
    }

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
                    InspectorBadgeLayout {
                        ForEach(SourceBadgeModel.badges(for: facts)) { badge in
                            SourceBadge(model: badge)
                        }
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

/// Wrap facts at their intrinsic width instead of reserving a full row each.
private struct InspectorBadgeLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        self.arrangement(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = self.arrangement(width: bounds.width, subviews: subviews)
        for (index, position) in layout.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, usedWidth: CGFloat = 0
        var positions: [CGPoint] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + 6
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + 6
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), positions)
    }
}
