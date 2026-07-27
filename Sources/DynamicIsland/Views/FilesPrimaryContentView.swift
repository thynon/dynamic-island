import AppKit
import SwiftUI
import DynamicIslandCore

struct FilesPrimaryContentView: View {
    let shelf: TemporaryFileShelf
    let selectedItemIDs: Set<TemporaryShelfItem.ID>
    let airDropUndoItemCount: Int
    let isDropTargetActive: Bool
    let isActive: Bool
    let displayMode: FilesDisplayMode
    let onAirDrop: ([TemporaryShelfItem.ID]) -> Void
    let onUndoAirDrop: () -> Void
    let onDisplayModeChange: (FilesDisplayMode) -> Void
    let onRemoveItems: ([TemporaryShelfItem.ID]) -> Void
    let onSelectItem: (TemporaryShelfItem.ID, Bool) -> Void
    let onDragStarted: ([TemporaryShelfItem.ID]) -> Void
    let onDragCompleted: ([TemporaryShelfItem.ID], Bool) -> Void

    @State private var isAirDropTargeted = false
    @State private var isMultiSelectionEnabled = false
    @State private var iconCache = FilesPrimaryIconCache()

    private let maximumAirDropZoneWidth: CGFloat = 220
    private let minimumAirDropZoneWidth: CGFloat = 150
    private let previewHorizontalInset: CGFloat = 12
    private let previewVerticalInset: CGFloat = 12
    private let fileTileSpacing: CGFloat = 9
    private let fileTileWidth: CGFloat = 76
    private let fileTileHeight: CGFloat = 58

    private var activeTransferItems: [TemporaryShelfItem] {
        let selectedItems = shelf.items.filter { selectedItemIDs.contains($0.id) }
        return selectedItems.isEmpty ? shelf.items : selectedItems
    }

    private var airDropItemCount: Int {
        activeTransferItems.count
    }

    private func airDropZoneWidth(for contentWidth: CGFloat) -> CGFloat {
        min(maximumAirDropZoneWidth, max(minimumAirDropZoneWidth, contentWidth * 0.30))
    }

