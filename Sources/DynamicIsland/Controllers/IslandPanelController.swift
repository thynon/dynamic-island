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
    private static let codexReasoningFallbackRefreshInterval: TimeInterval = 2
    private static let codexStatusBackgroundRefreshInterval: TimeInterval = 1

    private var metrics: NotchMetrics
    private var isExpanded = false
    private var collapseWorkItem: DispatchWorkItem?
    nonisolated(unsafe) private var tasksCanvasResizeWorkItem: DispatchWorkItem?
    nonisolated(unsafe) private var approvalAttachmentResizeWorkItem: DispatchWorkItem?
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
    private let usageSnapshotLoader: any UsageSnapshotLoading
    private let temporaryFileShelfStore = TemporaryFileShelfStore()
    private let interactionLogger = IslandInteractionLogger()
    private let codexTaskDismissalStore = CodexTaskDismissalStore()
    private let codexApprovalCoordinator: CodexApprovalCoordinator?
    private var codexApprovalApplicationOpenState = CodexApprovalApplicationOpenState()
    private var loggedCodexApprovalPresentedRequestIDs: Set<CodexApprovalRequest.ID> = []
    private var temporaryFileShelfSelection = TemporaryFileShelfSelection()
    private var lastNonFilesPrimaryFeature: IslandPrimaryFeature = .tasks
    private var lastObservedPassiveApprovalKeys: Set<String> = []
    private var musicPlaybackPollingTask: Task<Void, Never>?
    private var debugMusicSignalTask: Task<Void, Never>?
    private var codexReasoningEffortPollingTask: Task<Void, Never>?
    private var codexStatusPollingTask: Task<Void, Never>?
    private var dataUsageRefreshTask: Task<Void, Never>?
    private var dataUsageRefreshGeneration = 0
    private var musicSkipTask: Task<Void, Never>?
    private var temporaryFileShelfPruningTask: Task<Void, Never>?
    private var didStartDebugPrimaryFeatureFrameCapture = false
    private var activeAirDropSharingDelegates: [UUID: AirDropSharingDelegate] = [:]
    private var pendingAirDropItemIDs: Set<TemporaryShelfItem.ID> = []
    private var airDropUndoFileURLs: [URL] = []
    private var airDropUndoClearWorkItem: DispatchWorkItem?
    nonisolated(unsafe) private var runtimeSettingsCancellable: AnyCancellable?
    nonisolated(unsafe) private var pointerPassthroughMonitor: Any?
    private var pointerPassthroughSyncSource: DispatchSourceUserDataAdd?
    nonisolated(unsafe) private var hiddenScrollMonitor: Any?

    init(
        screen: NSScreen? = NSScreen.main,
        runtimeSettings: IslandRuntimeSettings = IslandRuntimeSettings(),
        musicPlaybackDataSource: any MusicPlaybackDataSource = ScriptableMusicPlaybackDataSource(),
        usageSnapshotLoader: any UsageSnapshotLoading = UsageAggregationService.live(),
        codexApprovalCoordinator: CodexApprovalCoordinator? = nil
    ) {
        self.runtimeSettings = runtimeSettings
        self.musicPlaybackDataSource = musicPlaybackDataSource
        self.usageSnapshotLoader = usageSnapshotLoader
        self.codexApprovalCoordinator = codexApprovalCoordinator
        runtimeSettings.isCalibrationModeEnabled = Self.shouldShowCalibrationOverlay
        let screenMetrics = ScreenMetricsProvider.metrics(for: screen)
        metrics = screenMetrics

        let overlayState = IslandOverlayState()
        overlayState.isCalibrationOverlayVisible = runtimeSettings.isCalibrationModeEnabled
        overlayState.calibrationHasCameraHousing = Self.hasCameraHousing(on: screen ?? NSScreen.main)
        overlayState.selectedPrimaryFeature = .tasks
        overlayState.dismissedCodexTaskKeys = codexTaskDismissalStore.activeKeys()
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
        codexApprovalCoordinator?.onPresentationChange = { [weak self] presentation in
            self?.updateManagedCodexApprovalPresentation(presentation)
        }
        codexApprovalCoordinator?.onAuditEvent = { [weak self] event in
            self?.logCodexApprovalAuditEvent(event)
        }
        codexApprovalCoordinator?.onNewRequest = { [weak self] request in
            self?.handleManagedCodexApprovalRequest(request)
        }
        if let codexApprovalCoordinator {
            updateManagedCodexApprovalPresentation(codexApprovalCoordinator.presentation)
        }

        TopBandEnergyEffectResources.prewarm()
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
        startCodexReasoningEffortPolling()
        startCodexStatusPolling()
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
        codexReasoningEffortPollingTask?.cancel()
        codexStatusPollingTask?.cancel()
        dataUsageRefreshTask?.cancel()
        musicSkipTask?.cancel()
        temporaryFileShelfPruningTask?.cancel()
        runtimeSettingsCancellable?.cancel()
        trackInfoDismissWorkItem?.cancel()
        musicSkipFeedbackWorkItem?.cancel()
        gestureResetWorkItem?.cancel()
        tasksCanvasResizeWorkItem?.cancel()
        approvalAttachmentResizeWorkItem?.cancel()
        if let pointerPassthroughMonitor {
            NSEvent.removeMonitor(pointerPassthroughMonitor)
        }
        pointerPassthroughSyncSource?.cancel()
        if let hiddenScrollMonitor {
            NSEvent.removeMonitor(hiddenScrollMonitor)
        }
    }

    func show() {
        refreshForCurrentScreen()
        panel.orderFrontRegardless()
        syncHoverWithPointer()
        interactionLogger.log("panel.show")
        startDebugPrimaryFeatureFrameCaptureIfNeeded()
    }

    func hide() {
        removePointerPassthroughMonitor()
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
        if overlayState.usesOpenCanvas {
            setPanelFrame(
                expandedPanelFrame(
                    shellHeight: expandedTasksShellHeight,
                    on: screen
                )
            )
        } else {
            setPanelFrame(
                Self.windowFrame(
                for: Self.windowSize(
                    for: metrics,
                    usesOpenCanvas: false,
                    showsTrackInfo: overlayState.isTrackInfoPresented
                ),
                on: screen
            )
            )
        }
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
                expandedPanelFrame(
                    shellHeight: expandedTasksShellHeight,
                    on: panel.screen ?? NSScreen.main
                )
            )

            DispatchQueue.main.async { [weak self] in
                guard let self, self.isExpanded else { return }
                withAnimation(self.expandAnimation) {
                    self.overlayState.isExpanded = true
                }
            }
            presentCodexApprovalAttachmentIfNeeded()
        } else {
            dismissCodexApprovalAttachment(shrinkPanel: false)
            setCodexTasksDetailExpansionHeight(0)
            tasksCanvasResizeWorkItem?.cancel()
            tasksCanvasResizeWorkItem = nil
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
            let canvasDelay = prefersReducedMotion
                ? animationProfile.reducedMotionFadeDuration
                : animationProfile.collapseCanvasDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + canvasDelay, execute: workItem)
        }
    }

    private var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var expandAnimation: Animation? {
        prefersReducedMotion ? nil : .interactiveSpring(
            response: animationProfile.expandResponse,
            dampingFraction: animationProfile.expandDampingFraction,
            blendDuration: animationProfile.expandBlendDuration
        )
    }

    private var collapseAnimation: Animation? {
        prefersReducedMotion ? nil : .easeOut(duration: animationProfile.collapseDuration)
    }

    private var tasksHeightAnimation: Animation? {
        prefersReducedMotion ? nil : .spring(
            response: animationProfile.primaryFeatureSelectionResponse,
            dampingFraction: animationProfile.primaryFeatureSelectionDamping,
            blendDuration: 0
        )
    }

    private var approvalAttachmentPresentationAnimation: Animation? {
        prefersReducedMotion
            ? .easeOut(duration: animationProfile.reducedMotionFadeDuration)
            : .spring(
                response: animationProfile.primaryFeatureSelectionResponse,
                dampingFraction: animationProfile.primaryFeatureSelectionDamping,
                blendDuration: 0
            )
    }

    private var approvalAttachmentDismissAnimation: Animation? {
        .easeOut(
            duration: prefersReducedMotion
                ? animationProfile.reducedMotionFadeDuration
                : animationProfile.attachedElementCollapseDuration
        )
    }

    private var expandedTasksShellHeight: CGFloat {
        metrics.openHeight + overlayState.codexTasksDetailExpansionHeight
    }

    private var currentApprovalAdditionalRightWidth: CGFloat {
        guard overlayState.isCodexApprovalAttachmentPresented else { return 0 }
        return CodexTasksApprovalLayout(
            metrics: metrics,
            shellHeight: expandedTasksShellHeight
        ).additionalCanvasWidth
    }

    private func expandedPanelFrame(
        shellHeight: CGFloat,
        additionalRightWidth: CGFloat? = nil,
        on screen: NSScreen?
    ) -> NSRect? {
        Self.expandedWindowFrame(
            metrics: metrics,
            shellHeight: shellHeight,
            additionalRightWidth: additionalRightWidth ?? currentApprovalAdditionalRightWidth,
            on: screen
        )
    }

    private func setCodexTasksDetailExpansionHeight(_ requestedHeight: CGFloat) {
        let maximumHeight = CodexTasksAdaptiveLayout.maximumExtraHeight
        let clampedHeight = min(max(0, requestedHeight), maximumHeight)
        let targetHeight = isExpanded && overlayState.selectedPrimaryFeature == .tasks
            ? clampedHeight
            : 0
        let currentHeight = overlayState.codexTasksDetailExpansionHeight
        guard currentHeight != targetHeight else { return }

        tasksCanvasResizeWorkItem?.cancel()
        tasksCanvasResizeWorkItem = nil
        let targetShellHeight = metrics.openHeight + targetHeight

        if targetHeight > currentHeight {
            setPanelFrame(
                expandedPanelFrame(
                    shellHeight: targetShellHeight,
                    on: panel.screen ?? NSScreen.main
                )
            )
        }

        withAnimation(tasksHeightAnimation) {
            overlayState.codexTasksDetailExpansionHeight = targetHeight
        }

        guard targetHeight < currentHeight else { return }
        let resize = { [weak self] in
            guard let self,
                  self.isExpanded,
                  self.overlayState.codexTasksDetailExpansionHeight == targetHeight
            else { return }
            self.setPanelFrame(
                self.expandedPanelFrame(
                    shellHeight: targetShellHeight,
                    on: self.panel.screen ?? NSScreen.main
                )
            )
        }

        if prefersReducedMotion {
            resize()
        } else {
            let workItem = DispatchWorkItem(block: resize)
            tasksCanvasResizeWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + animationProfile.primaryFeatureSelectionResponse,
                execute: workItem
            )
        }
    }

    private var hideAnimationDuration: TimeInterval {
        if prefersReducedMotion {
            return animationProfile.reducedMotionFadeDuration
        }
        return animationProfile.hideTransitionDuration * runtimeSettings.hideAnimationScale
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
        actions.onRemoveItems = { [weak self] itemIDs in
            self?.removeTemporaryFiles(ids: itemIDs)
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
        actions.onAirDropItems = { [weak self] itemIDs in
            self?.airDropTemporaryFiles(ids: itemIDs)
        }
        actions.onUndoAirDropItems = { [weak self] in
            self?.undoAirDropRemoval()
        }
        actions.onOpenFilesPrimaryFeature = { [weak self] in
            self?.openFilesPrimaryFeature()
        }
        actions.onSetFilesDisplayMode = { [weak self] mode in
            self?.setFilesDisplayMode(mode)
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
            onPrimaryFeatureChange: { [weak self] feature in
                self?.selectPrimaryFeature(feature)
            },
            onDataUsageTimeRangeChange: { [weak self] range in
                self?.selectDataUsageTimeRange(range)
            },
            onRefreshDataUsage: { [weak self] in
                self?.refreshDataUsage()
            },
            onDismissCodexTask: { [weak self] task in
                self?.dismissCodexTask(task)
            },
            onUndoCodexTask: { [weak self] task in
                self?.restoreCodexTask(task)
            },
            onCodexTaskSelection: { [weak self] threadID in
                self?.selectCodexTask(threadID)
            },
            onTasksExpansionHeightChange: { [weak self] height in
                self?.setCodexTasksDetailExpansionHeight(height)
            },
            onApprovalDecision: { [weak self] decision, requestID in
                self?.submitCodexApproval(decision, for: requestID)
            },
            onOpenCodexApproval: { [weak self] requestID in
                self?.openCodexApproval(requestID)
            },
            onRetryCodexApproval: { [weak self] in
                { requestID in
                    self?.openCodexApproval(requestID)
                }
            }(),
            fileShelfActions: actions
        )
    }

    private func selectCodexTask(_ threadID: String) {
        overlayState.selectedCodexTaskID = threadID
        if let codexApprovalCoordinator,
           codexApprovalCoordinator.selectRequest(threadID: threadID) {
            return
        }
        updatePassiveCodexApprovalPresentation(overlayState.codexStatusBarSnapshot)
        if overlayState.codexApprovalPresentation.request?.threadID == threadID {
            presentCodexApprovalAttachmentIfNeeded()
        } else {
            dismissCodexApprovalAttachment()
        }
    }

    private func logCodexApprovalAuditEvent(_ event: CodexApprovalAuditEvent) {
        switch event {
        case .detected(let kind, let source, let pendingCount, let threadIDLength):
            let sourceValue = source == .managedAppServer
                ? "managedAppServer"
                : "passiveObservation"
            interactionLogger.log("codex.approval.detected", metadata: [
                "kind": kind.rawValue,
                "source": sourceValue,
                "pendingCount": pendingCount,
                "threadIDLength": threadIDLength
            ])
        case .presented(let kind, let inlineCapable):
            interactionLogger.log("codex.approval.presented", metadata: [
                "kind": kind.rawValue,
                "inlineCapable": inlineCapable
            ])
        case .decisionSent(let decision, let kind):
            interactionLogger.log("codex.approval.decision.sent", metadata: [
                "decision": decision.rawValue,
                "kind": kind.rawValue
            ])
        case .resolved(let kind, let latencyMilliseconds):
            interactionLogger.log("codex.approval.resolved", metadata: [
                "kind": kind.rawValue,
                "latencyMilliseconds": latencyMilliseconds
            ])
        case .failed(let kind, let errorCategory):
            interactionLogger.log("codex.approval.failed", metadata: [
                "kind": kind.rawValue,
                "errorCategory": errorCategory.rawValue
            ])
        }
    }

    private func submitCodexApproval(
        _ decision: CodexApprovalDecision,
        for requestID: CodexApprovalRequest.ID
    ) {
        guard let codexApprovalCoordinator else {
            openCodexApproval(requestID)
            return
        }
        Task { [weak self] in
            do {
                try await codexApprovalCoordinator.submit(decision, for: requestID)
            } catch CodexApprovalCoordinatorError.capabilityUnavailable {
                self?.openCodexApproval(requestID)
            } catch {
                // The coordinator publishes a sanitized failure state.
            }
        }
    }

    private func openCodexApproval(_ requestID: CodexApprovalRequest.ID) {
        guard overlayState.codexApprovalPresentation.request?.id == requestID else { return }
        var applicationOpenState: CodexApprovalApplicationOpenState = codexApprovalApplicationOpenState
        let attempt = applicationOpenState.begin(requestID: requestID)
        codexApprovalApplicationOpenState = applicationOpenState
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.openai.codex"
        ) else {
            completeCodexApprovalApplicationOpenAttempt(
                attempt,
                requestID: requestID,
                succeeded: false
            )
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration,
            completionHandler: { [weak self] application, error in
                Task { @MainActor in
                    self?.completeCodexApprovalApplicationOpenAttempt(
                        attempt,
                        requestID: requestID,
                        succeeded: application != nil && error == nil
                    )
                }
            }
        )
    }

    private func completeCodexApprovalApplicationOpenAttempt(
        _ attempt: CodexApprovalApplicationOpenAttempt,
        requestID: CodexApprovalRequest.ID,
        succeeded: Bool
    ) {
        let completion = codexApprovalApplicationOpenState.complete(
            attempt,
            currentRequestID: overlayState.codexApprovalPresentation.request?.id,
            succeeded: succeeded
        )
        switch completion {
        case .ignored:
            return
        case .succeeded:
            refreshCodexApprovalPresentation(for: requestID)
        case .failed:
            publishCodexOpenFailure(for: requestID)
        }
    }

    private func refreshCodexApprovalPresentation(
        for requestID: CodexApprovalRequest.ID
    ) {
        guard overlayState.codexApprovalPresentation.request?.id == requestID else { return }
        if codexApprovalApplicationOpenState.hasFailure(for: requestID) {
            publishCodexOpenFailure(for: requestID)
            return
        }
        if let presentation = codexApprovalCoordinator?.presentation,
           presentation.request?.id == requestID {
            updateManagedCodexApprovalPresentation(presentation)
        } else {
            updatePassiveCodexApprovalPresentation(overlayState.codexStatusBarSnapshot)
        }
    }

    private func publishCodexOpenFailure(for requestID: CodexApprovalRequest.ID) {
        let current = overlayState.codexApprovalPresentation
        guard let request = current.request, request.id == requestID else { return }
        overlayState.codexApprovalPresentation = CodexApprovalPresentation(
            request: request,
            pendingCount: current.pendingCount,
            submissionState: .failed("无法打开 Codex"),
            pendingThreadIDs: current.pendingThreadIDs
        )
        logCodexApprovalAuditEvent(.failed(
            kind: request.kind,
            errorCategory: .applicationUnavailable
        ))
    }

    private func updateManagedCodexApprovalPresentation(
        _ presentation: CodexApprovalPresentation
    ) {
        if let request = presentation.request,
           let selectedCodexTaskID = overlayState.selectedCodexTaskID,
           request.threadID != selectedCodexTaskID {
            updatePassiveCodexApprovalPresentation(overlayState.codexStatusBarSnapshot)
            return
        }

        let requestID = presentation.request?.id
        codexApprovalApplicationOpenState.requestDidChange(to: requestID)
        if let requestID,
           codexApprovalApplicationOpenState.hasFailure(for: requestID) {
            overlayState.codexApprovalPresentation = CodexApprovalPresentation(
                request: presentation.request,
                pendingCount: presentation.pendingCount,
                submissionState: .failed("无法打开 Codex"),
                pendingThreadIDs: presentation.pendingThreadIDs
            )
        } else {
            overlayState.codexApprovalPresentation = presentation
        }

        guard let request = overlayState.codexApprovalPresentation.request,
              request.threadID == overlayState.selectedCodexTaskID
        else {
            dismissCodexApprovalAttachment()
            return
        }
        presentCodexApprovalAttachmentIfNeeded()
    }

    private func dismissCodexTask(_ task: CodexTaskStatus) {
        guard !task.activityState.isWorking, task.approvalState == .none else { return }
        codexTaskDismissalStore.dismiss(task.dismissalKey)
        overlayState.dismissedCodexTaskKeys = codexTaskDismissalStore.activeKeys()
        interactionLogger.log("codex.task.dismissed", metadata: [
            "threadIDLength": task.id.count,
            "titleLength": task.title.count,
            "turnIDLength": task.turnID?.count ?? 0,
            "activity": task.activityState.rawValue
        ])
    }

    private func handleManagedCodexApprovalRequest(_ request: CodexApprovalRequest) {
        let action = CodexApprovalAutoPresentationPolicy.action(
            isShellHidden: overlayState.isShellHidden,
            isFilesPinned: overlayState.selectedPrimaryFeature == .files
                && overlayState.isFileShelfPinnedOpen,
            isExpanded: isExpanded
        )
        guard action != .ignore else { return }
        overlayState.selectedCodexTaskID = request.threadID
        guard codexApprovalCoordinator?.selectRequest(threadID: request.threadID) == true else {
            return
        }
        guard action != .selectTaskOnly else {
            return
        }
        selectPrimaryFeature(.tasks)
        if action == .selectTasksAndExpand {
            setExpanded(true)
        }
        presentCodexApprovalAttachmentIfNeeded()
    }

    private func restoreCodexTask(_ task: CodexTaskStatus) {
        codexTaskDismissalStore.restore(task.dismissalKey)
        overlayState.dismissedCodexTaskKeys = codexTaskDismissalStore.activeKeys()
        interactionLogger.log("codex.task.dismissed.undo", metadata: [
            "threadIDLength": task.id.count,
            "titleLength": task.title.count,
            "turnIDLength": task.turnID?.count ?? 0
        ])
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
            self.syncHoverWithPointer()
            self.interactionLogger.log("hover.exited", metadata: [
                "isExpanded": self.isExpanded,
                "fileShelfPinned": self.overlayState.isFileShelfPinnedOpen,
                "filesDisplayMode": self.overlayState.filesDisplayMode.rawValue
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
        overlayState.isFileShelfOverlayVisible = false
        syncFilesPinnedOpenState()
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
        let currentSelectedItemIDs = temporaryFileShelfSelection.selectedItemIDs
        let nextSelectedItemIDs = extendingSelection
            ? currentSelectedItemIDs.union(itemIDs)
            : itemIDs
        guard nextSelectedItemIDs != currentSelectedItemIDs else { return }

        temporaryFileShelfSelection.select(nextSelectedItemIDs)
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
            let externalItemIDs = itemIDs.subtracting(pendingAirDropItemIDs)
            if !externalItemIDs.isEmpty {
                removeTemporaryFiles(ids: externalItemIDs)
            }
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

    private func removeTemporaryFiles(ids itemIDs: [TemporaryShelfItem.ID]) {
        let itemIDSet = Set(itemIDs)
        guard !itemIDSet.isEmpty else { return }
        let removedFileURLs = temporaryFileShelfStore.shelf.items
            .filter { itemIDSet.contains($0.id) }
            .map(\.fileURL)
        temporaryFileShelfStore.removeItems(ids: itemIDSet)
        syncTemporaryFileShelfState()
        interactionLogger.log("file.shelf.removeMany", metadata: [
            "count": itemIDSet.count,
            "remainingCount": temporaryFileShelfStore.shelf.items.count,
            "files": IslandInteractionLogger.sanitizedFileMetadata(for: removedFileURLs)
        ])
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

    private func openFilesPrimaryFeature() {
        guard runtimeSettings.isFileShelfEnabled else { return }
        temporaryFileShelfStore.pruneExpired()
        syncTemporaryFileShelfState()

        if overlayState.selectedPrimaryFeature == .files {
            closeFilesPrimaryFeature()
            return
        }

        lastNonFilesPrimaryFeature = overlayState.selectedPrimaryFeature
        if !isExpanded {
            setExpanded(true)
        }
        dismissCodexApprovalAttachment()
        setCodexTasksDetailExpansionHeight(0)
        overlayState.selectedPrimaryFeature = .files
        overlayState.isFileShelfOverlayVisible = false
        syncFilesPinnedOpenState()
        overlayState.isFileDropTargetActive = false
        interactionLogger.log("file.files.opened", metadata: [
            "itemCount": temporaryFileShelfStore.shelf.items.count,
            "displayMode": overlayState.filesDisplayMode.rawValue,
            "pinned": overlayState.isFileShelfPinnedOpen
        ])
    }

    private func selectPrimaryFeature(_ feature: IslandPrimaryFeature) {
        guard feature != .files else {
            openFilesPrimaryFeature()
            return
        }
        guard overlayState.selectedPrimaryFeature != feature else { return }

        if overlayState.selectedPrimaryFeature == .files {
            closeFilesPrimaryFeature()
        }
        if feature != .tasks {
            setCodexTasksDetailExpansionHeight(0)
        }
        lastNonFilesPrimaryFeature = feature
        overlayState.selectedPrimaryFeature = feature
        if feature == .tasks {
            presentCodexApprovalAttachmentIfNeeded()
        } else {
            dismissCodexApprovalAttachment()
        }
        if feature == .data, case .idle = overlayState.dataUsagePresentation {
            refreshDataUsage()
        }
    }

    private func selectDataUsageTimeRange(_ range: UsageTimeRange) {
        overlayState.dataUsageTimeRange = range
        refreshDataUsage()
    }

    private func refreshDataUsage() {
        let selectedRange = overlayState.dataUsageTimeRange
        let now = Date()
        let timeZone = TimeZone.current
        let window = selectedRange.queryWindow(now: now, timeZone: timeZone)
        dataUsageRefreshGeneration += 1
        let generation = dataUsageRefreshGeneration
        let requestIdentity = UsageRefreshRequestIdentity(
            generation: generation,
            range: selectedRange
        )
        let previous = overlayState.dataUsagePresentation.snapshot.flatMap {
            $0.queryWindow.range == selectedRange ? $0 : nil
        }
        overlayState.dataUsagePresentation = .loading(previous: previous)
        dataUsageRefreshTask?.cancel()
        let loader = usageSnapshotLoader
        let refreshStartedAt = ProcessInfo.processInfo.systemUptime
        interactionLogger.log("data.usage.refresh.started", metadata: [
            "range": selectedRange.rawValue
        ])
        dataUsageRefreshTask = Task { [weak self, loader] in
            let outcome = await loader.loadSnapshot(in: window, refreshedAt: now)
            guard let self,
                  requestIdentity.permitsPublication(
                    currentGeneration: self.dataUsageRefreshGeneration,
                    currentRange: self.overlayState.dataUsageTimeRange,
                    isCancelled: Task.isCancelled
                  ) else { return }
            let durationMs = Int(max(
                0,
                ((ProcessInfo.processInfo.systemUptime - refreshStartedAt) * 1_000).rounded()
            ))
            self.publishDataUsage(outcome, range: selectedRange, durationMs: durationMs)
        }
    }

    private func publishDataUsage(
        _ outcome: UsageAggregationOutcome,
        range: UsageTimeRange,
        durationMs: Int
    ) {
        switch outcome {
        case .cancelled:
            return
        case .snapshot(let snapshot):
            if snapshot.completeness == .partial {
                overlayState.dataUsagePresentation = .partial(snapshot)
            } else if snapshot.tokens.realTotal == 0 {
                overlayState.dataUsagePresentation = .empty(snapshot)
            } else {
                overlayState.dataUsagePresentation = .available(snapshot)
            }
            interactionLogger.log("data.usage.refresh.completed", metadata: [
                "range": range.rawValue,
                "totalTokens": snapshot.tokens.realTotal,
                "requestCount": snapshot.requestCount,
                "durationMs": durationMs,
                "scannedFileCount": snapshot.scannedFileCount,
                "completeness": snapshot.completeness == .partial ? "partial" : "complete",
                "warnings": snapshot.warnings.map(\.rawValue).sorted()
            ])
        case .failed(let warnings):
            overlayState.dataUsagePresentation = .failed(warnings)
            interactionLogger.log("data.usage.refresh.failed", metadata: [
                "range": range.rawValue,
                "durationMs": durationMs,
                "warnings": warnings.map(\.rawValue).sorted()
            ])
        }
    }

    private func closeFilesPrimaryFeature() {
        overlayState.selectedPrimaryFeature = lastNonFilesPrimaryFeature
        overlayState.isFileShelfOverlayVisible = false
        overlayState.isFileShelfPinnedOpen = false
        overlayState.isFileDropTargetActive = false
        presentCodexApprovalAttachmentIfNeeded()
        if lastNonFilesPrimaryFeature == .data, case .idle = overlayState.dataUsagePresentation {
            refreshDataUsage()
        }
        interactionLogger.log("file.files.closed", metadata: [
            "itemCount": temporaryFileShelfStore.shelf.items.count,
            "restoredPrimaryFeature": lastNonFilesPrimaryFeature.rawValue
        ])
    }

    private func setFilesDisplayMode(_ mode: FilesDisplayMode) {
        guard overlayState.filesDisplayMode != mode else { return }
        overlayState.filesDisplayMode = mode
        syncFilesPinnedOpenState()
        interactionLogger.log("file.files.displayMode", metadata: [
            "mode": mode.rawValue,
            "itemCount": temporaryFileShelfStore.shelf.items.count
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

    private func airDropTemporaryFiles(ids requestedItemIDs: [TemporaryShelfItem.ID]) {
        temporaryFileShelfStore.pruneExpired()
        syncTemporaryFileShelfState()

        let selectedItemIDs = temporaryFileShelfSelection.selectedItemIDs
        let requestedItemIDSet = Set(requestedItemIDs)
        let items: [TemporaryShelfItem]
        if !requestedItemIDSet.isEmpty {
            items = temporaryFileShelfStore.shelf.items.filter { requestedItemIDSet.contains($0.id) }
        } else if !selectedItemIDs.isEmpty {
            items = temporaryFileShelfStore.shelf.items.filter { selectedItemIDs.contains($0.id) }
        } else {
            items = temporaryFileShelfStore.shelf.items
        }
        let fileURLs = items.map(\.fileURL)
        let itemIDs = items.map(\.id)
        guard !fileURLs.isEmpty else { return }

        guard let sharingService = NSSharingService(named: .sendViaAirDrop) else {
            interactionLogger.log("file.airdrop.unavailable", metadata: [
                "count": fileURLs.count
            ])
            return
        }

        let delegate = AirDropSharingDelegate(
            itemIDs: Set(itemIDs),
            fileURLs: fileURLs,
            onDidShare: { [weak self] itemIDs, fileURLs in
                self?.completeAirDropTemporaryFiles(ids: itemIDs, fileURLs: fileURLs)
            },
            onDidFinish: { [weak self] token, itemIDs, succeeded, itemCount in
                self?.finishAirDropSharing(token: token, itemIDs: itemIDs, succeeded: succeeded, itemCount: itemCount)
            }
        )
        pendingAirDropItemIDs.formUnion(itemIDs)
        syncPendingAirDropState()
        activeAirDropSharingDelegates[delegate.token] = delegate
        sharingService.delegate = delegate
        sharingService.perform(withItems: fileURLs)
        interactionLogger.log("file.airdrop.opened", metadata: [
            "count": fileURLs.count,
            "files": IslandInteractionLogger.sanitizedFileMetadata(for: fileURLs)
        ])
    }

    private func completeAirDropTemporaryFiles(ids itemIDs: Set<TemporaryShelfItem.ID>, fileURLs: [URL]) {
        removeTemporaryFiles(ids: itemIDs)
        setAirDropUndoFileURLs(fileURLs)
        interactionLogger.log("file.airdrop.completed", metadata: [
            "count": fileURLs.count,
            "undoAvailable": true,
            "files": IslandInteractionLogger.sanitizedFileMetadata(for: fileURLs)
        ])
    }

    private func finishAirDropSharing(
        token: UUID,
        itemIDs: Set<TemporaryShelfItem.ID>,
        succeeded: Bool,
        itemCount: Int
    ) {
        activeAirDropSharingDelegates[token] = nil
        if !succeeded {
            pendingAirDropItemIDs.subtract(itemIDs)
            syncPendingAirDropState()
            interactionLogger.log("file.airdrop.cancelled", metadata: [
                "count": itemCount
            ])
        }
    }

    private func syncTemporaryFileShelfState() {
        temporaryFileShelfSelection.retainOnly(itemIDs: temporaryFileShelfStore.shelf.items.map(\.id))
        overlayState.temporaryFileShelf = temporaryFileShelfStore.shelf
        syncTemporaryFileShelfSelectionState()
        if !temporaryFileShelfStore.shelf.hasItems {
            overlayState.isFileShelfOverlayVisible = false
            overlayState.isFileDropTargetActive = false
            overlayState.temporaryFileShelfFilter = .all
        }
        syncPendingAirDropState()
        syncFilesPinnedOpenState()
    }

    private func syncTemporaryFileShelfSelectionState() {
        overlayState.temporaryFileShelfSelectedItemIDs = temporaryFileShelfSelection.selectedItemIDs
    }

    private func syncPendingAirDropState() {
        pendingAirDropItemIDs.formIntersection(temporaryFileShelfStore.shelf.items.map(\.id))
    }

    private func setAirDropUndoFileURLs(_ fileURLs: [URL]) {
        airDropUndoClearWorkItem?.cancel()
        airDropUndoFileURLs = fileURLs
        overlayState.airDropUndoItemCount = fileURLs.count

        let workItem = DispatchWorkItem { [weak self] in
            self?.clearAirDropUndo()
        }
        airDropUndoClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: workItem)
    }

    private func undoAirDropRemoval() {
        let fileURLs = airDropUndoFileURLs
        guard !fileURLs.isEmpty else { return }
        temporaryFileShelfStore.addFileURLs(fileURLs)
        clearAirDropUndo()
        syncTemporaryFileShelfState()
        interactionLogger.log("file.airdrop.undo", metadata: [
            "count": fileURLs.count,
            "files": IslandInteractionLogger.sanitizedFileMetadata(for: fileURLs)
        ])
    }

    private func clearAirDropUndo() {
        airDropUndoClearWorkItem?.cancel()
        airDropUndoClearWorkItem = nil
        airDropUndoFileURLs = []
        overlayState.airDropUndoItemCount = 0
    }

    private func syncFilesPinnedOpenState() {
        guard overlayState.selectedPrimaryFeature == .files else {
            overlayState.isFileShelfPinnedOpen = overlayState.isFileShelfOverlayVisible
            return
        }

        switch overlayState.filesDisplayMode {
        case .auto:
            overlayState.isFileShelfPinnedOpen = false
        case .pinned:
            overlayState.isFileShelfPinnedOpen = true
        case .untilEmpty:
            overlayState.isFileShelfPinnedOpen = temporaryFileShelfStore.shelf.hasItems
        }
    }

    private func shouldCollapseOnMouseExit() -> Bool {
        guard overlayState.selectedPrimaryFeature == .files else {
            return !overlayState.isFileShelfPinnedOpen
        }

        switch overlayState.filesDisplayMode {
        case .auto:
            return true
        case .pinned:
            return false
        case .untilEmpty:
            return !temporaryFileShelfStore.shelf.hasItems
        }
    }

    private func setFileDropTargeted(_ targeted: Bool) {
        let nextValue = targeted && runtimeSettings.isFileShelfEnabled && !overlayState.isShellHidden
        guard overlayState.isFileDropTargetActive != nextValue else { return }
        withAnimation(.easeOut(duration: 0.14)) {
            overlayState.isFileDropTargetActive = nextValue
            if nextValue {
                overlayState.isFileShelfOverlayVisible = false
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
            overlayState.musicSkipFeedbackDirection = direction
            overlayState.musicSkipGestureProgress = progress
            overlayState.isMusicSkipArmed = false
        case .armed(let direction, let progress):
            if !Self.isArmedMusicSkipState(previousState) {
                interactionLogger.log("music.skip.armed", metadata: [
                    "direction": Self.musicSkipDirectionDescription(direction),
                    "deltaX": Double(accumulatedScrollDeltaX)
                ])
            }
            overlayState.musicSkipFeedbackDirection = direction
            overlayState.musicSkipGestureProgress = progress
            withAnimation(.easeOut(duration: 0.10)) {
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
            withAnimation(.easeOut(duration: animationProfile.musicSkipFeedbackDismissDuration)) {
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
            removePointerPassthroughMonitor()
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
        }
        let animationDuration = hideAnimationDuration
        withAnimation(.easeOut(duration: animationDuration)) {
            overlayState.isShellHidden = hidden
        }
        if hidden {
            installHiddenScrollMonitor()
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
                guard let self, self.overlayState.isShellHidden else { return }
                self.panel.ignoresMouseEvents = hidden
            }
        } else {
            panel.ignoresMouseEvents = false
            removeHiddenScrollMonitor()
            syncHoverWithPointer()
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

    private func installPointerPassthroughMonitor() {
        guard pointerPassthroughMonitor == nil else { return }
        guard panel.isVisible, panel.ignoresMouseEvents, !overlayState.isShellHidden else { return }
        let syncSource = pointerPassthroughEventSource()
        pointerPassthroughMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { _ in
            syncSource.add(data: 1)
        }
    }

    private func pointerPassthroughEventSource() -> DispatchSourceUserDataAdd {
        if let pointerPassthroughSyncSource {
            return pointerPassthroughSyncSource
        }

        let source = DispatchSource.makeUserDataAddSource(queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pointerPassthroughMonitor != nil else { return }
                guard self.panel.isVisible, self.panel.ignoresMouseEvents, !self.overlayState.isShellHidden else { return }
                self.syncHoverWithPointer()
            }
        }
        source.resume()
        pointerPassthroughSyncSource = source
        return source
    }

    private func removePointerPassthroughMonitor() {
        if let pointerPassthroughMonitor {
            NSEvent.removeMonitor(pointerPassthroughMonitor)
            self.pointerPassthroughMonitor = nil
        }
    }

    private func syncHoverWithPointer() {
        let pointerInsideIsland = pointerInsideInteractiveShell()
        let shouldHover = pointerInsideIsland && !overlayState.isShellHidden
        if overlayState.isHovered != shouldHover {
            overlayState.isHovered = shouldHover
        }
        guard !overlayState.isShellHidden else { return }
        collapseExpandedShellIfPointerLeavesInteractiveShell(pointerInsideIsland)
        syncMouseEventPassthroughWithPointer(isPointerInside: pointerInsideIsland)
    }

    private func collapseExpandedShellIfPointerLeavesInteractiveShell(_ isPointerInside: Bool) {
        guard !isPointerInside, isExpanded, shouldCollapseOnMouseExit() else { return }
        setExpanded(false)
    }

    private func syncMouseEventPassthroughWithPointer(isPointerInside: Bool) {
        let shouldIgnoreMouseEvents = !isPointerInside
        if panel.ignoresMouseEvents != shouldIgnoreMouseEvents {
            panel.ignoresMouseEvents = shouldIgnoreMouseEvents
        }
        if shouldIgnoreMouseEvents {
            installPointerPassthroughMonitor()
        } else {
            removePointerPassthroughMonitor()
        }
    }

    private func pointerInsideInteractiveShell() -> Bool {
        pointInsideInteractiveShell(NSEvent.mouseLocation)
    }

    private func pointInsideInteractiveShell(_ mouseLocation: NSPoint) -> Bool {
        if pointInsideBaseShell(mouseLocation) {
            return true
        }
        return pointInsideApprovalAttachment(mouseLocation)
    }

    private func pointInsideBaseShell(_ mouseLocation: NSPoint) -> Bool {
        let shellFrame = currentShellFrameInScreenCoordinates
        guard shellFrame.insetBy(dx: -2, dy: -2).contains(mouseLocation) else { return false }

        let localPoint = CGPoint(
            x: mouseLocation.x - shellFrame.minX,
            y: shellFrame.maxY - mouseLocation.y
        )
        return currentShellPathForHitTesting(in: CGRect(origin: .zero, size: shellFrame.size)).contains(localPoint)
    }

    private func pointInsideApprovalAttachment(_ mouseLocation: NSPoint) -> Bool {
        guard isExpanded,
              overlayState.isCodexApprovalAttachmentPresented,
              overlayState.selectedPrimaryFeature == .tasks
        else { return false }

        let attachmentFrame = CodexTasksApprovalLayout(
            metrics: metrics,
            shellHeight: currentShellHeightForHitTesting
        ).attachmentFrame
        let screenFrame = NSRect(
            x: panel.frame.minX + attachmentFrame.minX,
            y: panel.frame.maxY - attachmentFrame.maxY,
            width: attachmentFrame.width,
            height: attachmentFrame.height
        )
        return screenFrame.insetBy(dx: -2, dy: -2).contains(mouseLocation)
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
        let hasAdditionalRightCanvas = isExpanded && panel.frame.width > metrics.openWidth + 0.5
        return NSRect(
            x: hasAdditionalRightCanvas
                ? panel.frame.minX
                : panel.frame.midX - (shellWidth / 2) + currentShellHorizontalOffsetForHitTesting,
            y: panel.frame.maxY - shellHeight,
            width: shellWidth,
            height: shellHeight
        )
    }

    private var currentShellWidthForHitTesting: CGFloat {
        guard !isExpanded else { return metrics.openWidth }
        let closedWidth = overlayState.musicPlayback.isPlaying ? metrics.musicClosedShellWidth : metrics.closedShellWidth
        return closedWidth + currentSkipExpansionForHitTesting
    }

    private var currentShellHeightForHitTesting: CGFloat {
        if isExpanded {
            metrics.openHeight + overlayState.codexTasksDetailExpansionHeight
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
        overlayState.isFileShelfOverlayVisible = false
        overlayState.isFileShelfPinnedOpen = false
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

    private func startCodexReasoningEffortPolling() {
        codexReasoningEffortPollingTask?.cancel()
        codexReasoningEffortPollingTask = Task { [weak self] in
            var lastSignal: CodexReasoningEffortSignal?
            var cachedFallbackSignal: CodexReasoningEffortSignal?
            var lastFallbackRefreshDate: Date?
            while !Task.isCancelled {
                let now = Date()
                let shouldRefreshFallback = lastFallbackRefreshDate.map {
                    now.timeIntervalSince($0) >= Self.codexReasoningFallbackRefreshInterval
                } ?? true
                let fallbackSignal = cachedFallbackSignal
                let signal = await Task.detached(priority: .utility) { @Sendable in
                    let signalSource = CodexReasoningEffortSignalSource()
                    if let realtimeSignal = signalSource.currentRealtimeSignal() {
                        return realtimeSignal
                    }
                    if !shouldRefreshFallback, let fallbackSignal {
                        return fallbackSignal
                    }
                    return signalSource.currentFallbackSignal()
                }.value

                if signal.source != .ccSwitchRealtime {
                    cachedFallbackSignal = signal
                    lastFallbackRefreshDate = now
                }

                guard let self else { return }
                if signal != lastSignal {
                    overlayState.isTopBandEnergyEffectEnabled = signal.triggersEnergyTail
                    interactionLogger.log("codex.reasoning.effort.changed", metadata: [
                        "source": signal.source.rawValue,
                        "effort": signal.effort?.rawValue ?? "",
                        "triggersEnergyTail": signal.triggersEnergyTail
                    ])
                    lastSignal = signal
                }

                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func startCodexStatusPolling() {
        codexStatusPollingTask?.cancel()
        codexStatusPollingTask = Task { [weak self] in
            let codexStatusSignalSource = CodexStatusSignalSource()
            var lastLoggedSummary: String?
            var lastSnapshotRefreshDate: Date?
            while !Task.isCancelled {
                guard let self else { return }
                let now = Date()
                let isTasksVisible = isExpanded
                    && overlayState.selectedPrimaryFeature == .tasks
                    && !overlayState.isFileShelfOverlayVisible
                let shouldRefresh = isTasksVisible || lastSnapshotRefreshDate.map {
                    now.timeIntervalSince($0) >= Self.codexStatusBackgroundRefreshInterval
                } ?? true

                guard shouldRefresh else {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }

                let snapshot = await Task.detached(priority: .utility) {
                    codexStatusSignalSource.currentSnapshot()
                }.value

                lastSnapshotRefreshDate = Date()
                for task in snapshot.tasks where task.activityState.isWorking {
                    codexTaskDismissalStore.restore(task.dismissalKey)
                }
                overlayState.dismissedCodexTaskKeys = codexTaskDismissalStore.activeKeys()
                self.overlayState.codexStatusBarSnapshot = snapshot
                updatePassiveCodexApprovalPresentation(snapshot)
                handleCodexApprovalTransition(snapshot)

                let logSummary = [
                    snapshot.threadID ?? "",
                    "\(snapshot.totalTokens)",
                    "\(snapshot.runningTasksCount)",
                    snapshot.activityState.rawValue
                ].joined(separator: "|")
                if logSummary != lastLoggedSummary {
                    self.interactionLogger.log("codex.status.changed", metadata: [
                        "activity": snapshot.activityState.rawValue,
                        "runningTasks": snapshot.runningTasksCount,
                        "totalTokens": snapshot.totalTokens,
                        "threadIDLength": snapshot.threadID?.count ?? 0,
                        "titleLength": snapshot.threadTitle?.count ?? 0
                    ])
                    lastLoggedSummary = logSummary
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
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
            "titleLength": signal.title.count,
            "artistLength": signal.artist.count,
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

    private func presentCodexApprovalAttachmentIfNeeded() {
        guard isExpanded,
              overlayState.selectedPrimaryFeature == .tasks,
              let request = overlayState.codexApprovalPresentation.request,
              request.threadID == overlayState.selectedCodexTaskID,
              !overlayState.isShellHidden
        else { return }

        approvalAttachmentResizeWorkItem?.cancel()
        approvalAttachmentResizeWorkItem = nil
        let layout = CodexTasksApprovalLayout(
            metrics: metrics,
            shellHeight: expandedTasksShellHeight
        )
        setPanelFrame(
            expandedPanelFrame(
                shellHeight: expandedTasksShellHeight,
                additionalRightWidth: layout.additionalCanvasWidth,
                on: panel.screen ?? NSScreen.main
            )
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let overlayState = self.overlayState
            guard self.isExpanded,
                  overlayState.selectedPrimaryFeature == .tasks,
                  let request = overlayState.codexApprovalPresentation.request,
                  request.threadID == overlayState.selectedCodexTaskID,
                  !overlayState.isShellHidden
            else { return }
            withAnimation(self.approvalAttachmentPresentationAnimation) {
                overlayState.isCodexApprovalAttachmentPresented = true
            }
            self.logCodexApprovalPresentedIfNeeded(request)
        }
    }

    private func logCodexApprovalPresentedIfNeeded(_ request: CodexApprovalRequest) {
        guard overlayState.isCodexApprovalAttachmentPresented,
              overlayState.codexApprovalPresentation.request?.id == request.id,
              loggedCodexApprovalPresentedRequestIDs.insert(request.id).inserted
        else { return }
        logCodexApprovalAuditEvent(.presented(
            kind: request.kind,
            inlineCapable: request.canRespondInline
        ))
    }

    private func dismissCodexApprovalAttachment(shrinkPanel: Bool = true) {
        approvalAttachmentResizeWorkItem?.cancel()
        approvalAttachmentResizeWorkItem = nil
        let hasAdditionalRightCanvas = isExpanded && panel.frame.width > metrics.openWidth + 0.5
        guard overlayState.isCodexApprovalAttachmentPresented || hasAdditionalRightCanvas else {
            return
        }
        withAnimation(approvalAttachmentDismissAnimation) {
            overlayState.isCodexApprovalAttachmentPresented = false
        }

        guard shrinkPanel, isExpanded else { return }
        let resize = { [weak self] in
            guard let self,
                  self.isExpanded,
                  !self.overlayState.isCodexApprovalAttachmentPresented
            else { return }
            self.setPanelFrame(
                self.expandedPanelFrame(
                    shellHeight: self.expandedTasksShellHeight,
                    additionalRightWidth: 0,
                    on: self.panel.screen ?? NSScreen.main
                )
            )
        }
        let workItem = DispatchWorkItem(block: resize)
        approvalAttachmentResizeWorkItem = workItem
        let delay = prefersReducedMotion
            ? animationProfile.reducedMotionFadeDuration
            : animationProfile.attachedElementCollapseDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func updatePassiveCodexApprovalPresentation(_ snapshot: CodexStatusBarSnapshot) {
        let managedPresentation = codexApprovalCoordinator?.presentation
        if let managedRequest = managedPresentation?.request,
           managedRequest.threadID == overlayState.selectedCodexTaskID {
            return
        }
        let managedPendingThreadIDs = managedPresentation?.pendingThreadIDs ?? []
        let pendingTasks = snapshot.tasks.filter {
            $0.approvalState.requiresManualApproval
        }
        let pendingThreadIDs = managedPendingThreadIDs.union(pendingTasks.map(\.id))
        let task: CodexTaskStatus?
        if let selectedCodexTaskID = overlayState.selectedCodexTaskID {
            task = pendingTasks.first { $0.id == selectedCodexTaskID }
        } else {
            task = pendingTasks.first
        }
        guard let task else {
            codexApprovalApplicationOpenState.requestDidChange(to: nil)
            overlayState.codexApprovalPresentation = CodexApprovalPresentation(
                request: nil,
                pendingCount: pendingThreadIDs.count,
                submissionState: .ready,
                pendingThreadIDs: pendingThreadIDs
            )
            dismissCodexApprovalAttachment()
            return
        }

        let kind: CodexApprovalKind
        switch task.approvalState {
        case .pending, .pendingCommand:
            kind = .command
        case .pendingFileChange:
            kind = .fileChange
        case .pendingPermissions:
            kind = .permissions
        case .none, .autoReviewing:
            return
        }

        let request = CodexApprovalRequest.passive(
            threadID: task.id,
            turnID: task.turnID ?? "",
            kind: kind,
            startedAtMilliseconds: 0
        )
        codexApprovalApplicationOpenState.requestDidChange(to: request.id)
        overlayState.codexApprovalPresentation = CodexApprovalPresentation(
            request: request,
            pendingCount: pendingThreadIDs.count,
            submissionState: codexApprovalApplicationOpenState.hasFailure(for: request.id)
                ? .failed("无法打开 Codex")
                : .ready,
            pendingThreadIDs: pendingThreadIDs
        )
    }

    private func handleCodexApprovalTransition(_ snapshot: CodexStatusBarSnapshot) {
        let pendingTasks = snapshot.tasks.filter {
            $0.approvalState.requiresManualApproval
        }
        let keys = Set(pendingTasks.map {
            [$0.id, $0.turnID ?? "", $0.approvalState.rawValue].joined(separator: "|")
        })
        let newKeys = keys.subtracting(lastObservedPassiveApprovalKeys)
        lastObservedPassiveApprovalKeys = keys

        let action = CodexApprovalAutoPresentationPolicy.action(
            isShellHidden: overlayState.isShellHidden,
            isFilesPinned: overlayState.selectedPrimaryFeature == .files
                && overlayState.isFileShelfPinnedOpen,
            isExpanded: isExpanded
        )

        guard !newKeys.isEmpty,
              let task = pendingTasks.first(where: {
                  newKeys.contains([$0.id, $0.turnID ?? "", $0.approvalState.rawValue].joined(separator: "|"))
              }),
              !overlayState.isShellHidden,
              action != .ignore
        else { return }

        overlayState.selectedCodexTaskID = task.id
        updatePassiveCodexApprovalPresentation(snapshot)
        if let request = overlayState.codexApprovalPresentation.request,
           request.threadID == task.id {
            logCodexApprovalAuditEvent(.detected(
                kind: request.kind,
                source: request.source,
                pendingCount: pendingTasks.count,
                threadIDLength: request.threadID.count
            ))
        }

        if overlayState.selectedPrimaryFeature == .files,
           overlayState.isFileShelfPinnedOpen {
            return
        }

        selectPrimaryFeature(.tasks)
        if !isExpanded {
            setExpanded(true)
        }
        presentCodexApprovalAttachmentIfNeeded()
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
                "titleLength": snapshot.title.count,
                "artistLength": snapshot.artist.count
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
        withAnimation(prefersReducedMotion ? nil : .easeOut(duration: animationProfile.trackInfoTransitionDuration)) {
            overlayState.isTrackInfoPresented = true
        }
        interactionLogger.log("track.info.shown", metadata: [
            "titleLength": overlayState.musicPlayback.title.count,
            "artistLength": overlayState.musicPlayback.artist.count
        ])

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(self.prefersReducedMotion ? nil : .easeOut(duration: self.animationProfile.trackInfoTransitionDuration)) {
                self.overlayState.isTrackInfoPresented = false
            }
            self.interactionLogger.log("track.info.dismissed")
            let frameDelay = self.prefersReducedMotion ? 0 : self.animationProfile.trackInfoTransitionDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + frameDelay) { [weak self] in
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
        if overlayState.usesOpenCanvas {
            setPanelFrame(
                expandedPanelFrame(
                    shellHeight: expandedTasksShellHeight,
                    on: screen
                )
            )
        } else {
            setPanelFrame(Self.windowFrame(for: panel.frame.size, on: screen))
        }
    }

    private func setPanelFrame(_ frame: NSRect?) {
        guard let frame else { return }
        panel.setFrame(frame, display: true)
    }

    private static func windowSize(
        for metrics: NotchMetrics,
        usesOpenCanvas: Bool,
        showsTrackInfo: Bool = false,
        expandedShellHeight requestedExpandedShellHeight: CGFloat? = nil
    ) -> CGSize {
        if usesOpenCanvas {
            let expandedShellHeight = max(metrics.openHeight, requestedExpandedShellHeight ?? metrics.openHeight)
            return CGSize(
                width: metrics.openWidth,
                height: expandedShellHeight + NotchMetrics.defaultClosedCanvasBottomSlack
            )
        }
        return CGSize(
            width: metrics.musicClosedShellWidth + NotchMetrics.closedCanvasHorizontalSlack,
            height: (showsTrackInfo ? metrics.musicTrackInfoShellHeight : metrics.closedHeight) + NotchMetrics.closedHoverBottomSlack
        )
    }

    private static func expandedWindowFrame(
        metrics: NotchMetrics,
        shellHeight: CGFloat,
        additionalRightWidth: CGFloat,
        on screen: NSScreen?
    ) -> NSRect? {
        guard let screen else { return nil }
        let baseX = screen.frame.midX - (metrics.openWidth / 2)
        let width = metrics.openWidth + max(0, additionalRightWidth)
        return NSRect(
            x: baseX,
            y: screen.frame.maxY - shellHeight - NotchMetrics.defaultClosedCanvasBottomSlack,
            width: width,
            height: shellHeight + NotchMetrics.defaultClosedCanvasBottomSlack
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

private final class AirDropSharingDelegate: NSObject, NSSharingServiceDelegate {
    let token = UUID()

    private let itemIDs: Set<TemporaryShelfItem.ID>
    private let fileURLs: [URL]
    private let onDidShare: @MainActor (Set<TemporaryShelfItem.ID>, [URL]) -> Void
    private let onDidFinish: @MainActor (UUID, Set<TemporaryShelfItem.ID>, Bool, Int) -> Void

    init(
        itemIDs: Set<TemporaryShelfItem.ID>,
        fileURLs: [URL],
        onDidShare: @escaping @MainActor (Set<TemporaryShelfItem.ID>, [URL]) -> Void,
        onDidFinish: @escaping @MainActor (UUID, Set<TemporaryShelfItem.ID>, Bool, Int) -> Void
    ) {
        self.itemIDs = itemIDs
        self.fileURLs = fileURLs
        self.onDidShare = onDidShare
        self.onDidFinish = onDidFinish
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        Task { @MainActor in
            onDidShare(itemIDs, fileURLs)
            onDidFinish(token, itemIDs, true, fileURLs.count)
        }
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        Task { @MainActor in
            onDidFinish(token, itemIDs, false, fileURLs.count)
        }
    }
}
