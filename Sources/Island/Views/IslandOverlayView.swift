import SwiftUI
import IslandCore

@MainActor
final class IslandOverlayState: ObservableObject {
    @Published var isExpanded = false
    @Published var usesOpenCanvas = false
    @Published var taskActivity: TaskActivityState = .idle
    @Published var audioPlayback: AudioPlaybackSnapshot = .idle
    @Published var dataPanelMode: DataPanelMode = .defaultMode
    @Published var calibrationCaption: String?
    @Published var completionFeedbackTrigger = 0
    @Published var fileDropFeedbackTrigger = 0
    @Published var fileShelfItems: [TemporaryShelfItem] = []
    @Published var fileShelfSelectedItemIDs: Set<TemporaryShelfItem.ID> = []
    @Published var isFileShelfOverlayVisible = false
    @Published var isFileShelfPinnedOpen = false
    @Published var isFileDropTargetActive = false
}

struct IslandOverlayView: View {
    let metrics: NotchMetrics
    @ObservedObject var state: IslandOverlayState
    let onExpansionChange: @MainActor (Bool) -> Void
    let onFileShelfButtonClick: @MainActor () -> Void
    let onOpenShelfItem: @MainActor (TemporaryShelfItem) -> Void
    let onRemoveShelfItem: @MainActor (TemporaryShelfItem.ID) -> Void
    let onClearShelf: @MainActor () -> Void
    let onDismissFileShelf: @MainActor () -> Void
    let onSelectShelfItem: @MainActor (TemporaryShelfItem.ID) -> Void
    let onClearShelfSelection: @MainActor () -> Void
    let onSelectShelfItems: @MainActor (Set<TemporaryShelfItem.ID>) -> Void
    private let animationProfile = IslandAnimationProfile.default
    @State private var completionBottomEdgeDrop: CGFloat = 0
    @State private var completionBounceTask: Task<Void, Never>?

    init(
        metrics: NotchMetrics,
        state: IslandOverlayState,
        onExpansionChange: @escaping @MainActor (Bool) -> Void = { _ in },
        onFileShelfButtonClick: @escaping @MainActor () -> Void = {},
        onOpenShelfItem: @escaping @MainActor (TemporaryShelfItem) -> Void = { _ in },
        onRemoveShelfItem: @escaping @MainActor (TemporaryShelfItem.ID) -> Void = { _ in },
        onClearShelf: @escaping @MainActor () -> Void = {},
        onDismissFileShelf: @escaping @MainActor () -> Void = {},
        onSelectShelfItem: @escaping @MainActor (TemporaryShelfItem.ID) -> Void = { _ in },
        onClearShelfSelection: @escaping @MainActor () -> Void = {},
        onSelectShelfItems: @escaping @MainActor (Set<TemporaryShelfItem.ID>) -> Void = { _ in }
    ) {
        self.metrics = metrics
        self.state = state
        self.onExpansionChange = onExpansionChange
        self.onFileShelfButtonClick = onFileShelfButtonClick
        self.onOpenShelfItem = onOpenShelfItem
        self.onRemoveShelfItem = onRemoveShelfItem
        self.onClearShelf = onClearShelf
        self.onDismissFileShelf = onDismissFileShelf
        self.onSelectShelfItem = onSelectShelfItem
        self.onClearShelfSelection = onClearShelfSelection
        self.onSelectShelfItems = onSelectShelfItems
    }

    private var isExpanded: Bool {
        state.isExpanded
    }

    private var shellWidth: CGFloat {
        isExpanded ? metrics.openWidth : metrics.closedShellWidth
    }

    private var shellHeight: CGFloat {
        isExpanded ? metrics.openHeight : metrics.closedHeight
    }

    private var shellCanvasHeight: CGFloat {
        isExpanded ? metrics.openCompletionFeedbackWindowSize.height : metrics.closedCompletionFeedbackWindowSize.height
    }

    private var canvasWidth: CGFloat {
        state.usesOpenCanvas ? metrics.openWidth : metrics.closedShellWidth
    }

    private var canvasHeight: CGFloat {
        state.usesOpenCanvas ? metrics.openCompletionFeedbackWindowSize.height : metrics.closedCompletionFeedbackWindowSize.height
    }

