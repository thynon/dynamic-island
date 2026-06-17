import AppKit
import SwiftUI

@MainActor
final class IslandTrackingHostingView: NSHostingView<IslandOverlayView> {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onScroll: ((CGFloat) -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area

        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaY)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
