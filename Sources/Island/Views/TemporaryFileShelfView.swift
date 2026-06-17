import AppKit
import SwiftUI
import IslandCore

struct TemporaryFileShelfView: View {
    let items: [TemporaryShelfItem]
    let selectedItemIDs: Set<TemporaryShelfItem.ID>
    let isDropTargetActive: Bool
    let onOpen: @MainActor (TemporaryShelfItem) -> Void
    let onRemove: @MainActor (TemporaryShelfItem.ID) -> Void
    let onClear: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void
    let onSelectItem: @MainActor (TemporaryShelfItem.ID) -> Void
    let onClearSelection: @MainActor () -> Void
    let onSelectItems: @MainActor (Set<TemporaryShelfItem.ID>) -> Void
    @State private var selectionOrigin: CGPoint?
    @State private var selectionRect: CGRect?
    @State private var shelfItemFrames: [TemporaryShelfItem.ID: CGRect] = [:]
    @State private var selectedFilter: TemporaryFileShelfFilter = .all

    private let selectionDragThreshold: CGFloat = 5
    private let coordinateSpaceName = "TemporaryFileShelfSelectionSpace"
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var filteredItems: [TemporaryShelfItem] {
        items.filter { selectedFilter.matches($0.category) }
    }

    private var filteredGroupedItems: [ShelfCategoryGroup] {
        TemporaryShelfFileCategory.allCases.compactMap { category in
            let categoryItems = filteredItems.filter { $0.category == category }
            guard !categoryItems.isEmpty else {
                return nil
            }
            return ShelfCategoryGroup(category: category, items: categoryItems)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(isDropTargetActive ? "Drop Files" : "File Shelf")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.90))

