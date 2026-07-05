import AppKit
import Combine
import SwiftUI
import DynamicIslandCore

@MainActor
final class IslandPanelController {
    private enum ActiveScrollGesture {
        case none
        case vertical
        case horizontal
    }

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
    private static let debugCalibrationEnvironmentKey = "ISLAND_DEBUG_CALIBRATION"
    private static let debugPrimaryFeatureFrameCaptureDirectoryEnvironmentKey = "ISLAND_DEBUG_PRIMARY_FEATURE_FRAME_CAPTURE_DIR"

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
    private var horizontalMusicSkipGesture = MusicSkipGestureStateMachine(
        commitDistance: IslandPanelController.horizontalCommitDistance,
        cancelDistance: IslandPanelController.horizontalCancelDistance
    )
    private var scrollGestureUsesExplicitPhase = false
    private var hasTriggeredHorizontalSkip = false
    private var scrollSuppressionUntil: Date?
    private let panel: NSPanel
    private let overlayState: IslandOverlayState
    private let hostingView: IslandTrackingHostingView
    private let animationProfile = IslandAnimationProfile.default
    private let runtimeSettings: IslandRuntimeSettings
    private let musicPlaybackDataSource: any MusicPlaybackDataSource
    private let temporaryFileShelfStore = TemporaryFileShelfStore()
    private let interactionLogger = IslandInteractionLogger()
    private var temporaryFileShelfSelection = TemporaryFileShelfSelection()
    private var musicPlaybackPollingTask: Task<Void, Never>?
    private var debugMusicSignalTask: Task<Void, Never>?
    private var musicSkipTask: Task<Void, Never>?
    private var temporaryFileShelfPruningTask: Task<Void, Never>?
    private var didStartDebugPrimaryFeatureFrameCapture = false
    nonisolated(unsafe) private var runtimeSettingsCancellable: AnyCancellable?
    nonisolated(unsafe) private var hiddenScrollMonitor: Any?

