import AppKit
import SwiftUI
import DynamicIslandCore

@MainActor
final class IslandPanelController {
    private static let closedHoverHorizontalSlack: CGFloat = 22
    private static let closedHoverBottomSlack: CGFloat = 10
    private static let scrollActivationThreshold: CGFloat = 0.8
    private static let trackInfoDismissDelay: TimeInterval = 2.5

    private var metrics: NotchMetrics
    private var isExpanded = false
    private var collapseWorkItem: DispatchWorkItem?
    nonisolated(unsafe) private var trackInfoDismissWorkItem: DispatchWorkItem?
    private var lastPresentedTrackIdentity: String?
    private let panel: NSPanel
    private let overlayState: IslandOverlayState
    private let hostingView: IslandTrackingHostingView
    private let animationProfile = IslandAnimationProfile.default
    private let musicPlaybackDataSource: any MusicPlaybackDataSource
    private var musicPlaybackPollingTask: Task<Void, Never>?
    nonisolated(unsafe) private var hiddenScrollMonitor: Any?

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
        trackInfoDismissWorkItem?.cancel()
        if let hiddenScrollMonitor {
            NSEvent.removeMonitor(hiddenScrollMonitor)
        }
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
            guard let self, !self.overlayState.isShellHidden else { return }
            self.overlayState.isHovered = self.panel.frame.contains(NSEvent.mouseLocation)
        }
        hostingView.onMouseExited = { [weak self] in
            self?.overlayState.isHovered = false
            self?.setExpanded(false)
        }
        hostingView.onScroll = { [weak self] deltaY in
            self?.handleScroll(deltaY: deltaY)
        }
    }

    private func handleScroll(deltaY: CGFloat) {
        let pointerInsideIsland = panel.frame.contains(NSEvent.mouseLocation)
        guard pointerInsideIsland else { return }

        if overlayState.isShellHidden {
            if deltaY > Self.scrollActivationThreshold {
                setShellHidden(false)
            }
            return
        }

        if deltaY < -Self.scrollActivationThreshold {
            setShellHidden(true)
        } else if deltaY > Self.scrollActivationThreshold {
            setShellHidden(false)
        }
    }

    private func setShellHidden(_ hidden: Bool) {
        guard overlayState.isShellHidden != hidden else { return }
        if hidden {
            overlayState.isHovered = false
            overlayState.isTrackInfoPresented = false
            trackInfoDismissWorkItem?.cancel()
            trackInfoDismissWorkItem = nil
            setExpanded(false)
        } else {
            panel.ignoresMouseEvents = false
            removeHiddenScrollMonitor()
            overlayState.isHovered = panel.frame.contains(NSEvent.mouseLocation)
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
                guard self.panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.handleScroll(deltaY: event.scrollingDeltaY)
            }
        }
    }

    private func removeHiddenScrollMonitor() {
        if let hiddenScrollMonitor {
            NSEvent.removeMonitor(hiddenScrollMonitor)
            self.hiddenScrollMonitor = nil
        }
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

    private func updateMusicPlayback(_ snapshot: MusicPlaybackSnapshot) {
        let previousIdentity = overlayState.musicPlayback.trackIdentity
        overlayState.musicPlayback = snapshot

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
            width: metrics.musicClosedShellWidth + Self.closedHoverHorizontalSlack,
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
