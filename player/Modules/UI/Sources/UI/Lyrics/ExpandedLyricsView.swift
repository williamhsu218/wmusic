import Metadata
import SwiftUI

/// A spacious lyric treatment for the expanded player. Manual browsing pauses
/// following until the listener seeks a line or explicitly returns to playback.
struct ExpandedLyricsView: View {
    @ObservedObject var vm: LyricsViewModel
    let isPresented: Bool
    let trackID: Int64?
    let onSeek: (TimeInterval) -> Void

    @State private var followsPlayback = true
    @State private var syncedPosition = ScrollPosition(idType: Int.self, edge: .top)
    @State private var plainPosition = ScrollPosition(edge: .top)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            let fontSize = min(44, max(28, geometry.size.width * 0.062))
            let inset = min(56, max(24, geometry.size.width * 0.065))

            Group {
                switch self.vm.document {
                case let .synced(lines, _):
                    self.syncedLyrics(lines, size: geometry.size, fontSize: fontSize, inset: inset)
                case let .unsynced(text):
                    ScrollView {
                        Text(text)
                            .font(.system(size: fontSize, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                            .lineSpacing(12)
                            .multilineTextAlignment(.leading)
                            .textSelection(.disabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, inset)
                            .padding(.vertical, 36)
                    }
                    .modifier(LyricsScrollInteraction(position: self.$plainPosition))
                    .onAppear { self.plainPosition.scrollTo(edge: .top) }
                    .id(self.trackID)
                case .none:
                    LyricsView(vm: self.vm, onSeek: self.onSeek)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: self.trackID) { _, _ in self.followsPlayback = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11y.NowPlaying.expandedLyrics)
    }

    private func syncedLyrics(
        _ lines: [LyricsDocument.LyricsLine], size: CGSize, fontSize: CGFloat, inset: CGFloat
    ) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    self.lineRow(line, index: index, fontSize: fontSize)
                        .id(index)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, inset)
            // Enough breathing room to center the first and last lines too.
            .padding(.top, max(28, size.height * 0.35))
            .padding(.bottom, max(40, size.height * 0.5))
        }
        .modifier(LyricsScrollInteraction(position: self.$syncedPosition) {
            self.followsPlayback = false
        })
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { self.followsPlayback = false }
        }
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.09),
                .init(color: .black, location: 0.86),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .overlay(alignment: .bottomTrailing) {
            if !self.followsPlayback {
                Button {
                    self.followsPlayback = true
                    self.scrollToCurrentLine(animated: true)
                } label: {
                    Label(L10n.string("Follow Lyrics"), systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding(20)
                .accessibilityIdentifier(A11y.NowPlaying.expandedLyricsFollow)
            }
        }
        .onAppear { self.scrollToCurrentLine(animated: false) }
        .onChange(of: self.vm.currentLineIndex) { _, _ in
            guard self.followsPlayback else { return }
            self.scrollToCurrentLine(animated: true)
        }
        .onChange(of: self.trackID) { _, _ in
            self.followsPlayback = true
            self.scrollToCurrentLine(animated: false)
        }
        .onChange(of: self.isPresented) { _, visible in
            if visible {
                self.followsPlayback = true
                self.scrollToCurrentLine(animated: false)
            }
        }
        .onChange(of: size) { _, _ in
            if self.followsPlayback { self.scrollToCurrentLine(animated: false) }
        }
    }

    private func lineRow(_ line: LyricsDocument.LyricsLine, index: Int, fontSize: CGFloat) -> some View {
        let isCurrent = index == self.vm.currentLineIndex
        let isBlank = line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            self.followsPlayback = true
            self.onSeek(self.vm.playbackPosition(for: line))
        } label: {
            Text(isBlank ? "•••" : line.text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(Color.textPrimary.opacity(isCurrent ? 1 : (self.contrast == .increased ? 0.7 : 0.38)))
                .lineSpacing(7)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.3), value: isCurrent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isBlank ? L10n.string("Instrumental") : line.text)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        .accessibilityHint(L10n.string("Seek to this line"))
        .help(L10n.string("Jumps playback to this line."))
    }

    private func scrollToCurrentLine(animated: Bool) {
        guard self.isPresented else { return }
        withAnimation(animated && !self.reduceMotion ? .easeInOut(duration: 0.45) : nil) {
            self.syncedPosition.scrollTo(id: self.vm.currentLineIndex ?? 0, anchor: .center)
        }
    }
}