    var body: some View {
        GeometryReader { proxy in
            let resolvedAirDropZoneWidth = airDropZoneWidth(for: proxy.size.width)
            HStack(spacing: 10) {
                airDropZone
                    .frame(width: resolvedAirDropZoneWidth, height: proxy.size.height)

                previewZone
                    .frame(
                        width: max(1, proxy.size.width - resolvedAirDropZoneWidth - 10),
                        height: proxy.size.height
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var airDropZone: some View {
        ZStack {
            zoneBackground(isActive: isDropTargetActive || isAirDropTargeted)

            VStack(spacing: 8) {
                Image(systemName: "airdrop")
                    .font(.system(size: 26, weight: .medium))
                    .symbolRenderingMode(.monochrome)

                Text("隔空投送")
                    .font(.system(size: 13, weight: .semibold))

                Text("\(airDropItemCount)")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .opacity(0.58)
            }
            .foregroundStyle(.white.opacity(shelf.hasItems ? 0.88 : 0.34))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)

            FilesAirDropTargetView(
                items: shelf.items,
                selectedItemIDs: selectedItemIDs,
                isActive: isActive,
                onAirDrop: onAirDrop,
                onTargetedChange: { isAirDropTargeted = $0 }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if airDropUndoItemCount > 0 {
                airDropUndoControl
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("AirDrop")
    }

    private var airDropUndoControl: some View {
        VStack {
            Button(action: onUndoAirDrop) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 20, height: 20)

                    Text("\(airDropUndoItemCount)")
                        .font(.system(size: 6.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.black.opacity(0.82))
                        .frame(minWidth: 10, minHeight: 10)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.92))
                        )
                        .offset(x: 5, y: -5)
                }
            }
            .buttonStyle(IslandPressButtonStyle())
            .foregroundStyle(.white.opacity(0.9))
            .padding(4)
            .background(
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.36))
            )
            .help("撤销 AirDrop 移除")
            .accessibilityLabel("Undo AirDrop removal")
            .padding(.top, 8)
            .padding(.trailing, 8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private var previewZone: some View {
        ZStack {
            zoneBackground(isActive: isDropTargetActive)

            if shelf.hasItems {
                fileGrid
            } else {
                emptyPreview
            }

            VStack {
                HStack {
                    Spacer(minLength: 0)
                    previewToolbar
                    .padding(.top, 9)
                    .padding(.trailing, 10)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("文件预览")
    }

    private var previewToolbar: some View {
        HStack(spacing: 7) {
            FilesMultiSelectionButton(
                isActive: isMultiSelectionEnabled,
                selectedCount: selectedItemIDs.count,
                totalCount: shelf.items.count,
                onToggle: { isMultiSelectionEnabled.toggle() }
            )

            FilesDeleteSelectionButton(
                selectedCount: selectedItemIDs.count,
                onDelete: { onRemoveItems(Array(selectedItemIDs)) }
            )

            FilesDisplayModeControl(
                mode: displayMode,
                onChange: onDisplayModeChange
            )
        }
    }

    private var fileGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(
                rows: [
                    GridItem(.adaptive(minimum: fileTileHeight, maximum: fileTileHeight), spacing: fileTileSpacing)
                ],
                alignment: .top,
                spacing: fileTileSpacing
            ) {
                ForEach(shelf.items) { item in
                    fileTile(item)
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, previewHorizontalInset)
            .padding(.trailing, previewHorizontalInset + 28)
            .padding(.vertical, previewVerticalInset + 18)
        }
    }

    private func fileTile(_ item: TemporaryShelfItem) -> some View {
        let isSelected = selectedItemIDs.contains(item.id)

        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.13 : 0.045))

            VStack(spacing: 5) {
                fileTileArtwork(for: item)
                    .frame(width: 30, height: 30)

                Text(item.displayName)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 5)

            if isMultiSelectionEnabled || isSelected {
                fileSelectionIndicator(isSelected: isSelected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(5)
            }

            FilesPrimaryDragSourceView(
                item: item,
                items: shelf.items,
                selectedItemIDs: selectedItemIDs,
                isMultiSelectionEnabled: isMultiSelectionEnabled,
                onSelectItem: onSelectItem,
                onDragStarted: onDragStarted,
                onDragCompleted: onDragCompleted
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: fileTileWidth, height: fileTileHeight)
    }

    private func fileTileArtwork(for item: TemporaryShelfItem) -> some View {
        Image(nsImage: iconCache.icon(for: item))
            .resizable()
            .scaledToFit()
    }

    private func fileSelectionIndicator(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 10, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.42))
            .allowsHitTesting(false)
    }

    private var emptyPreview: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 28, weight: .medium))
            Text("文件预览")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.34))
    }

    private func zoneBackground(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(isActive ? 0.07 : 0.025))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        Color.gray.opacity(isActive ? 0.62 : 0.38),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                    )
            )
    }
}

@MainActor
private final class FilesPrimaryIconCache {
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

private struct FilesMultiSelectionButton: View {
    let isActive: Bool
    let selectedCount: Int
    let totalCount: Int
    let onToggle: () -> Void

    private var isEnabled: Bool {
        totalCount > 0
    }

    var body: some View {
        Button(action: onToggle) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: isActive ? "checklist.checked" : "checklist")
                    .font(.system(size: 8.5, weight: .semibold))
                    .frame(width: 17, height: 17)

