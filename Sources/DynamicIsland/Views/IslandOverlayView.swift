import AppKit
import SwiftUI
import DynamicIslandCore

struct IslandOverlayView: View {
    let metrics: NotchMetrics
    @ObservedObject var state: IslandOverlayState
    let onExpansionChange: @MainActor (Bool) -> Void
    let onPrimaryFeatureChange: @MainActor (IslandPrimaryFeature) -> Void
    let onDataUsageTimeRangeChange: @MainActor (UsageTimeRange) -> Void
    let onRefreshDataUsage: @MainActor () -> Void
    let onDismissCodexTask: @MainActor (CodexTaskStatus) -> Void
    let onUndoCodexTask: @MainActor (CodexTaskStatus) -> Void
    let onCodexTaskSelection: @MainActor (String) -> Void
    let onTasksExpansionHeightChange: @MainActor (CGFloat) -> Void
    let onApprovalDecision: @MainActor (CodexApprovalDecision, CodexApprovalRequest.ID) -> Void
    let onOpenCodexApproval: @MainActor (CodexApprovalRequest.ID) -> Void
    let onRetryCodexApproval: @MainActor (CodexApprovalRequest.ID) -> Void
    let fileShelfActions: FileShelfActions
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isTopBandEnergyActive = false
    @State private var topBandEnergyActivationSequence = 0
    @State private var isPrimaryContentEntranceActive = false
    @State private var mountedPrimaryFeatures: [IslandPrimaryFeature] = []
    @State private var primaryContentEntranceSequence = 0
    @State private var primaryContentExitDeadline: Date?
    @State private var isDataTimeRangeDrawerPresented = false

    private let animationProfile = IslandAnimationProfile.default
    private let musicSkipIconSize: CGFloat = 18
    private let trackInfoTextCenterY: CGFloat = 55

    init(
        metrics: NotchMetrics,
        state: IslandOverlayState,
        onExpansionChange: @escaping @MainActor (Bool) -> Void = { _ in },
        onPrimaryFeatureChange: @escaping @MainActor (IslandPrimaryFeature) -> Void = { _ in },
        onDataUsageTimeRangeChange: @escaping @MainActor (UsageTimeRange) -> Void = { _ in },
        onRefreshDataUsage: @escaping @MainActor () -> Void = {},
        onDismissCodexTask: @escaping @MainActor (CodexTaskStatus) -> Void = { _ in },
        onUndoCodexTask: @escaping @MainActor (CodexTaskStatus) -> Void = { _ in },
        onCodexTaskSelection: @escaping @MainActor (String) -> Void = { _ in },
        onTasksExpansionHeightChange: @escaping @MainActor (CGFloat) -> Void = { _ in },
        onApprovalDecision: @escaping @MainActor (CodexApprovalDecision, CodexApprovalRequest.ID) -> Void = { _, _ in },
        onOpenCodexApproval: @escaping @MainActor (CodexApprovalRequest.ID) -> Void = { _ in },
        onRetryCodexApproval: @escaping @MainActor (CodexApprovalRequest.ID) -> Void = { _ in },
        fileShelfActions: FileShelfActions = FileShelfActions()
    ) {
        self.metrics = metrics
        self.state = state
        self.onExpansionChange = onExpansionChange
        self.onPrimaryFeatureChange = onPrimaryFeatureChange
        self.onDataUsageTimeRangeChange = onDataUsageTimeRangeChange
        self.onRefreshDataUsage = onRefreshDataUsage
        self.onDismissCodexTask = onDismissCodexTask
        self.onUndoCodexTask = onUndoCodexTask
        self.onCodexTaskSelection = onCodexTaskSelection
        self.onTasksExpansionHeightChange = onTasksExpansionHeightChange
        self.onApprovalDecision = onApprovalDecision
        self.onOpenCodexApproval = onOpenCodexApproval
        self.onRetryCodexApproval = onRetryCodexApproval
        self.fileShelfActions = fileShelfActions
    }

    private var isExpanded: Bool {
        state.isExpanded
    }

    private var isShellLayoutExpanded: Bool {
        accessibilityReduceMotion ? state.usesOpenCanvas : isExpanded
    }

