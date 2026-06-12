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
    private var taskActivityPollingTask: Task<Void, Never>?

    init(
        screen: NSScreen? = NSScreen.main,
        taskActivityDataSource: any TaskActivityDataSource = ClaudeTaskActivityDataSource()
    ) {
        let metrics = ScreenMetricsProvider.metrics(for: screen)
        self.metrics = metrics
        self.taskActivityDataSource = taskActivityDataSource
        let overlayState = IslandOverlayState()
        self.overlayState = overlayState

        let contentSize = Self.windowSize(for: metrics, isExpanded: false)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )

        hostingView = IslandTrackingHostingView(
            rootView: IslandOverlayView(metrics: metrics, state: overlayState)
        )
        configurePanel()
        installHostingView()
        installTrackingCallbacks()
        updateRootView()
        position(on: screen ?? NSScreen.main)
    }

    deinit {
        taskActivityPollingTask?.cancel()
    }

    func show() {
        refreshForCurrentScreen()
        startTaskActivityPolling()
        panel.orderFrontRegardless()
    }

    func hide() {
        taskActivityPollingTask?.cancel()
        taskActivityPollingTask = nil
        panel.orderOut(nil)
    }

    func refreshForCurrentScreen() {
        let screen = NSScreen.main
        metrics = ScreenMetricsProvider.metrics(for: screen)
        updateRootView()
        setPanelFrame(
            Self.windowFrame(
                for: Self.windowSize(for: metrics, usesOpenCanvas: overlayState.usesOpenCanvas),
                on: screen
            )
        )
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
                withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)) {
                    self.overlayState.isExpanded = true
                }
            }
        } else {
            withAnimation(.easeOut(duration: 0.12)) {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13, execute: workItem)
        }
    }

    private func updateRootView() {
        hostingView.rootView = IslandOverlayView(metrics: metrics, state: overlayState) { [weak self] expanded in
            self?.setExpanded(expanded)
        }
    }

    private func refreshTaskActivityState() async {
        let nextState = await taskActivityDataSource.currentState()
        guard overlayState.taskActivity != nextState else { return }
        overlayState.taskActivity = nextState
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
            self?.setExpanded(false)
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
        isExpanded ? metrics.openWindowSize : metrics.closedWindowSize
    }

    private static func windowSize(for metrics: NotchMetrics, usesOpenCanvas: Bool) -> CGSize {
        usesOpenCanvas ? metrics.openWindowSize : metrics.closedWindowSize
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