                if selectedCount > 0 {
                    Text(badgeText)
                        .font(.system(size: 6.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.black.opacity(0.82))
                        .frame(minWidth: 10, minHeight: 10)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.92))
                        )
                        .offset(x: 5, y: -5)
                }
            }
            .foregroundStyle(.white.opacity(isEnabled ? 0.9 : 0.28))
            .background(
                Circle()
                    .fill(.white.opacity(isActive ? 0.16 : 0))
            )
        }
        .buttonStyle(IslandPressButtonStyle())
        .disabled(!isEnabled)
        .help(isActive ? "关闭多选" : "多选文件")
        .accessibilityLabel(isActive ? "Disable multiple selection" : "Enable multiple selection")
    }

    private var badgeText: String {
        selectedCount > 99 ? "99+" : "\(selectedCount)"
    }
}

private struct FilesDeleteSelectionButton: View {
    let selectedCount: Int
    let onDelete: () -> Void

    private var isEnabled: Bool {
        selectedCount > 0
    }

    var body: some View {
        Button(action: onDelete) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "trash")
                    .font(.system(size: 8.5, weight: .semibold))
                    .frame(width: 17, height: 17)

                if selectedCount > 1 {
                    Text(badgeText)
                        .font(.system(size: 6.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.black.opacity(0.82))
                        .frame(minWidth: 10, minHeight: 10)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.92))
                        )
                        .offset(x: 5, y: -5)
                }
            }
            .foregroundStyle(.white.opacity(isEnabled ? 0.9 : 0.28))
            .background(
                Circle()
                    .fill(.white.opacity(isEnabled ? 0.14 : 0))
            )
        }
        .buttonStyle(IslandPressButtonStyle())
        .disabled(!isEnabled)
        .help(isEnabled ? "删除选中文件" : "先选择文件")
        .accessibilityLabel("Delete selected files")
    }

    private var badgeText: String {
        selectedCount > 99 ? "99+" : "\(selectedCount)"
    }
}

private struct FilesDisplayModeControl: View {
    let mode: FilesDisplayMode
    let onChange: (FilesDisplayMode) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(FilesDisplayMode.allCases) { option in
                Button {
                    onChange(option)
                } label: {
                    Image(systemName: option.systemImageName)
                        .font(.system(size: 8.5, weight: .semibold))
                        .frame(width: 17, height: 17)
                        .foregroundStyle(.white.opacity(mode == option ? 0.92 : 0.42))
                        .background(
                            Circle()
                                .fill(.white.opacity(mode == option ? 0.16 : 0))
                        )
                }
                .buttonStyle(IslandPressButtonStyle())
                .help(option.accessibilityLabel)
                .accessibilityLabel(option.accessibilityLabel)
            }
        }
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .fill(.black.opacity(0.35))
        )
    }
}

private struct FilesAirDropTargetView: NSViewRepresentable {
    let items: [TemporaryShelfItem]
    let selectedItemIDs: Set<TemporaryShelfItem.ID>
    let isActive: Bool
    let onAirDrop: ([TemporaryShelfItem.ID]) -> Void
    let onTargetedChange: (Bool) -> Void

    func makeNSView(context: Context) -> FilesAirDropTargetNSView {
        FilesAirDropTargetNSView()
    }

    func updateNSView(_ nsView: FilesAirDropTargetNSView, context: Context) {
        nsView.items = items
        nsView.selectedItemIDs = selectedItemIDs
        nsView.setActive(isActive)
        nsView.onAirDrop = onAirDrop
        nsView.onTargetedChange = onTargetedChange
    }
}

private final class FilesAirDropTargetNSView: NSView {
    var items: [TemporaryShelfItem] = []
    var selectedItemIDs: Set<TemporaryShelfItem.ID> = []
    var onAirDrop: (([TemporaryShelfItem.ID]) -> Void)?
    var onTargetedChange: ((Bool) -> Void)?

    private var mouseDownLocation: NSPoint?
    private var isTargeted = false
    private var isActive = false
    private var activeDragItemIDs: [TemporaryShelfItem.ID] = []