    private var topCornerRadius: CGFloat {
        isExpanded ? metrics.openTopCornerRadius : metrics.closedTopCornerRadius
    }

    private var bottomCornerRadius: CGFloat {
        isExpanded ? metrics.openBottomCornerRadius : metrics.closedBottomCornerRadius
    }

    private var statusDotX: CGFloat {
        isExpanded ? topStatusBandLayout.statusDotFrame.midX : metrics.closedStatusDotCenterX
    }

    private var statusDotY: CGFloat {
        isExpanded ? topStatusBandLayout.statusDotFrame.midY : metrics.closedStatusDotCenterY
    }

    private var statusDotHaloDiameter: CGFloat {
        isExpanded ? metrics.expandedStatusDotHaloDiameter : metrics.closedStatusDotHaloDiameter
    }

    private var audioWaveformX: CGFloat {
        isExpanded ? topStatusBandLayout.audioWaveformFrame.midX : metrics.closedAudioWaveformCenterX
    }

    private var audioWaveformY: CGFloat {
        isExpanded ? topStatusBandLayout.audioWaveformFrame.midY : metrics.closedAudioWaveformCenterY
    }

    private var visibleAudioPlayback: AudioPlaybackSnapshot {
        isExpanded ? state.audioPlayback : .idle
    }

    private var topStatusBandLayout: IslandTopStatusBandLayout {
        metrics.expandedTopStatusBandLayout
    }

    private var fileShelfButtonFrame: CGRect {
        topStatusBandLayout.fileShelfButtonFrame(width: 58, height: 22)
    }

    private var hoverExpandAnimation: Animation {
        .interactiveSpring(
            response: animationProfile.expandResponse,
            dampingFraction: animationProfile.expandDampingFraction,
            blendDuration: animationProfile.expandBlendDuration
        )
    }

    private var closeAnimation: Animation {
        .easeOut(duration: animationProfile.collapseDuration)
    }

    private var statusDotTravelAnimation: Animation {
        let curve = isExpanded
            ? animationProfile.attachedElementExpandCurve
            : animationProfile.attachedElementCollapseCurve
        let duration = isExpanded
            ? animationProfile.attachedElementExpandDuration
            : animationProfile.attachedElementCollapseDuration

        return .timingCurve(
            curve.x1,
            curve.y1,
            curve.x2,
            curve.y2,
            duration: duration
        )
    }

    private var expandedHorizontalPadding: CGFloat {
        metrics.expandedHorizontalContentPadding
    }

