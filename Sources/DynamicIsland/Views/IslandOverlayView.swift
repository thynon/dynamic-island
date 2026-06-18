import AppKit
import SwiftUI
import DynamicIslandCore

enum IslandPrimaryFeature: String, CaseIterable, Equatable, Identifiable {
    case tasks
    case data
    case tools
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks:
            "Tasks"
        case .data:
            "Data"
        case .tools:
            "Tools"
        case .settings:
            "Settings"
        }
    }
}

@MainActor
final class IslandOverlayState: ObservableObject {
    @Published var isExpanded = false
    @Published var usesOpenCanvas = false
    @Published var isShellHidden = false
    @Published var isHovered = false
    @Published var isTrackInfoPresented = false
    @Published var musicSkipFeedbackDirection: MusicSkipDirection?
    @Published var musicSkipGestureProgress: CGFloat = 0
    @Published var isMusicSkipArmed = false
    @Published var isCalibrationOverlayVisible = false
    @Published var calibrationHasCameraHousing = false
    @Published var musicPlayback: MusicPlaybackSnapshot = .idle
    @Published var temporaryFileShelf = TemporaryFileShelf()
    @Published var temporaryFileShelfSelectedItemIDs: Set<TemporaryShelfItem.ID> = []
    @Published var temporaryFileShelfFilter: TemporaryFileShelfFilter = .all
    @Published var isFileShelfOverlayVisible = false
    @Published var isFileShelfPinnedOpen = false
    @Published var isFileDropTargetActive = false
    @Published var selectedPrimaryFeature: IslandPrimaryFeature = .tasks
}

struct IslandOverlayView: View {
    let metrics: NotchMetrics
    @ObservedObject var state: IslandOverlayState
    let onExpansionChange: @MainActor (Bool) -> Void
    let onSelectTemporaryFile: @MainActor (TemporaryShelfItem.ID, Bool) -> Void
    let onSelectTemporaryFiles: @MainActor ([TemporaryShelfItem.ID], Bool) -> Void
    let onRemoveTemporaryFile: @MainActor (TemporaryShelfItem.ID) -> Void
    let onClearTemporaryFiles: @MainActor () -> Void
    let onStartTemporaryFileDrag: @MainActor ([TemporaryShelfItem.ID]) -> Void
    let onCompleteTemporaryFileDrag: @MainActor ([TemporaryShelfItem.ID], Bool) -> Void
    let onChangeTemporaryFileFilter: @MainActor (TemporaryFileShelfFilter) -> Void
    let onClearTemporaryFileSelection: @MainActor () -> Void
    let onToggleFileShelfOverlay: @MainActor () -> Void
    let onDoneFileShelfOverlay: @MainActor () -> Void

    private let animationProfile = IslandAnimationProfile.default
    private let closedHoverHorizontalSlack: CGFloat = 22
    private let closedHoverBottomSlack: CGFloat = 10
    private let musicSkipEdgeExpansionMax: CGFloat = 50
    private let musicSkipIconSize: CGFloat = 18
    private let trackInfoTextCenterY: CGFloat = 55

    init(
        metrics: NotchMetrics,
        state: IslandOverlayState,
        onExpansionChange: @escaping @MainActor (Bool) -> Void = { _ in },
        onSelectTemporaryFile: @escaping @MainActor (TemporaryShelfItem.ID, Bool) -> Void = { _, _ in },
        onSelectTemporaryFiles: @escaping @MainActor ([TemporaryShelfItem.ID], Bool) -> Void = { _, _ in },
        onRemoveTemporaryFile: @escaping @MainActor (TemporaryShelfItem.ID) -> Void = { _ in },
        onClearTemporaryFiles: @escaping @MainActor () -> Void = {},
        onStartTemporaryFileDrag: @escaping @MainActor ([TemporaryShelfItem.ID]) -> Void = { _ in },
        onCompleteTemporaryFileDrag: @escaping @MainActor ([TemporaryShelfItem.ID], Bool) -> Void = { _, _ in },
        onChangeTemporaryFileFilter: @escaping @MainActor (TemporaryFileShelfFilter) -> Void = { _ in },
        onClearTemporaryFileSelection: @escaping @MainActor () -> Void = {},
        onToggleFileShelfOverlay: @escaping @MainActor () -> Void = {},
        onDoneFileShelfOverlay: @escaping @MainActor () -> Void = {}
    ) {
        self.metrics = metrics
        self.state = state
        self.onExpansionChange = onExpansionChange
        self.onSelectTemporaryFile = onSelectTemporaryFile
        self.onSelectTemporaryFiles = onSelectTemporaryFiles
        self.onRemoveTemporaryFile = onRemoveTemporaryFile
        self.onClearTemporaryFiles = onClearTemporaryFiles
        self.onStartTemporaryFileDrag = onStartTemporaryFileDrag
        self.onCompleteTemporaryFileDrag = onCompleteTemporaryFileDrag
        self.onChangeTemporaryFileFilter = onChangeTemporaryFileFilter
        self.onClearTemporaryFileSelection = onClearTemporaryFileSelection
        self.onToggleFileShelfOverlay = onToggleFileShelfOverlay
        self.onDoneFileShelfOverlay = onDoneFileShelfOverlay
    }

