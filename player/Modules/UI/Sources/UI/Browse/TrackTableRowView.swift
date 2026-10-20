import AppKit
import SwiftUI

final class TrackTableRowView: NSTableRowView {
    var striped = false
    var current = false {
        didSet {
            if oldValue != self.current {
                self.needsDisplay = true
            }
        }
    }

    private var hovered = false
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = self.hoverTrackingArea {
            self.removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        self.hoverTrackingArea = area
        self.addTrackingArea(area)
        self.updateHoverFromPointer()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: self.window)
        if let newWindow {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.windowResignedKey(_:)),
                name: NSWindow.didResignKeyNotification,
                object: newWindow
            )
        }
        self.clearHover()
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        self.updateHoverFromPointer()
    }

    override func mouseExited(with event: NSEvent) {
        self.clearHover()
    }

    @objc private func windowResignedKey(_ notification: Notification) {
        self.clearHover()
    }

    private func clearHover() {
        if self.hovered {
            self.hovered = false
            self.needsDisplay = true
        }
    }

    private func updateHoverFromPointer() {
        let next = self.window.map {
            $0.isKeyWindow && self.visibleRect.contains(self.convert($0.mouseLocationOutsideOfEventStream, from: nil))
        } ?? false
        if self.hovered != next {
            self.hovered = next
            self.needsDisplay = true
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        NSColor(Color.bgPrimary).setFill()
        self.bounds.fill()
        let opacity = self.current ? 0.10 : (self.hovered ? 0.07 : (self.striped ? 0.025 : 0))
        (self.current ? NSColor.controlAccentColor : NSColor.labelColor).withAlphaComponent(opacity).setFill()
        NSBezierPath(roundedRect: self.bounds.insetBy(dx: 4, dy: 1), xRadius: 6, yRadius: 6).fill()
        if self.current {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 4, y: 4, width: 3, height: max(0, self.bounds.height - 8)),
                xRadius: 1.5,
                yRadius: 1.5
            ).fill()
        }
    }
}

class TrackTextCell: NSTableCellView {
    var current = false {
        didSet { self.updateTextColour() }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { self.updateTextColour() }
    }

    private func updateTextColour() {
        self.textField?.textColor = self.backgroundStyle == .emphasized
            ? .alternateSelectedControlTextColor : (self.current ? .controlAccentColor : .labelColor)
    }
}

final class TrackTitleCell: TrackTextCell {
    let indicator: NSHostingView<PlayingBarsIndicator> = {
        let view = NSHostingView(rootView: PlayingBarsIndicator(isPlaying: false))
        view.isHidden = true
        return view
    }()

    private(set) var playbackState: Bool?

    func updatePlaybackIndicator(isCurrent: Bool, isPlaying: Bool) {
        let next: Bool? = isCurrent ? isPlaying : nil
        guard self.playbackState != next else { return }
        self.playbackState = next
        self.indicator.isHidden = !isCurrent
        self.indicator.rootView = PlayingBarsIndicator(isPlaying: next == true)
    }
}
