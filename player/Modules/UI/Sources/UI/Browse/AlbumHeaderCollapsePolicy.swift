import Foundation

/// Shrinking a header grows the viewport and can clamp its scroll offset.
/// Keep enough offset in reserve that the clamp cannot reopen the header.
enum AlbumHeaderCollapsePolicy {
    static func isCollapsed(
        after offset: CGFloat,
        wasCollapsed: Bool,
        expandedHeight: CGFloat,
        compactHeight: CGFloat
    ) -> Bool {
        if wasCollapsed {
            return offset > 4
        }
        return offset > max(0, expandedHeight - compactHeight) + 64
    }
}

/// Only height changes can clamp the vertical offset as the header shrinks.
/// A scroller appearing can change the width during genuine vertical input.
struct TrackScrollObservation {
    private var bounds: CGRect?

    mutating func verticalOffset(after next: CGRect) -> CGFloat? {
        defer { self.bounds = next }
        guard let previous = self.bounds else { return next.minY == 0 ? nil : next.minY }
        guard previous.height == next.height,
              previous.minY != next.minY else { return nil }
        return next.minY
    }
}
