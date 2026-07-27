import AppKit
import SwiftUI
import DynamicIslandCore

struct FileShelfOverlayView: View {
    let shelf: TemporaryFileShelf
    let filter: TemporaryFileShelfFilter
    let selectedItemIDs: Set<TemporaryShelfItem.ID>
    let isDropTargetActive: Bool
    let onFilterChange: (TemporaryFileShelfFilter) -> Void
    let onDone: () -> Void
    let onClearSelection: () -> Void
    let onSelectItem: (TemporaryShelfItem.ID, Bool) -> Void
    let onSelectItems: ([TemporaryShelfItem.ID], Bool) -> Void
    let onRemoveItem: (TemporaryShelfItem.ID) -> Void
    let onClear: () -> Void
    let onDragStarted: ([TemporaryShelfItem.ID]) -> Void
    let onDragCompleted: ([TemporaryShelfItem.ID], Bool) -> Void
    let contentBoundaryInset: CGFloat
    let topBoundaryInset: CGFloat

    private let emptyShelfBodyHeight: CGFloat = 86
    private let filterBarHeight: CGFloat = 20
    private let selectionDragThreshold: CGFloat = 5
    private let temporaryFileTileFramePreferenceKey = "temporaryFileTileFramePreferenceKey"

    @State private var tileFrames: [TemporaryShelfItem.ID: CGRect] = [:]
    @State private var selectionStartPoint: CGPoint?
    @State private var selectionCurrentPoint: CGPoint?
    @State private var iconCache = TemporaryFileIconCache()

    private let columns = [
        GridItem(.adaptive(minimum: 112, maximum: 150), spacing: 6)
    ]

    private var visibleItems: [TemporaryShelfItem] {
        shelf.items(filteredBy: filter)
    }

    private var visibleItemCount: Int {
        visibleItems.count
    }

    private var shellContentInset: CGFloat {
        max(contentBoundaryInset, topBoundaryInset)
    }

    private var selectionRect: CGRect? {
        guard let selectionStartPoint, let selectionCurrentPoint else { return nil }
        return CGRect(
            x: min(selectionStartPoint.x, selectionCurrentPoint.x),
            y: min(selectionStartPoint.y, selectionCurrentPoint.y),
            width: abs(selectionCurrentPoint.x - selectionStartPoint.x),
            height: abs(selectionCurrentPoint.y - selectionStartPoint.y)
        )
    }