    private var primaryFeatureSelection: Binding<IslandPrimaryFeature> {
        Binding(
            get: { state.selectedPrimaryFeature },
            set: { feature in
                setDataTimeRangeDrawerPresented(false)
                onPrimaryFeatureChange(feature)
            }
        )
    }

    private var hasManualCodexApproval: Bool {
        state.codexApprovalPresentation.pendingCount > 0
            || state.codexStatusBarSnapshot.tasks.contains {
                $0.approvalState.requiresManualApproval
            }
    }

    private var shellWidth: CGFloat {
        isShellLayoutExpanded ? metrics.openWidth : closedShellWidth + musicSkipEdgeExpansion
    }

    private var closedShellWidth: CGFloat {
        if accessibilityReduceMotion,
           state.isShellHidden,
           state.musicPlayback.isPlaying,
           metrics.closedMusicAccessorySize > 0 {
            return metrics.musicClosedShellWidth
        }
        return showsMusicAccessories ? metrics.musicClosedShellWidth : metrics.closedShellWidth
    }

    private var closedCanvasHorizontalSlack: CGFloat {
        NotchMetrics.closedCanvasHorizontalSlack
    }

    private var shellHeight: CGFloat {
        if isShellLayoutExpanded {
            metrics.openHeight + state.codexTasksDetailExpansionHeight
        } else if showsTrackInfo {
            metrics.musicTrackInfoShellHeight
        } else {
            metrics.closedHeight
        }
    }

    private var canvasWidth: CGFloat {
        let baseWidth = state.usesOpenCanvas
            ? metrics.openWidth
            : metrics.musicClosedShellWidth + closedCanvasHorizontalSlack
        guard state.usesOpenCanvas, state.isCodexApprovalAttachmentPresented else {
            return baseWidth
        }
        return baseWidth + approvalLayout.additionalCanvasWidth
    }

    private var canvasHeight: CGFloat {
        state.usesOpenCanvas
            ? metrics.openHeight + state.codexTasksDetailExpansionHeight + NotchMetrics.defaultClosedCanvasBottomSlack
            : metrics.musicTrackInfoShellHeight + NotchMetrics.closedHoverBottomSlack
    }

    private var showsHoverPreview: Bool {
        (state.isHovered || (state.isFileDropTargetActive && !isExpanded)) && !isExpanded && !state.isShellHidden
    }

    private var hoverPreviewScale: CGFloat {
        accessibilityReduceMotion ? 1 : (showsHoverPreview ? 1.035 : 1)
    }

    private var hoverShadowOpacity: Double {
        showsHoverPreview ? 0.12 : 0
    }

    private var hoverShadowRadius: CGFloat {
        accessibilityReduceMotion ? 6 : (showsHoverPreview ? 6 : 0)
    }

    private var hoverShadowYOffset: CGFloat {
        accessibilityReduceMotion ? 1 : (showsHoverPreview ? 1 : 0)
    }

    private var shellFillColor: Color {
        .black
    }

    private var foregroundContentColor: Color {
        .white
    }

    private var musicSkipProgress: CGFloat {
        guard state.musicSkipFeedbackDirection != nil, showsMusicAccessories, !showsTrackInfo, !isShellLayoutExpanded else {
            return 0
        }
        return min(1, max(0, state.musicSkipGestureProgress))
    }

    private var musicSkipEdgeExpansion: CGFloat {
        accessibilityReduceMotion ? 0 : NotchMetrics.musicSkipEdgeExpansionMax * musicSkipProgress
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
        showsMusicAccessories && !isShellLayoutExpanded && state.isTrackInfoPresented
    }

    private var musicArtworkSize: CGFloat {
        showsTrackInfo ? 36 : metrics.closedMusicAccessorySize
    }

    private var musicArtworkCenterX: CGFloat {
        (isShellLayoutExpanded ? metrics.expandedMusicArtworkCenterX : metrics.closedLeftMusicAccessoryCenterX) + contentOriginShiftX
    }

    private var musicWaveformCenterX: CGFloat {
        (isShellLayoutExpanded ? metrics.expandedMusicWaveformCenterX : metrics.closedRightMusicAccessoryCenterX) + contentOriginShiftX
    }

