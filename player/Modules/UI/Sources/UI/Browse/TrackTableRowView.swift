import AppKit
import SwiftUI

final class TrackTableRowView: NSTableRowView {
    var striped = false
    var current = false { didSet { if oldValue != self.current { self.needsDisplay = true } } }
    private var hovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        self.trackingAreas.forEach(self.removeTrackingArea)
        self.addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        self.hovered = true
        self.needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        self.hovered = false
        self.needsDisplay = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        NSColor(Color.bgPrimary).setFill()
        self.bounds.fill()
        let opacity = self.current ? 0.10 : (self.hovered ? 0.07 : (self.striped ? 0.025 : 0))
        (self.current ? NSColor.controlAccentColor : NSColor.labelColor).withAlphaComponent(opacity)
            .setFill()
        self.bounds.fill()
        if self.current {
            NSColor.controlAccentColor.setFill()
            NSRect(x: 0, y: 3, width: 3, height: max(0, self.bounds.height - 6)).fill()
        }
    }
}

class TrackTextCell: NSTableCellView {
    var current = false { didSet { self.updateTextColour() } }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { self.updateTextColour() }
    }

    private func updateTextColour() {
        self.textField?.textColor = self.backgroundStyle == .emphasized
            ? .alternateSelectedControlTextColor : (self.current ? .controlAccentColor : .labelColor)
    }
}

final class TrackTitleCell: TrackTextCell {
    let indicator = NSHostingView(rootView: PlayingBarsIndicator(isPlaying: false))
}