                Text("\(items.count)")
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .frame(minWidth: 18, minHeight: 16)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    }

                Spacer(minLength: 0)

                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(ShelfActionButtonStyle())

                if !items.isEmpty {
                    Button("Clear") {
                        onClear()
                    }
                    .buttonStyle(ShelfActionButtonStyle(isDestructive: true))
                }
            }
            .frame(height: 24)

            if !items.isEmpty {
                filterBar
            }

            shelfBody
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.025, green: 0.028, blue: 0.034))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(isDropTargetActive ? 0.20 : 0.09), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var shelfBody: some View {
        shelfContentBoundary {
            if items.isEmpty {
                emptyDropZone
            } else if filteredItems.isEmpty {
                emptyFilterZone
            } else {
                groupedShelfContent
            }
        }
    }

    private var groupedShelfContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(groupedItems) { group in
                    categorySection(group)
                }
            }
            .padding(8)
        }
        .scrollIndicators(.never)
    }

    private var groupedItems: [ShelfCategoryGroup] {
        filteredGroupedItems
    }

    private var filterBar: some View {
        HStack(spacing: 5) {
            ForEach(TemporaryFileShelfFilter.allCases, id: \.self) { filter in
                let isSelected = selectedFilter == filter

                Button {
                    selectedFilter = filter
                } label: {
                    Text(filter.title)
                        .font(.system(size: 8.2, weight: .heavy, design: .rounded))
                        .foregroundStyle(isSelected ? Color.black.opacity(0.86) : Color.white.opacity(0.56))
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                        .frame(maxWidth: .infinity)
                        .frame(height: 18)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.white.opacity(0.88) : Color.white.opacity(0.065))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 18)
    }

    private var emptyDropZone: some View {
        VStack(spacing: 4) {
            Text("Drop files here")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
            Text("Temporary for this app run, up to 24h")
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFilterZone: some View {
        VStack(spacing: 4) {
            Text("No \(selectedFilter.title)")
                .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.70))
            Text("Switch filter or drop matching files")
                .font(.system(size: 8.3, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.36))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func categorySection(_ group: ShelfCategoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            categoryHeader(group)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(group.items) { item in
                    shelfItemTile(item)
                }
            }
        }
    }

    private func categoryHeader(_ group: ShelfCategoryGroup) -> some View {
        HStack(spacing: 6) {
            Text(group.category.title)
                .font(.system(size: 8.5, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)

            Text("\(group.items.count)")
                .font(.system(size: 7.2, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.36))
                .frame(minWidth: 14, minHeight: 13)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.065))
                }

            Spacer(minLength: 0)
        }
        .frame(height: 16)
    }

    private func shelfContentBoundary<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let selectionRect {
                selectionRectangle(selectionRect)
            }
        }
        .coordinateSpace(name: coordinateSpaceName)
        .contentShape(Rectangle())
        .simultaneousGesture(selectionDragGesture)
        .onTapGesture {
            onClearSelection()
        }
        .onPreferenceChange(ShelfItemFramePreferenceKey.self) { frames in
            shelfItemFrames = frames
        }
        .onChange(of: selectedFilter) { _, _ in
            shelfItemFrames.removeAll()
            selectionRect = nil
        }
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(isDropTargetActive ? 0.070 : 0.035))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(.white.opacity(isDropTargetActive ? 0.30 : 0.16))
        }
    }

    private var selectionDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if selectionOrigin == nil {
                    selectionOrigin = value.startLocation
                }

                guard let selectionOrigin else { return }
                let distance = hypot(
                    value.location.x - selectionOrigin.x,
                    value.location.y - selectionOrigin.y
                )
                guard distance >= selectionDragThreshold else { return }

                let rect = CGRect(
                    x: min(selectionOrigin.x, value.location.x),
                    y: min(selectionOrigin.y, value.location.y),
                    width: abs(selectionOrigin.x - value.location.x),
                    height: abs(selectionOrigin.y - value.location.y)
                )
                selectionRect = rect

                let selectedIDs = Set(
                    shelfItemFrames.compactMap { id, frame in
                        frame.intersects(rect) ? id : nil
                    }
                )
                onSelectItems(selectedIDs)
            }
            .onEnded { value in
                defer {
                    selectionOrigin = nil
                    selectionRect = nil
                }

                guard let selectionOrigin else { return }
                let distance = hypot(
                    value.location.x - selectionOrigin.x,
                    value.location.y - selectionOrigin.y
                )
                if distance < selectionDragThreshold {
                    onClearSelection()
                }
            }
    }

    private func selectionRectangle(_ rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.white.opacity(0.075))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.34), lineWidth: 1)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    private func shelfItemTile(_ item: TemporaryShelfItem) -> some View {
        let isSelected = selectedItemIDs.contains(item.id)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.fileURL.path))
                    .resizable()
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    Text(item.fileExtension?.uppercased() ?? "FILE")
                        .font(.system(size: 6.8, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.34))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onDragItems { dragItemProviders(for: item) } fileURLs: {
                draggedItems(for: item).map(\.fileURL)
            } onClick: {
                onSelectItem(item.id)
            }

            HStack(spacing: 6) {
                Button("Open") {
                    onOpen(item)
                }
                .buttonStyle(ShelfActionButtonStyle())

                Button("Remove") {
                    onRemove(item.id)
                }
                .buttonStyle(ShelfActionButtonStyle(isDestructive: true))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ShelfItemFramePreferenceKey.self,
                    value: [item.id: proxy.frame(in: .named(coordinateSpaceName))]
                )
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.12 : 0.062))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.white.opacity(0.34) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                }
        }
        .onTapGesture {
            onSelectItem(item.id)
        }
    }

    private func draggedItems(for item: TemporaryShelfItem) -> [TemporaryShelfItem] {
        guard selectedItemIDs.contains(item.id) else {
            return [item]
        }

        let selectedItems = items.filter { selectedItemIDs.contains($0.id) }
        return selectedItems.isEmpty ? [item] : selectedItems
    }

    private func dragItemProviders(for item: TemporaryShelfItem) -> [NSItemProvider] {
        draggedItems(for: item).map { item in
            NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider()
        }
    }

}

