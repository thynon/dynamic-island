import AppKit
import SwiftUI
import DynamicIslandCore

@MainActor
final class IslandPanelController {
    private enum ActiveScrollGesture {
        case none
        case vertical
        case horizontal
    }

    private static let closedHoverHorizontalSlack: CGFloat = 22
    private static let closedHoverBottomSlack: CGFloat = 10
    private static let musicSkipEdgeExpansionMax: CGFloat = 50
    private static let closedCanvasHorizontalSlack: CGFloat = max(closedHoverHorizontalSlack, musicSkipEdgeExpansionMax * 2)
    private static let gestureAxisLockThreshold: CGFloat = 6
    private static let scrollActivationThreshold: CGFloat = 6
    private static let horizontalCommitDistance: CGFloat = 50
    private static let horizontalCancelDistance: CGFloat = 38
    private static let gestureResetDelay: TimeInterval = 0.22
    private static let scrollSuppressionAfterExpansionDuration: TimeInterval = 0.35
    private static let musicSkipCooldown: TimeInterval = 0.7
    private static let musicSkipFeedbackDuration: TimeInterval = 0.42
    private static let trackInfoDismissDelay: TimeInterval = 2.5
    private static let debugMusicSignalEnvironmentKey = "ISLAND_DEBUG_MUSIC_SIGNAL_FILE"
    private static let debugExpandedOnLaunchEnvironmentKey = "ISLAND_DEBUG_EXPANDED_ON_LAUNCH"
    private static let debugFileShelfURLsEnvironmentKey = "ISLAND_DEBUG_FILE_SHELF_URLS"

    private var metrics: NotchMetrics
    private var isExpanded = false
    private var collapseWorkItem: DispatchWorkItem?
    nonisolated(unsafe) private var trackInfoDismissWorkItem: DispatchWorkItem?
    nonisolated(unsafe) private var musicSkipFeedbackWorkItem: DispatchWorkItem?
    nonisolated(unsafe) private var gestureResetWorkItem: DispatchWorkItem?
    private var lastPresentedTrackIdentity: String?
    private var lastMusicSkipDate: Date?
    private var activeScrollGesture: ActiveScrollGesture = .none
    private var accumulatedScrollDeltaX: CGFloat = 0
    private var accumulatedScrollDeltaY: CGFloat = 0
    private var pendingHorizontalSkipDirection: MusicSkipDirection?
    private var isHorizontalSkipArmed = false
    private var scrollGestureUsesExplicitPhase = false
    private var hasTriggeredHorizontalSkip = false
    private var scrollSuppressionUntil: Date?
    private let panel: NSPanel
    private let overlayState: IslandOverlayState
    private let hostingView: IslandTrackingHostingView
    private let animationProfile = IslandAnimationProfile.default
    private let musicPlaybackDataSource: any MusicPlaybackDataSource
    private let temporaryFileShelfStore = TemporaryFileShelfStore()
    private let interactionLogger = IslandInteractionLogger()
    private var temporaryFileShelfSelection = TemporaryFileShelfSelection()
    private var musicPlaybackPollingTask: Task<Void, Never>?
    private var debugMusicSignalTask: Task<Void, Never>?
    private var musicSkipTask: Task<Void, Never>?
    private var temporaryFileShelfPruningTask: Task<Void, Never>?
    nonisolated(unsafe) private var hiddenScrollMonitor: Any?

    init(
        screen: NSScreen? = NSScreen.main,
        musicPlaybackDataSource: any MusicPlaybackDataSource = ScriptableMusicPlaybackDataSource()
    ) {
        self.musicPlaybackDataSource = musicPlaybackDataSource
        let screenMetrics = ScreenMetricsProvider.profile(for: screen)
        metrics = screenMetrics

        let overlayState = IslandOverlayState()
        self.overlayState = overlayState

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize(for: screenMetrics, usesOpenCanvas: false)),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        hostingView = IslandTrackingHostingView(
            rootView: IslandOverlayView(metrics: screenMetrics, state: overlayState)
        )