    private var isExpanded: Bool {
        state.isExpanded
    }

    private var shellWidth: CGFloat {
        isExpanded ? metrics.openWidth : closedShellWidth + musicSkipEdgeExpansion
    }

    private var closedShellWidth: CGFloat {
        showsMusicAccessories ? metrics.musicClosedShellWidth : metrics.closedShellWidth
    }

    private var closedCanvasHorizontalSlack: CGFloat {
        max(closedHoverHorizontalSlack, musicSkipEdgeExpansionMax * 2)
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
        state.usesOpenCanvas ? metrics.openWidth : metrics.musicClosedShellWidth + closedCanvasHorizontalSlack
    }

    private var canvasHeight: CGFloat {
        state.usesOpenCanvas ? metrics.openCanvasWindowSize.height : metrics.musicTrackInfoShellHeight + closedHoverBottomSlack
    }

    private var showsHoverPreview: Bool {
        (state.isHovered || (state.isFileDropTargetActive && !isExpanded)) && !isExpanded && !state.isShellHidden
    }

    private var hoverPreviewScale: CGFloat {
        showsHoverPreview ? 1.035 : 1
    }

    private var hoverShadowOpacity: Double {
        showsHoverPreview ? 0.12 : 0
    }

    private var shellFillColor: Color {
        .black
    }

    private var foregroundContentColor: Color {
        .white
    }

    private var musicSkipProgress: CGFloat {
        guard state.musicSkipFeedbackDirection != nil, showsMusicAccessories, !showsTrackInfo, !isExpanded else {
            return 0
        }
        return min(1, max(0, state.musicSkipGestureProgress))
    }

    private var musicSkipEdgeExpansion: CGFloat {
        musicSkipEdgeExpansionMax * musicSkipProgress
    }

    private var shellHorizontalScale: CGFloat {
        hoverPreviewScale * hiddenShellHorizontalScale
    }

    private var shellHorizontalOffset: CGFloat {
        guard let direction = state.musicSkipFeedbackDirection else { return 0 }
        let scaledExpansion = musicSkipEdgeExpansion * shellHorizontalScale
        return direction == .next ? scaledExpansion / 2 : -scaledExpansion / 2
    }

    private var contentOriginShiftX: CGFloat {
        switch state.musicSkipFeedbackDirection {
        case .previous:
            musicSkipEdgeExpansion
        case .next:
            0
        case nil:
            0
        }
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
        (isExpanded ? metrics.expandedMusicArtworkCenterX : metrics.closedLeftMusicAccessoryCenterX) + contentOriginShiftX
    }

    private var musicWaveformCenterX: CGFloat {
        (isExpanded ? metrics.expandedMusicWaveformCenterX : metrics.closedRightMusicAccessoryCenterX) + contentOriginShiftX
    }

    private var musicAccessoryCenterY: CGFloat {
        isExpanded ? metrics.expandedMusicAccessoryCenterY : metrics.closedMusicAccessoryCenterY
    }

    private var musicArtworkCenterY: CGFloat {
        showsTrackInfo ? 50 : musicAccessoryCenterY
    }

    private func musicSkipFeedbackCenterX(for direction: MusicSkipDirection) -> CGFloat {
        let minimumCenterX = metrics.closedTopCornerRadius + metrics.closedMusicAccessoryGuardInset + (musicSkipIconSize / 2)

        switch direction {
        case .previous:
            return minimumCenterX
        case .next:
            return metrics.musicClosedShellWidth + musicSkipEdgeExpansion - minimumCenterX
        }
    }