    init(
        screen: NSScreen? = NSScreen.main,
        runtimeSettings: IslandRuntimeSettings = IslandRuntimeSettings(),
        musicPlaybackDataSource: any MusicPlaybackDataSource = ScriptableMusicPlaybackDataSource()
    ) {
        self.runtimeSettings = runtimeSettings
        self.musicPlaybackDataSource = musicPlaybackDataSource
        runtimeSettings.isCalibrationModeEnabled = Self.shouldShowCalibrationOverlay
        let screenMetrics = ScreenMetricsProvider.metrics(for: screen)
        metrics = screenMetrics

        let overlayState = IslandOverlayState()
        overlayState.isCalibrationOverlayVisible = runtimeSettings.isCalibrationModeEnabled
        overlayState.calibrationHasCameraHousing = Self.hasCameraHousing(on: screen ?? NSScreen.main)
        overlayState.selectedPrimaryFeature = .tasks
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
        if Self.shouldStartExpandedForDebug, Self.debugPrimaryFeatureFrameCaptureDirectoryURL == nil {
            setExpanded(true)
        }
        var launchMetadata = Self.displayLogMetadata(for: screen ?? NSScreen.main, metrics: metrics)
        launchMetadata["launchMode"] = Self.debugMusicSignalFileURL == nil ? "musicPlaybackPolling" : "debugMusicSignal"
        launchMetadata["calibrationOverlay"] = Self.shouldShowCalibrationOverlay
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
        observeRuntimeSettings()
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

        metadata["hasCameraHousing"] = hasCameraHousing(on: screen)
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

    private static func hasCameraHousing(on screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        return screen.safeAreaInsets.top > 0
            && screen.auxiliaryTopLeftArea != nil
            && screen.auxiliaryTopRightArea != nil
    }

    deinit {
        musicPlaybackPollingTask?.cancel()
        debugMusicSignalTask?.cancel()
        musicSkipTask?.cancel()
        temporaryFileShelfPruningTask?.cancel()
        runtimeSettingsCancellable?.cancel()
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
        startDebugPrimaryFeatureFrameCaptureIfNeeded()
    }

    func hide() {
        panel.orderOut(nil)
        interactionLogger.log("panel.hide")
    }

    func refreshForCurrentScreen() {
        let screen = NSScreen.main
        let previousMetrics = metrics
        metrics = ScreenMetricsProvider.metrics(for: screen)
        overlayState.calibrationHasCameraHousing = Self.hasCameraHousing(on: screen)
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

    func resetDisplayAdaptation() {
        try? FileManager.default.removeItem(at: DisplayProfileStore.defaultProfileURL)
        try? FileManager.default.removeItem(at: DisplayProfileStore.legacyProfileURL)
        interactionLogger.log("display.adaptation.reset")
        refreshForCurrentScreen()
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

    private var hideAnimationDuration: TimeInterval {
        0.22 * runtimeSettings.hideAnimationScale
    }

    private func scaledGestureThreshold(_ value: CGFloat) -> CGFloat {
        value * CGFloat(runtimeSettings.gestureThresholdMultiplier)
    }

    private func observeRuntimeSettings() {
        let featureSettings = Publishers.CombineLatest3(
            runtimeSettings.$isFileShelfEnabled,
            runtimeSettings.$isMusicModeEnabled,
            runtimeSettings.$isCalibrationModeEnabled
        )
        let tuningSettings = Publishers.CombineLatest(
            runtimeSettings.$gestureSensitivity,
            runtimeSettings.$hideAnimationStrength
        )
        runtimeSettingsCancellable = Publishers.CombineLatest(featureSettings, tuningSettings)
        .dropFirst()
        .sink { [weak self] featureValues, tuningValues in
            let (fileShelfEnabled, musicModeEnabled, calibrationModeEnabled) = featureValues
            let (gestureSensitivity, hideAnimationStrength) = tuningValues
            Task { @MainActor in
                self?.runtimeSettingsDidChange(
                    fileShelfEnabled: fileShelfEnabled,
                    musicModeEnabled: musicModeEnabled,
                    calibrationModeEnabled: calibrationModeEnabled,
                    gestureSensitivity: gestureSensitivity,
                    hideAnimationStrength: hideAnimationStrength
                )
            }
        }
    }

    private func runtimeSettingsDidChange(
        fileShelfEnabled: Bool,
        musicModeEnabled: Bool,
        calibrationModeEnabled: Bool,
        gestureSensitivity: Double,
        hideAnimationStrength: Double
    ) {
        if !fileShelfEnabled {
            overlayState.isFileShelfOverlayVisible = false
            overlayState.isFileShelfPinnedOpen = false
            overlayState.isFileDropTargetActive = false
        }

        if !musicModeEnabled {
            musicPlaybackPollingTask?.cancel()
            musicPlaybackPollingTask = nil
            overlayState.musicPlayback = .idle
            overlayState.isTrackInfoPresented = false
            overlayState.musicSkipFeedbackDirection = nil
            overlayState.musicSkipGestureProgress = 0
            overlayState.isMusicSkipArmed = false
            resetScrollGesture(shouldCommitPendingSkip: false)
        } else if Self.debugMusicSignalFileURL == nil, musicPlaybackPollingTask == nil {
            startMusicPlaybackPolling()
        }

        overlayState.isCalibrationOverlayVisible = calibrationModeEnabled
        overlayState.calibrationHasCameraHousing = Self.hasCameraHousing(on: NSScreen.main)

        interactionLogger.log("settings.changed", metadata: [
            "fileShelfEnabled": fileShelfEnabled,
            "musicModeEnabled": musicModeEnabled,
            "calibrationModeEnabled": calibrationModeEnabled,
            "gestureSensitivity": gestureSensitivity,
            "hideAnimationStrength": hideAnimationStrength,
            "selectedPrimaryFeature": overlayState.selectedPrimaryFeature.rawValue
        ])
    }

    private func updateRootView() {
        var actions = FileShelfActions()
        actions.onSelectItem = { [weak self] itemID, extendingSelection in
            self?.selectTemporaryFile(id: itemID, extendingSelection: extendingSelection)
        }
        actions.onSelectItems = { [weak self] itemIDs, extendingSelection in
            self?.selectTemporaryFiles(ids: itemIDs, extendingSelection: extendingSelection)
        }
        actions.onRemoveItem = { [weak self] itemID in
            self?.removeTemporaryFile(id: itemID)
        }
        actions.onClearItems = { [weak self] in
            self?.clearTemporaryFiles()
        }
        actions.onDragStarted = { [weak self] itemIDs in
            self?.startTemporaryFileDrag(ids: itemIDs)
        }
        actions.onDragCompleted = { [weak self] itemIDs, succeeded in
            self?.completeTemporaryFileDrag(ids: itemIDs, succeeded: succeeded)
        }
        actions.onFilterChange = { [weak self] filter in
            self?.setTemporaryFileShelfFilter(filter)
        }
        actions.onClearSelection = { [weak self] in
            self?.clearTemporaryFileSelection()
        }
        actions.onToggleOverlay = { [weak self] in
            self?.toggleTemporaryFileShelfOverlayFromButton()
        }
        actions.onDoneOverlay = { [weak self] in
            self?.closeTemporaryFileShelfOverlay()
        }

        hostingView.rootView = IslandOverlayView(
            metrics: metrics,
            state: overlayState,
            onExpansionChange: { [weak self] expanded in
                self?.setExpanded(expanded)
            },
            fileShelfActions: actions
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
            self.interactionLogger.log("hover.entered", metadata: [
                "isExpanded": self.isExpanded,
                "musicPlaying": self.overlayState.musicPlayback.isPlaying
            ])
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
            self.interactionLogger.log("hover.exited", metadata: [
                "isExpanded": self.isExpanded,
                "fileShelfPinned": self.overlayState.isFileShelfPinnedOpen
            ])
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
        guard runtimeSettings.isFileShelfEnabled else { return false }
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

    private func selectTemporaryFiles(ids: [TemporaryShelfItem.ID], extendingSelection: Bool) {
        let itemIDs = Set(ids)
        if extendingSelection {
            temporaryFileShelfSelection.select(temporaryFileShelfSelection.selectedItemIDs.union(itemIDs))
        } else {
            temporaryFileShelfSelection.select(itemIDs)
        }
        syncTemporaryFileShelfSelectionState()
        interactionLogger.log("file.shelf.select", metadata: [
            "selectedCount": temporaryFileShelfSelection.selectedItemIDs.count,
            "extendingSelection": extendingSelection,
            "rectangleSelection": true
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
        guard runtimeSettings.isFileShelfEnabled else { return }
        temporaryFileShelfStore.pruneExpired()
        syncTemporaryFileShelfState()
        guard temporaryFileShelfStore.shelf.hasItems else { return }
        if !isExpanded {
            setExpanded(true)
        }
        overlayState.isFileShelfOverlayVisible = true
        overlayState.isFileShelfPinnedOpen = pinned
        interactionLogger.log("file.shelf.opened", metadata: [
            "pinned": pinned,
            "itemCount": temporaryFileShelfStore.shelf.items.count
        ])
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
        guard runtimeSettings.isFileShelfEnabled else { return }
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
        let nextValue = targeted && runtimeSettings.isFileShelfEnabled && !overlayState.isShellHidden
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
            let activationThreshold = scaledGestureThreshold(Self.scrollActivationThreshold)
            if deltaY > activationThreshold {
                setShellHidden(false)
            } else if accumulatedScrollDeltaY > activationThreshold {
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
        let axisLockThreshold = scaledGestureThreshold(Self.gestureAxisLockThreshold)

        if canHandleHorizontalMusicSkip, horizontalDominant, abs(accumulatedScrollDeltaX) >= axisLockThreshold {
            activeScrollGesture = .horizontal
            interactionLogger.log("scroll.gesture.locked", metadata: [
                "axis": "horizontal",
                "deltaX": Double(accumulatedScrollDeltaX),
                "deltaY": Double(accumulatedScrollDeltaY),
                "phase": Self.scrollPhaseDescription(phase),
                "usesExplicitPhase": scrollGestureUsesExplicitPhase
            ])
            updateHorizontalMusicSkip()
        } else if canHandleVerticalHideShow, verticalDominant, abs(accumulatedScrollDeltaY) >= axisLockThreshold {
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
        runtimeSettings.isMusicModeEnabled
            && overlayState.musicPlayback.isPlaying
            && !isExpanded
            && !overlayState.isShellHidden
            && !overlayState.isTrackInfoPresented
    }

    private var canHandleVerticalHideShow: Bool {
        !isExpanded
            && !overlayState.isShellHidden
    }

    private func updateVerticalScrollIntent() {
        guard canHandleVerticalHideShow else {
            resetScrollGesture(shouldCommitPendingSkip: false)
            return
        }

        let activationThreshold = scaledGestureThreshold(Self.scrollActivationThreshold)
        if accumulatedScrollDeltaY < -activationThreshold {
            setShellHidden(true)
            resetScrollGesture()
        } else if accumulatedScrollDeltaY > activationThreshold {
            setShellHidden(false)
        }
    }

    private func updateHorizontalMusicSkip() {
        guard canHandleHorizontalMusicSkip else {
            resetScrollGesture()
            return
        }

        syncHorizontalMusicSkipGestureSettings()
        let previousState = horizontalMusicSkipGesture.state
        let nextState = horizontalMusicSkipGesture.update(accumulatedDeltaX: accumulatedScrollDeltaX)
        applyHorizontalMusicSkipGestureState(nextState, previousState: previousState)
    }

    private func syncHorizontalMusicSkipGestureSettings() {
        let commitDistance = scaledGestureThreshold(Self.horizontalCommitDistance)
        let cancelDistance = scaledGestureThreshold(Self.horizontalCancelDistance)
        guard horizontalMusicSkipGesture.commitDistance != commitDistance
            || horizontalMusicSkipGesture.cancelDistance != cancelDistance
        else {
            return
        }
        horizontalMusicSkipGesture = MusicSkipGestureStateMachine(
            commitDistance: commitDistance,
            cancelDistance: cancelDistance
        )
    }

    private func applyHorizontalMusicSkipGestureState(
        _ state: MusicSkipGestureState,
        previousState: MusicSkipGestureState
    ) {
        switch state {
        case .idle:
            break
        case .tracking(let direction, let progress):
            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.82)) {
                overlayState.musicSkipFeedbackDirection = direction
                overlayState.musicSkipGestureProgress = progress
                overlayState.isMusicSkipArmed = false
            }
        case .armed(let direction, let progress):
            if !Self.isArmedMusicSkipState(previousState) {
                interactionLogger.log("music.skip.armed", metadata: [
                    "direction": Self.musicSkipDirectionDescription(direction),
                    "deltaX": Double(accumulatedScrollDeltaX)
                ])
            }
            withAnimation(.easeOut(duration: 0.10)) {
                overlayState.musicSkipFeedbackDirection = direction
                overlayState.musicSkipGestureProgress = progress
                overlayState.isMusicSkipArmed = true
            }
        case .cancelled(let direction):
            if Self.isArmedMusicSkipState(previousState) {
                logHorizontalMusicSkipCancelled(direction: direction, reason: "returnedToCancelBoundary")
            }
            withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.82)) {
                overlayState.musicSkipGestureProgress = 0
                overlayState.musicSkipFeedbackDirection = nil
                overlayState.isMusicSkipArmed = false
            }
        case .committed:
            break
        }
    }

    private func logHorizontalMusicSkipCancelled(direction: MusicSkipDirection?, reason: String) {
        guard let direction else { return }
        interactionLogger.log("music.skip.cancelled", metadata: [
            "reason": reason,
            "direction": Self.musicSkipDirectionDescription(direction),
            "deltaX": Double(accumulatedScrollDeltaX)
        ])
    }

    private func commitPendingHorizontalMusicSkipIfNeeded(shouldCommitPendingSkip: Bool) -> Bool {
        guard
            activeScrollGesture == .horizontal,
            !hasTriggeredHorizontalSkip
        else {
            return false
        }

        let directionBeforeFinish = horizontalMusicSkipGesture.currentDirection()
        if horizontalMusicSkipGesture.isArmed, !shouldCommitPendingSkip {
            logHorizontalMusicSkipCancelled(direction: directionBeforeFinish, reason: "gestureCancelled")
        }

        let now = Date()
        if horizontalMusicSkipGesture.isArmed,
           shouldCommitPendingSkip,
           let lastMusicSkipDate,
           now.timeIntervalSince(lastMusicSkipDate) < Self.musicSkipCooldown {
            logHorizontalMusicSkipCancelled(direction: directionBeforeFinish, reason: "cooldown")
            _ = horizontalMusicSkipGesture.finish(shouldCommit: false)
            return false
        }

        let finalState = horizontalMusicSkipGesture.finish(shouldCommit: shouldCommitPendingSkip)
        guard case .committed(let direction) = finalState else {
            return false
        }

        hasTriggeredHorizontalSkip = true
        lastMusicSkipDate = now
        overlayState.isMusicSkipArmed = false
        interactionLogger.log("music.skip.commit", metadata: [
            "direction": Self.musicSkipDirectionDescription(direction),
            "deltaX": Double(accumulatedScrollDeltaX)
        ])
        performMusicSkip(direction)
        return true
    }

    private static func musicSkipDirectionDescription(_ direction: MusicSkipDirection) -> String {
        switch direction {
        case .previous:
            return "previous"
        case .next:
            return "next"
        }
    }

    private static func isArmedMusicSkipState(_ state: MusicSkipGestureState) -> Bool {
        if case .armed = state { return true }
        return false
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
        resetScrollGesture(shouldCommitPendingSkip: shouldCommitPendingSkip)
    }

    private func prepareForNewScrollGesture() {
        gestureResetWorkItem?.cancel()
        gestureResetWorkItem = nil
        activeScrollGesture = .none
        accumulatedScrollDeltaX = 0
        accumulatedScrollDeltaY = 0
        horizontalMusicSkipGesture.reset()
        scrollGestureUsesExplicitPhase = false
        overlayState.isMusicSkipArmed = false
        hasTriggeredHorizontalSkip = false
    }

    private func resetScrollGesture(shouldCommitPendingSkip: Bool = true) {
        gestureResetWorkItem?.cancel()
        gestureResetWorkItem = nil
        let didCommitPendingSkip = commitPendingHorizontalMusicSkipIfNeeded(shouldCommitPendingSkip: shouldCommitPendingSkip)
        let shouldDismissFeedback = activeScrollGesture == .horizontal && !didCommitPendingSkip
        activeScrollGesture = .none
        accumulatedScrollDeltaX = 0
        accumulatedScrollDeltaY = 0
        horizontalMusicSkipGesture.reset()
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
        let animationDuration = hideAnimationDuration
        withAnimation(.easeInOut(duration: animationDuration)) {
            overlayState.isShellHidden = hidden
        }
        if hidden {
            installHiddenScrollMonitor()
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
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
        return NotchMetrics.musicSkipEdgeExpansionMax * min(max(overlayState.musicSkipGestureProgress, 0), 1)
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

    private static var shouldShowCalibrationOverlay: Bool {
        let value = ProcessInfo.processInfo.environment[debugCalibrationEnvironmentKey] ?? ""
        return ["1", "true", "yes"].contains(value.lowercased())
    }

    private static var debugPrimaryFeatureFrameCaptureDirectoryURL: URL? {
        guard
            let path = ProcessInfo.processInfo.environment[debugPrimaryFeatureFrameCaptureDirectoryEnvironmentKey],
            !path.isEmpty
        else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
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

    private func startDebugPrimaryFeatureFrameCaptureIfNeeded() {
        guard !didStartDebugPrimaryFeatureFrameCapture else { return }
        guard let directoryURL = Self.debugPrimaryFeatureFrameCaptureDirectoryURL else { return }
        didStartDebugPrimaryFeatureFrameCapture = true

        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        captureDebugPrimaryFeatureFrame(directoryURL: directoryURL, index: 0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.setExpanded(true)
        }

        for index in 1...24 {
            let delay = 0.05 + (Double(index) * 0.035)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.captureDebugPrimaryFeatureFrame(directoryURL: directoryURL, index: index)
            }
        }
    }

    private func captureDebugPrimaryFeatureFrame(directoryURL: URL, index: Int) {
        let bounds = hostingView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        bitmap.size = bounds.size
        hostingView.cacheDisplay(in: bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        let fileName = String(format: "frame-%03d.png", index)
        try? data.write(to: directoryURL.appendingPathComponent(fileName))
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
        interactionLogger.log("track.info.shown", metadata: [
            "title": overlayState.musicPlayback.title,
            "artist": overlayState.musicPlayback.artist
        ])

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.linear(duration: 0.22)) {
                self.overlayState.isTrackInfoPresented = false
            }
            self.interactionLogger.log("track.info.dismissed")
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
        guard !usesOpenCanvas else { return metrics.openCanvasWindowSize }
        return CGSize(
            width: metrics.musicClosedShellWidth + NotchMetrics.closedCanvasHorizontalSlack,
            height: (showsTrackInfo ? metrics.musicTrackInfoShellHeight : metrics.closedHeight) + NotchMetrics.closedHoverBottomSlack
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
