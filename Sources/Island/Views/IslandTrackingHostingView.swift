import AppKit
import SwiftUI

@MainActor
final class IslandTrackingHostingView: NSHostingView<IslandOverlayView> {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onFileDragEntered: (([URL]) -> Void)?
    var onFileDragExited: (() -> Void)?
    var onFileDrop: (([URL]) -> Void)?

    private var trackingArea: NSTrackingArea?

    required init(rootView: IslandOverlayView) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let fileURLs = draggedFileURLs(from: sender)
        guard !fileURLs.isEmpty else { return [] }
        onFileDragEntered?(fileURLs)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onFileDragExited?()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let fileURLs = draggedFileURLs(from: sender)
        guard !fileURLs.isEmpty else { return false }
        onFileDrop?(fileURLs)
        return true
    }

    private func draggedFileURLs(from sender: any NSDraggingInfo) -> [URL] {
        let pasteboard = sender.draggingPasteboard
        return pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }
}