    private func musicSkipFeedbackIcon(_ direction: MusicSkipDirection) -> some View {
        let progress = min(1, max(0, state.musicSkipGestureProgress))
        return MusicSkipGlyph(direction: direction)
            .frame(width: musicSkipIconSize, height: musicSkipIconSize)
            .opacity(Double(state.isMusicSkipArmed ? 1 : progress))
            .scaleEffect(state.isMusicSkipArmed ? 1.08 : 0.86 + (progress * 0.12))
            .position(
                x: musicSkipFeedbackCenterX(for: direction),
                y: musicAccessoryCenterY
            )
            .zIndex(3)
            .accessibilityHidden(true)
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

    private var expandedTemporaryShelfWidth: CGFloat {
        metrics.openWidth
    }

    private var expandedTemporaryShelfHeight: CGFloat {
        metrics.openHeight - metrics.closedHeight - metrics.expandedContentBottomGuard - 8
    }

    private var expandedTemporaryShelfCenterY: CGFloat {
        metrics.closedHeight + 4 + (expandedTemporaryShelfHeight / 2)
    }

    private var fileShelfButtonFrame: CGRect {
        metrics.expandedTopStatusBandLayout.fileShelfButtonFrame(width: 68, height: 22)
    }

    private var primaryNavigationFrame: CGRect {
        metrics.expandedTopStatusBandLayout.primaryNavigationFrame(width: 168, height: 22)
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
            shellFillColor

            if isExpanded {
                PrimaryFeatureSwitcher(selection: $state.selectedPrimaryFeature)
                    .frame(width: primaryNavigationFrame.width, height: primaryNavigationFrame.height)
                    .position(x: primaryNavigationFrame.midX, y: primaryNavigationFrame.midY)
                    .zIndex(4)
            }

            if isExpanded, state.temporaryFileShelf.hasItems {
                FileShelfButton(
                    count: state.temporaryFileShelf.items.count,
                    isActive: state.isFileShelfOverlayVisible,
                    action: onToggleFileShelfOverlay
                )
                .frame(width: fileShelfButtonFrame.width, height: fileShelfButtonFrame.height)
                .position(x: fileShelfButtonFrame.midX, y: fileShelfButtonFrame.midY)
                .zIndex(4)
            }

            if isExpanded, state.isFileShelfOverlayVisible {
                FileShelfOverlayView(
                    shelf: state.temporaryFileShelf,
                    filter: state.temporaryFileShelfFilter,
                    selectedItemIDs: state.temporaryFileShelfSelectedItemIDs,
                    isDropTargetActive: state.isFileDropTargetActive,
                    onFilterChange: onChangeTemporaryFileFilter,
                    onDone: onDoneFileShelfOverlay,
                    onClearSelection: onClearTemporaryFileSelection,
                    onSelectItem: onSelectTemporaryFile,
                    onSelectItems: onSelectTemporaryFiles,
                    onRemoveItem: onRemoveTemporaryFile,
                    onClear: onClearTemporaryFiles,
                    onDragStarted: onStartTemporaryFileDrag,
                    onDragCompleted: onCompleteTemporaryFileDrag,
                    contentBoundaryInset: metrics.expandedContentGuardInset,
                    topBoundaryInset: metrics.expandedHorizontalContentPadding
                )
                .frame(width: expandedTemporaryShelfWidth, height: expandedTemporaryShelfHeight)
                .position(x: metrics.openWidth / 2, y: expandedTemporaryShelfCenterY)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(3)
            }

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
                    .foregroundStyle(foregroundContentColor)
                    .multilineTextAlignment(.center)
                    .frame(width: 190, alignment: .center)
                    .position(x: (metrics.musicClosedShellWidth / 2) + contentOriginShiftX, y: trackInfoTextCenterY)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if let direction = state.musicSkipFeedbackDirection, showsMusicAccessories, !showsTrackInfo {
                musicSkipFeedbackIcon(direction)
            }

            if state.isCalibrationOverlayVisible {
                CalibrationOverlayView(
                    layout: IslandCalibrationLayout(metrics: metrics, hasCameraHousing: state.calibrationHasCameraHousing),
                    metrics: metrics,
                    shellWidth: shellWidth,
                    shellHeight: shellHeight,
                    isExpanded: isExpanded,
                    isMusicShell: showsMusicAccessories,
                    hasCameraHousing: state.calibrationHasCameraHousing
                )
                .zIndex(20)
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
            .offset(x: shellHorizontalOffset)
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
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.82), value: state.musicSkipGestureProgress)
            .animation(.easeInOut(duration: 0.16), value: state.musicSkipFeedbackDirection)
            .animation(.easeInOut(duration: 0.22), value: state.isShellHidden)
            .animation(.easeOut(duration: 0.14), value: state.isHovered)
            .animation(.easeOut(duration: 0.14), value: state.isFileDropTargetActive)
            .animation(.easeOut(duration: 0.14), value: state.isFileShelfOverlayVisible)
    }
}