    private var musicAccessoryCenterY: CGFloat {
        isShellLayoutExpanded ? metrics.expandedMusicAccessoryCenterY : metrics.closedMusicAccessoryCenterY
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
        let scale = accessibilityReduceMotion ? 1 : (state.isMusicSkipArmed ? 1.08 : 0.86 + (progress * 0.12))
        return MusicSkipGlyph(direction: direction)
            .frame(width: musicSkipIconSize, height: musicSkipIconSize)
            .opacity(Double(state.isMusicSkipArmed ? 1 : progress))
            .scaleEffect(scale)
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
        accessibilityReduceMotion ? 1 : (state.isShellHidden ? 0.04 : 1)
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
        IslandPrimaryContentLayout(metrics: metrics, shellHeight: shellHeight).tasksContentFrame
    }

    private var approvalLayout: CodexTasksApprovalLayout {
        CodexTasksApprovalLayout(metrics: metrics, shellHeight: shellHeight)
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

    private var primaryContentEntranceDelay: TimeInterval {
        accessibilityReduceMotion ? 0 : animationProfile.primaryContentEntranceDelay
    }

    private var expandAnimation: Animation? {
        accessibilityReduceMotion ? nil : .interactiveSpring(
            response: animationProfile.expandResponse,
            dampingFraction: animationProfile.expandDampingFraction,
            blendDuration: animationProfile.expandBlendDuration
        )
    }

    private var collapseAnimation: Animation? {
        accessibilityReduceMotion ? nil : .easeOut(duration: animationProfile.collapseDuration)
    }

    private var tasksHeightAnimation: Animation? {
        accessibilityReduceMotion ? nil : .spring(
            response: animationProfile.primaryFeatureSelectionResponse,
            dampingFraction: animationProfile.primaryFeatureSelectionDamping,
            blendDuration: 0
        )
    }

    private var fileShelfTransition: AnyTransition {
        accessibilityReduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }

    private var musicAccessoryTransition: AnyTransition {
        accessibilityReduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94))
    }

    private var trackInfoTransition: AnyTransition {
        accessibilityReduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
    }

    private var primaryContentTransition: AnyTransition {
        accessibilityReduceMotion
            ? .opacity
            : .opacity.combined(
                with: .offset(y: -animationProfile.primaryContentTransitionDistance)
            )
    }

    private var approvalAttachmentTransition: AnyTransition {
        accessibilityReduceMotion
            ? .opacity
            : .opacity.combined(
                with: .offset(x: -animationProfile.primaryFeatureButtonSlideDistance)
            )
    }

    private var primaryContentEntranceAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: animationProfile.reducedMotionFadeDuration)
            : .spring(
                response: animationProfile.primaryFeatureSelectionResponse,
                dampingFraction: animationProfile.primaryFeatureSelectionDamping
            )
    }

    private var primaryContentExitAnimation: Animation {
        .easeOut(duration: primaryContentExitDuration)
    }

    private var primaryContentExitDuration: TimeInterval {
        accessibilityReduceMotion
            ? animationProfile.reducedMotionFadeDuration
            : animationProfile.attachedElementCollapseDuration
    }

    private func primaryContentOffset(for feature: IslandPrimaryFeature) -> CGFloat {
        guard !accessibilityReduceMotion, state.selectedPrimaryFeature != feature else { return 0 }
        return -animationProfile.primaryContentTransitionDistance
    }

    @ViewBuilder
    private func reducedMotionFade<Value: Equatable, Content: View>(
        value: Value,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if accessibilityReduceMotion {
            content()
                .animation(
                    .easeOut(duration: animationProfile.reducedMotionFadeDuration),
                    value: value
                )
        } else {
            content()
        }
    }

    private var primaryFeatureCanvasMask: some View {
        Rectangle()
            .frame(width: shellWidth, height: metrics.expandedTopStatusBandLayout.bandHeight)
            .frame(
                width: canvasWidth,
                height: metrics.expandedTopStatusBandLayout.bandHeight,
                alignment: state.isCodexApprovalAttachmentPresented ? .topLeading : .top
            )
            .animation(isExpanded ? expandAnimation : collapseAnimation, value: shellWidth)
    }

    private var primaryFeatureCanvasLayer: some View {
        ZStack(alignment: .topLeading) {
            PrimaryFeatureSwitcher(
                selection: primaryFeatureSelection,
                isExpanded: isExpanded,
                hasManualCodexApproval: hasManualCodexApproval,
                animationProfile: animationProfile
            )
                .frame(width: primaryNavigationFrame.width, height: primaryNavigationFrame.height)
                .position(x: primaryNavigationFrame.midX, y: primaryNavigationFrame.midY)
                .disabled(!isExpanded)
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)

            FilesPrimaryFeatureButton(
                count: state.temporaryFileShelf.items.count,
                isSelected: state.selectedPrimaryFeature == .files,
                isExpanded: isExpanded,
                animationProfile: animationProfile
            ) {
                setDataTimeRangeDrawerPresented(false)
                fileShelfActions.onOpenFilesPrimaryFeature()
            }
            .frame(width: filesPrimaryFeatureFrame.width, height: filesPrimaryFeatureFrame.height)
            .position(x: filesPrimaryFeatureFrame.midX, y: filesPrimaryFeatureFrame.midY)
            .disabled(!isExpanded)
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
        }
        .frame(width: canvasWidth, height: metrics.expandedTopStatusBandLayout.bandHeight, alignment: .topLeading)
        .mask {
            primaryFeatureCanvasMask
        }
        .zIndex(4)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            islandShell
                .frame(
                    width: state.usesOpenCanvas ? metrics.openWidth : canvasWidth,
                    height: canvasHeight,
                    alignment: .top
                )

            if state.isCodexApprovalAttachmentPresented,
               let request = state.codexApprovalPresentation.request,
               request.threadID == state.selectedCodexTaskID {
                CodexApprovalActionView(
                    presentation: state.codexApprovalPresentation,
                    onDecision: onApprovalDecision,
                    onOpenCodexApproval: onOpenCodexApproval,
                    onRetry: onRetryCodexApproval
                )
                .frame(
                    width: approvalLayout.attachmentFrame.width,
                    height: approvalLayout.attachmentFrame.height
                )
                .position(
                    x: approvalLayout.attachmentFrame.midX,
                    y: approvalLayout.attachmentFrame.midY
                )
                .disabled(!isExpanded || state.selectedPrimaryFeature != .tasks)
                .allowsHitTesting(isExpanded && state.selectedPrimaryFeature == .tasks)
                .accessibilityHidden(!isExpanded || state.selectedPrimaryFeature != .tasks)
                .transition(approvalAttachmentTransition)
                .zIndex(3)
            }

            primaryFeatureCanvasLayer
        }
        .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
    }

    private var islandShell: some View {
        ZStack(alignment: .topLeading) {
            shellFillColor

            if isExpanded && state.isTopBandEnergyEffectEnabled && isTopBandEnergyActive && !accessibilityReduceMotion {
                TopBandEnergyEffectView()
                    .frame(width: topBandEnergyFrame.width, height: topBandEnergyFrame.height)
                    .position(x: topBandEnergyFrame.midX, y: topBandEnergyFrame.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if isPrimaryContentEntranceActive {
                if mountedPrimaryFeatures.contains(.tasks) {
                    CodexTasksContentView(
                        snapshot: state.codexStatusBarSnapshot,
                        dismissedTaskKeys: state.dismissedCodexTaskKeys,
                        isActive: isExpanded && state.selectedPrimaryFeature == .tasks,
                        isApprovalAttachmentPresented: state.isCodexApprovalAttachmentPresented,
                        approvalPresentation: state.codexApprovalPresentation,
                        selectedTaskID: $state.selectedCodexTaskID,
                        onDeleteTask: onDismissCodexTask,
                        onUndoTask: onUndoCodexTask,
                        onTaskSelection: onCodexTaskSelection,
                        onExpansionHeightChange: onTasksExpansionHeightChange
                    )
                    .frame(width: primaryContentFrame.width, height: primaryContentFrame.height)
                    .position(x: primaryContentFrame.midX, y: primaryContentFrame.midY)
                    .opacity(state.selectedPrimaryFeature == .tasks ? 1 : 0)
                    .offset(y: primaryContentOffset(for: .tasks))
                    .disabled(!isExpanded || state.selectedPrimaryFeature != .tasks)
                    .allowsHitTesting(isExpanded && state.selectedPrimaryFeature == .tasks)
                    .accessibilityHidden(!isExpanded || state.selectedPrimaryFeature != .tasks)
                    .transition(primaryContentTransition)
                    .zIndex(state.selectedPrimaryFeature == .tasks ? 21 : 20)
                }

                if mountedPrimaryFeatures.contains(.files) {
                    FilesPrimaryContentView(
                        shelf: state.temporaryFileShelf,
                        selectedItemIDs: state.temporaryFileShelfSelectedItemIDs,
                        airDropUndoItemCount: state.airDropUndoItemCount,
                        isDropTargetActive: state.isFileDropTargetActive,
                        isActive: isExpanded && state.selectedPrimaryFeature == .files,
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
                    .opacity(state.selectedPrimaryFeature == .files ? 1 : 0)
                    .offset(y: primaryContentOffset(for: .files))
                    .disabled(!isExpanded || state.selectedPrimaryFeature != .files)
                    .allowsHitTesting(isExpanded && state.selectedPrimaryFeature == .files)
                    .accessibilityHidden(!isExpanded || state.selectedPrimaryFeature != .files)
                    .transition(primaryContentTransition)
                    .zIndex(state.selectedPrimaryFeature == .files ? 21 : 20)
                }

                if mountedPrimaryFeatures.contains(.data) {
                    DataPrimaryContentView(
                        presentation: state.dataUsagePresentation,
                        selectedTimeRange: state.dataUsageTimeRange,
                        isActive: isExpanded && state.selectedPrimaryFeature == .data,
                        isTimeRangeDrawerPresented: isDataTimeRangeDrawerPresented,
                        onTimeRangeDrawerPresentationChange: setDataTimeRangeDrawerPresented,
                        onSelectTimeRange: { range in
                            setDataTimeRangeDrawerPresented(false)
                            onDataUsageTimeRangeChange(range)
                        },
                        onRefresh: {
                            setDataTimeRangeDrawerPresented(false)
                            onRefreshDataUsage()
                        }
                    )
                    .frame(width: primaryContentFrame.width, height: primaryContentFrame.height)
                    .position(x: primaryContentFrame.midX, y: primaryContentFrame.midY)
                    .opacity(state.selectedPrimaryFeature == .data ? 1 : 0)
                    .offset(y: primaryContentOffset(for: .data))
                    .disabled(!isExpanded || state.selectedPrimaryFeature != .data)
                    .allowsHitTesting(isExpanded && state.selectedPrimaryFeature == .data)
                    .accessibilityHidden(!isExpanded || state.selectedPrimaryFeature != .data)
                    .transition(primaryContentTransition)
                    .zIndex(isDataTimeRangeDrawerPresented ? 24 : (state.selectedPrimaryFeature == .data ? 21 : 20))
                }
            }

            if isDataTimeRangeDrawerPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        setDataTimeRangeDrawerPresented(false)
                    }
                    .zIndex(23)
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
                .transition(fileShelfTransition)
                .zIndex(22)
            }

            reducedMotionFade(value: showsMusicAccessories) {
                Group {
                    if showsMusicAccessories {
                        ClosedMusicAvatarView(artworkData: state.musicPlayback.artworkData)
                            .frame(width: musicArtworkSize, height: musicArtworkSize)
                            .position(
                                x: musicArtworkCenterX,
                                y: musicArtworkCenterY
                            )
                            .transition(musicAccessoryTransition)

                        ClosedMusicWaveformView(snapshot: state.musicPlayback.waveform)
                            .frame(width: metrics.closedMusicAccessorySize, height: metrics.closedMusicAccessorySize)
                            .position(
                                x: musicWaveformCenterX,
                                y: musicAccessoryCenterY
                            )
                            .transition(musicAccessoryTransition)

                        reducedMotionFade(value: showsTrackInfo) {
                            Group {
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
                                    .transition(trackInfoTransition)
                                }
                            }
                        }
                    }
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
                    isExpanded: isShellLayoutExpanded,
                    isMusicShell: showsMusicAccessories,
                    hasCameraHousing: state.calibrationHasCameraHousing
                )
                .zIndex(20)
            }
        }
            .frame(width: shellWidth, height: shellHeight, alignment: .top)
            .clipShape(
                IslandShape(
                    topCornerRadius: isShellLayoutExpanded ? metrics.openTopCornerRadius : metrics.closedTopCornerRadius,
                    concaveTopRadius: isShellLayoutExpanded ? metrics.openTopCornerRadius : metrics.closedConcaveTopRadius,
                    bottomCornerRadius: isShellLayoutExpanded ? metrics.openBottomCornerRadius : metrics.closedBottomCornerRadius,
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
                radius: hoverShadowRadius,
                x: 0,
                y: hoverShadowYOffset
            )
            .onTapGesture {
                if !isExpanded && !state.isShellHidden {
                    onExpansionChange(true)
                }
            }
            .animation(isExpanded ? expandAnimation : collapseAnimation, value: isExpanded)
            .animation(tasksHeightAnimation, value: state.codexTasksDetailExpansionHeight)
            .animation(accessibilityReduceMotion ? nil : .easeOut(duration: animationProfile.musicAccessoryTransitionDuration), value: showsMusicAccessories)
            .animation(.easeOut(duration: accessibilityReduceMotion ? animationProfile.reducedMotionFadeDuration : 0.14), value: state.isHovered)
            .animation(.easeOut(duration: accessibilityReduceMotion ? animationProfile.reducedMotionFadeDuration : 0.14), value: state.isFileDropTargetActive)
            .animation(.easeOut(duration: accessibilityReduceMotion ? animationProfile.reducedMotionFadeDuration : 0.14), value: state.isFileShelfOverlayVisible)
            .animation(primaryContentEntranceAnimation, value: state.selectedPrimaryFeature)
            .onAppear {
                scheduleTopBandEnergyActivation(expanded: isExpanded && state.isTopBandEnergyEffectEnabled && !accessibilityReduceMotion)
                schedulePrimaryContentEntrance(expanded: isExpanded)
            }
            .onChange(of: isExpanded) { _, expanded in
                if !expanded {
                    setDataTimeRangeDrawerPresented(false)
                }
                scheduleTopBandEnergyActivation(expanded: expanded && state.isTopBandEnergyEffectEnabled && !accessibilityReduceMotion)
                schedulePrimaryContentEntrance(expanded: expanded)
            }
            .onChange(of: state.selectedPrimaryFeature) { _, feature in
                if isPrimaryContentEntranceActive {
                    withAnimation(primaryContentEntranceAnimation) {
                        mountPrimaryFeature(feature)
                    }
                }
                if feature != .data {
                    setDataTimeRangeDrawerPresented(false)
                }
            }
            .onChange(of: state.isShellHidden) { _, hidden in
                if hidden {
                    setDataTimeRangeDrawerPresented(false)
                }
            }
            .onChange(of: state.isTopBandEnergyEffectEnabled) { _, isEnabled in
                scheduleTopBandEnergyActivation(expanded: isExpanded && isEnabled && !accessibilityReduceMotion)
            }
            .onChange(of: accessibilityReduceMotion) { _, reduceMotion in
                scheduleTopBandEnergyActivation(expanded: isExpanded && state.isTopBandEnergyEffectEnabled && !reduceMotion)
                schedulePrimaryContentEntrance(expanded: isExpanded)
            }
            .onExitCommand {
                setDataTimeRangeDrawerPresented(false)
            }
    }

    @MainActor
    private func setDataTimeRangeDrawerPresented(_ isPresented: Bool) {
        let drawerAnimation: Animation
        if accessibilityReduceMotion {
            drawerAnimation = .easeOut(duration: animationProfile.reducedMotionFadeDuration)
        } else {
            drawerAnimation = .spring(
                response: animationProfile.dataRangeDrawerResponse,
                dampingFraction: animationProfile.dataRangeDrawerDampingFraction
            )
        }

        withAnimation(drawerAnimation) {
            isDataTimeRangeDrawerPresented = isPresented
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

    private func schedulePrimaryContentEntrance(expanded: Bool) {
        primaryContentEntranceSequence += 1
        let sequence = primaryContentEntranceSequence

        guard expanded else {
            let exitDuration = primaryContentExitDuration
            primaryContentExitDeadline = isPrimaryContentEntranceActive
                ? Date().addingTimeInterval(exitDuration)
                : nil
            withAnimation(primaryContentExitAnimation) {
                isPrimaryContentEntranceActive = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + exitDuration) {
                guard sequence == primaryContentEntranceSequence, !state.isExpanded else { return }
                mountedPrimaryFeatures.removeAll()
            }
            return
        }

        let shouldReverseExit = primaryContentExitDeadline.map { Date() < $0 } ?? false
        primaryContentExitDeadline = nil
        guard !isPrimaryContentEntranceActive else { return }

        let entranceDelay = shouldReverseExit ? 0 : primaryContentEntranceDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + entranceDelay) {
            guard sequence == primaryContentEntranceSequence, state.isExpanded else { return }
            withAnimation(primaryContentEntranceAnimation) {
                mountPrimaryFeature(state.selectedPrimaryFeature)
                isPrimaryContentEntranceActive = true
            }
        }
    }

    private func mountPrimaryFeature(_ feature: IslandPrimaryFeature) {
        switch feature {
        case .tasks, .files, .data:
            guard !mountedPrimaryFeatures.contains(feature) else { return }
            mountedPrimaryFeatures.append(feature)
        case .tools, .settings:
            return
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
    let hasManualCodexApproval: Bool
    let animationProfile: IslandAnimationProfile

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Namespace private var selectionNamespace

    private var entranceAnimation: Animation {
        if accessibilityReduceMotion {
            return .easeOut(duration: animationProfile.reducedMotionFadeDuration)
        }
        guard isExpanded else {
            return .easeOut(duration: animationProfile.attachedElementCollapseDuration)
        }

        return Animation.linear(duration: animationProfile.primaryFeatureEntranceDuration)
            .delay(animationProfile.primaryFeatureEntranceStartDelay)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(IslandPrimaryFeature.rightNavigationCases) { feature in
                Button {
                    selection = feature
                } label: {
                    ZStack(alignment: .topTrailing) {
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

                        if feature == .tasks, hasManualCodexApproval {
                            Circle()
                                .fill(Color(red: 1, green: 0.74, blue: 0.34))
                                .frame(width: 5, height: 5)
                                .offset(x: -3, y: 3)
                                .accessibilityHidden(true)
                            }
                    }
                }
                .buttonStyle(IslandPressButtonStyle())
                .accessibilityLabel(
                    feature == .tasks && hasManualCodexApproval
                        ? "Tasks，有待审批请求"
                        : feature.title
                )
            }
        }
        .foregroundStyle(.white)
        .offset(y: accessibilityReduceMotion || isExpanded ? 0 : -animationProfile.primaryFeatureButtonSlideDistance)
        .opacity(isExpanded ? 1 : 0)
        .animation(entranceAnimation, value: isExpanded)
        .animation(
            accessibilityReduceMotion ? nil : .spring(
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
    let animationProfile: IslandAnimationProfile
    let action: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var entranceAnimation: Animation {
        if accessibilityReduceMotion {
            return .easeOut(duration: animationProfile.reducedMotionFadeDuration)
        }
        guard isExpanded else {
            return .easeOut(duration: animationProfile.attachedElementCollapseDuration)
        }

        return Animation.linear(duration: animationProfile.primaryFeatureEntranceDuration)
            .delay(animationProfile.primaryFeatureEntranceStartDelay)
    }

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
                .animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.18), value: isSelected)

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
        .buttonStyle(IslandPressButtonStyle())
        .contentShape(Rectangle())
        .offset(y: accessibilityReduceMotion || isExpanded ? 0 : -animationProfile.primaryFeatureButtonSlideDistance)
        .opacity(isExpanded ? 1 : 0)
        .animation(entranceAnimation, value: isExpanded)
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
