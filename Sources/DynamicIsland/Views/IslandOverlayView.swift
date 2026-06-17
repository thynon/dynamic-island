import SwiftUI
import DynamicIslandCore

@MainActor
final class IslandOverlayState: ObservableObject {
    @Published var isExpanded = false
    @Published var usesOpenCanvas = false
    @Published var isHovered = false
    @Published var musicPlayback: MusicPlaybackSnapshot = .idle
}

struct IslandOverlayView: View {
    let metrics: NotchMetrics
    @ObservedObject var state: IslandOverlayState
    let onExpansionChange: @MainActor (Bool) -> Void

    private let animationProfile = IslandAnimationProfile.default
    private let closedHoverHorizontalSlack: CGFloat = 22
    private let closedHoverBottomSlack: CGFloat = 10

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
        isExpanded ? metrics.openWidth : closedShellWidth
    }

    private var closedShellWidth: CGFloat {
        showsClosedMusicAccessories ? metrics.musicClosedShellWidth : metrics.closedShellWidth
    }

    private var shellHeight: CGFloat {
        isExpanded ? metrics.openHeight : metrics.closedHeight
    }

    private var canvasWidth: CGFloat {
        state.usesOpenCanvas ? metrics.openWidth : metrics.musicClosedShellWidth + closedHoverHorizontalSlack
    }

    private var canvasHeight: CGFloat {
        state.usesOpenCanvas ? metrics.openCompletionFeedbackWindowSize.height : metrics.closedHeight + closedHoverBottomSlack
    }

    private var showsHoverPreview: Bool {
        state.isHovered && !isExpanded
    }

    private var hoverPreviewScale: CGFloat {
        showsHoverPreview ? 1.035 : 1
    }

    private var hoverShadowOpacity: Double {
        showsHoverPreview ? 0.12 : 0
    }

    private var showsClosedMusicAccessories: Bool {
        state.musicPlayback.isPlaying && !isExpanded
    }

    private var topCornerRadius: CGFloat {
        isExpanded ? metrics.openTopCornerRadius : metrics.closedTopCornerRadius
    }

    private var bottomCornerRadius: CGFloat {
        isExpanded ? metrics.openBottomCornerRadius : metrics.closedBottomCornerRadius
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

    var body: some View {
        islandShell
            .frame(width: canvasWidth, height: canvasHeight, alignment: .top)
    }

    private var islandShell: some View {
        ZStack(alignment: .topLeading) {
            Color.white

            if showsClosedMusicAccessories {
                ClosedMusicAvatarView(artworkData: state.musicPlayback.artworkData)
                    .frame(width: metrics.closedMusicAccessorySize, height: metrics.closedMusicAccessorySize)
                    .position(
                        x: metrics.closedLeftMusicAccessoryCenterX,
                        y: metrics.closedMusicAccessoryCenterY
                    )

                ClosedMusicWaveformView(snapshot: state.musicPlayback.waveform)
                    .frame(width: metrics.closedMusicAccessorySize, height: metrics.closedMusicAccessorySize)
                    .position(
                        x: metrics.closedRightMusicAccessoryCenterX,
                        y: metrics.closedMusicAccessoryCenterY
                    )
            }
        }
            .frame(width: shellWidth, height: shellHeight, alignment: .top)
            .clipShape(
                IslandShape(
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius,
                    baseHeight: shellHeight
                )
            )
            .contentShape(Rectangle())
            .scaleEffect(hoverPreviewScale, anchor: .top)
            .shadow(
                color: .black.opacity(hoverShadowOpacity),
                radius: showsHoverPreview ? 6 : 0,
                x: 0,
                y: showsHoverPreview ? 1 : 0
            )
            .onTapGesture {
                if !isExpanded {
                    onExpansionChange(true)
                }
            }
            .animation(isExpanded ? expandAnimation : collapseAnimation, value: isExpanded)
            .animation(.easeInOut(duration: 0.18), value: state.musicPlayback.isPlaying)
            .animation(.easeOut(duration: 0.14), value: state.isHovered)
    }
}