        configurePanel()
        installHostingView()
        installTrackingCallbacks()
        updateRootView()
        position(on: screen ?? NSScreen.main)
        loadDebugTemporaryFileShelfIfNeeded()
        if Self.shouldStartExpandedForDebug {
            setExpanded(true)
        }
        var launchMetadata = Self.displayLogMetadata(for: screen ?? NSScreen.main, metrics: metrics)
        launchMetadata["launchMode"] = Self.debugMusicSignalFileURL == nil ? "musicPlaybackPolling" : "debugMusicSignal"
        launchMetadata["bundleIdentifier"] = Bundle.main.bundleIdentifier ?? ""
        launchMetadata["executable"] = Bundle.main.executableURL?.lastPathComponent ?? "DynamicIsland"
        launchMetadata["logFile"] = interactionLogger.logURL.lastPathComponent
        interactionLogger.log("app.launch", metadata: launchMetadata)
        if Self.debugMusicSignalFileURL != nil {
            startDebugMusicSignalPolling()
        } else {
            startMusicPlaybackPolling()
        }
        startTemporaryFileShelfPruning()
    }

    private static func displayLogMetadata(for screen: NSScreen?, metrics: NotchMetrics) -> [String: Any] {
        var metadata: [String: Any] = [
            "openWidth": Int(metrics.openWidth),
            "openHeight": Int(metrics.openHeight),
            "closedHeight": Int(metrics.closedHeight),
            "cameraHousingWidth": Int(metrics.cameraHousingWidth)
        ]

        guard let screen else {
            metadata["hasCameraHousing"] = false
            return metadata
        }

        let hasCameraHousing = screen.safeAreaInsets.top > 0
            && screen.auxiliaryTopLeftArea != nil
            && screen.auxiliaryTopRightArea != nil
        metadata["hasCameraHousing"] = hasCameraHousing
        metadata["screenWidth"] = Int(screen.frame.width.rounded())
        metadata["screenHeight"] = Int(screen.frame.height.rounded())
        metadata["safeAreaTopInset"] = Int(screen.safeAreaInsets.top.rounded())
        metadata["backingScaleFactor"] = Double(screen.backingScaleFactor)

        if let auxiliaryTopLeftArea = screen.auxiliaryTopLeftArea {
            metadata["auxiliaryTopLeftWidth"] = Int(auxiliaryTopLeftArea.width.rounded())
        }
        if let auxiliaryTopRightArea = screen.auxiliaryTopRightArea {
            metadata["auxiliaryTopRightWidth"] = Int(auxiliaryTopRightArea.width.rounded())
        }

        return metadata
    }

    deinit {
        musicPlaybackPollingTask?.cancel()
        debugMusicSignalTask?.cancel()
        musicSkipTask?.cancel()
        temporaryFileShelfPruningTask?.cancel()
        trackInfoDismissWorkItem?.cancel()
        musicSkipFeedbackWorkItem?.cancel()
        gestureResetWorkItem?.cancel()
        if let hiddenScrollMonitor {
            NSEvent.removeMonitor(hiddenScrollMonitor)
        }
    }

    func show() {
        refreshForCurrentScreen()
        panel.orderFrontRegardless()
        interactionLogger.log("panel.show")
    }

    func hide() {
        panel.orderOut(nil)
        interactionLogger.log("panel.hide")
    }

    func refreshForCurrentScreen() {
        let screen = NSScreen.main
        let previousMetrics = metrics
        metrics = ScreenMetricsProvider.profile(for: screen)
        if metrics != previousMetrics {
            interactionLogger.log("display.metrics.changed", metadata: Self.displayLogMetadata(for: screen, metrics: metrics))
        }
        updateRootView()
        setPanelFrame(
            Self.windowFrame(
                for: Self.windowSize(
                    for: metrics,
                    usesOpenCanvas: overlayState.usesOpenCanvas,
                    showsTrackInfo: overlayState.isTrackInfoPresented
                ),
                on: screen
            )
        )
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        collapseWorkItem?.cancel()
        collapseWorkItem = nil

        isExpanded = expanded
        interactionLogger.log("shell.expanded", metadata: [
            "expanded": expanded
        ])

        if expanded {
            resetScrollGesture()
            scrollSuppressionUntil = Date().addingTimeInterval(Self.scrollSuppressionAfterExpansionDuration)
            overlayState.usesOpenCanvas = true
            setPanelFrame(
                Self.windowFrame(
                    for: Self.windowSize(for: metrics, usesOpenCanvas: true),
                    on: panel.screen ?? NSScreen.main
                )
            )

            DispatchQueue.main.async { [weak self] in
                guard let self, self.isExpanded else { return }
                withAnimation(self.expandAnimation) {
                    self.overlayState.isExpanded = true
                }
            }
        } else {
            scrollSuppressionUntil = nil
            withAnimation(collapseAnimation) {
                overlayState.isExpanded = false
            }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self, !self.isExpanded else { return }
                self.overlayState.usesOpenCanvas = false
                self.setPanelFrame(
                    Self.windowFrame(
                        for: Self.windowSize(for: self.metrics, usesOpenCanvas: false),
                        on: self.panel.screen ?? NSScreen.main
                    )
                )
            }
            collapseWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + animationProfile.collapseCanvasDelay, execute: workItem)
        }
    }

    private var expandAnimation: Animation {
        .interactiveSpring(
            response: animationProfile.expandResponse,
            dampingFraction: animationProfile.expandDampingFraction,
            blendDuration: animationProfile.expandBlendDuration
        )
    }

    private var collapseAnimation: Animation {
        .easeOut(duration: animationProfile.collapseDuration)
    }

    private func updateRootView() {
        hostingView.rootView = IslandOverlayView(
            metrics: metrics,
            state: overlayState,
            onExpansionChange: { [weak self] expanded in
                self?.setExpanded(expanded)
            },
            onSelectTemporaryFile: { [weak self] itemID, extendingSelection in
                self?.selectTemporaryFile(id: itemID, extendingSelection: extendingSelection)
            },
            onRemoveTemporaryFile: { [weak self] itemID in
                self?.removeTemporaryFile(id: itemID)
            },
            onClearTemporaryFiles: { [weak self] in
                self?.clearTemporaryFiles()
            },
            onStartTemporaryFileDrag: { [weak self] itemIDs in
                self?.startTemporaryFileDrag(ids: itemIDs)
            },
            onCompleteTemporaryFileDrag: { [weak self] itemIDs, succeeded in
                self?.completeTemporaryFileDrag(ids: itemIDs, succeeded: succeeded)
            },
            onChangeTemporaryFileFilter: { [weak self] filter in
                self?.setTemporaryFileShelfFilter(filter)
            },
            onClearTemporaryFileSelection: { [weak self] in
                self?.clearTemporaryFileSelection()
            },
            onToggleFileShelfOverlay: { [weak self] in
                self?.toggleTemporaryFileShelfOverlayFromButton()
            },
            onDoneFileShelfOverlay: { [weak self] in
                self?.closeTemporaryFileShelfOverlay()
            }
        )
    }

    private func configurePanel() {
        panel.title = "Dynamic Island"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
    }

    private func installHostingView() {
        hostingView.frame = NSRect(origin: .zero, size: panel.frame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
    }

    private func installTrackingCallbacks() {
        hostingView.onMouseEntered = { [weak self] in
            guard let self, !self.overlayState.isShellHidden else { return }
            self.syncHoverWithPointer()
        }
        hostingView.onMouseMoved = { [weak self] in
            guard let self, !self.overlayState.isShellHidden else { return }
            self.syncHoverWithPointer()
        }
        hostingView.onMouseExited = { [weak self] in
            guard let self else { return }
            self.overlayState.isHovered = false
            if !self.overlayState.isFileShelfPinnedOpen {
                self.setExpanded(false)
            }
        }
        hostingView.onScroll = { [weak self] deltaX, deltaY, phase, momentumPhase in
            self?.handleScroll(deltaX: deltaX, deltaY: deltaY, phase: phase, momentumPhase: momentumPhase)
        }
        hostingView.canAcceptFileDrop = { [weak self] dropPoint in
            self?.canAcceptFileDrop(at: dropPoint) ?? false
        }
        hostingView.onFileDropTargetedChange = { [weak self] targeted in
            self?.setFileDropTargeted(targeted)
        }
        hostingView.onFileDrop = { [weak self] fileURLs, dropPoint in
            self?.handleFileDrop(fileURLs, at: dropPoint)
        }
    }

    private func canAcceptFileDrop(at dropPoint: NSPoint) -> Bool {
        guard !overlayState.isShellHidden else { return false }
        return pointInsideInteractiveShell(screenPointFromDraggingLocation(dropPoint))
    }

    private func handleFileDrop(_ fileURLs: [URL], at dropPoint: NSPoint) {
        guard canAcceptFileDrop(at: dropPoint) else { return }
        temporaryFileShelfStore.pruneExpired()
        temporaryFileShelfStore.addFileURLs(fileURLs)
        syncTemporaryFileShelfState()
        if !isExpanded {
            setExpanded(true)
        }
        overlayState.isFileShelfOverlayVisible = true
        overlayState.isFileShelfPinnedOpen = true
        overlayState.isFileDropTargetActive = false
        interactionLogger.log("file.drop.accepted", metadata: [
            "count": fileURLs.count,
            "files": IslandInteractionLogger.sanitizedFileMetadata(for: fileURLs)
        ])
    }

    private func selectTemporaryFile(id: TemporaryShelfItem.ID, extendingSelection: Bool) {
        if extendingSelection {
            temporaryFileShelfSelection.toggle(id)
        } else {
            temporaryFileShelfSelection.selectOnly(id)
        }
        syncTemporaryFileShelfSelectionState()
        interactionLogger.log("file.shelf.select", metadata: [
            "selectedCount": temporaryFileShelfSelection.selectedItemIDs.count,
            "extendingSelection": extendingSelection
        ])
    }

    private func startTemporaryFileDrag(ids: [TemporaryShelfItem.ID]) {
        let itemIDs = Set(ids)
        guard !itemIDs.isEmpty else { return }
        temporaryFileShelfSelection.select(itemIDs)
        syncTemporaryFileShelfSelectionState()
        interactionLogger.log("file.drag.start", metadata: [
            "count": itemIDs.count
        ])
    }

    private func completeTemporaryFileDrag(ids: [TemporaryShelfItem.ID], succeeded: Bool) {
        let itemIDs = Set(ids)
        guard !itemIDs.isEmpty else { return }
        interactionLogger.log("file.drag.completed", metadata: [
            "count": itemIDs.count,
            "succeeded": succeeded
        ])

        if succeeded {
            removeTemporaryFiles(ids: itemIDs)
        }
    }

    private func removeTemporaryFile(id: TemporaryShelfItem.ID) {
        let removedItem = temporaryFileShelfStore.shelf.items.first { $0.id == id }
        temporaryFileShelfStore.removeItem(id: id)
        syncTemporaryFileShelfState()
        interactionLogger.log("file.shelf.remove", metadata: [
            "remainingCount": temporaryFileShelfStore.shelf.items.count,
            "files": removedItem.map { IslandInteractionLogger.sanitizedFileMetadata(for: [$0.fileURL]) } ?? []
        ])
    }

    private func removeTemporaryFiles(ids: Set<TemporaryShelfItem.ID>) {
        temporaryFileShelfStore.removeItems(ids: ids)
        syncTemporaryFileShelfState()
    }

    private func clearTemporaryFiles() {
        let removedCount = temporaryFileShelfStore.shelf.items.count
        temporaryFileShelfStore.clear()
        temporaryFileShelfSelection.clear()
        syncTemporaryFileShelfState()
        interactionLogger.log("file.shelf.clear", metadata: [
            "removedCount": removedCount
        ])
    }

    private func openTemporaryFileShelfOverlay(pinned: Bool) {
        temporaryFileShelfStore.pruneExpired()
        syncTemporaryFileShelfState()
        guard temporaryFileShelfStore.shelf.hasItems else { return }
        if !isExpanded {
            setExpanded(true)
        }
        overlayState.isFileShelfOverlayVisible = true
        overlayState.isFileShelfPinnedOpen = pinned
    }

    private func closeTemporaryFileShelfOverlay() {
        overlayState.isFileShelfOverlayVisible = false
        overlayState.isFileShelfPinnedOpen = false
        overlayState.isFileDropTargetActive = false
        interactionLogger.log("file.shelf.done", metadata: [
            "remainingCount": temporaryFileShelfStore.shelf.items.count
        ])
    }

    private func toggleTemporaryFileShelfOverlayFromButton() {
        temporaryFileShelfStore.pruneExpired()
        syncTemporaryFileShelfState()
        guard temporaryFileShelfStore.shelf.hasItems else { return }

        if overlayState.isFileShelfOverlayVisible, overlayState.isFileShelfPinnedOpen {
            closeTemporaryFileShelfOverlay()
        } else {
            openTemporaryFileShelfOverlay(pinned: true)
        }
    }

    private func setTemporaryFileShelfFilter(_ filter: TemporaryFileShelfFilter) {
        overlayState.temporaryFileShelfFilter = filter
        interactionLogger.log("file.shelf.filter", metadata: [
            "filter": filter.title,
            "visibleCount": temporaryFileShelfStore.shelf.items(filteredBy: filter).count
        ])
    }

    private func clearTemporaryFileSelection() {
        temporaryFileShelfSelection.clear()
        syncTemporaryFileShelfSelectionState()
    }

    private func syncTemporaryFileShelfState() {
        temporaryFileShelfSelection.retainOnly(itemIDs: temporaryFileShelfStore.shelf.items.map(\.id))
        overlayState.temporaryFileShelf = temporaryFileShelfStore.shelf
        syncTemporaryFileShelfSelectionState()
        if !temporaryFileShelfStore.shelf.hasItems {
            overlayState.isFileShelfOverlayVisible = false
            overlayState.isFileShelfPinnedOpen = false
            overlayState.isFileDropTargetActive = false
            overlayState.temporaryFileShelfFilter = .all
        }
    }

    private func syncTemporaryFileShelfSelectionState() {
        overlayState.temporaryFileShelfSelectedItemIDs = temporaryFileShelfSelection.selectedItemIDs
    }

    private func setFileDropTargeted(_ targeted: Bool) {
        let nextValue = targeted && !overlayState.isShellHidden
        guard overlayState.isFileDropTargetActive != nextValue else { return }
        withAnimation(.easeOut(duration: 0.14)) {
            overlayState.isFileDropTargetActive = nextValue
            if nextValue {
                overlayState.isFileShelfOverlayVisible = true
            } else if !overlayState.isFileShelfPinnedOpen, !temporaryFileShelfStore.shelf.hasItems {
                overlayState.isFileShelfOverlayVisible = false
            }
            if !self.isExpanded {
                overlayState.isHovered = nextValue
            }
        }
        interactionLogger.log("file.drop.targeted", metadata: [
            "targeted": nextValue
        ])
    }

    private func handleScroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        phase: NSEvent.Phase = [],
        momentumPhase: NSEvent.Phase = []
    ) {
        let scrollGestureEnded = phase.contains(.ended)
        let scrollGestureCancelled = phase.contains(.cancelled)

        if (phase.contains(.began) || phase.contains(.mayBegin)) && !scrollGestureUsesExplicitPhase {
            prepareForNewScrollGesture()
        }
        if !phase.isEmpty {
            scrollGestureUsesExplicitPhase = true
        }

        if let scrollSuppressionUntil {
            if Date() < scrollSuppressionUntil {
                resetScrollGesture(shouldCommitPendingSkip: false)
                return
            }
            self.scrollSuppressionUntil = nil
        }

        let pointerInsideIsland = pointerInsideInteractiveShell()
        guard pointerInsideIsland else {
            resetScrollGesture(shouldCommitPendingSkip: false)
            return
        }

        guard momentumPhase.isEmpty else {
            if !scrollGestureUsesExplicitPhase {
                scheduleGestureReset(delay: 0.08)
            }
            return
        }

        if overlayState.isShellHidden {
            accumulatedScrollDeltaY += deltaY
            if scrollGestureEnded || scrollGestureCancelled {
                finalizeScrollGesture(shouldCommitPendingSkip: false)
            } else if !scrollGestureUsesExplicitPhase {
                scheduleGestureReset()
            }
            if deltaY > Self.scrollActivationThreshold {
                setShellHidden(false)
            } else if accumulatedScrollDeltaY > Self.scrollActivationThreshold {
                setShellHidden(false)
            }
            return
        }

        accumulatedScrollDeltaX += deltaX
        accumulatedScrollDeltaY += deltaY

        switch activeScrollGesture {
        case .none:
            lockScrollGestureIfNeeded(phase: phase)
        case .horizontal:
            updateHorizontalMusicSkip()
        case .vertical:
            updateVerticalScrollIntent()
        }

        if scrollGestureEnded || scrollGestureCancelled {
            finalizeScrollGesture(shouldCommitPendingSkip: scrollGestureEnded)
        } else if !scrollGestureUsesExplicitPhase {
            scheduleGestureReset()
        }
    }

    private func lockScrollGestureIfNeeded(phase: NSEvent.Phase) {
        let horizontalDominant = abs(accumulatedScrollDeltaX) > abs(accumulatedScrollDeltaY) * 1.4
        let verticalDominant = abs(accumulatedScrollDeltaY) > abs(accumulatedScrollDeltaX) * 1.4

        if canHandleHorizontalMusicSkip, horizontalDominant, abs(accumulatedScrollDeltaX) >= Self.gestureAxisLockThreshold {
            activeScrollGesture = .horizontal
            interactionLogger.log("scroll.gesture.locked", metadata: [
                "axis": "horizontal",
                "deltaX": Double(accumulatedScrollDeltaX),
                "deltaY": Double(accumulatedScrollDeltaY),
                "phase": Self.scrollPhaseDescription(phase),
                "usesExplicitPhase": scrollGestureUsesExplicitPhase
            ])
            updateHorizontalMusicSkip()
        } else if verticalDominant, abs(accumulatedScrollDeltaY) >= Self.gestureAxisLockThreshold {
            activeScrollGesture = .vertical
            interactionLogger.log("scroll.gesture.locked", metadata: [
                "axis": "vertical",
                "deltaX": Double(accumulatedScrollDeltaX),
                "deltaY": Double(accumulatedScrollDeltaY),
                "phase": Self.scrollPhaseDescription(phase),
                "usesExplicitPhase": scrollGestureUsesExplicitPhase
            ])
            updateVerticalScrollIntent()
        }
    }

    private static func scrollPhaseDescription(_ phase: NSEvent.Phase) -> String {
        var values: [String] = []
        if phase.contains(.mayBegin) { values.append("mayBegin") }
        if phase.contains(.began) { values.append("began") }
        if phase.contains(.changed) { values.append("changed") }
        if phase.contains(.stationary) { values.append("stationary") }
        if phase.contains(.ended) { values.append("ended") }
        if phase.contains(.cancelled) { values.append("cancelled") }
        return values.isEmpty ? "none" : values.joined(separator: "+")
    }

    private var canHandleHorizontalMusicSkip: Bool {
        overlayState.musicPlayback.isPlaying
            && !isExpanded
            && !overlayState.isShellHidden
            && !overlayState.isTrackInfoPresented
    }

    private func updateVerticalScrollIntent() {
        if accumulatedScrollDeltaY < -Self.scrollActivationThreshold {
            setShellHidden(true)
            resetScrollGesture()
        } else if accumulatedScrollDeltaY > Self.scrollActivationThreshold {
            setShellHidden(false)
        }
    }

    private func updateHorizontalMusicSkip() {
        guard canHandleHorizontalMusicSkip else {
            resetScrollGesture()
            return
        }

        let direction: MusicSkipDirection = accumulatedScrollDeltaX < 0 ? .previous : .next
        let absoluteDeltaX = abs(accumulatedScrollDeltaX)
        let progress = min(abs(accumulatedScrollDeltaX) / Self.horizontalCommitDistance, 1)

        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.82)) {
            overlayState.musicSkipFeedbackDirection = direction
            overlayState.musicSkipGestureProgress = progress
        }

        var cancelledArmedSkip = false
        if isHorizontalSkipArmed {
            if pendingHorizontalSkipDirection != direction {
                cancelPendingHorizontalMusicSkip(reason: "directionChanged")
                cancelledArmedSkip = true
            } else if absoluteDeltaX <= Self.horizontalCancelDistance {
                cancelPendingHorizontalMusicSkip(reason: "returnedToCancelBoundary")
                cancelledArmedSkip = true
            }
        }

        if !isHorizontalSkipArmed, !cancelledArmedSkip, progress >= 1 {
            armPendingHorizontalMusicSkip(direction)
        }
    }

    private func armPendingHorizontalMusicSkip(_ direction: MusicSkipDirection) {
        guard !isHorizontalSkipArmed else { return }
        isHorizontalSkipArmed = true
        pendingHorizontalSkipDirection = direction
        withAnimation(.easeOut(duration: 0.10)) {
            overlayState.isMusicSkipArmed = true
        }
        interactionLogger.log("music.skip.armed", metadata: [
            "direction": direction == .next ? "next" : "previous",
            "deltaX": Double(accumulatedScrollDeltaX)
        ])
    }

    private func cancelPendingHorizontalMusicSkip(reason: String) {
        guard isHorizontalSkipArmed || pendingHorizontalSkipDirection != nil else { return }
        interactionLogger.log("music.skip.cancelled", metadata: [
            "reason": reason,
            "deltaX": Double(accumulatedScrollDeltaX)
        ])
        isHorizontalSkipArmed = false
        pendingHorizontalSkipDirection = nil
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.82)) {
            overlayState.isMusicSkipArmed = false
        }
    }

    private func commitPendingHorizontalMusicSkipIfNeeded() -> Bool {
        guard
            activeScrollGesture == .horizontal,
            isHorizontalSkipArmed,
            let direction = pendingHorizontalSkipDirection,
            !hasTriggeredHorizontalSkip
        else {
            return false
        }

        let now = Date()
        if let lastMusicSkipDate, now.timeIntervalSince(lastMusicSkipDate) < Self.musicSkipCooldown {
            cancelPendingHorizontalMusicSkip(reason: "cooldown")
            return false
        }

        hasTriggeredHorizontalSkip = true
        lastMusicSkipDate = now
        overlayState.isMusicSkipArmed = false
        interactionLogger.log("music.skip.commit", metadata: [
            "direction": direction == .next ? "next" : "previous",
            "deltaX": Double(accumulatedScrollDeltaX)
        ])
        performMusicSkip(direction)
        return true
    }

    private func performMusicSkip(_ direction: MusicSkipDirection) {
        musicSkipFeedbackWorkItem?.cancel()
        musicSkipTask?.cancel()

        withAnimation(.easeOut(duration: 0.16)) {
            overlayState.musicSkipFeedbackDirection = direction
            overlayState.musicSkipGestureProgress = 1
        }

        musicSkipTask = Task { [weak self] in
            guard let self else { return }
            let didSkip = await musicPlaybackDataSource.skipTrack(direction)
            guard didSkip, !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            let snapshot = await musicPlaybackDataSource.currentSnapshot()
            updateMusicPlayback(snapshot)
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                self.overlayState.musicSkipGestureProgress = 0
                self.overlayState.musicSkipFeedbackDirection = nil
            }
        }
        musicSkipFeedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.musicSkipFeedbackDuration, execute: workItem)
    }

    private func scheduleGestureReset(delay: TimeInterval? = nil) {
        gestureResetWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.resetScrollGesture()
        }
        gestureResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay ?? Self.gestureResetDelay), execute: workItem)
    }

    private func finalizeScrollGesture(shouldCommitPendingSkip: Bool) {
        if !shouldCommitPendingSkip, activeScrollGesture == .horizontal, isHorizontalSkipArmed {
            cancelPendingHorizontalMusicSkip(reason: "gestureCancelled")
        }
        resetScrollGesture(shouldCommitPendingSkip: shouldCommitPendingSkip)
    }

    private func prepareForNewScrollGesture() {
        gestureResetWorkItem?.cancel()
        gestureResetWorkItem = nil
        activeScrollGesture = .none
        accumulatedScrollDeltaX = 0
        accumulatedScrollDeltaY = 0
        pendingHorizontalSkipDirection = nil
        isHorizontalSkipArmed = false
        scrollGestureUsesExplicitPhase = false
        overlayState.isMusicSkipArmed = false
        hasTriggeredHorizontalSkip = false
    }

    private func resetScrollGesture(shouldCommitPendingSkip: Bool = true) {
        gestureResetWorkItem?.cancel()
        gestureResetWorkItem = nil
        let didCommitPendingSkip = shouldCommitPendingSkip && commitPendingHorizontalMusicSkipIfNeeded()
        let shouldDismissFeedback = activeScrollGesture == .horizontal && !didCommitPendingSkip
        activeScrollGesture = .none
        accumulatedScrollDeltaX = 0
        accumulatedScrollDeltaY = 0
        pendingHorizontalSkipDirection = nil
        isHorizontalSkipArmed = false
        scrollGestureUsesExplicitPhase = false
        overlayState.isMusicSkipArmed = false
        hasTriggeredHorizontalSkip = false

        if shouldDismissFeedback {
            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.82)) {
                overlayState.musicSkipGestureProgress = 0
                overlayState.musicSkipFeedbackDirection = nil
            }
        }
    }

    private func setShellHidden(_ hidden: Bool) {
        guard overlayState.isShellHidden != hidden else { return }
        interactionLogger.log("shell.hidden", metadata: [
            "hidden": hidden
        ])
        if hidden {
            overlayState.isHovered = false
            overlayState.isTrackInfoPresented = false
            overlayState.musicSkipGestureProgress = 0
            overlayState.musicSkipFeedbackDirection = nil
            overlayState.isMusicSkipArmed = false
            trackInfoDismissWorkItem?.cancel()
            trackInfoDismissWorkItem = nil
            musicSkipFeedbackWorkItem?.cancel()
            musicSkipFeedbackWorkItem = nil
            resetScrollGesture()
            setExpanded(false)
        } else {
            panel.ignoresMouseEvents = false
            removeHiddenScrollMonitor()
            syncHoverWithPointer()
        }
        withAnimation(.easeInOut(duration: 0.22)) {
            overlayState.isShellHidden = hidden
        }
        if hidden {
            installHiddenScrollMonitor()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                guard let self, self.overlayState.isShellHidden else { return }
                self.panel.ignoresMouseEvents = hidden
            }
        }
    }

    private func installHiddenScrollMonitor() {
        guard hiddenScrollMonitor == nil else { return }
        hiddenScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                guard self.overlayState.isShellHidden else { return }
                guard self.pointerInsideInteractiveShell() else { return }
                self.handleScroll(
                    deltaX: event.scrollingDeltaX,
                    deltaY: event.scrollingDeltaY,
                    phase: event.phase,
                    momentumPhase: event.momentumPhase
                )
            }
        }
    }

    private func removeHiddenScrollMonitor() {
        if let hiddenScrollMonitor {
            NSEvent.removeMonitor(hiddenScrollMonitor)
            self.hiddenScrollMonitor = nil
        }
    }

    private func syncHoverWithPointer() {
        overlayState.isHovered = pointerInsideInteractiveShell()
    }

    private func pointerInsideInteractiveShell() -> Bool {
        pointInsideInteractiveShell(NSEvent.mouseLocation)
    }

    private func pointInsideInteractiveShell(_ mouseLocation: NSPoint) -> Bool {
        let shellFrame = currentShellFrameInScreenCoordinates
        guard shellFrame.insetBy(dx: -2, dy: -2).contains(mouseLocation) else { return false }

        let localPoint = CGPoint(
            x: mouseLocation.x - shellFrame.minX,
            y: shellFrame.maxY - mouseLocation.y
        )
        return currentShellPathForHitTesting(in: CGRect(origin: .zero, size: shellFrame.size)).contains(localPoint)
    }

    private func screenPointFromDraggingLocation(_ dropPoint: NSPoint) -> NSPoint {
        panel.convertPoint(toScreen: dropPoint)
    }

    private func currentShellPathForHitTesting(in rect: CGRect) -> Path {
        IslandShape(
            topCornerRadius: isExpanded ? metrics.openTopCornerRadius : metrics.closedTopCornerRadius,
            concaveTopRadius: isExpanded ? metrics.openTopCornerRadius : metrics.closedConcaveTopRadius,
            bottomCornerRadius: isExpanded ? metrics.openBottomCornerRadius : metrics.closedBottomCornerRadius,
            baseHeight: currentShellHeightForHitTesting
        )
        .path(in: rect)
    }

    private var currentShellFrameInScreenCoordinates: NSRect {
        let shellWidth = currentShellWidthForHitTesting
        let shellHeight = currentShellHeightForHitTesting
        return NSRect(
            x: panel.frame.midX - (shellWidth / 2) + currentShellHorizontalOffsetForHitTesting,
            y: panel.frame.maxY - shellHeight,
            width: shellWidth,
            height: shellHeight
        )
        .insetBy(dx: -2, dy: -2)
    }

    private var currentShellWidthForHitTesting: CGFloat {
        guard !isExpanded else { return metrics.openWidth }
        let closedWidth = overlayState.musicPlayback.isPlaying ? metrics.musicClosedShellWidth : metrics.closedShellWidth
        return closedWidth + currentSkipExpansionForHitTesting
    }

    private var currentShellHeightForHitTesting: CGFloat {
        if isExpanded {
            metrics.openHeight
        } else if overlayState.isTrackInfoPresented {
            metrics.musicTrackInfoShellHeight
        } else {
            metrics.closedHeight
        }
    }

    private var currentSkipExpansionForHitTesting: CGFloat {
        guard
            overlayState.musicPlayback.isPlaying,
            !isExpanded,
            !overlayState.isTrackInfoPresented,
            overlayState.musicSkipFeedbackDirection != nil
        else {
            return 0
        }
        return Self.musicSkipEdgeExpansionMax * min(max(overlayState.musicSkipGestureProgress, 0), 1)
    }

    private var currentShellHorizontalOffsetForHitTesting: CGFloat {
        guard let direction = overlayState.musicSkipFeedbackDirection else { return 0 }
        let expansion = currentSkipExpansionForHitTesting
        return direction == .next ? expansion / 2 : -expansion / 2
    }

    private static var debugMusicSignalFileURL: URL? {
        guard
            let path = ProcessInfo.processInfo.environment[debugMusicSignalEnvironmentKey],
            !path.isEmpty
        else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private static var shouldStartExpandedForDebug: Bool {
        let value = ProcessInfo.processInfo.environment[debugExpandedOnLaunchEnvironmentKey] ?? ""
        return ["1", "true", "yes"].contains(value.lowercased())
    }

    private static var debugFileShelfURLs: [URL] {
        let rawValue = ProcessInfo.processInfo.environment[debugFileShelfURLsEnvironmentKey] ?? ""
        return rawValue
            .split(separator: "|")
            .map(String.init)
            .filter { !$0.isEmpty }
            .map(URL.init(fileURLWithPath:))
    }

    private func loadDebugTemporaryFileShelfIfNeeded() {
        let fileURLs = Self.debugFileShelfURLs
        guard !fileURLs.isEmpty else { return }
        temporaryFileShelfStore.addFileURLs(fileURLs)
        syncTemporaryFileShelfState()
        overlayState.isFileShelfOverlayVisible = true
        overlayState.isFileShelfPinnedOpen = true
    }

    private func startDebugMusicSignalPolling() {
        guard let signalFileURL = Self.debugMusicSignalFileURL else { return }
        debugMusicSignalTask?.cancel()
        debugMusicSignalTask = Task { [weak self] in
            var lastSignal: DebugMusicSignal?
            while !Task.isCancelled {
                guard let self else { return }
                if let signal = DebugMusicSignal.read(from: signalFileURL), signal != lastSignal {
                    applyDebugMusicSignal(signal)
                    lastSignal = signal
                }
                try? await Task.sleep(nanoseconds: 160_000_000)
            }
        }
    }

    private func applyDebugMusicSignal(_ signal: DebugMusicSignal) {
        overlayState.musicPlayback = signal.isPlaying
            ? .playing(title: signal.title, artist: signal.artist)
            : .idle
        overlayState.isTrackInfoPresented = false
        interactionLogger.log("debug.music.signal", metadata: [
            "isPlaying": signal.isPlaying,
            "title": signal.title,
            "artist": signal.artist,
            "feedbackDirection": signal.feedbackDirection.map { $0 == .next ? "next" : "previous" } ?? "",
            "progress": Double(signal.clampedProgress)
        ])

        if signal.isPlaying, let direction = signal.feedbackDirection, signal.clampedProgress > 0 {
            overlayState.musicSkipFeedbackDirection = direction
            overlayState.musicSkipGestureProgress = signal.clampedProgress
        } else {
            overlayState.musicSkipFeedbackDirection = nil
            overlayState.musicSkipGestureProgress = 0
        }
        overlayState.isMusicSkipArmed = false
    }

    private func startMusicPlaybackPolling() {
        musicPlaybackPollingTask?.cancel()
        musicPlaybackPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = await musicPlaybackDataSource.currentSnapshot()
                updateMusicPlayback(snapshot)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func startTemporaryFileShelfPruning() {
        temporaryFileShelfPruningTask?.cancel()
        temporaryFileShelfPruningTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self else { return }
                temporaryFileShelfStore.pruneExpired()
                syncTemporaryFileShelfState()
            }
        }
    }

    private func updateMusicPlayback(_ snapshot: MusicPlaybackSnapshot) {
        let previousIdentity = overlayState.musicPlayback.trackIdentity
        let previousIsPlaying = overlayState.musicPlayback.isPlaying
        overlayState.musicPlayback = snapshot
        if previousIdentity != snapshot.trackIdentity || previousIsPlaying != snapshot.isPlaying {
            interactionLogger.log("music.playback.changed", metadata: [
                "isPlaying": snapshot.isPlaying,
                "title": snapshot.title,
                "artist": snapshot.artist
            ])
        }

        guard
            !isExpanded,
            !overlayState.isShellHidden,
            let trackIdentity = snapshot.trackIdentity
        else {
            lastPresentedTrackIdentity = snapshot.trackIdentity
            return
        }

        let shouldPresent = previousIdentity != nil
            && previousIdentity != trackIdentity
            && lastPresentedTrackIdentity != trackIdentity
        lastPresentedTrackIdentity = trackIdentity

        if shouldPresent {
            showTrackInfoTemporarily()
        }
    }

    private func showTrackInfoTemporarily() {
        trackInfoDismissWorkItem?.cancel()
        setPanelFrame(
            Self.windowFrame(
                for: Self.windowSize(for: metrics, usesOpenCanvas: false, showsTrackInfo: true),
                on: panel.screen ?? NSScreen.main
            )
        )
        withAnimation(.linear(duration: 0.22)) {
            overlayState.isTrackInfoPresented = true
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.linear(duration: 0.22)) {
                self.overlayState.isTrackInfoPresented = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                guard let self, !self.overlayState.isTrackInfoPresented, !self.overlayState.usesOpenCanvas else { return }
                self.setPanelFrame(
                    Self.windowFrame(
                        for: Self.windowSize(for: self.metrics, usesOpenCanvas: false, showsTrackInfo: false),
                        on: self.panel.screen ?? NSScreen.main
                    )
                )
            }
        }
        trackInfoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.trackInfoDismissDelay, execute: workItem)
    }

    private func position(on screen: NSScreen?) {
        setPanelFrame(Self.windowFrame(for: panel.frame.size, on: screen))
    }

    private func setPanelFrame(_ frame: NSRect?) {
        guard let frame else { return }
        panel.setFrame(frame, display: true)
    }

    private static func windowSize(
        for metrics: NotchMetrics,
        usesOpenCanvas: Bool,
        showsTrackInfo: Bool = false
    ) -> CGSize {
        guard !usesOpenCanvas else { return metrics.openCompletionFeedbackWindowSize }
        return CGSize(
            width: metrics.musicClosedShellWidth + Self.closedCanvasHorizontalSlack,
            height: (showsTrackInfo ? metrics.musicTrackInfoShellHeight : metrics.closedHeight) + Self.closedHoverBottomSlack
        )
    }

    private static func windowFrame(for size: CGSize, on screen: NSScreen?) -> NSRect? {
        guard let screen else { return nil }
        let screenFrame = screen.frame

        return NSRect(
            x: screenFrame.midX - (size.width / 2),
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
