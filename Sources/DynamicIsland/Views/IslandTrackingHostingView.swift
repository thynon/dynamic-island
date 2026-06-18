import AppKit
import SwiftUI

@MainActor
final class IslandTrackingHostingView: NSHostingView<IslandOverlayView> {
    var onMouseEntered: (() -> Void)?
    var onMouseMoved: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onScroll: ((CGFloat, CGFloat, NSEvent.Phase, NSEvent.Phase) -> Void)?
    var canAcceptFileDrop: ((NSPoint) -> Bool)?
    var onFileDrop: (([URL], NSPoint) -> Void)?
    var onFileDropTargetedChange: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL])
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
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

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaX, event.scrollingDeltaY, event.phase, event.momentumPhase)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard
            !sender.draggingPasteboard.fileURLs.isEmpty,
            canAcceptFileDrop?(sender.draggingLocation) == true
        else {
            onFileDropTargetedChange?(false)
            return []
        }

        onFileDropTargetedChange?(true)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onFileDropTargetedChange?(false)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        onFileDropTargetedChange?(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let fileURLs = sender.draggingPasteboard.fileURLs
        guard !fileURLs.isEmpty, canAcceptFileDrop?(sender.draggingLocation) == true else {
            onFileDropTargetedChange?(false)
            return false
        }

        onFileDrop?(fileURLs, sender.draggingLocation)
        onFileDropTargetedChange?(false)
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private extension NSPasteboard {
    var fileURLs: [URL] {
        guard let urls = readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return []
        }
        return urls
    }
}