    var body: some View {
        ZStack(alignment: .top) {
            islandShell

            if let caption = state.calibrationCaption {
                Text(caption)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 10)
                    .frame(height: 18)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.56))
                    }
                    .offset(y: metrics.closedHeight + 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .allowsHitTesting(false)
            }

        }
        .frame(
            width: canvasWidth,
            height: canvasHeight,
            alignment: .top
        )
        .onChange(of: state.completionFeedbackTrigger) { _, newValue in
            guard newValue > 0 else { return }
            playCompletionBounce()
        }
        .onChange(of: state.fileDropFeedbackTrigger) { _, newValue in
            guard newValue > 0 else { return }
            playCompletionBounce()
        }
        .onDisappear {
            completionBounceTask?.cancel()
            completionBounceTask = nil
        }
    }

    private var islandShell: some View {
        ZStack(alignment: .top) {
            Color.black

            StatusDotView(
                activity: state.taskActivity,
                haloDiameter: statusDotHaloDiameter,
                style: metrics.statusDotSoftGlowStyle
            )
                .frame(width: statusDotHaloDiameter, height: statusDotHaloDiameter)
                .position(
                    x: statusDotX,
                    y: statusDotY
                )
                .animation(
                    statusDotTravelAnimation,
                    value: isExpanded
                )
                .zIndex(2)

            AudioWaveformView(snapshot: visibleAudioPlayback)
                .frame(
                    width: topStatusBandLayout.audioWaveformFrame.width,
                    height: topStatusBandLayout.audioWaveformFrame.height
                )
                .position(
                    x: audioWaveformX,
                    y: audioWaveformY
                )
                .opacity(isExpanded ? 1 : 0)
                .scaleEffect(isExpanded ? 1 : animationProfile.audioWaveformCollapsedScale, anchor: .leading)
                .animation(
                    statusDotTravelAnimation,
                    value: isExpanded
                )
                .zIndex(2)

            if state.usesOpenCanvas {
                expandedContent
            }

            if isExpanded && !state.fileShelfItems.isEmpty {
                Button {
                    onFileShelfButtonClick()
                } label: {
                    Text("Files")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black.opacity(0.86))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(width: fileShelfButtonFrame.width, height: fileShelfButtonFrame.height)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.90))
                        }
                }
                .buttonStyle(.plain)
                .position(x: fileShelfButtonFrame.midX, y: fileShelfButtonFrame.midY)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .zIndex(4)
            }
        }
        .frame(width: shellWidth, height: shellCanvasHeight, alignment: .top)
        .clipShape(
            IslandShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius,
                bottomEdgeDrop: completionBottomEdgeDrop,
                baseHeight: shellHeight
            )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isExpanded {
                setExpanded(true)
            }
        }
        .contextMenu {
            Button("Idle") { state.taskActivity = .idle }
            Button("Running") { state.taskActivity = .running }
            Button("Warning") { state.taskActivity = .warning }
            Button("Error") { state.taskActivity = .error }
        }
        .animation(isExpanded ? hoverExpandAnimation : closeAnimation, value: isExpanded)
    }

    @MainActor
    private func setExpanded(_ expanded: Bool) {
        onExpansionChange(expanded)
    }

    @MainActor
    private func playCompletionBounce() {
        completionBounceTask?.cancel()
        completionBounceTask = Task { @MainActor in
            for _ in 0..<CompletionBottomEdgeBounce.repeatCount {
                withAnimation(.easeOut(duration: CompletionBottomEdgeBounce.dropDuration)) {
                    completionBottomEdgeDrop = metrics.closedCompletionBounceDrop
                }
                try? await Task.sleep(nanoseconds: CompletionBottomEdgeBounce.holdNanoseconds)
                guard !Task.isCancelled else { return }

                withAnimation(.easeOut(duration: CompletionBottomEdgeBounce.returnDuration)) {
                    completionBottomEdgeDrop = 0
                }
                try? await Task.sleep(nanoseconds: CompletionBottomEdgeBounce.restNanoseconds)
                guard !Task.isCancelled else { return }
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: metrics.expandedContentTopSpacerHeight)

            ZStack {
                DataPanelView(mode: $state.dataPanelMode)
                    .opacity(state.isFileShelfOverlayVisible || state.isFileDropTargetActive ? 0 : 1)
                    .allowsHitTesting(!(state.isFileShelfOverlayVisible || state.isFileDropTargetActive))

                if state.isFileShelfOverlayVisible || state.isFileDropTargetActive {
                    TemporaryFileShelfView(
                        items: state.fileShelfItems,
                        selectedItemIDs: state.fileShelfSelectedItemIDs,
                        isDropTargetActive: state.isFileDropTargetActive,
                        onOpen: onOpenShelfItem,
                        onRemove: onRemoveShelfItem,
                        onClear: onClearShelf,
                        onDismiss: onDismissFileShelf,
                        onSelectItem: onSelectShelfItem,
                        onClearSelection: onClearShelfSelection,
                        onSelectItems: onSelectShelfItems
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, expandedHorizontalPadding)
        .padding(.bottom, metrics.expandedContentBottomGuard)
        .frame(width: shellWidth, height: shellHeight, alignment: .topLeading)
        .opacity(isExpanded ? 1 : 0)
        .scaleEffect(isExpanded ? 1 : animationProfile.expandedContentScale, anchor: .top)
        .allowsHitTesting(isExpanded)
    }
}

private enum CompletionBottomEdgeBounce {
    static let repeatCount = 2
    static let dropDuration = 0.07
    static let returnDuration = 0.11
    static let holdNanoseconds: UInt64 = 90_000_000
    static let restNanoseconds: UInt64 = 100_000_000
}
