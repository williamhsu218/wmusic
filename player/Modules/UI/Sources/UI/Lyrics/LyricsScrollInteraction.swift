import SwiftUI

/// Native wheel/trackpad scrolling remains available. A pointer drag provides
/// another way to browse without relying on a visible scrollbar.
struct LyricsScrollInteraction: ViewModifier {
    @Binding var position: ScrollPosition
    var onManualScroll: () -> Void = {}

    @State private var geometry = ScrollMetrics()
    @State private var dragStartOffset: CGFloat?

    func body(content: Content) -> some View {
        content
            // Unlike .hidden, .never also overrides macOS's mouse-connected
            // policy, which can otherwise keep the indicators visible.
            .scrollIndicators(.never)
            .scrollPosition(self.$position)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(
                    offset: geometry.contentOffset.y,
                    limit: max(0, geometry.contentSize.height - geometry.containerSize.height)
                )
            } action: { _, geometry in
                self.geometry = geometry
            }
            .contentShape(Rectangle())
            // The threshold keeps ordinary lyric clicks intact; once a drag
            // starts it wins over the line's Button instead of also seeking.
            .highPriorityGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        if self.dragStartOffset == nil {
                            self.dragStartOffset = self.geometry.offset
                            self.onManualScroll()
                        }
                        let target = (self.dragStartOffset ?? self.geometry.offset) - value.translation.height
                        self.position.scrollTo(y: min(self.geometry.limit, max(0, target)))
                    }
                    .onEnded { _ in self.dragStartOffset = nil }
            )
    }

    private struct ScrollMetrics: Equatable {
        var offset: CGFloat = 0
        var limit: CGFloat = 0
    }
}
