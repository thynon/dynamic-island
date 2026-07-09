import AppKit
import SwiftUI
import DynamicIslandCore

struct IslandOverlayView: View {
    let metrics: NotchMetrics
    @ObservedObject var state: IslandOverlayState
    let onExpansionChange: @MainActor (Bool) -> Void
    let fileShelfActions: FileShelfActions
    @State private var isTopBandEnergyActive = false
    @State private var topBandEnergyActivationSequence = 0

    private let animationProfile = IslandAnimationProfile.default
    private let musicSkipIconSize: CGFloat = 18
    private let trackInfoTextCenterY: CGFloat = 55

    init(
        metrics: NotchMetrics,
        state: IslandOverlayState,
        onExpansionChange: @escaping @MainActor (Bool) -> Void = { _ in },
        fileShelfActions: FileShelfActions = FileShelfActions()
    ) {
        self.metrics = metrics
        self.state = state
        self.onExpansionChange = onExpansionChange
        self.fileShelfActions = fileShelfActions
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
        NotchMetrics.closedCanvasHorizontalSlack
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
        state.usesOpenCanvas ? metrics.openCanvasWindowSize.height : metrics.musicTrackInfoShellHeight + NotchMetrics.closedHoverBottomSlack
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
        NotchMetrics.musicSkipEdgeExpansionMax * musicSkipProgress
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

    private var filesPrimaryFeatureFrame: CGRect {
        metrics.expandedTopStatusBandLayout.fileShelfButtonFrame(width: 30, height: 22)
    }

    private var primaryNavigationFrame: CGRect {
        metrics.expandedTopStatusBandLayout.primaryNavigationFrame(width: 168, height: 22)
    }

    private var primaryContentFrame: CGRect {
        metrics.expandedPrimaryContentLayout.tasksContentFrame
    }

    private var filesPrimaryContentFrame: CGRect {
        metrics.expandedPrimaryContentLayout.filesContentFrame
    }

    private var topBandEnergyFrame: CGRect {
        let layout = metrics.expandedTopStatusBandLayout
        return CGRect(
            x: layout.rightInfoRegion.minX,
            y: 0,
            width: metrics.openWidth - layout.rightInfoRegion.minX,
            height: layout.bandHeight
        )
    }

    private var topBandEnergyActivationDelay: TimeInterval {
        animationProfile.expandResponse + 0.08
    }

    private var primaryFeatureEntranceOffsetY: CGFloat {
        primaryNavigationFrame.height + metrics.openTopCornerRadius
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

    private var primaryFeatureEntranceAnimation: Animation {
        guard isExpanded else {
            return .easeOut(duration: animationProfile.attachedElementCollapseDuration)
        }

        let animation = Animation.spring(
            response: animationProfile.primaryFeatureEntranceResponse,
            dampingFraction: animationProfile.primaryFeatureEntranceDampingFraction,
            blendDuration: animationProfile.primaryFeatureEntranceBlendDuration
        )

        guard animationProfile.primaryFeatureEntranceStartDelay > 0 else {
            return animation
        }

        return animation.delay(animationProfile.primaryFeatureEntranceStartDelay)
    }

    var body: some View {
        islandShell
            .frame(width: canvasWidth, height: canvasHeight, alignment: .top)
    }

    private var islandShell: some View {
        ZStack(alignment: .topLeading) {
            shellFillColor

            if isExpanded && state.isTopBandEnergyEffectEnabled && isTopBandEnergyActive {
                TopBandEnergyEffectView()
                    .frame(width: topBandEnergyFrame.width, height: topBandEnergyFrame.height)
                    .position(x: topBandEnergyFrame.midX, y: topBandEnergyFrame.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            PrimaryFeatureSwitcher(
                selection: $state.selectedPrimaryFeature,
                isExpanded: isExpanded,
                animationProfile: animationProfile
            )
                .frame(width: primaryNavigationFrame.width, height: primaryNavigationFrame.height)
                .position(x: primaryNavigationFrame.midX, y: primaryNavigationFrame.midY)
                .allowsHitTesting(isExpanded)
                .zIndex(4)

            FilesPrimaryFeatureButton(
                count: state.temporaryFileShelf.items.count,
                isSelected: state.selectedPrimaryFeature == .files,
                isExpanded: isExpanded
            ) {
                fileShelfActions.onOpenFilesPrimaryFeature()
            }
            .frame(width: filesPrimaryFeatureFrame.width, height: filesPrimaryFeatureFrame.height)
            .position(x: filesPrimaryFeatureFrame.midX, y: filesPrimaryFeatureFrame.midY)
            .allowsHitTesting(isExpanded)
            .zIndex(4)

            if isExpanded && state.selectedPrimaryFeature == .tasks && state.isCalibrationOverlayVisible {
                CodexTasksContentView(snapshot: state.codexStatusBarSnapshot)
                    .frame(width: primaryContentFrame.width, height: primaryContentFrame.height)
                    .position(x: primaryContentFrame.midX, y: primaryContentFrame.midY)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(21)
            }

            if isExpanded && state.selectedPrimaryFeature == .files {
                FilesPrimaryContentView(
                    shelf: state.temporaryFileShelf,
                    selectedItemIDs: state.temporaryFileShelfSelectedItemIDs,
                    airDropUndoItemCount: state.airDropUndoItemCount,
                    isDropTargetActive: state.isFileDropTargetActive,
                    displayMode: state.filesDisplayMode,
                    onAirDrop: fileShelfActions.onAirDropItems,
                    onUndoAirDrop: fileShelfActions.onUndoAirDropItems,
                    onDisplayModeChange: fileShelfActions.onSetFilesDisplayMode,
                    onRemoveItems: fileShelfActions.onRemoveItems,
                    onSelectItem: fileShelfActions.onSelectItem,
                    onDragStarted: fileShelfActions.onDragStarted,
                    onDragCompleted: fileShelfActions.onDragCompleted
                )
                .frame(width: filesPrimaryContentFrame.width, height: filesPrimaryContentFrame.height)
                .position(x: filesPrimaryContentFrame.midX, y: filesPrimaryContentFrame.midY)
                .transition(.opacity)
                .zIndex(2)
            }

            if isExpanded, state.isFileShelfOverlayVisible {
                FileShelfOverlayView(
                    shelf: state.temporaryFileShelf,
                    filter: state.temporaryFileShelfFilter,
                    selectedItemIDs: state.temporaryFileShelfSelectedItemIDs,
                    isDropTargetActive: state.isFileDropTargetActive,
                    onFilterChange: fileShelfActions.onFilterChange,
                    onDone: fileShelfActions.onDoneOverlay,
                    onClearSelection: fileShelfActions.onClearSelection,
                    onSelectItem: fileShelfActions.onSelectItem,
                    onSelectItems: fileShelfActions.onSelectItems,
                    onRemoveItem: fileShelfActions.onRemoveItem,
                    onClear: fileShelfActions.onClearItems,
                    onDragStarted: fileShelfActions.onDragStarted,
                    onDragCompleted: fileShelfActions.onDragCompleted,
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
            .animation(.easeInOut(duration: 0.18), value: state.selectedPrimaryFeature)
            .onAppear {
                scheduleTopBandEnergyActivation(expanded: isExpanded && state.isTopBandEnergyEffectEnabled)
            }
            .onChange(of: isExpanded) { _, expanded in
                scheduleTopBandEnergyActivation(expanded: expanded && state.isTopBandEnergyEffectEnabled)
            }
            .onChange(of: state.isTopBandEnergyEffectEnabled) { _, isEnabled in
                scheduleTopBandEnergyActivation(expanded: isExpanded && isEnabled)
            }
    }

    private func scheduleTopBandEnergyActivation(expanded: Bool) {
        topBandEnergyActivationSequence += 1
        let sequence = topBandEnergyActivationSequence
        isTopBandEnergyActive = false

        guard expanded else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + topBandEnergyActivationDelay) {
            guard sequence == topBandEnergyActivationSequence, state.isExpanded else { return }
            isTopBandEnergyActive = true
        }
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
    let isExpanded: Bool
    let animationProfile: IslandAnimationProfile

    @Namespace private var selectionNamespace

    private func featureEntranceAnimation(index: Int) -> Animation {
        guard isExpanded else {
            return .easeOut(duration: animationProfile.attachedElementCollapseDuration)
        }

        let baseAnimation = Animation.spring(
            response: animationProfile.primaryFeatureEntranceResponse,
            dampingFraction: animationProfile.primaryFeatureEntranceDampingFraction,
            blendDuration: animationProfile.primaryFeatureEntranceBlendDuration
        )

        let staggerDelay = animationProfile.primaryFeatureEntranceStartDelay + (Double(index) * animationProfile.primaryFeatureStaggerDelay)

        return baseAnimation.delay(staggerDelay)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(IslandPrimaryFeature.rightNavigationCases.enumerated()), id: \.element.id) { index, feature in
                Button {
                    selection = feature
                } label: {
                    Text(feature.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .background(
                            ZStack {
                                if selection == feature {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(.white.opacity(0.16))
                                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                                } else {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(.white.opacity(0.05))
                                }
                            }
                        )
                }
                .buttonStyle(PrimaryFeatureButtonStyle(animationProfile: animationProfile))
                .offset(y: isExpanded ? 0 : -animationProfile.primaryFeatureButtonSlideDistance)
                .opacity(isExpanded ? 1 : 0)
                .animation(featureEntranceAnimation(index: index), value: isExpanded)
            }
        }
        .foregroundStyle(.white)
        .animation(
            .spring(
                response: animationProfile.primaryFeatureSelectionResponse,
                dampingFraction: animationProfile.primaryFeatureSelectionDamping
            ),
            value: selection
        )
    }
}

private struct FilesPrimaryFeatureButton: View {
    let count: Int
    let isSelected: Bool
    let isExpanded: Bool
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Image(systemName: "tray.full")
                        .opacity(isSelected ? 0 : 1)

                    Image(systemName: "tray.full.fill")
                        .opacity(isSelected ? 1 : 0)
                }
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 18, height: 18)
                .animation(.easeInOut(duration: 0.18), value: isSelected)

                if count > 0 {
                    Text(badgeText)
                        .font(.system(size: 7, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.black.opacity(0.82))
                        .frame(minWidth: 11, minHeight: 11)
                        .padding(.horizontal, count > 9 ? 2 : 0)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.white.opacity(0.92))
                        )
                        .offset(x: 5, y: -4)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.22 : 0.08))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(isSelected ? 0.2 : 0), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .offset(y: isExpanded ? 0 : -6)
        .opacity(isExpanded ? 1 : 0)
        .accessibilityLabel("Files")
    }

    private var badgeText: String {
        count > 99 ? "99+" : "\(count)"
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

private struct PrimaryFeatureButtonStyle: ButtonStyle {
    let animationProfile: IslandAnimationProfile

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? animationProfile.primaryFeatureButtonPressScale : 1.0)
            .animation(.easeOut(duration: animationProfile.primaryFeatureButtonPressDuration), value: configuration.isPressed)
    }
}
