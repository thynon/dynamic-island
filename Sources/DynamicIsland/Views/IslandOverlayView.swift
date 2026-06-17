import AppKit
import SwiftUI
import DynamicIslandCore

@MainActor
final class IslandOverlayState: ObservableObject {
    @Published var isExpanded = false
    @Published var usesOpenCanvas = false
    @Published var isShellHidden = false
    @Published var isHovered = false
    @Published var isTrackInfoPresented = false
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
        showsMusicAccessories ? metrics.musicClosedShellWidth : metrics.closedShellWidth
    }

    private var shellHeight: CGFloat {
        if isExpanded {
            metrics.openHeight
        } else if showsTrackInfo {
            metrics.musicTrackInfoShellHeight
        } else {
            metrics.closedHeight
        }
    }

    private var canvasWidth: CGFloat {
        state.usesOpenCanvas ? metrics.openWidth : metrics.musicClosedShellWidth + closedHoverHorizontalSlack
    }

    private var canvasHeight: CGFloat {
        state.usesOpenCanvas ? metrics.openCompletionFeedbackWindowSize.height : metrics.musicTrackInfoShellHeight + closedHoverBottomSlack
    }

    private var showsHoverPreview: Bool {
        state.isHovered && !isExpanded && !state.isShellHidden
    }

    private var hoverPreviewScale: CGFloat {
        showsHoverPreview ? 1.035 : 1
    }

    private var hoverShadowOpacity: Double {
        showsHoverPreview ? 0.12 : 0
    }

    private var showsMusicAccessories: Bool {
        state.musicPlayback.isPlaying && !state.isShellHidden && metrics.closedMusicAccessorySize > 0
    }

    private var showsTrackInfo: Bool {
        showsMusicAccessories && !isExpanded && state.isTrackInfoPresented
    }

    private var musicArtworkSize: CGFloat {
        showsTrackInfo ? 36 : metrics.closedMusicAccessorySize
    }

    private var musicArtworkCenterX: CGFloat {
        isExpanded ? metrics.expandedMusicArtworkCenterX : metrics.closedLeftMusicAccessoryCenterX
    }

    private var musicWaveformCenterX: CGFloat {
        isExpanded ? metrics.expandedMusicWaveformCenterX : metrics.closedRightMusicAccessoryCenterX
    }

    private var musicAccessoryCenterY: CGFloat {
        isExpanded ? metrics.expandedMusicAccessoryCenterY : metrics.closedMusicAccessoryCenterY
    }

    private var musicArtworkCenterY: CGFloat {
        showsTrackInfo ? 47 : musicAccessoryCenterY
    }

    private var trackTitleText: String {
        state.musicPlayback.title.isEmpty ? "Unknown Track" : state.musicPlayback.title
    }

    private var trackArtistText: String {
        state.musicPlayback.artist.isEmpty ? "Unknown Artist" : state.musicPlayback.artist
    }

    private var hiddenShellOpacity: Double {
        state.isShellHidden ? 0 : 1
    }

    private var hiddenShellHorizontalScale: CGFloat {
        state.isShellHidden ? 0.04 : 1
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

            if showsMusicAccessories {
                ClosedMusicAvatarView(artworkData: state.musicPlayback.artworkData)
                    .frame(width: musicArtworkSize, height: musicArtworkSize)
                    .position(
                        x: musicArtworkCenterX,
                        y: musicArtworkCenterY
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.72)))

                ClosedMusicWaveformView(snapshot: state.musicPlayback.waveform)
                    .frame(width: metrics.closedMusicAccessorySize, height: metrics.closedMusicAccessorySize)
                    .position(
                        x: musicWaveformCenterX,
                        y: musicAccessoryCenterY
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.72)))

                if showsTrackInfo {
                    VStack(alignment: .center, spacing: 2) {
                        Text(trackTitleText)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(trackArtistText)
                            .font(.system(size: 10, weight: .regular))
                            .lineLimit(1)
                            .opacity(0.68)
                    }
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .frame(width: 190, alignment: .center)
                    .position(x: metrics.musicClosedShellWidth / 2, y: 49)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
            .frame(width: shellWidth, height: shellHeight, alignment: .top)
            .clipShape(
                IslandShape(
                    topCornerRadius: isExpanded ? metrics.openTopCornerRadius : metrics.closedTopCornerRadius,
                    concaveTopRadius: isExpanded ? metrics.openTopCornerRadius : metrics.closedConcaveTopRadius,
                    bottomCornerRadius: isExpanded ? metrics.openBottomCornerRadius : metrics.closedBottomCornerRadius,
                    baseHeight: shellHeight
                )
            )
            .contentShape(Rectangle())
            .allowsHitTesting(!state.isShellHidden)
            .scaleEffect(hoverPreviewScale, anchor: .top)
            .scaleEffect(x: hiddenShellHorizontalScale, y: 1, anchor: .top)
            .opacity(hiddenShellOpacity)
            .shadow(
                color: .black.opacity(hoverShadowOpacity),
                radius: showsHoverPreview ? 6 : 0,
                x: 0,
                y: showsHoverPreview ? 1 : 0
            )
            .onTapGesture {
                if !isExpanded && !state.isShellHidden {
                    onExpansionChange(true)
                }
            }
            .animation(isExpanded ? expandAnimation : collapseAnimation, value: isExpanded)
            .animation(.easeInOut(duration: 0.18), value: state.musicPlayback.isPlaying)
            .animation(.easeInOut(duration: 0.22), value: showsMusicAccessories)
            .animation(.linear(duration: 0.22), value: state.isTrackInfoPresented)
            .animation(.easeInOut(duration: 0.22), value: state.isShellHidden)
            .animation(.easeOut(duration: 0.14), value: state.isHovered)
    }
}