    var body: some View {
        VStack(spacing: 5) {
            header
                .padding(.horizontal, shellContentInset)
            if shelf.hasItems {
                filterBar
                    .padding(.horizontal, shellContentInset)
                groupedShelfBody
                    .padding(.horizontal, shellContentInset)
            } else {
                emptyDropBody
                    .frame(height: emptyShelfBodyHeight)
                    .padding(.horizontal, shellContentInset)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text("Files")
                .font(.system(size: 12, weight: .semibold))
            Text("\(shelf.items.count)")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.58))
            Spacer(minLength: 0)
            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.1))
                    )
            }
            .buttonStyle(IslandPressButtonStyle())
            .accessibilityLabel("Done")
            if shelf.hasItems {
                Button(action: onClear) {
                    Text("Clear")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.white.opacity(0.1))
                        )
                }
                .buttonStyle(IslandPressButtonStyle())
                .contentShape(Rectangle())
                .accessibilityLabel("Clear temporary files")
            }
        }
        .frame(height: 20)
    }

    private var filterBar: some View {
        HStack(spacing: 5) {
            ForEach(TemporaryFileShelfFilter.allCases, id: \.self) { filterOption in
                Button {
                    onFilterChange(filterOption)
                } label: {
                    Text(filterOption.title)
                        .font(.system(size: 8.5, weight: .semibold))
                        .lineLimit(1)
                        .frame(height: filterBarHeight)
                        .padding(.horizontal, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.white.opacity(filter == filterOption ? 0.16 : 0.06))
                        )
                }
                .buttonStyle(IslandPressButtonStyle())
            }
            Spacer(minLength: 0)
        }
    }

    private var emptyDropBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    .white.opacity(isDropTargetActive ? 0.52 : 0.18),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(isDropTargetActive ? 0.08 : 0.035))
                )

            Image(systemName: isDropTargetActive ? "plus.circle.fill" : "tray")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white.opacity(isDropTargetActive ? 0.86 : 0.28))
                .accessibilityHidden(true)
        }
    }

    private var groupedShelfBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    .white.opacity(isDropTargetActive ? 0.52 : 0.14),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(isDropTargetActive ? 0.08 : 0.025))
                )

            if visibleItems.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 22, weight: .medium))
                    Text("No \(filter.title)")
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(0.55)
                }
                .foregroundStyle(.white)
                .accessibilityLabel("No files for current filter")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(visibleItems) { item in
                            fileTile(item)
                        }
                    }
                    .padding(6)
                }
                .coordinateSpace(name: temporaryFileTileFramePreferenceKey)
                .onPreferenceChange(TemporaryFileTileFramePreferenceKey.self) { frames in
                    tileFrames = frames
                }
                .scrollIndicators(.never)
                .contentShape(Rectangle())
                .simultaneousGesture(selectionDragGesture)
                .overlay(alignment: .topLeading) {
                    selectionOverlay
                }
                .onTapGesture {
                    onClearSelection()
                }
            }
        }
        .accessibilityValue("\(visibleItemCount) visible files")
    }

    private var selectionDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(temporaryFileTileFramePreferenceKey))
            .onChanged { value in
                if selectionStartPoint == nil {
                    guard !tileFrames.values.contains(where: { $0.contains(value.startLocation) }) else { return }
                    selectionStartPoint = value.startLocation
                }
                selectionCurrentPoint = value.location

                guard let selectionRect,
                      selectionRect.width >= selectionDragThreshold || selectionRect.height >= selectionDragThreshold
                else {
                    return
                }

                let selectedIDs = visibleItems.compactMap { item -> TemporaryShelfItem.ID? in
                    guard let frame = tileFrames[item.id], frame.intersects(selectionRect) else { return nil }
                    return item.id
                }
                onSelectItems(selectedIDs, NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift))
            }
            .onEnded { _ in
                selectionStartPoint = nil
                selectionCurrentPoint = nil
            }
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if let selectionRect,
           selectionRect.width >= selectionDragThreshold || selectionRect.height >= selectionDragThreshold {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                )
                .frame(width: selectionRect.width, height: selectionRect.height)
                .position(x: selectionRect.midX, y: selectionRect.midY)
                .allowsHitTesting(false)
        }
    }

    private func fileTile(_ item: TemporaryShelfItem) -> some View {
        let isSelected = selectedItemIDs.contains(item.id)

        return HStack(spacing: 5) {
            Image(nsImage: iconCache.icon(for: item))
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.category.title)
                    .font(.system(size: 7.5, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.42))
            }
            .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onRemoveItem(item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(IslandPressButtonStyle())
            .frame(width: 16, height: 18)
            .contentShape(Rectangle())
            .accessibilityLabel("Remove \(item.displayName)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.15 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(isSelected ? 0.42 : 0.08), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            GeometryReader { proxy in
                TemporaryFileDragSourceView(
                    item: item,
                    items: shelf.items,
                    selectedItemIDs: selectedItemIDs,
                    onSelectItem: onSelectItem,
                    onDragStarted: onDragStarted,
                    onDragCompleted: onDragCompleted
                )
                .frame(width: max(proxy.size.width - 26, 0), height: proxy.size.height)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TemporaryFileTileFramePreferenceKey.self,
                    value: [item.id: proxy.frame(in: .named(temporaryFileTileFramePreferenceKey))]
                )
            }
        )
    }
}

@MainActor
private final class TemporaryFileIconCache {
    private var imagesByItemID: [TemporaryShelfItem.ID: NSImage] = [:]

    func icon(for item: TemporaryShelfItem) -> NSImage {
        if let image = imagesByItemID[item.id] {
            return image
        }

        let image = NSWorkspace.shared.icon(forFile: item.fileURL.path)
        imagesByItemID[item.id] = image
        return image
    }
}

private struct TemporaryFileTileFramePreferenceKey: PreferenceKey {
    static var defaultValue: [TemporaryShelfItem.ID: CGRect] { [:] }

