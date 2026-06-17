import AppKit
import SwiftUI
import IslandCore

@MainActor
final class IslandPanelController {
    private var metrics: NotchMetrics
    private var isExpanded = false
    private var collapseWorkItem: DispatchWorkItem?
    private let panel: NSPanel
    private let overlayState: IslandOverlayState
    private let hostingView: IslandTrackingHostingView
    private let taskActivityDataSource: any TaskActivityDataSource
    private let audioPlaybackDataSource: any AudioPlaybackDataSource
    private let temporaryFileShelfStore = TemporaryFileShelfStore()
    private let animationProfile = IslandAnimationProfile.default
    private var fileShelfSelection = TemporaryFileShelfSelection()
    private var taskActivityPollingTask: Task<Void, Never>?
    private var audioPlaybackPollingTask: Task<Void, Never>?
    private var fileShelfPruneTask: Task<Void, Never>?
    private var calibrationCaptionTask: Task<Void, Never>?
    private var completionSoundTask: Task<Void, Never>?
    private var fileDropSoundTask: Task<Void, Never>?
    private var lastCompletionEventID: String?

    init(
        screen: NSScreen? = NSScreen.main,
        taskActivityDataSource: any TaskActivityDataSource = CodexTaskActivityDataSource(),
        audioPlaybackDataSource: any AudioPlaybackDataSource = AudioPlaybackDataSourceFactory.defaultSource()
    ) {
        let screenProfile = ScreenMetricsProvider.profile(for: screen)
        self.metrics = screenProfile.metrics
        self.taskActivityDataSource = taskActivityDataSource
        self.audioPlaybackDataSource = audioPlaybackDataSource
        let overlayState = IslandOverlayState()
        self.overlayState = overlayState

        let contentSize = Self.windowSize(for: screenProfile.metrics, isExpanded: false)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        hostingView = IslandTrackingHostingView(
            rootView: IslandOverlayView(metrics: screenProfile.metrics, state: overlayState)
        )
        configurePanel()
        installHostingView()
        installTrackingCallbacks()
        updateRootView()
        position(on: screen ?? NSScreen.main)
        showCalibrationCaptionIfNeeded(screenProfile.shouldShowCalibrationCaption)
    }

    deinit {
        taskActivityPollingTask?.cancel()
        audioPlaybackPollingTask?.cancel()
        fileShelfPruneTask?.cancel()
        calibrationCaptionTask?.cancel()
        completionSoundTask?.cancel()
        fileDropSoundTask?.cancel()
    }

    func show() {
        refreshForCurrentScreen()
        startTaskActivityPolling()
        startAudioPlaybackPolling()
        startTemporaryFileShelfPruning()
        panel.orderFrontRegardless()
    }

    func hide() {
        taskActivityPollingTask?.cancel()
        taskActivityPollingTask = nil
        audioPlaybackPollingTask?.cancel()
        audioPlaybackPollingTask = nil
        fileShelfPruneTask?.cancel()
        fileShelfPruneTask = nil
        panel.orderOut(nil)
    }

    func refreshForCurrentScreen() {
        let screen = NSScreen.main
        let screenProfile = ScreenMetricsProvider.profile(for: screen)
        metrics = screenProfile.metrics
        updateRootView()
        setPanelFrame(
            Self.windowFrame(
                for: Self.windowSize(for: metrics, usesOpenCanvas: overlayState.usesOpenCanvas),
                on: screen
            )
        )
        showCalibrationCaptionIfNeeded(screenProfile.shouldShowCalibrationCaption)
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        collapseWorkItem?.cancel()
        collapseWorkItem = nil

        isExpanded = expanded

        if expanded {
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
            onFileShelfButtonClick: { [weak self] in
                self?.openFileShelfFromButton()
            },
            onOpenShelfItem: { [weak self] item in
                self?.openShelfItem(item)
            },
            onRemoveShelfItem: { [weak self] id in
                self?.removeShelfItem(id: id)
            },
            onClearShelf: { [weak self] in
                self?.clearShelfItems()
            },
            onDismissFileShelf: { [weak self] in
                self?.closeFileShelfOverlay(collapses: false)
            },
            onSelectShelfItem: { [weak self] id in
                self?.selectShelfItem(id: id)
            },
            onClearShelfSelection: { [weak self] in
                self?.clearShelfSelection()
            },
            onSelectShelfItems: { [weak self] ids in
                self?.selectShelfItems(ids)
            }
        )
    }

