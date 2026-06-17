import AppKit
import SwiftUI
import DynamicIslandCore

@MainActor
final class IslandPanelController {
    private static let closedHoverHorizontalSlack: CGFloat = 22
    private static let closedHoverBottomSlack: CGFloat = 10

    private var metrics: NotchMetrics
    private var isExpanded = false
    private var collapseWorkItem: DispatchWorkItem?
    private let panel: NSPanel
    private let overlayState: IslandOverlayState
    private let hostingView: IslandTrackingHostingView
    private let animationProfile = IslandAnimationProfile.default
    private let musicPlaybackDataSource: any MusicPlaybackDataSource
    private var musicPlaybackPollingTask: Task<Void, Never>?

    init(
        screen: NSScreen? = NSScreen.main,
        musicPlaybackDataSource: any MusicPlaybackDataSource = ScriptableMusicPlaybackDataSource()
    ) {
        self.musicPlaybackDataSource = musicPlaybackDataSource
        let screenProfile = ScreenMetricsProvider.profile(for: screen)
        metrics = screenProfile.metrics

        let overlayState = IslandOverlayState()
        self.overlayState = overlayState

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize(for: screenProfile.metrics, usesOpenCanvas: false)),
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
        startMusicPlaybackPolling()
    }

    deinit {
        musicPlaybackPollingTask?.cancel()
    }

    func show() {
        refreshForCurrentScreen()
        panel.orderFrontRegardless()
    }

    func hide() {
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
            self?.overlayState.isHovered = true
        }
        hostingView.onMouseExited = { [weak self] in
            self?.overlayState.isHovered = false
            self?.setExpanded(false)
        }
    }

    private func startMusicPlaybackPolling() {
        musicPlaybackPollingTask?.cancel()
        musicPlaybackPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = await musicPlaybackDataSource.currentSnapshot()
                overlayState.musicPlayback = snapshot
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func position(on screen: NSScreen?) {
        setPanelFrame(Self.windowFrame(for: panel.frame.size, on: screen))
    }

    private func setPanelFrame(_ frame: NSRect?) {
        guard let frame else { return }
        panel.setFrame(frame, display: true)
    }

    private static func windowSize(for metrics: NotchMetrics, usesOpenCanvas: Bool) -> CGSize {
        guard !usesOpenCanvas else { return metrics.openCompletionFeedbackWindowSize }
        return CGSize(
            width: metrics.musicClosedShellWidth + Self.closedHoverHorizontalSlack,
            height: metrics.closedHeight + Self.closedHoverBottomSlack
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
