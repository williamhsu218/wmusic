import AppKit
import SwiftUI

/// A native divider keeps mouse tracking stable while its leading edge moves.
struct PlaybackPanelResizeHandle: View {
    @Binding var width: Double

    var body: some View {
        PlaybackPanelDivider(width: self.$width)
            .frame(width: 8)
            .frame(maxHeight: .infinity)
            .accessibilityLabel(L10n.string("Resize Playback Panel"))
            .accessibilityValue(L10n.string("\(Int(min(420, max(300, self.width)))) points"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: self.width = min(420, max(300, self.width) + 20)
                case .decrement: self.width = max(300, min(420, self.width) - 20)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("inspector.resize")
    }
}

private struct PlaybackPanelDivider: NSViewRepresentable {
    @Binding var width: Double

    func makeNSView(context _: Context) -> DividerView {
        DividerView()
    }

    func updateNSView(_ view: DividerView, context _: Context) {
        view.panelWidth = self.width
        view.onWidthChange = { self.width = $0 }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.splitter)
        view.setAccessibilityLabel(L10n.string("Resize Playback Panel"))
        view.setAccessibilityValue(L10n.string("\(Int(min(420, max(300, self.width)))) points"))
        view.setAccessibilityIdentifier("inspector.resize")
    }

    final class DividerView: NSView {
        var panelWidth = 340.0
        var onWidthChange: ((Double) -> Void)?
        private var dragStart: (x: CGFloat, width: Double)?

        override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
            true
        }

        override func resetCursorRects() {
            self.addCursorRect(self.bounds, cursor: .resizeLeftRight)
        }

        override func draw(_: NSRect) {
            NSColor.separatorColor.setFill()
            NSRect(x: 0, y: 0, width: 1, height: self.bounds.height).fill()
        }

        override func mouseDown(with event: NSEvent) {
            self.dragStart = (event.locationInWindow.x, min(420, max(300, self.panelWidth)))
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = self.dragStart else { return }
            self.onWidthChange?(min(420, max(300, start.width - (event.locationInWindow.x - start.x))))
        }

        override func mouseUp(with _: NSEvent) {
            self.dragStart = nil
        }

        override func accessibilityPerformIncrement() -> Bool {
            self.onWidthChange?(min(420, max(300, self.panelWidth) + 20))
            return true
        }

        override func accessibilityPerformDecrement() -> Bool {
            self.onWidthChange?(max(300, min(420, self.panelWidth) - 20))
            return true
        }
    }
}