    static func reduce(value: inout [TemporaryShelfItem.ID: CGRect], nextValue: () -> [TemporaryShelfItem.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct TemporaryFileDragSourceView: NSViewRepresentable {
    let item: TemporaryShelfItem
    let items: [TemporaryShelfItem]
    let selectedItemIDs: Set<TemporaryShelfItem.ID>
    let onSelectItem: (TemporaryShelfItem.ID, Bool) -> Void
    let onDragStarted: ([TemporaryShelfItem.ID]) -> Void
    let onDragCompleted: ([TemporaryShelfItem.ID], Bool) -> Void

    func makeNSView(context: Context) -> TemporaryFileDragSourceNSView {
        TemporaryFileDragSourceNSView()
    }

    func updateNSView(_ nsView: TemporaryFileDragSourceNSView, context: Context) {
        nsView.item = item
        nsView.items = items
        nsView.selectedItemIDs = selectedItemIDs
        nsView.onSelectItem = onSelectItem
        nsView.onDragStarted = onDragStarted
        nsView.onDragCompleted = onDragCompleted
    }
}

private final class TemporaryFileDragSourceNSView: NSView, NSDraggingSource {
    var item: TemporaryShelfItem?
    var items: [TemporaryShelfItem] = []
    var selectedItemIDs: Set<TemporaryShelfItem.ID> = []
    var onSelectItem: ((TemporaryShelfItem.ID, Bool) -> Void)?
    var onDragStarted: (([TemporaryShelfItem.ID]) -> Void)?
    var onDragCompleted: (([TemporaryShelfItem.ID], Bool) -> Void)?

    private var mouseDownLocation: NSPoint?
    private var didBeginDrag = false
    private var activeDragItemIDs: [TemporaryShelfItem.ID] = []

    override var isFlipped: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        didBeginDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didBeginDrag, let item, let mouseDownLocation else { return }

        let currentLocation = convert(event.locationInWindow, from: nil)
        let distance = hypot(currentLocation.x - mouseDownLocation.x, currentLocation.y - mouseDownLocation.y)
        guard distance >= 4 else { return }

        didBeginDrag = true
        let draggedItems = itemsForDrag(startingWith: item)
        activeDragItemIDs = draggedItems.map(\.id)
        onDragStarted?(activeDragItemIDs)

        let dragImageSize = NSSize(width: 32, height: 32)
        let dragImageOrigin = NSPoint(
            x: currentLocation.x - (dragImageSize.width / 2),
            y: currentLocation.y - (dragImageSize.height / 2)
        )
        let dragIcon = NSWorkspace.shared.icon(forFile: draggedItems.first?.fileURL.path ?? item.fileURL.path)
        dragIcon.size = dragImageSize

        let draggingItems = draggedItems.enumerated().map { index, shelfItem in
            let draggingItem = NSDraggingItem(pasteboardWriter: shelfItem.fileURL as NSURL)
            let offset = CGFloat(index) * 3
            draggingItem.setDraggingFrame(
                NSRect(
                    x: dragImageOrigin.x + offset,
                    y: dragImageOrigin.y - offset,
                    width: dragImageSize.width,
                    height: dragImageSize.height
                ),
                contents: dragIcon
            )
            return draggingItem
        }

        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
            didBeginDrag = false
        }

        guard !didBeginDrag, let item else { return }
        let extendingSelection = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
        onSelectItem?(item.id, extendingSelection)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        [.copy, .move, .link, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragCompleted?(activeDragItemIDs, isExternalSuccessfulDrag(screenPoint: screenPoint, operation: operation))
        activeDragItemIDs = []
        mouseDownLocation = nil
        didBeginDrag = false
    }

    private func isExternalSuccessfulDrag(screenPoint: NSPoint, operation: NSDragOperation) -> Bool {
        guard operation != [] else { return false }
        if window?.frame.contains(screenPoint) == true {
            return false
        }
        return true
    }

    private func itemsForDrag(startingWith item: TemporaryShelfItem) -> [TemporaryShelfItem] {
        let selectedItems = items.filter { selectedItemIDs.contains($0.id) }
        guard selectedItemIDs.contains(item.id), !selectedItems.isEmpty else {
            return [item]
        }
        return selectedItems
    }
}
