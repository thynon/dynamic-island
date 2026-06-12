import SwiftUI
import IslandCore

@MainActor
final class IslandOverlayState: ObservableObject {
    @Published var isExpanded = false
    @Published var usesOpenCanvas = false
    @Published var taskActivity: TaskActivityState = .idle
    @Published var dataPanelMode: DataPanelMode = .defaultMode
}

struct IslandOverlayView: View {
    let metrics: NotchMetrics
    @ObservedObject var state: IslandOverlayState
    let onExpansionChange: @MainActor (Bool) -> Void

    init(
        metrics: NotchMetrics,
        state: IslandOverlayState,
        onExpansionChange: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.metrics = metrics
        self.state = state
        self.onExpansionChange = onExpansionChange
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

    private var canvasWidth: CGFloat {
        state.usesOpenCanvas ? metrics.openWidth : metrics.closedShellWidth
    }

    private var canvasHeight: CGFloat {
        state.usesOpenCanvas ? metrics.openHeight : metrics.closedHeight
    }

    private var topCornerRadius: CGFloat {
        isExpanded ? metrics.openTopCornerRadius : metrics.closedTopCornerRadius
    }

    private var bottomCornerRadius: CGFloat {
        isExpanded ? metrics.openBottomCornerRadius : metrics.closedBottomCornerRadius
    }

    private var statusDotX: CGFloat {
        isExpanded ? metrics.expandedStatusDotCenterX : metrics.closedStatusDotCenterX
    }

    private var statusDotY: CGFloat {
        isExpanded ? metrics.expandedStatusDotCenterY : metrics.closedStatusDotCenterY
    }

    private var statusDotHaloDiameter: CGFloat {
        isExpanded ? metrics.expandedStatusDotHaloDiameter : metrics.closedStatusDotHaloDiameter
    }

    private var hoverExpandAnimation: Animation {
        .interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    }

    private var closeAnimation: Animation {
        .easeOut(duration: 0.14)
    }

    private var statusDotTravelAnimation: Animation {
        isExpanded
            ? .timingCurve(0.18, 0.86, 0.22, 1.0, duration: 0.34)
            : .timingCurve(0.20, 0.82, 0.22, 1.0, duration: 0.14)
    }

    private var expandedHorizontalPadding: CGFloat {
        metrics.expandedHorizontalContentPadding
    }

    var body: some View {
        ZStack(alignment: .top) {
            islandShell
        }
        .frame(
            width: canvasWidth,
            height: canvasHeight,
            alignment: .top
        )
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

            if state.usesOpenCanvas {
                expandedContent
            }
        }
        .frame(width: shellWidth, height: shellHeight, alignment: .top)
        .clipShape(
            IslandShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
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

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: metrics.expandedContentTopSpacerHeight)

            DataPanelView(mode: $state.dataPanelMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, expandedHorizontalPadding)
        .padding(.bottom, metrics.expandedContentBottomGuard)
        .frame(width: shellWidth, height: shellHeight, alignment: .topLeading)
        .opacity(isExpanded ? 1 : 0)
        .scaleEffect(isExpanded ? 1 : 0.88, anchor: .top)
        .allowsHitTesting(isExpanded)
    }
}