private struct CalibrationOverlayView: View {
    let layout: IslandCalibrationLayout
    let metrics: NotchMetrics
    let shellWidth: CGFloat
    let shellHeight: CGFloat
    let isExpanded: Bool
    let isMusicShell: Bool
    let hasCameraHousing: Bool

    private let calibrationSafeRegionYOffset: CGFloat = 2

    private var contentBoundaryFrame: CGRect {
        CGRect(x: 0, y: 0, width: shellWidth, height: shellHeight)
            .insetBy(dx: metrics.contentBoundaryInset, dy: metrics.contentBoundaryInset)
    }

    private var currentCameraHousingForbiddenRegion: CGRect? {
        guard hasCameraHousing else { return nil }
        if isExpanded {
            return layout.cameraHousingForbiddenRegion
        }
        let minX = isMusicShell ? metrics.musicCameraHousingLeftEdgeX : metrics.cameraHousingLeftEdgeX
        return CGRect(x: minX, y: 0, width: metrics.cameraHousingWidth, height: metrics.closedHeight)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            IslandShape(
                topCornerRadius: isExpanded ? metrics.openTopCornerRadius : metrics.closedTopCornerRadius,
                concaveTopRadius: isExpanded ? metrics.openTopCornerRadius : metrics.closedConcaveTopRadius,
                bottomCornerRadius: isExpanded ? metrics.openBottomCornerRadius : metrics.closedBottomCornerRadius,
                baseHeight: shellHeight
            )
            .stroke(Color.white.opacity(0.75), lineWidth: 1)
            .frame(width: shellWidth, height: shellHeight)

            calibrationBoundaryRect(contentBoundaryFrame)

            if isExpanded {
                calibrationRect(
                    layout.leftSafeRegion.offsetBy(dx: 0, dy: calibrationSafeRegionYOffset),
                    color: .green,
                    fillOpacity: 0.06,
                    dash: [3, 2]
                )
                calibrationRect(
                    layout.rightSafeRegion.offsetBy(dx: 0, dy: calibrationSafeRegionYOffset),
                    color: .cyan,
                    fillOpacity: 0.06,
                    dash: [3, 2]
                )
            }

            if let cameraHousingForbiddenRegion = currentCameraHousingForbiddenRegion {
                calibrationRect(cameraHousingForbiddenRegion, color: .red, fillOpacity: 0.18, dash: [])
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(hasCameraHousing ? "Camera housing" : "No camera housing")
                Text("5pt content boundary  shell \(Int(shellWidth))x\(Int(shellHeight))")
                Text("camera \(Int(metrics.cameraHousingWidth))  open \(Int(metrics.openWidth))x\(Int(metrics.openHeight))")
            }
            .font(.system(size: 7, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .position(x: min(shellWidth - 74, max(74, shellWidth / 2)), y: max(14, shellHeight - 18))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func calibrationRect(
        _ rect: CGRect,
        color: Color,
        fillOpacity: Double,
        dash: [CGFloat]
    ) -> some View {
        Rectangle()
            .fill(color.opacity(fillOpacity))
            .overlay(
                Rectangle()
                    .strokeBorder(color.opacity(0.72), style: StrokeStyle(lineWidth: 1, dash: dash))
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func calibrationBoundaryRect(_ rect: CGRect) -> some View {
        Rectangle()
            .fill(Color.yellow.opacity(0.03))
            .overlay(
                Rectangle()
                    .strokeBorder(
                        Color.yellow.opacity(0.95),
                        style: StrokeStyle(lineWidth: 1.25, dash: [5, 3])
                    )
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

private struct PrimaryFeatureSwitcher: View {
    @Binding var selection: IslandPrimaryFeature

    var body: some View {
        HStack(spacing: 2) {
            ForEach(IslandPrimaryFeature.allCases) { feature in
                Button {
                    selection = feature
                } label: {
                    Text(feature.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selection == feature ? .white.opacity(0.16) : .white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct FileShelfButton: View {
    let count: Int
    let isActive: Bool
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "tray.full")
                    .font(.system(size: 10, weight: .semibold))
                Text("Files")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .opacity(0.62)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(isActive ? 0.16 : 0.08))
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("Files")
    }
}

private struct MusicSkipGlyph: View {
    let direction: MusicSkipDirection

    var body: some View {
        Image(systemName: direction == .next ? "forward.end.fill" : "backward.end.fill")
            .font(.system(size: 15, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white)
        .frame(width: 18, height: 18)
    }
}