private extension View {
    func onDragItems(
        _ providers: @escaping () -> [NSItemProvider],
        fileURLs: @escaping () -> [URL],
        onClick: @escaping @MainActor () -> Void
    ) -> some View {
        modifier(
            ShelfFileDragSourceModifier(
                itemProviders: providers,
                fileURLs: fileURLs,
                onClick: onClick
            )
        )
    }
}

private struct ShelfFileDragSourceModifier: ViewModifier {
    let itemProviders: () -> [NSItemProvider]
    let fileURLs: () -> [URL]
    let onClick: @MainActor () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            ShelfFileDragSourceView(
                itemProviders: itemProviders,
                fileURLs: fileURLs,
                onClick: onClick
            )
        }
    }
}

private struct ShelfFileDragSourceView: NSViewRepresentable {
    let itemProviders: () -> [NSItemProvider]
    let fileURLs: () -> [URL]
    let onClick: @MainActor () -> Void

    func makeNSView(context: Context) -> ShelfFileDragSourceNSView {
        let view = ShelfFileDragSourceNSView()
        view.itemProviders = itemProviders
        view.fileURLs = fileURLs
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: ShelfFileDragSourceNSView, context: Context) {
        nsView.itemProviders = itemProviders
        nsView.fileURLs = fileURLs
        nsView.onClick = onClick
    }
}

@MainActor
private final class ShelfFileDragSourceNSView: NSView, NSDraggingSource {
    var itemProviders: (() -> [NSItemProvider])?
    var fileURLs: (() -> [URL])?
    var onClick: (() -> Void)?

    private var mouseDownEvent: NSEvent?
    private var hasStartedDrag = false
    private let dragThreshold: CGFloat = 4

    override var isFlipped: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        hasStartedDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !hasStartedDrag, let mouseDownEvent else { return }

        let start = convert(mouseDownEvent.locationInWindow, from: nil)
        let current = convert(event.locationInWindow, from: nil)
        let distance = hypot(current.x - start.x, current.y - start.y)
        guard distance >= dragThreshold else { return }

        let draggingItems = makeDraggingItems()
        guard !draggingItems.isEmpty else { return }

        hasStartedDrag = true
        beginDraggingSession(with: draggingItems, event: mouseDownEvent, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownEvent = nil
            hasStartedDrag = false
        }

        guard !hasStartedDrag else { return }
        onClick?()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    private func makeDraggingItems() -> [NSDraggingItem] {
        _ = itemProviders?()
        let urls = fileURLs?() ?? []
        guard !urls.isEmpty else { return [] }

        let itemSize = CGSize(width: max(28, min(bounds.width, 120)), height: max(28, min(bounds.height, 48)))
        return urls.enumerated().map { index, fileURL in
            let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
            let origin = CGPoint(x: CGFloat(index) * 3, y: CGFloat(index) * 3)
            draggingItem.setDraggingFrame(CGRect(origin: origin, size: itemSize), contents: NSWorkspace.shared.icon(forFile: fileURL.path))
            return draggingItem
        }
    }
}

private struct ShelfCategoryGroup: Identifiable {
    let category: TemporaryShelfFileCategory
    let items: [TemporaryShelfItem]

    var id: TemporaryShelfFileCategory {
        category
    }
}

private struct ShelfItemFramePreferenceKey: PreferenceKey {
    static let defaultValue: [TemporaryShelfItem.ID: CGRect] = [:]

    static func reduce(value: inout [TemporaryShelfItem.ID: CGRect], nextValue: () -> [TemporaryShelfItem.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct ShelfActionButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 8.2, weight: .heavy, design: .rounded))
            .foregroundStyle(isDestructive ? .white.opacity(0.62) : .black.opacity(0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isDestructive ? Color.white.opacity(0.075) : Color.white.opacity(0.86))
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