    override var isFlipped: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncDragRegistration()
    }

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        syncDragRegistration()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownLocation = nil }
        guard !items.isEmpty, let mouseDownLocation else { return }

        let mouseUpLocation = convert(event.locationInWindow, from: nil)
        let distance = hypot(mouseUpLocation.x - mouseDownLocation.x, mouseUpLocation.y - mouseDownLocation.y)
        guard distance < 4 else { return }

        onAirDrop?(activeItemIDs())
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isActive else { return [] }
        activeDragItemIDs = matchedItemIDs(from: sender.draggingPasteboard.filesPrimaryFileURLs)
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isActive, !activeDragItemIDs.isEmpty else {
            setTargeted(false)
            return []
        }

        setTargeted(true)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        activeDragItemIDs = []
        setTargeted(false)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        activeDragItemIDs = []
        setTargeted(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isActive else {
            activeDragItemIDs = []
            setTargeted(false)
            return false
        }

        let itemIDs = activeDragItemIDs.isEmpty
            ? matchedItemIDs(from: sender.draggingPasteboard.filesPrimaryFileURLs)
            : activeDragItemIDs
        defer {
            activeDragItemIDs = []
            setTargeted(false)
        }

        guard !itemIDs.isEmpty else {
            return false
        }

        onAirDrop?(itemIDs)
        return true
    }

    private func activeItemIDs() -> [TemporaryShelfItem.ID] {
        let selectedItems = items.filter { selectedItemIDs.contains($0.id) }
        let activeItems = selectedItems.isEmpty ? items : selectedItems
        return activeItems.map(\.id)
    }

    private func matchedItemIDs(from fileURLs: [URL]) -> [TemporaryShelfItem.ID] {
        let draggedFileIDs = Set(fileURLs.map { $0.standardizedFileURL.path })
        guard !draggedFileIDs.isEmpty else { return [] }
        return items.filter { draggedFileIDs.contains($0.id) }.map(\.id)
    }

    private func syncDragRegistration() {
        guard isActive, window != nil else {
            unregisterDraggedTypes()
            activeDragItemIDs = []
            setTargeted(false)
            return
        }
        registerForDraggedTypes([.fileURL])
    }

    private func setTargeted(_ targeted: Bool) {
        guard isTargeted != targeted else { return }
        isTargeted = targeted
        onTargetedChange?(targeted)
    }
}

private struct FilesPrimaryDragSourceView: NSViewRepresentable {
    let item: TemporaryShelfItem
    let items: [TemporaryShelfItem]
    let selectedItemIDs: Set<TemporaryShelfItem.ID>
    let isMultiSelectionEnabled: Bool
    let onSelectItem: (TemporaryShelfItem.ID, Bool) -> Void
    let onDragStarted: ([TemporaryShelfItem.ID]) -> Void
    let onDragCompleted: ([TemporaryShelfItem.ID], Bool) -> Void

    func makeNSView(context: Context) -> FilesPrimaryDragSourceNSView {
        FilesPrimaryDragSourceNSView()
    }

    func updateNSView(_ nsView: FilesPrimaryDragSourceNSView, context: Context) {
        nsView.item = item
        nsView.items = items
        nsView.selectedItemIDs = selectedItemIDs
        nsView.isMultiSelectionEnabled = isMultiSelectionEnabled
        nsView.onSelectItem = onSelectItem
        nsView.onDragStarted = onDragStarted
        nsView.onDragCompleted = onDragCompleted
    }
}

private final class FilesPrimaryDragSourceNSView: NSView, NSDraggingSource {
    var item: TemporaryShelfItem?
    var items: [TemporaryShelfItem] = []
    var selectedItemIDs: Set<TemporaryShelfItem.ID> = []
    var isMultiSelectionEnabled = false
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

        let dragImageSize = NSSize(width: 28, height: 28)
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
        let extendingSelection = isMultiSelectionEnabled || event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
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
        if selectedItemIDs.contains(item.id), !selectedItems.isEmpty {
            return selectedItems
        }
        return [item]
    }
}

private extension NSPasteboard {
    var filesPrimaryFileURLs: [URL] {
        guard let urls = readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return []
        }
        return urls
    }
}