    private func showCalibrationCaptionIfNeeded(_ shouldShow: Bool) {
        guard shouldShow else { return }
        calibrationCaptionTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) {
            overlayState.calibrationCaption = "Calibrating display..."
        }
        calibrationCaptionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.20)) {
                    self?.overlayState.calibrationCaption = nil
                }
            }
        }
    }

    func previewCompletionBounce() {
        triggerCompletionFeedback()
    }

    private func refreshTaskActivityState() async {
        let snapshot = await taskActivityDataSource.currentSnapshot()
        if let completionEventID = snapshot.completionEventID,
           completionEventID != lastCompletionEventID {
            lastCompletionEventID = completionEventID
            triggerCompletionFeedback()
        }

        guard overlayState.taskActivity != snapshot.state else { return }
        overlayState.taskActivity = snapshot.state
    }

    private func refreshAudioPlaybackState() async {
        let nextState = await audioPlaybackDataSource.currentState()
        guard overlayState.audioPlayback != nextState else { return }
        overlayState.audioPlayback = nextState
    }

    private func triggerCompletionFeedback() {
        overlayState.completionFeedbackTrigger += 1
        completionSoundTask?.cancel()
        completionSoundTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: CompletionFeedbackSound.initialDelayNanoseconds)
            guard !Task.isCancelled else { return }
            playSystemCompletionSounds()
        }
    }

    private func playSystemCompletionSounds() {
        completionSoundTask = Task { @MainActor in
            for index in 0..<CompletionFeedbackSound.repeatCount {
                NSSound(named: CompletionFeedbackSound.name)?.play()
                if index < CompletionFeedbackSound.repeatCount - 1 {
                    try? await Task.sleep(nanoseconds: CompletionFeedbackSound.intervalNanoseconds)
                    guard !Task.isCancelled else { return }
                }
            }
        }
    }

    private func startTaskActivityPolling() {
        guard taskActivityPollingTask == nil else { return }

        taskActivityPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshTaskActivityState()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func startAudioPlaybackPolling() {
        guard audioPlaybackPollingTask == nil else { return }

        audioPlaybackPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshAudioPlaybackState()
                try? await Task.sleep(nanoseconds: 83_333_333)
            }
        }
    }

    private func startTemporaryFileShelfPruning() {
        guard fileShelfPruneTask == nil else { return }

        fileShelfPruneTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await MainActor.run {
                    let items = self.temporaryFileShelfStore.pruneExpired()
                    if self.overlayState.fileShelfItems != items
                        || self.overlayState.isFileShelfOverlayVisible
                        || self.overlayState.isFileDropTargetActive
                        || self.overlayState.isFileShelfPinnedOpen {
                        self.applyFileShelfItems(items)
                    }
                }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    private func configurePanel() {
        panel.title = "Island"
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
            self?.setExpanded(true)
        }
        hostingView.onMouseExited = { [weak self] in
            guard let self else { return }
            if self.overlayState.isFileShelfPinnedOpen {
                return
            }
            self.closeFileShelfOverlay(collapses: false)
            self.setExpanded(false)
        }
        hostingView.onFileDragEntered = { [weak self] fileURLs in
            self?.handleFileDragEntered(fileURLs)
        }
        hostingView.onFileDragExited = { [weak self] in
            self?.handleFileDragExited()
        }
        hostingView.onFileDrop = { [weak self] fileURLs in
            self?.handleFileDrop(fileURLs)
        }
    }

    private func handleFileDragEntered(_ fileURLs: [URL]) {
        guard !fileURLs.isEmpty else { return }
        overlayState.isFileDropTargetActive = true
        overlayState.isFileShelfOverlayVisible = true
        triggerFileDropTargetFeedback()
        setExpanded(true)
    }

    private func handleFileDragExited() {
        let wasDropTargetActive = overlayState.isFileDropTargetActive
        overlayState.isFileDropTargetActive = false
        if wasDropTargetActive {
            fileDropSoundTask?.cancel()
            playFileDragCancelSound()
        }
        if !overlayState.isFileShelfPinnedOpen && temporaryFileShelfStore.items.isEmpty {
            overlayState.isFileShelfOverlayVisible = false
            setExpanded(false)
        }
    }

    private func handleFileDrop(_ fileURLs: [URL]) {
        overlayState.isFileDropTargetActive = false
        overlayState.isFileShelfOverlayVisible = true
        applyFileShelfItems(temporaryFileShelfStore.addFileURLs(fileURLs))
        setExpanded(true)
    }

    private func openFileShelfFromButton() {
        applyFileShelfItems(temporaryFileShelfStore.pruneExpired())
        guard !overlayState.fileShelfItems.isEmpty else { return }

        if overlayState.isFileShelfOverlayVisible && overlayState.isFileShelfPinnedOpen {
            closeFileShelfOverlay(collapses: false)
            return
        }

        overlayState.isFileShelfOverlayVisible = true
        overlayState.isFileShelfPinnedOpen = true
        overlayState.isFileDropTargetActive = false
        setExpanded(true)
    }

    private func closeFileShelfOverlay(collapses: Bool) {
        overlayState.isFileShelfOverlayVisible = false
        overlayState.isFileShelfPinnedOpen = false
        overlayState.isFileDropTargetActive = false

        if collapses {
            setExpanded(false)
        }
    }

    private func openShelfItem(_ item: TemporaryShelfItem) {
        _ = NSWorkspace.shared.open(item.fileURL)
    }

    private func removeShelfItem(id: TemporaryShelfItem.ID) {
        applyFileShelfItems(temporaryFileShelfStore.removeItem(id: id))
    }

    private func clearShelfItems() {
        temporaryFileShelfStore.clear()
        clearShelfSelection()
        applyFileShelfItems([])
    }

    private func applyFileShelfItems(_ items: [TemporaryShelfItem]) {
        overlayState.fileShelfItems = items
        fileShelfSelection.retainOnly(itemIDs: items.map(\.id))
        overlayState.fileShelfSelectedItemIDs = fileShelfSelection.selectedItemIDs
        guard items.isEmpty else { return }

        overlayState.isFileShelfOverlayVisible = false
        overlayState.isFileShelfPinnedOpen = false
        overlayState.isFileDropTargetActive = false
        if isExpanded {
            setExpanded(false)
        }
    }

    private func selectShelfItem(id: TemporaryShelfItem.ID) {
        fileShelfSelection.selectOnly(id)
        overlayState.fileShelfSelectedItemIDs = fileShelfSelection.selectedItemIDs
    }

    private func selectShelfItems(_ ids: Set<TemporaryShelfItem.ID>) {
        fileShelfSelection.select(ids)
        overlayState.fileShelfSelectedItemIDs = fileShelfSelection.selectedItemIDs
    }

    private func clearShelfSelection() {
        fileShelfSelection.clear()
        overlayState.fileShelfSelectedItemIDs.removeAll()
    }

    private func playFileDragCancelSound() {
        NSSound(named: FileDragCancelSound.name)?.play()
    }

    private func triggerFileDropTargetFeedback() {
        overlayState.fileDropFeedbackTrigger += 1
        fileDropSoundTask?.cancel()
        fileDropSoundTask = Task { @MainActor in
            NSSound(named: FileDragAcceptSound.name)?.play()
        }
    }

    private func position(on screen: NSScreen?) {
        setPanelFrame(Self.windowFrame(for: panel.frame.size, on: screen))
    }

    private func setPanelFrame(_ frame: NSRect?) {
        guard let frame else { return }
        panel.setFrame(frame, display: true)
    }

    private static func windowSize(for metrics: NotchMetrics, isExpanded: Bool) -> CGSize {
        windowSize(for: metrics, usesOpenCanvas: isExpanded)
    }

    private static func windowSize(for metrics: NotchMetrics, usesOpenCanvas: Bool) -> CGSize {
        guard !usesOpenCanvas else { return metrics.openCompletionFeedbackWindowSize }
        return metrics.closedCompletionFeedbackWindowSize
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

private enum CompletionFeedbackSound {
    static let name = NSSound.Name("Glass")
    static let repeatCount = 3
    static let initialDelayNanoseconds: UInt64 = 820_000_000
    static let intervalNanoseconds: UInt64 = 260_000_000
}

private enum FileDragCancelSound {
    static let name = NSSound.Name("Tink")
}

private enum FileDragAcceptSound {
    static let name = NSSound.Name("Glass")
}
