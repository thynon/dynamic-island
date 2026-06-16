import CoreGraphics
import Foundation
import IslandCore

private func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard actual == expected else {
        fputs("FAIL: \(message). Expected \(expected), got \(actual) at \(file):\(line)\n", stderr)
        Foundation.exit(1)
    }
}

private func testDerivesApprovedFourteenInchNotchMetrics() {
    let metrics = NotchMetrics.fromDisplay(
        frameWidth: 1512,
        auxiliaryTopLeftWidth: 663,
        auxiliaryTopRightWidth: 664,
        safeAreaTopInset: 32
    )

    expectEqual(metrics.cameraHousingWidth, 185, "camera housing width")
    expectEqual(metrics.closedHeight, 32, "closed height")
    expectEqual(metrics.closedShellWidth, 245, "closed shell width")
    expectEqual(metrics.openWidth, 700, "open width")
    expectEqual(metrics.openHeight, 230, "open height")
}

private func testFallsBackToApprovedPreviewMetricsWhenScreenDataIsMissing() {
    let metrics = NotchMetrics.fromDisplay(
        frameWidth: 1512,
        auxiliaryTopLeftWidth: nil,
        auxiliaryTopRightWidth: nil,
        safeAreaTopInset: 0
    )

    expectEqual(metrics.cameraHousingWidth, 185, "fallback camera housing width")
    expectEqual(metrics.closedHeight, 32, "fallback closed height")
    expectEqual(metrics.closedShellWidth, 245, "fallback closed shell width")
}

private func testDoesNotShrinkBelowApprovedCameraHousingWhenScreenDataJitters() {
    let metrics = NotchMetrics.fromDisplay(
        frameWidth: 1512,
        auxiliaryTopLeftWidth: 665,
        auxiliaryTopRightWidth: 666,
        safeAreaTopInset: 32
    )

    expectEqual(metrics.cameraHousingWidth, 185, "minimum camera housing width")
    expectEqual(metrics.closedShellWidth, 245, "minimum closed shell width")
}

private func testKeepsStatusSlotPinnedToCameraHousingLeftSide() {
    let metrics = NotchMetrics.preview14Inch

    expectEqual(metrics.statusSlotWidth, 30, "status slot width")
    expectEqual(metrics.statusDotCenterXFromShellCenter, -107.5, "status dot center")
}

private func testClosedShellKeepsSymmetricSideSlots() {
    let metrics = NotchMetrics.preview14Inch
    let leftSlotWidth = metrics.statusSlotWidth
    let rightSlotWidth = metrics.closedShellWidth - metrics.cameraHousingWidth - metrics.statusSlotWidth

    expectEqual(leftSlotWidth, rightSlotWidth, "closed shell side slots")
}

private func testUsesOneTopCornerRadiusForClosedAndOpenStates() {
    let metrics = NotchMetrics.preview14Inch

    expectEqual(metrics.closedTopCornerRadius, metrics.openTopCornerRadius, "shared top corner radius")
    expectEqual(metrics.closedTopCornerRadius, 16, "approved top corner radius")
}

private func testCollapsedWindowOnlyCoversVisibleClosedIsland() {
    let metrics = NotchMetrics.preview14Inch

    expectEqual(metrics.closedWindowSize.width, 245, "closed window width")
    expectEqual(metrics.closedWindowSize.height, 32, "closed window height")
    expectEqual(metrics.openWindowSize.width, 700, "open window width")
    expectEqual(metrics.openWindowSize.height, 230, "open window height")
}

private func testClosedStatusDotStaysInsideVisibleLeftSlot() {
    let metrics = NotchMetrics.preview14Inch
    let radius = metrics.closedStatusDotHaloDiameter / 2
    let leftEdge = metrics.closedStatusDotCenterX - radius
    let rightEdge = metrics.closedStatusDotCenterX + radius
    let topEdge = metrics.closedStatusDotCenterY - radius
    let bottomEdge = metrics.closedStatusDotCenterY + radius
    let cameraLeftEdge = metrics.cameraHousingLeftEdgeX
    let visibleLeftEdge = metrics.closedTopCornerRadius

    expectEqual(metrics.closedStatusDotHaloDiameter, 10, "closed status dot visible halo diameter")
    expectEqual(metrics.closedStatusDotCenterX, 23, "closed status dot center x")
    expectEqual(metrics.closedStatusDotCenterY, 16, "closed status dot center y")
    expectEqual(leftEdge >= visibleLeftEdge + metrics.closedStatusDotGuardInset, true, "closed dot avoids shell edge")
    expectEqual(rightEdge <= cameraLeftEdge - metrics.closedStatusDotGuardInset, true, "closed dot avoids camera housing")
    expectEqual(topEdge >= metrics.closedStatusDotGuardInset, true, "closed dot avoids top edge")
    expectEqual(bottomEdge <= metrics.closedHeight - metrics.closedStatusDotGuardInset, true, "closed dot avoids bottom edge")
}

private func testExpandedStatusDotMovesLeftWithoutTouchingOpenShell() {
    let metrics = NotchMetrics.preview14Inch
    let radius = metrics.expandedStatusDotHaloDiameter / 2
    let visibleLeftEdgeAtTopBand = metrics.openTopCornerRadius
    let closedScreenOffset = metrics.closedStatusDotCenterX - (metrics.closedShellWidth / 2)
    let expandedScreenOffset = metrics.expandedStatusDotCenterX - (metrics.openWidth / 2)

    expectEqual(metrics.expandedStatusDotHaloDiameter, metrics.closedStatusDotHaloDiameter, "expanded status dot matches closed size")
    expectEqual(metrics.expandedStatusDotHaloDiameter, 10, "expanded status dot halo diameter")
    expectEqual(metrics.expandedStatusDotCenterX, 25, "expanded status dot center x")
    expectEqual(metrics.expandedStatusDotCenterY, metrics.closedStatusDotCenterY, "expanded status dot keeps closed vertical lane")
    expectEqual(expandedScreenOffset < closedScreenOffset, true, "expanded dot moves left in screen space")
    expectEqual(
        metrics.expandedStatusDotCenterX - radius >= visibleLeftEdgeAtTopBand + metrics.closedStatusDotGuardInset,
        true,
        "expanded dot avoids open shell edge"
    )
}

private func testStatusDotUsesSoftGlowVisualContract() {
    let metrics = NotchMetrics.preview14Inch
    let style = metrics.statusDotSoftGlowStyle

    expectEqual(style.haloDiameter, metrics.closedStatusDotHaloDiameter, "soft glow halo matches approved dot size")
    expectEqual(style.haloDiameter, metrics.expandedStatusDotHaloDiameter, "soft glow halo stays same in expanded state")
    expectEqual(style.renderClipDiameter, style.haloDiameter, "soft glow render is clipped to safe halo")
    expectEqual(style.outerSourceDiameter >= style.haloDiameter * 0.88, true, "breathing glow reaches visible halo edge")
    expectEqual(style.coreDiameter < style.haloDiameter, true, "soft glow core stays inside halo")
    expectEqual(style.coreDiameter <= style.haloDiameter * 0.24, true, "center source is not a visible solid dot")
    expectEqual(style.solidCoreOpacity, 0, "status dot does not render a hard solid core")
    expectEqual(style.outerBlurRadius >= 1.8, true, "soft glow keeps visible outer blur")
    expectEqual(style.mediumBlurRadius >= 0.8, true, "soft glow keeps visible middle blur")
    expectEqual(style.ringLineWidth <= 1.2, true, "soft glow ring stays atmospheric")
    expectEqual(style.coreShadowOpacity, 0, "status dot core shadow is disabled")
    expectEqual(style.highlightOpacity, 0, "status dot solid highlight is disabled")
}

private func testStatusDotUsesDirectionalTravelWithoutRebound() {
    let metrics = NotchMetrics.preview14Inch
    let radius = metrics.closedStatusDotHaloDiameter / 2
    let cameraLeftEdge = metrics.cameraHousingLeftEdgeX
    let closedVisibleLeftEdge = metrics.closedTopCornerRadius
    let expandedVisibleLeftEdge = metrics.openTopCornerRadius
    let closedScreenOffset = metrics.closedStatusDotCenterX - (metrics.closedShellWidth / 2)
    let expandedScreenOffset = metrics.expandedStatusDotCenterX - (metrics.openWidth / 2)

    expectEqual(metrics.statusDotDirectionalOvershootOffset, 0, "status dot directional travel has no rebound offset")
    expectEqual(metrics.expandedStatusDotCenterX, 25, "expanded final target follows enlarged left shell slot")
    expectEqual(metrics.closedStatusDotCenterX, 23, "closed final target remains safe left status slot position")
    expectEqual(expandedScreenOffset < closedScreenOffset, true, "open travel direction is leftward in screen space")
    expectEqual(closedScreenOffset > expandedScreenOffset, true, "close travel direction is rightward in screen space")
    expectEqual(metrics.expandedStatusDotCenterX - radius >= expandedVisibleLeftEdge + metrics.closedStatusDotGuardInset, true, "expanded final target remains inside open shell")
    expectEqual(metrics.closedStatusDotCenterX + radius <= cameraLeftEdge - metrics.closedStatusDotGuardInset, true, "closed final target remains camera-safe")
    expectEqual(metrics.closedStatusDotCenterX - radius >= closedVisibleLeftEdge + metrics.closedStatusDotGuardInset, true, "closed final target remains inside closed shell")
}

private func testExpandedTopStatusBandDefinesPhysicalRegions() {
    let metrics = NotchMetrics.preview14Inch
    let layout = metrics.expandedTopStatusBandLayout

    expectEqual(layout.bandHeight, metrics.closedHeight, "top status band follows physical notch height")
    expectEqual(layout.leftStatusRegion.maxX <= layout.cameraHousingRegion.minX - layout.guardInset, true, "left status region avoids camera housing")
    expectEqual(layout.rightInfoRegion.minX >= layout.cameraHousingRegion.maxX + layout.guardInset, true, "right info region avoids camera housing")
    expectEqual(layout.cameraHousingRegion.width, metrics.cameraHousingWidth, "camera region uses real housing width")
    expectEqual(layout.cameraHousingRegion.midX, metrics.openWidth / 2, "camera region is centered in expanded island")
    expectEqual(layout.leftStatusRegion.minX >= metrics.openTopCornerRadius, true, "left status region avoids open shell corner")
    expectEqual(layout.rightInfoRegion.maxX <= metrics.openWidth - metrics.openTopCornerRadius, true, "right info region avoids open shell corner")
}

private func testTopStatusBandKeepsGlanceableItemsInApprovedRegions() {
    let metrics = NotchMetrics.preview14Inch
    let layout = metrics.expandedTopStatusBandLayout
    let dotFrame = layout.statusDotFrame
    let waveformFrame = layout.audioWaveformFrame
    let costFrame = layout.costBadgeFrame(width: 86, height: 24)

    expectEqual(layout.leftStatusRegion.contains(dotFrame), true, "expanded status dot stays inside left status region")
    expectEqual(layout.rightInfoRegion.contains(waveformFrame), true, "expanded waveform stays inside right info region")
    expectEqual(layout.rightInfoRegion.contains(costFrame), true, "top cost badge stays inside right info region")
    expectEqual(waveformFrame.minX >= layout.cameraHousingRegion.maxX + layout.guardInset, true, "waveform does not enter camera housing")
    expectEqual(waveformFrame.maxX <= costFrame.minX - 8, true, "waveform leaves room before the cost badge")
    expectEqual(costFrame.minX >= layout.cameraHousingRegion.maxX + layout.guardInset, true, "cost badge does not enter camera housing")
    expectEqual(waveformFrame.midY, costFrame.midY, "waveform and cost badge share the same horizontal centerline")
}

private func testOverlayUsesTopStatusBandContractForTopLaneItems() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Views/IslandOverlayView.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("topStatusBandLayout"), true, "overlay routes top lane placement through layout contract")
    expectEqual(source.contains("statusDotFrame"), true, "overlay places status dot from top status band contract")
    expectEqual(source.contains("audioWaveformFrame"), true, "overlay places waveform from top status band contract")
}

private func testIslandAnimationProfileUsesSingleExpansionRhythm() {
    let profile = IslandAnimationProfile.default

    expectEqual(profile.expandResponse, 0.38, "expanded shell response uses approved primary rhythm")
    expectEqual(profile.expandDampingFraction, 0.82, "expanded shell damping keeps island feeling attached")
    expectEqual(profile.collapseDuration, 0.14, "collapse duration stays quick")
    expectEqual(profile.attachedElementExpandDuration, 0.34, "attached elements use one expand travel duration")
    expectEqual(profile.attachedElementCollapseDuration, profile.collapseDuration, "attached elements close with shell")
    expectEqual(profile.expandedContentScale, 0.88, "expanded content starts from existing approved scale")
    expectEqual(profile.audioWaveformCollapsedScale, 0.92, "waveform keeps existing approved collapsed scale")
}

private func testOverlayAndPanelUseUnifiedAnimationProfile() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let overlayURL = projectRoot.appendingPathComponent("Sources/Island/Views/IslandOverlayView.swift")
    let controllerURL = projectRoot.appendingPathComponent("Sources/Island/Controllers/IslandPanelController.swift")
    let overlay = (try? String(contentsOf: overlayURL, encoding: .utf8)) ?? ""
    let controller = (try? String(contentsOf: controllerURL, encoding: .utf8)) ?? ""

    expectEqual(overlay.contains("IslandAnimationProfile.default"), true, "overlay reads the shared animation profile")
    expectEqual(controller.contains("IslandAnimationProfile.default"), true, "panel controller reads the shared animation profile")
    expectEqual(overlay.contains(".interactiveSpring(response: 0.38"), false, "overlay no longer hardcodes expand spring")
    expectEqual(controller.contains(".interactiveSpring(response: 0.38"), false, "panel controller no longer hardcodes expand spring")
    expectEqual(overlay.contains(".timingCurve(0.18, 0.86, 0.22, 1.0, duration: 0.34)"), false, "attached element timing is not scattered in overlay")
}

private func testTaskActivityBreathingContracts() {
    let idle = TaskActivityState.idle.breathingProfile
    let running = TaskActivityState.running.breathingProfile
    let thinking = TaskActivityState.thinking.breathingProfile
    let compacting = TaskActivityState.compacting.breathingProfile
    let warning = TaskActivityState.warning.breathingProfile
    let error = TaskActivityState.error.breathingProfile

    expectEqual(idle.isActive, false, "idle task state does not breathe")
    expectEqual(idle.minOpacity, idle.maxOpacity, "idle glow opacity stays static")
    expectEqual(idle.minScale, idle.maxScale, "idle glow scale stays static")
    expectEqual(idle.minBlurRadius, idle.maxBlurRadius, "idle glow blur stays static")
    expectEqual(idle.minOpacity, 0, "idle glow is hidden")
    expectEqual(idle.maxOpacity, 0, "idle glow stays hidden")

    expectEqual(running.isActive, true, "running task state breathes")
    expectEqual(running.minScale < 1.0, true, "running glow contracts at the low point")
    expectEqual(running.maxScale > 1.0, true, "running glow expands at the bright peak")
    expectEqual(running.minOpacity > 0, true, "running breathing keeps a faint visible glow")
    expectEqual(running.maxOpacity, 1.0, "running breathing keeps the approved bright peak")
    expectEqual(running.minBlurRadius < running.maxBlurRadius, true, "running breathing softens at the bright peak")
    expectEqual(running.duration >= 1.8, true, "running breathing stays calm rather than pulsing fast")

    expectEqual(thinking, running, "thinking uses running active breathing")
    expectEqual(compacting, running, "context compaction uses running active breathing")

    expectEqual(warning.isActive, true, "warning task state breathes")
    expectEqual(warning.minScale < 1.0, true, "warning glow contracts at the low point")
    expectEqual(warning.maxScale > 1.0, true, "warning glow expands at the bright peak")
    expectEqual(warning.minOpacity > 0, true, "warning breathing keeps a faint visible glow")
    expectEqual(warning.minBlurRadius < warning.maxBlurRadius, true, "warning breathing softens at the bright peak")
    expectEqual(warning.duration > running.duration, true, "warning breathes a little slower than running")
    expectEqual(warning.duration > error.duration, true, "warning stays slower than error pulse")
    expectEqual(warning.maxOpacity, running.maxOpacity, "warning breathing uses the same bright peak")

    expectEqual(error.isActive, true, "error task state can pulse")
    expectEqual(error.minScale <= 0.25, true, "error glow still starts from center")
    expectEqual(error.maxScale, 1.0, "error glow expands to full halo")
    expectEqual(error.minOpacity, 0, "error breathing starts invisible")
    expectEqual(error.duration <= 1.0, true, "error pulse is fast")
    expectEqual(error.maxOpacity, running.maxOpacity, "error pulse uses the same bright peak")
}

private func testTaskActivityBreathingStaysInsideStatusDotClip() {
    let metrics = NotchMetrics.preview14Inch
    let style = metrics.statusDotSoftGlowStyle

    for state in TaskActivityState.allCases {
        let profile = state.breathingProfile
        expectEqual(profile.clipDiameter(for: style), style.renderClipDiameter, "\(state) breathing clip matches halo")
        expectEqual(profile.minScale >= 0, true, "\(state) glow radius never becomes negative")
        expectEqual(profile.maxScale <= 1.2, true, "\(state) glow expansion remains restrained")
        expectEqual(profile.maxBlurRadius <= style.renderClipDiameter / 2, true, "\(state) breathing blur remains restrained")
    }
}

private func testStatusDotHostViewUsesOnlySafeHaloFrame() {
    let metrics = NotchMetrics.preview14Inch
    let radius = metrics.closedStatusDotHaloDiameter / 2
    let closedLocalFrameMinX = metrics.closedStatusDotCenterX - radius
    let closedLocalFrameMaxX = metrics.closedStatusDotCenterX + radius
    let expandedLocalFrameMinX = metrics.expandedStatusDotCenterX - radius
    let expandedLocalFrameMaxX = metrics.expandedStatusDotCenterX + radius

    expectEqual(metrics.closedStatusDotHaloDiameter, 10, "status dot host frame width is the safe halo width")
    expectEqual(metrics.expandedStatusDotHaloDiameter, 10, "expanded status dot host frame width is the safe halo width")
    expectEqual(closedLocalFrameMaxX <= metrics.cameraHousingLeftEdgeX - metrics.closedStatusDotGuardInset, true, "closed host frame does not enter camera housing")
    expectEqual(closedLocalFrameMinX >= metrics.closedTopCornerRadius + metrics.closedStatusDotGuardInset, true, "closed host frame stays inside left slot")
    expectEqual(expandedLocalFrameMinX >= metrics.openTopCornerRadius + metrics.closedStatusDotGuardInset, true, "expanded host frame stays inside open shell")
    expectEqual(expandedLocalFrameMaxX <= metrics.expandedStatusDotCenterX + radius, true, "expanded host frame stays clipped to its safe halo")
}

private func testAudioWaveformUsesMarkedExpandedRightInfoRegion() {
    let metrics = NotchMetrics.preview14Inch
    let layout = metrics.expandedTopStatusBandLayout
    let waveformFrame = layout.audioWaveformFrame
    let costFrame = layout.costBadgeFrame(width: 86, height: 24)

    expectEqual(metrics.expandedAudioWaveformSize.width >= 120, true, "expanded waveform is wide enough for a real trace")
    expectEqual(metrics.expandedAudioWaveformSize.width <= 150, true, "expanded waveform does not crowd the camera housing")
    expectEqual(metrics.expandedAudioWaveformSize.height, 22, "expanded waveform has enough height for a real trace")
    expectEqual(layout.rightInfoRegion.contains(waveformFrame), true, "expanded waveform stays inside the right info region")
    expectEqual(waveformFrame.minX >= layout.cameraHousingRegion.maxX + layout.guardInset, true, "expanded waveform avoids the physical camera housing")
    expectEqual(waveformFrame.maxX <= costFrame.minX - 8, true, "expanded waveform leaves a gap before the cost badge")
    expectEqual(waveformFrame.minY >= metrics.closedStatusDotGuardInset, true, "expanded waveform avoids top edge")
    expectEqual(waveformFrame.maxY <= metrics.closedHeight - metrics.closedStatusDotGuardInset, true, "expanded waveform stays inside the top status lane")
    expectEqual(metrics.expandedAudioWaveformCenterY, metrics.closedAudioWaveformCenterY, "expanded waveform keeps the top status lane")
}

private func testAudioWaveformUsesContinuousTraceStyle() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Views/AudioWaveformView.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("Path"), true, "audio waveform draws a continuous trace")
    expectEqual(source.contains(".stroke"), true, "audio waveform uses a stroked line")
    expectEqual(source.contains("Capsule"), false, "audio waveform is not a vertical bar visualizer")
    expectEqual(source.contains("baseline"), true, "audio waveform includes a center baseline like the reference")
}

private func testAudioWaveformDefaultsToStaticLineWithoutAudio() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Views/AudioWaveformView.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("snapshot: AudioPlaybackSnapshot = .idle"), true, "audio waveform defaults to a static line when no audio snapshot is provided")
    expectEqual(source.contains("case .audioLevels"), true, "audio waveform has a real audio rendering mode")
    expectEqual(source.contains("case .heartbeat"), false, "audio waveform no longer keeps a heartbeat rendering mode")
    expectEqual(source.contains("ecgWaveform"), false, "audio waveform no longer keeps an ECG rendering branch")
    expectEqual(source.contains("ECGWaveformModel"), false, "audio waveform no longer references an ECG model")
}

private func testAudioWaveformConsumesRealAudioLevels() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Views/AudioWaveformView.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("snapshot: AudioPlaybackSnapshot"), true, "audio waveform accepts a real audio snapshot")
    expectEqual(source.contains("snapshot.levels"), true, "audio waveform draws from captured audio levels")
}

private func testMusicWaveformPathDoesNotKeepHeartbeatRendering() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Views/AudioWaveformView.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("audioLevelsWaveform"), true, "music playback uses a dedicated audio waveform branch")
    expectEqual(source.contains("ecgWaveform"), false, "heartbeat fallback branch is removed")
    expectEqual(source.contains("ECGWaveformModel"), false, "ECG model usage is removed from the waveform view")
    expectEqual(source.contains("drawScanHead"), false, "monitor scan head code is removed")
    expectEqual(source.contains("monitorECGColor"), false, "monitor ECG color is removed")
    expectEqual(source.contains("let waveA = sin"), true, "only the music branch can add sinusoidal shimmer")
}

private func testDefaultAudioSnapshotIsIdleStaticLine() {
    expectEqual(AudioPlaybackSnapshot.defaultFallback, .idle, "default no-music presentation is a static line")
    expectEqual(AudioPlaybackSnapshot.defaultFallback.presentationMode, .idle, "default no-music presentation uses idle mode")
    expectEqual(AudioPlaybackSnapshot.defaultFallback.isWaveformActive, false, "default idle fallback does not run continuous animation")
}

private func testOverlayInitialAudioPlaybackIsIdle() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Views/IslandOverlayView.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(
        source.contains("@Published var audioPlayback: AudioPlaybackSnapshot = .idle"),
        true,
        "real overlay state starts idle to avoid default animation overhead"
    )
}

private func testAudioWaveformUsesTimelineForContinuousMotion() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Views/AudioWaveformView.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("TimelineView(.animation"), true, "active audio waveform redraws continuously instead of only when polling state changes")
    expectEqual(source.contains("timeIntervalSinceReferenceDate"), true, "active audio waveform uses time as the animation phase")
}

private func testAudioPlaybackStateControlsWaveformActivity() {
    expectEqual(AudioPlaybackSnapshot.idle.isWaveformActive, false, "idle audio snapshot remains inactive")
    expectEqual(AudioPlaybackSnapshot(levels: [0.2, -0.1]).isWaveformActive, true, "non-empty audio levels animate waveform")
    expectEqual(AudioPlaybackSnapshot(levels: []).isWaveformActive, false, "empty audio levels do not animate waveform")
}

private func testAudioPlaybackSnapshotSeparatesPresentationModeFromDetectedAudio() {
    expectEqual(AudioPlaybackSnapshot.idle.presentationMode, .idle, "idle snapshot has an explicit idle presentation mode")
    expectEqual(AudioPlaybackSnapshot(levels: [0.2]).presentationMode, .audioLevels, "real levels use audio-level presentation mode")
}

private func testAudioPlaybackSourceFallsBackToStaticLineWithoutPlayerProcess() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Support/AudioPlaybackDataSource.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(
        source.contains("return AudioPlaybackSnapshot.defaultFallback"),
        true,
        "privacy-friendly audio source returns the static line default when no player is active"
    )
    expectEqual(
        source.contains("return AudioPlaybackSnapshot.fallbackHeartbeat"),
        false,
        "privacy-friendly audio source no longer turns the default no-player state into a heartbeat animation"
    )
}

private func testIslandOverlayPassesAudioPlaybackStateToWaveform() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Views/IslandOverlayView.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("@Published var audioPlayback"), true, "overlay state stores audio playback snapshot")
    expectEqual(source.contains("AudioWaveformView(snapshot: visibleAudioPlayback)"), true, "waveform receives the visible audio snapshot")
}

private func testIslandOverlayPausesWaveformWhileCollapsed() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Views/IslandOverlayView.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("visibleAudioPlayback"), true, "overlay derives a visible audio state")
    expectEqual(source.contains("isExpanded ? state.audioPlayback : .idle"), true, "collapsed overlay pauses waveform animation instead of running default ECG")
    expectEqual(source.contains("AudioWaveformView(snapshot: visibleAudioPlayback)"), true, "waveform receives the visible audio state")
}

private func testPanelPollsAudioPlaybackStateSeparatelyFromTaskActivity() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Controllers/IslandPanelController.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("audioPlaybackDataSource"), true, "panel has a separate audio playback data source")
    expectEqual(source.contains("AudioPlaybackDataSourceFactory.defaultSource()"), true, "panel defaults to the privacy-friendly audio source factory")
    expectEqual(source.contains("refreshAudioPlaybackState"), true, "panel refreshes audio state separately")
    expectEqual(source.contains("startAudioPlaybackPolling"), true, "panel starts audio playback polling")
    expectEqual(source.contains("83_333_333"), true, "panel refreshes audio snapshots often enough for real waveform motion")
}

private func testAudioPlaybackSourceDefaultsToPrivacyFriendlyPlayerStateMode() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Support/AudioPlaybackDataSource.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("AudioPlaybackDataSourceFactory"), true, "audio source factory exists")
    expectEqual(source.contains("ISLAND_REAL_AUDIO_WAVEFORM"), true, "real system audio capture is opt-in")
    expectEqual(source.contains("AppleScriptAudioPlaybackDataSource()"), true, "default audio source avoids ScreenCaptureKit sharing indicators")
    expectEqual(source.contains("cachedState"), true, "player-state detection is cached for high-frequency UI refresh")
}

private func testAudioPlaybackSourceCanUseCoreAudioProcessTapForRealSamples() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Support/AudioPlaybackDataSource.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("CoreAudioProcessTapAudioPlaybackDataSource"), true, "Core Audio process tap source exists")
    expectEqual(source.contains("AudioHardwareCreateProcessTap"), true, "real audio source creates a Core Audio process tap")
    expectEqual(source.contains("kAudioHardwarePropertyTranslatePIDToProcessObject"), true, "real audio source maps player PID to Core Audio process object")
    expectEqual(source.contains("AudioDeviceCreateIOProcID"), true, "real audio source reads tap audio through an IO proc")
    expectEqual(source.contains("AudioHardwareDestroyProcessTap"), true, "real audio source destroys the process tap")
    expectEqual(source.contains("ISLAND_CORE_AUDIO_TAP_WAVEFORM"), true, "Core Audio process tap mode is explicitly selectable")
}

private func testAudioPlaybackSourceDoesNotAskToLocateMissingPlayers() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Support/AudioPlaybackDataSource.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("NSWorkspace.shared.runningApplications"), true, "player-state detection checks running apps before AppleScript")
    expectEqual(source.contains("bundleIdentifier"), true, "player-state detection uses bundle identifiers instead of only display names")
    expectEqual(source.contains("isPlayerRunning"), true, "missing players are skipped before AppleScript can ask the user to locate them")
}

private func testAudioPlaybackSourceUsesScreenCaptureKitForRealSamples() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Support/AudioPlaybackDataSource.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("import ScreenCaptureKit"), true, "audio playback source uses ScreenCaptureKit")
    expectEqual(source.contains("SCStreamOutputType.audio"), true, "audio playback source captures system audio samples")
    expectEqual(source.contains("CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer"), true, "audio playback source reads real PCM sample buffers")
}

private func testAudioPlaybackSourceReadsActualPCMFormatAndLogsCaptureState() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Support/AudioPlaybackDataSource.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("CMAudioFormatDescriptionGetStreamBasicDescription"), true, "audio source reads the sample buffer audio format")
    expectEqual(source.contains("kAudioFormatFlagIsFloat"), true, "audio source supports Float32 PCM samples")
    expectEqual(source.contains("kAudioFormatFlagIsSignedInteger"), true, "audio source supports signed integer PCM samples")
    expectEqual(source.contains("Logger(subsystem: \"cx.island.mvp\", category: \"audio\")"), true, "audio source logs capture state for permission and sample debugging")
}

private func testAudioPlaybackSourceRequestsScreenCaptureAccessBeforeStartingStream() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Support/AudioPlaybackDataSource.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("CGPreflightScreenCaptureAccess"), true, "audio source checks ScreenCaptureKit TCC access before starting")
    expectEqual(source.contains("CGRequestScreenCaptureAccess"), true, "audio source requests ScreenCaptureKit TCC access when needed")
    expectEqual(source.contains("screen capture permission was not granted"), true, "audio source logs a clear permission denial")
}

private func testAppBundleDeclaresAppleEventsUsageForMusicDetection() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let scriptURL = projectRoot.appendingPathComponent("script/build_and_run.sh")
    let source = (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("NSAppleEventsUsageDescription"), true, "app bundle explains Apple Events usage for music playback detection")
    expectEqual(source.contains("NSScreenCaptureUsageDescription"), true, "app bundle explains system audio capture usage for real waveform")
}

private func testBuildScriptSignsAppBundleForTCCIdentity() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let scriptURL = projectRoot.appendingPathComponent("script/build_and_run.sh")
    let source = (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("ISLAND_CODESIGN_IDENTITY"), true, "build script allows a stable local signing identity")
    expectEqual(source.contains("security find-identity -v -p codesigning"), true, "build script discovers local signing identities")
    expectEqual(source.contains("codesign --force --deep --sign \"$CODESIGN_IDENTITY\""), true, "app bundle is signed after Info.plist is written")
    expectEqual(source.contains("codesign -dv"), true, "build script verifies the signed app identity")
}

private func testExpandedContentStartsBelowCameraHousingBand() {
    let metrics = NotchMetrics.preview14Inch
    let minimumContentStartY = metrics.closedHeight + metrics.closedStatusDotGuardInset

    expectEqual(
        metrics.expandedContentTopSpacerHeight >= minimumContentStartY,
        true,
        "expanded controls start below the camera housing band"
    )
}

private func testTaskActivityStateParsesOnlyExplicitDebugValues() {
    expectEqual(TaskActivityState(debugValue: "running"), .running, "debug state parses running")
    expectEqual(TaskActivityState(debugValue: "thinking"), .thinking, "debug state parses thinking")
    expectEqual(TaskActivityState(debugValue: "compacting"), .compacting, "debug state parses compacting")
    expectEqual(TaskActivityState(debugValue: "context_compression"), .compacting, "debug state parses context compression alias")
    expectEqual(TaskActivityState(debugValue: "  WARNING\n"), .warning, "debug state trims and lowercases")
    expectEqual(TaskActivityState(debugValue: "error"), .error, "debug state parses error")
    expectEqual(TaskActivityState(debugValue: "idle"), .idle, "debug state parses idle")
    expectEqual(TaskActivityState(debugValue: "Codex"), nil, "debug state does not treat process names as running")
    expectEqual(TaskActivityState(debugValue: ""), nil, "debug state ignores empty values")
}

private func testPanelDefaultsToCodexTaskActivityState() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Controllers/IslandPanelController.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(
        source.contains("taskActivityDataSource: any TaskActivityDataSource = CodexTaskActivityDataSource()"),
        true,
        "panel defaults to Codex session lifecycle task activity state"
    )
    expectEqual(
        source.contains("ClaudeTaskActivityDataSource"),
        false,
        "panel does not infer activity from persistent Codex or Claude app processes"
    )
}

private func testCodexTaskActivityDataSourceKeepsFileOverride() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Support/TaskActivityDataSource.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(
        source.contains("struct CodexTaskActivityDataSource"),
        true,
        "Codex task activity data source exists"
    )
    expectEqual(
        source.contains("FileBackedTaskActivityDataSource.readState"),
        true,
        "Codex task activity source keeps the explicit file state override"
    )
    expectEqual(
        source.contains("recentEventTypes"),
        true,
        "Codex task activity source reads recent session event types"
    )
}

private func testCodexUsageDataSourceDoesNotMergeClaudeSessionLogs() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Support/CodexUsageDataSource.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
    let legacyClaudeUsageSourceURL = projectRoot
        .appendingPathComponent("Sources/Island/Support/ClaudeUsageDataSource.swift")

    expectEqual(
        FileManager.default.fileExists(atPath: legacyClaudeUsageSourceURL.path),
        false,
        "legacy Claude usage source is removed from the app source tree"
    )
    expectEqual(
        source.contains("ClaudeUsageDataSource"),
        false,
        "codex usage stats do not silently merge Claude session logs"
    )
}

private func testCodexUsageDataSourcePrefersCCSwitchLedger() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Support/CodexUsageDataSource.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(
        source.contains("CCSwitchUsageDataSource.loadSummary"),
        true,
        "codex usage stats prefer the CC Switch usage ledger when available"
    )
    expectEqual(
        source.contains("fallbackSummary"),
        true,
        "codex usage stats keep local session logs as fallback"
    )
}

private func testCCSwitchUsageDataSourceDefaultsToAllSources() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Support/CCSwitchUsageDataSource.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(
        source.contains("appType: String? = nil"),
        true,
        "CC Switch usage source defaults to the same all-sources scope as the CC Switch dashboard"
    )
    expectEqual(
        source.contains("appType: String = \"codex\""),
        false,
        "CC Switch usage source does not force codex-only filtering by default"
    )
    expectEqual(
        source.contains("cacheCreationTokens"),
        true,
        "CC Switch usage source includes cache creation tokens in the real token total"
    )
    expectEqual(
        source.contains("effectiveUsageLogFilter"),
        true,
        "CC Switch usage source copies the upstream session/proxy dedupe filter"
    )
    expectEqual(
        source.contains("freshInputSQL"),
        true,
        "CC Switch usage source copies the upstream fresh-input normalization"
    )
    expectEqual(
        source.contains("inputTokens: freshInputTokens + cachedInputTokens"),
        true,
        "CC Switch usage source passes cache-inclusive input tokens for cache hit-rate math"
    )
    expectEqual(
        source.contains("events.append(contentsOf: loadDailyRollupEvents"),
        false,
        "CC Switch usage source does not double-count detail logs and daily rollups as events"
    )
}

private func testDataPanelShowsTopRightCostBadge() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Views/DataPanelView.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(
        source.contains("topRightCostBadge"),
        true,
        "data panel defines the top-right cost badge"
    )
    expectEqual(
        source.contains("costBadgeVerticalOffset"),
        true,
        "cost badge has an explicit vertical offset above the feature switcher"
    )
    expectEqual(
        source.contains("costBadgeVerticalOffset: CGFloat = -30"),
        true,
        "cost badge aligns vertically with the top status band centerline"
    )
    expectEqual(
        source.contains("Text(rangedUsageSummary.costSource == .ledger ? \"CCS\" : \"EST\")"),
        false,
        "cost badge does not show a CCS or EST source prefix before the amount"
    )
}

private func testCodexUsageSummaryComputesCachedInputHitRate() {
    let calendar = Calendar(identifier: .gregorian)
    let event = CodexUsageEvent(
        timestamp: Date(timeIntervalSince1970: 1_789_000_000),
        usage: CodexTokenUsage(
            inputTokens: 1_000,
            cachedInputTokens: 875,
            outputTokens: 120,
            reasoningOutputTokens: 0,
            totalTokens: 1_120
        )
    )
    let summary = CodexUsageSummary.build(events: [event], calendar: calendar, costEstimator: .zero)

    expectEqual(summary.cachedInputHitRate, 0.875, "cached input hit rate uses cached input over total input")
    expectEqual(CodexUsageSummary.empty.cachedInputHitRate, 0, "empty cached input hit rate is zero")
}

private func testDataPanelOverviewShowsCacheHitRateInsteadOfEstimatedCostCard() {
    let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("Sources/Island/Views/DataPanelView.swift")
    let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""

    expectEqual(source.contains("(\"CACHE HIT\", formatCacheHitRate(summary.cachedInputHitRate))"), true, "overview stats show cache hit rate card in English")
    expectEqual(source.contains("(\"命中缓存\", formatCacheHitRate(summary.cachedInputHitRate))"), false, "overview stats do not use Chinese cache hit label")
    expectEqual(source.contains("(\"EST COST\", formatCost(summary.estimatedCost))"), false, "overview stats no longer show estimated cost card")
    expectEqual(source.contains("formatCacheHitRate"), true, "data panel formats cache hit rate percentage")
}

private func testTaskActivityUsesApprovedStatusDotAnimationKinds() {
    expectEqual(TaskActivityState.idle.statusDotAnimationKind, .hidden, "idle hides the status dot")
    expectEqual(TaskActivityState.thinking.statusDotAnimationKind, .breathingGlow, "thinking uses green breathing glow")
    expectEqual(TaskActivityState.running.statusDotAnimationKind, .breathingGlow, "running uses green breathing glow")
    expectEqual(TaskActivityState.compacting.statusDotAnimationKind, .breathingGlow, "compacting uses green breathing glow")
    expectEqual(TaskActivityState.warning.statusDotAnimationKind, .breathingGlow, "warning uses yellow breathing glow")
    expectEqual(TaskActivityState.error.statusDotAnimationKind, .fastPulse, "error uses fast red pulse")
}

private func testCodexTaskActivityHeuristicUsesLifecycleEvents() {
    expectEqual(
        CodexTaskActivityHeuristic.state(
            recentEventTypes: ["task_started", "token_count", "function_call"],
            secondsSinceLatestWrite: 120
        ),
        .running,
        "task started without terminal event stays running"
    )
    expectEqual(
        CodexTaskActivityHeuristic.state(
            recentEventTypes: ["task_started", "token_count", "function_call"],
            secondsSinceLatestWrite: 1_200
        ),
        .idle,
        "stale task started without terminal event does not keep breathing forever"
    )
    expectEqual(
        CodexTaskActivityHeuristic.state(
            recentEventTypes: ["task_started", "token_count", "task_complete"],
            secondsSinceLatestWrite: 1
        ),
        .idle,
        "task complete stops breathing even when file was just written"
    )
    expectEqual(
        CodexTaskActivityHeuristic.state(
            recentEventTypes: ["task_started", "turn_aborted"],
            secondsSinceLatestWrite: 1
        ),
        .idle,
        "turn aborted stops breathing"
    )
    expectEqual(
        CodexTaskActivityHeuristic.state(
            recentEventTypes: ["token_count"],
            secondsSinceLatestWrite: 8
        ),
        .running,
        "recent token activity without lifecycle metadata is treated as active"
    )
    expectEqual(
        CodexTaskActivityHeuristic.state(
            recentEventTypes: ["token_count"],
            secondsSinceLatestWrite: 45
        ),
        .idle,
        "old token activity does not keep breathing forever"
    )
}

private func testCodexTaskActivityEventParsingReadsPayloadEventTypes() {
    let taskStartedLine = #"{"timestamp":"2026-06-15T02:56:35.514Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#
    let taskCompleteLine = #"{"timestamp":"2026-06-15T02:56:40.514Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}"#
    let functionCallLine = #"{"timestamp":"2026-06-15T02:56:37.514Z","type":"response_item","payload":{"type":"function_call","name":"exec_command"}}"#

    expectEqual(CodexTaskActivityEvent.eventType(in: taskStartedLine), "task_started", "Codex event parsing reads event_msg payload type")
    expectEqual(CodexTaskActivityEvent.eventType(in: taskCompleteLine), "task_complete", "Codex event parsing reads terminal payload type")
    expectEqual(CodexTaskActivityEvent.eventType(in: functionCallLine), "function_call", "Codex event parsing reads response item payload type")
}

private func testTaskActivityOverridePolicyOnlyUsesFreshManualState() {
    let now = Date(timeIntervalSinceReferenceDate: 1_000)

    expectEqual(
        TaskActivityOverridePolicy.effectiveState(
            .idle,
            modificationDate: now.addingTimeInterval(-10),
            now: now,
            freshnessSeconds: 300
        ),
        .idle,
        "fresh manual idle can force the status dot to stop for verification"
    )
    expectEqual(
        TaskActivityOverridePolicy.effectiveState(
            .running,
            modificationDate: now.addingTimeInterval(-10),
            now: now,
            freshnessSeconds: 300
        ),
        .running,
        "fresh manual running can force the status dot to breathe for verification"
    )
    expectEqual(
        TaskActivityOverridePolicy.effectiveState(
            .running,
            modificationDate: now.addingTimeInterval(-600),
            now: now,
            freshnessSeconds: 300
        ),
        nil,
        "stale manual running does not keep the status dot breathing forever"
    )
    expectEqual(
        TaskActivityOverridePolicy.effectiveState(
            nil,
            modificationDate: now,
            now: now,
            freshnessSeconds: 300
        ),
        nil,
        "missing manual state does not override automatic detection"
    )
}

private func testDataPanelMVPUsesApprovedModesAndCadence() {
    expectEqual(DataPanelMode.allCases.map(\.label), ["Trends", "Overview", "All"], "data panel mode labels")
    expectEqual(DataPanelMode.defaultMode, .all, "data panel default mode")
    expectEqual(DataPanelMode.trends.refreshCadenceSeconds, 30, "trends mock cadence")
    expectEqual(DataPanelMode.overview.refreshCadenceSeconds, 3600, "overview mock cadence")
    expectEqual(DataPanelMode.all.refreshCadenceSeconds, 30, "all mode fastest visible cadence")
    expectEqual(DataPanelMode.trends.shouldRefreshUsage(elapsedSeconds: 29), false, "trends waits for refresh cadence")
    expectEqual(DataPanelMode.trends.shouldRefreshUsage(elapsedSeconds: 30), true, "trends refreshes at cadence")
    expectEqual(DataPanelMode.overview.shouldRefreshUsage(elapsedSeconds: 3599), false, "overview avoids 30s log rescans")
    expectEqual(DataPanelMode.overview.shouldRefreshUsage(elapsedSeconds: 3600), true, "overview refreshes hourly")
    expectEqual(DataPanelMode.trends.showsTrendLayer, true, "trends mode shows trend layer")
    expectEqual(DataPanelMode.trends.showsOverviewLayer, false, "trends mode hides overview layer")
    expectEqual(DataPanelMode.overview.showsTrendLayer, false, "overview mode hides trend layer")
    expectEqual(DataPanelMode.overview.showsOverviewLayer, true, "overview mode shows overview layer")
    expectEqual(DataPanelMode.all.showsTrendLayer, true, "all mode shows trend layer")
    expectEqual(DataPanelMode.all.showsOverviewLayer, true, "all mode shows overview layer")
}

private func testDataPanelTooltipPolicyUsesApprovedModes() {
    expectEqual(DataPanelTooltipPolicy.isTrendTooltipEnabled(in: .trends), true, "trends mode enables trend tooltip")
    expectEqual(DataPanelTooltipPolicy.isTrendTooltipEnabled(in: .overview), false, "overview mode disables trend tooltip")
    expectEqual(DataPanelTooltipPolicy.isTrendTooltipEnabled(in: .all), false, "all mode disables trend tooltip")

    expectEqual(DataPanelTooltipPolicy.isCalendarTooltipEnabled(in: .overview), true, "overview mode enables calendar tooltip")
    expectEqual(DataPanelTooltipPolicy.isCalendarTooltipEnabled(in: .trends), false, "trends mode disables calendar tooltip")
    expectEqual(DataPanelTooltipPolicy.isCalendarTooltipEnabled(in: .all), false, "all mode disables calendar tooltip")
    expectEqual(DataPanelTooltipPolicy.calendarTooltipDelaySeconds, 3, "calendar tooltip uses three second hover delay")
}

private func testDataPanelTooltipFormatsTrendAndCalendarDetails() {
    let calendar = fixedCalendar()
    let timestamp = fixedDate(year: 2026, month: 6, day: 10, hour: 14, minute: 30, calendar: calendar)
    let trend = UsageTrendPoint(timestamp: timestamp, tokens: 15320, cost: 0.42, requests: 18)
    let trendTooltip = DataPanelTooltipPolicy.trendTooltip(for: trend, calendar: calendar)

    expectEqual(trendTooltip.title, "06/10 14:30", "trend tooltip uses timeline timestamp")
    expectEqual(trendTooltip.rows.map(\.label), ["Tokens", "Cost", "Requests"], "trend tooltip row labels")
    expectEqual(trendTooltip.rows.map(\.value), ["15.3K", "$0.42", "18"], "trend tooltip row values")

    let calendarCell = CalendarHeatmapCell(
        id: "date",
        date: timestamp,
        tokens: 2060,
        cost: 0.18,
        requests: 7,
        intensity: 0.8
    )
    let calendarTooltip = DataPanelTooltipPolicy.calendarTooltip(for: calendarCell, calendar: calendar)

    expectEqual(calendarTooltip?.title, "Jun 10, 2026", "calendar tooltip shows natural date")
    expectEqual(calendarTooltip?.subtitle, "2.1K tokens", "calendar tooltip shows compact token count")
}

private func testDataPanelTooltipIgnoresPaddingCalendarCells() {
    let calendar = fixedCalendar()
    let paddingCell = CalendarHeatmapCell(
        id: "padding",
        date: nil,
        tokens: 0,
        cost: 0,
        requests: 0,
        intensity: 0
    )

    expectEqual(DataPanelTooltipPolicy.calendarTooltip(for: paddingCell, calendar: calendar) == nil, true, "padding heatmap cells do not show tooltips")
}

private func testCalendarHeatmapVisualPolicyImprovesBlackBackgroundContrast() {
    expectEqual(CalendarHeatmapVisualPolicy.emptyCellOpacity(mode: .overview) >= 0.56, true, "overview empty heatmap cells remain readable on black")
    expectEqual(CalendarHeatmapVisualPolicy.emptyCellOpacity(mode: .all) >= 0.46, true, "all empty heatmap cells remain readable through overlay")
    expectEqual(
        CalendarHeatmapVisualPolicy.emptyCellOpacity(mode: .overview) > CalendarHeatmapVisualPolicy.emptyCellOpacity(mode: .all),
        true,
        "all mode only slightly lowers empty cell opacity"
    )
    expectEqual(CalendarHeatmapVisualPolicy.dataCellOpacity(intensity: 0, mode: .overview) > CalendarHeatmapVisualPolicy.emptyCellOpacity(mode: .overview), true, "overview data cells start clearer than empty cells")
    expectEqual(CalendarHeatmapVisualPolicy.dataCellOpacity(intensity: 1, mode: .overview) >= 0.96, true, "overview strongest data cell reaches clear blue")
    expectEqual(CalendarHeatmapVisualPolicy.dataCellOpacity(intensity: 1, mode: .all) >= 0.84, true, "all strongest data cell stays clear over trend layer")
    expectEqual(CalendarHeatmapVisualPolicy.cellBorderOpacity(isActive: false, mode: .overview) > 0.10, true, "empty cells keep subtle border")
    expectEqual(CalendarHeatmapVisualPolicy.cellBorderOpacity(isActive: true, mode: .overview) > CalendarHeatmapVisualPolicy.cellBorderOpacity(isActive: false, mode: .overview), true, "active cells keep slightly stronger border")
}

private func testNearestTrendTooltipPointUsesHorizontalPosition() {
    let calendar = fixedCalendar()
    let points = (0..<5).map { index in
        UsageTrendPoint(
            timestamp: fixedDate(year: 2026, month: 6, day: 10, hour: index, calendar: calendar),
            tokens: Double(index),
            cost: 0,
            requests: 0
        )
    }

    expectEqual(DataPanelTooltipPolicy.nearestTrendPointIndex(points: points, x: 0, plotMinX: 10, plotMaxX: 110), 0, "hover before plot clamps to first point")
    expectEqual(DataPanelTooltipPolicy.nearestTrendPointIndex(points: points, x: 62, plotMinX: 10, plotMaxX: 110), 2, "hover maps to nearest middle point")
    expectEqual(DataPanelTooltipPolicy.nearestTrendPointIndex(points: points, x: 140, plotMinX: 10, plotMaxX: 110), 4, "hover after plot clamps to last point")
    expectEqual(DataPanelTooltipPolicy.nearestTrendPointIndex(points: [], x: 62, plotMinX: 10, plotMaxX: 110), nil, "empty trend has no tooltip point")
}

private func testIslandFeatureUsesApprovedHierarchy() {
    expectEqual(IslandFeature.allCases.map(\.label), ["Status", "Stats", "Tools"], "top-level feature labels")
    expectEqual(IslandFeature.defaultFeature, .stats, "top-level feature defaults to stats")
}

private func testStatsTimeRangeUsesApprovedOrderAndNaturalDayStarts() {
    let calendar = fixedCalendar()
    let today = fixedDate(year: 2026, month: 6, day: 10, hour: 20, minute: 35, calendar: calendar)

    expectEqual(StatsTimeRange.allCases.map(\.label), ["Today", "7d", "30d", "All"], "stats time range labels")
    expectEqual(StatsTimeRange.today.startDate(today: today, calendar: calendar), fixedDate(year: 2026, month: 6, day: 10, calendar: calendar), "today starts at local midnight")
    expectEqual(StatsTimeRange.sevenDays.startDate(today: today, calendar: calendar), fixedDate(year: 2026, month: 6, day: 4, calendar: calendar), "seven days starts six days before today")
    expectEqual(StatsTimeRange.thirtyDays.startDate(today: today, calendar: calendar), fixedDate(year: 2026, month: 5, day: 12, calendar: calendar), "thirty days starts twenty-nine days before today")
    expectEqual(StatsTimeRange.all.startDate(today: today, calendar: calendar), fixedDate(year: 2025, month: 12, day: 11, calendar: calendar), "all uses recent six-month window")
}

private func fixedCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    calendar.firstWeekday = 2
    return calendar
}

private func fixedDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int = 0,
    minute: Int = 0,
    calendar: Calendar
) -> Date {
    DateComponents(
        calendar: calendar,
        timeZone: calendar.timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
    ).date ?? Date(timeIntervalSinceReferenceDate: 0)
}

private func testCalendarHeatmapUsesRealSevenDayRangeWithWeekPadding() {
    let calendar = fixedCalendar()
    let today = fixedDate(year: 2026, month: 6, day: 10, calendar: calendar)
    let expectedStart = fixedDate(year: 2026, month: 6, day: 4, calendar: calendar)
    let record = UsageHeatmapRecord(date: today, tokens: 100, cost: 5, requests: 10)
    let weeks = CalendarHeatmap.weeks(
        range: .sevenDays,
        today: today,
        calendar: calendar,
        records: [record]
    )
    let cells = weeks.flatMap(\.cells)
    let datedCells = cells.compactMap(\.date)
    let todayCell = cells.first { $0.date == today }
    let noDataCell = cells.first { $0.date == expectedStart }

    expectEqual(CalendarHeatmap.rowsPerWeek, 7, "calendar heatmap rows per week")
    expectEqual(weeks.count, 2, "seven day range pads to two week columns")
    expectEqual(weeks.allSatisfy { $0.cells.count == 7 }, true, "each heatmap week has seven weekdays")
    expectEqual(cells.count, 14, "seven day range includes visible week padding cells")
    expectEqual(datedCells.count, 7, "seven day range contains seven real dates")
    expectEqual(datedCells.first, expectedStart, "seven day range starts six days before today")
    expectEqual(datedCells.last, today, "seven day range ends today")
    expectEqual(cells.filter(\.isPadding).count, 7, "week padding cells do not represent data")
    expectEqual((todayCell?.intensity ?? 0) > 0, true, "recorded date has blue intensity")
    expectEqual(noDataCell?.intensity, 0, "real date without data stays low intensity")
}

private func testCalendarHeatmapTodayRangeUsesOneRealNaturalDate() {
    let calendar = fixedCalendar()
    let today = fixedDate(year: 2026, month: 6, day: 10, hour: 20, minute: 35, calendar: calendar)
    let todayStart = fixedDate(year: 2026, month: 6, day: 10, calendar: calendar)
    let yesterday = fixedDate(year: 2026, month: 6, day: 9, calendar: calendar)
    let weeks = CalendarHeatmap.weeks(
        range: .today,
        today: today,
        calendar: calendar,
        records: [
            UsageHeatmapRecord(date: yesterday, tokens: 999, cost: 9, requests: 9),
            UsageHeatmapRecord(date: today, tokens: 100, cost: 5, requests: 10)
        ]
    )
    let cells = weeks.flatMap(\.cells)
    let datedCells = cells.compactMap(\.date)
    let todayCell = cells.first { $0.date == todayStart }

    expectEqual(datedCells, [todayStart], "today heatmap contains only current natural day")
    expectEqual(cells.filter(\.isPadding).count, 6, "today range pads the rest of the week")
    expectEqual(todayCell?.tokens, 100, "today heatmap ignores previous day data")
    expectEqual((todayCell?.intensity ?? 0) > 0, true, "today heatmap shows current day intensity")
}

private func testCalendarHeatmapThirtyDayRangeUsesThirtyRealDates() {
    let calendar = fixedCalendar()
    let today = fixedDate(year: 2026, month: 6, day: 10, calendar: calendar)
    let expectedStart = fixedDate(year: 2026, month: 5, day: 12, calendar: calendar)
    let weeks = CalendarHeatmap.weeks(
        range: .thirtyDays,
        today: today,
        calendar: calendar,
        records: []
    )
    let cells = weeks.flatMap(\.cells)
    let datedCells = cells.compactMap(\.date)

    expectEqual(weeks.count, 5, "thirty day range pads to five week columns")
    expectEqual(datedCells.count, 30, "thirty day range contains thirty real dates")
    expectEqual(datedCells.first, expectedStart, "thirty day range starts twenty-nine days before today")
    expectEqual(datedCells.last, today, "thirty day range ends today")
    expectEqual(cells.filter(\.isPadding).count, 5, "thirty day range keeps padding separate from data")
}

private func testCalendarHeatmapAllRangeUsesSixMonthWindow() {
    let calendar = fixedCalendar()
    let today = fixedDate(year: 2026, month: 6, day: 10, calendar: calendar)
    let expectedStart = fixedDate(year: 2025, month: 12, day: 11, calendar: calendar)
    let oldRecord = fixedDate(year: 2025, month: 10, day: 1, calendar: calendar)
    let weeks = CalendarHeatmap.weeks(
        range: .all,
        today: today,
        calendar: calendar,
        records: [
            UsageHeatmapRecord(date: oldRecord, tokens: 10, cost: 1, requests: 2),
            UsageHeatmapRecord(date: today, tokens: 100, cost: 9, requests: 50)
        ]
    )
    let cells = weeks.flatMap(\.cells)
    let datedCells = cells.compactMap(\.date)
    let oldCell = cells.first { $0.date == oldRecord }

    expectEqual(datedCells.first, expectedStart, "all range starts at recent six-month window")
    expectEqual(datedCells.last, today, "all range ends today")
    expectEqual(oldCell == nil, true, "all range does not include older historical records")
}

private func testUsageTrendTimelineTodayUsesHourlyBucketsFromMidnight() {
    let calendar = fixedCalendar()
    let today = fixedDate(year: 2026, month: 6, day: 10, hour: 20, minute: 35, calendar: calendar)
    let yesterdayRecordTime = fixedDate(year: 2026, month: 6, day: 9, hour: 23, minute: 50, calendar: calendar)
    let todayRecordTime = fixedDate(year: 2026, month: 6, day: 10, hour: 8, minute: 15, calendar: calendar)
    let points = UsageTrendTimeline.points(
        range: .today,
        today: today,
        calendar: calendar,
        records: [
            UsageTrendRecord(timestamp: yesterdayRecordTime, tokens: 900, cost: 9, requests: 1),
            UsageTrendRecord(timestamp: todayRecordTime, tokens: 100, cost: 1, requests: 1)
        ]
    )
    let hourEight = points.first {
        calendar.component(.hour, from: $0.timestamp) == 8
    }

    expectEqual(points.count, 21, "today trend has hourly buckets through current hour")
    expectEqual(points.first?.timestamp, fixedDate(year: 2026, month: 6, day: 10, calendar: calendar), "today trend starts at local midnight")
    expectEqual(calendar.component(.hour, from: points.last?.timestamp ?? today), 20, "today trend ends at current hour")
    expectEqual(hourEight?.tokens, 100, "today trend includes current day records")
    expectEqual(points.map(\.tokens).contains(900), false, "today trend excludes previous day records")
}

private func testUsageTrendTimelineAllRangeUsesSixMonthDailyWindow() {
    let calendar = fixedCalendar()
    let today = fixedDate(year: 2026, month: 6, day: 10, hour: 20, minute: 35, calendar: calendar)
    let oldRecordTime = fixedDate(year: 2025, month: 10, day: 1, hour: 8, minute: 15, calendar: calendar)
    let firstVisibleRecordTime = fixedDate(year: 2025, month: 12, day: 11, hour: 8, minute: 45, calendar: calendar)
    let lateRecordTime = fixedDate(year: 2026, month: 6, day: 10, hour: 19, minute: 10, calendar: calendar)
    let points = UsageTrendTimeline.points(
        range: .all,
        today: today,
        calendar: calendar,
        records: [
            UsageTrendRecord(timestamp: oldRecordTime, tokens: 900, cost: 9, requests: 1),
            UsageTrendRecord(timestamp: firstVisibleRecordTime, tokens: 20, cost: 2, requests: 1),
            UsageTrendRecord(timestamp: lateRecordTime, tokens: 300, cost: 3, requests: 1)
        ]
    )
    let axisLabels = UsageTrendTimeline.axisLabels(
        points: points,
        maxCount: 6,
        calendar: calendar
    )

    expectEqual(points.first?.timestamp, fixedDate(year: 2025, month: 12, day: 11, calendar: calendar), "all trend starts at recent six-month window")
    expectEqual(points.last?.timestamp, fixedDate(year: 2026, month: 6, day: 10, calendar: calendar), "all trend ends today")
    expectEqual(points.map(\.tokens).contains(900), false, "all trend excludes older historical records")
    expectEqual(points.first?.tokens, 20, "all trend includes first visible day")
    expectEqual(points.last?.tokens, 300, "all trend includes current day")
    expectEqual(axisLabels.first, "12/11 00:00", "all axis starts with month day and time")
    expectEqual(axisLabels.last, "06/10 00:00", "all axis ends with current natural day")
}

private func testUsageTrendTimelineUsesDailyBucketsForThirtyDays() {
    let calendar = fixedCalendar()
    let today = fixedDate(year: 2026, month: 6, day: 10, hour: 20, minute: 35, calendar: calendar)
    let firstRecordTime = fixedDate(year: 2026, month: 5, day: 12, hour: 10, calendar: calendar)
    let lastRecordTime = fixedDate(year: 2026, month: 6, day: 10, hour: 14, calendar: calendar)
    let points = UsageTrendTimeline.points(
        range: .thirtyDays,
        today: today,
        calendar: calendar,
        records: [
            UsageTrendRecord(timestamp: firstRecordTime, tokens: 100, cost: 1, requests: 1),
            UsageTrendRecord(timestamp: lastRecordTime, tokens: 300, cost: 3, requests: 1)
        ]
    )
    let axisLabels = UsageTrendTimeline.axisLabels(
        points: points,
        maxCount: 5,
        calendar: calendar
    )

    expectEqual(points.count, 30, "thirty-day trend has thirty daily buckets")
    expectEqual(points.first?.timestamp, fixedDate(year: 2026, month: 5, day: 12, calendar: calendar), "thirty-day trend starts twenty-nine days before today")
    expectEqual(points.last?.timestamp, fixedDate(year: 2026, month: 6, day: 10, calendar: calendar), "thirty-day trend ends today")
    expectEqual(axisLabels.first, "05/12 00:00", "multi-day axis starts with month day and time")
    expectEqual(axisLabels.last, "06/10 00:00", "multi-day axis ends with month day and time")
}

private func testCodexUsageSummaryFiltersByStatsTimeRange() {
    let calendar = fixedCalendar()
    let today = fixedDate(year: 2026, month: 6, day: 10, hour: 20, minute: 35, calendar: calendar)
    let yesterday = fixedDate(year: 2026, month: 6, day: 9, hour: 11, calendar: calendar)
    let olderThanSixMonths = fixedDate(year: 2025, month: 10, day: 1, hour: 10, calendar: calendar)
    let events = [
        CodexUsageEvent(
            timestamp: olderThanSixMonths,
            usage: CodexTokenUsage(inputTokens: 1000, cachedInputTokens: 0, outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 1000),
            model: "old"
        ),
        CodexUsageEvent(
            timestamp: yesterday,
            usage: CodexTokenUsage(inputTokens: 300, cachedInputTokens: 0, outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 300),
            model: "weekly"
        ),
        CodexUsageEvent(
            timestamp: today,
            usage: CodexTokenUsage(inputTokens: 200, cachedInputTokens: 0, outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 200),
            model: "today"
        )
    ]
    let summary = CodexUsageSummary.build(events: events, calendar: calendar, costEstimator: .zero)
    let todaySummary = summary.filtered(range: .today, today: today, calendar: calendar, costEstimator: .zero)
    let sevenDaySummary = summary.filtered(range: .sevenDays, today: today, calendar: calendar, costEstimator: .zero)
    let allSummary = summary.filtered(range: .all, today: today, calendar: calendar, costEstimator: .zero)

    expectEqual(todaySummary.totalTokens, 200, "today summary includes only current natural day")
    expectEqual(todaySummary.requestCount, 1, "today summary request count")
    expectEqual(todaySummary.favoriteModel, "today", "today summary model preference")
    expectEqual(sevenDaySummary.totalTokens, 500, "seven day summary includes recent natural days")
    expectEqual(sevenDaySummary.requestCount, 2, "seven day summary request count")
    expectEqual(allSummary.totalTokens, 500, "all summary excludes records older than six-month window")
    expectEqual(allSummary.requestCount, 2, "all summary request count excludes old history")
}

private func testCodexUsageParserPrefersCumulativeTokenUsage() {
    let line = """
    {"timestamp":"2026-06-10T01:24:33.917Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"cached_input_tokens":100,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":320},"last_token_usage":{"input_tokens":200,"cached_input_tokens":40,"output_tokens":10,"reasoning_output_tokens":3,"total_tokens":210},"model_context_window":950000}}}
    """
    let parsed = CodexSessionLogParser.parseLine(line)

    guard case let .token(event)? = parsed else {
        fputs("FAIL: expected token usage event\n", stderr)
        Foundation.exit(1)
    }

    expectEqual(event.usage.inputTokens, 300, "parser prefers cumulative input tokens")
    expectEqual(event.usage.cachedInputTokens, 100, "parser prefers cumulative cached tokens")
    expectEqual(event.usage.outputTokens, 20, "parser prefers cumulative output tokens")
    expectEqual(event.usage.reasoningOutputTokens, 5, "parser prefers cumulative reasoning tokens")
    expectEqual(event.usage.totalTokens, 320, "parser prefers cumulative total tokens")
}

private func testCodexUsageParserFallsBackToLastUsageWhenCumulativeIsEmpty() {
    let line = """
    {"timestamp":"2026-06-15T01:07:27.030Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":0},"last_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"total_tokens":5413}}}}
    """
    let parsed = CodexSessionLogParser.parseLine(line)

    guard case let .token(event)? = parsed else {
        fputs("FAIL: expected fallback token usage event\n", stderr)
        Foundation.exit(1)
    }

    expectEqual(event.usage.inputTokens, 0, "fallback keeps empty last input tokens")
    expectEqual(event.usage.cachedInputTokens, 0, "fallback keeps empty last cached tokens")
    expectEqual(event.usage.outputTokens, 0, "fallback keeps empty last output tokens")
    expectEqual(event.usage.reasoningOutputTokens, 0, "fallback keeps empty last reasoning tokens")
    expectEqual(event.usage.totalTokens, 5413, "fallback keeps last total tokens")
}

private func testCodexUsageSummaryAggregatesRealDailyUsage() {
    let calendar = fixedCalendar()
    let firstDay = fixedDate(year: 2026, month: 6, day: 9, calendar: calendar)
    let secondDay = fixedDate(year: 2026, month: 6, day: 10, calendar: calendar)
    let events = [
        CodexUsageEvent(
            timestamp: firstDay,
            usage: CodexTokenUsage(
                inputTokens: 100,
                cachedInputTokens: 20,
                outputTokens: 30,
                reasoningOutputTokens: 4,
                totalTokens: 130
            ),
            model: "gpt-5.5"
        ),
        CodexUsageEvent(
            timestamp: secondDay,
            usage: CodexTokenUsage(
                inputTokens: 200,
                cachedInputTokens: 50,
                outputTokens: 80,
                reasoningOutputTokens: 10,
                totalTokens: 280
            ),
            model: "gpt-5.5"
        )
    ]
    let summary = CodexUsageSummary.build(
        events: events,
        calendar: calendar,
        costEstimator: .zero
    )

    expectEqual(summary.totalTokens, 410, "summary total tokens")
    expectEqual(summary.requestCount, 2, "summary request count")
    expectEqual(summary.activeDayCount, 2, "summary active days")
    expectEqual(summary.favoriteModel, "gpt-5.5", "summary favorite model")
    expectEqual(summary.heatmapRecords.count, 2, "summary heatmap record count")
    expectEqual(summary.heatmapRecords.map(\.requests), [1, 1], "summary heatmap request count")
    expectEqual(summary.trendPoints.map(\.tokens), [130, 280], "summary trend tokens")
}

private func shellLeftBoundaryAtBottomBand(metrics: NotchMetrics, y: CGFloat) -> CGFloat {
    let top = metrics.openTopCornerRadius
    let bottom = metrics.openBottomCornerRadius
    let curveTopY = metrics.openHeight - bottom

    guard y > curveTopY else {
        return top
    }

    let dy = metrics.openHeight - y
    let t = sqrt(max(0, dy / bottom))
    let oneMinusT = 1 - t
    let startX = top + bottom
    let controlX = top
    let endX = top

    return (oneMinusT * oneMinusT * startX)
        + (2 * oneMinusT * t * controlX)
        + (t * t * endX)
}

private func testExpandedBottomChipsHugBottomInnerEdge() {
    let metrics = NotchMetrics.preview14Inch
    let chipBottomY = metrics.expandedContentTopSpacerHeight
        + metrics.expandedContentSectionSpacing
        + metrics.expandedHeaderHeight
        + metrics.expandedContentSectionSpacing
        + metrics.expandedDemoSlotHeight
        + metrics.expandedContentSectionSpacing
        + metrics.expandedStatusChipHeight
    let totalContentHeight = chipBottomY + metrics.expandedContentBottomGuard
    let bottomGap = metrics.openHeight - chipBottomY
    let shellLeftBoundary = shellLeftBoundaryAtBottomBand(metrics: metrics, y: chipBottomY)
    let chipBottomLeftPaintX = metrics.expandedHorizontalContentPadding + metrics.expandedStatusChipCornerRadius
    let chipBottomRightPaintX = metrics.openWidth - metrics.expandedHorizontalContentPadding - metrics.expandedStatusChipCornerRadius
    let shellRightBoundary = metrics.openWidth - shellLeftBoundary
    let leftGap = chipBottomLeftPaintX - shellLeftBoundary
    let rightGap = shellRightBoundary - chipBottomRightPaintX

    expectEqual(metrics.expandedContentBottomEdgeInset, 2, "expanded bottom chip inset")
    expectEqual(bottomGap, metrics.expandedContentBottomEdgeInset, "expanded status chips hug bottom edge")
    expectEqual(totalContentHeight, metrics.openHeight, "expanded content fills open height with bottom inset")
    expectEqual(leftGap >= 1.5 && leftGap <= 2.5, true, "left chip bottom follows shell curve with near 2pt inset")
    expectEqual(rightGap >= 1.5 && rightGap <= 2.5, true, "right chip bottom follows shell curve with near 2pt inset")
}

testDerivesApprovedFourteenInchNotchMetrics()
testFallsBackToApprovedPreviewMetricsWhenScreenDataIsMissing()
testDoesNotShrinkBelowApprovedCameraHousingWhenScreenDataJitters()
testKeepsStatusSlotPinnedToCameraHousingLeftSide()
testClosedShellKeepsSymmetricSideSlots()
testUsesOneTopCornerRadiusForClosedAndOpenStates()
testCollapsedWindowOnlyCoversVisibleClosedIsland()
testClosedStatusDotStaysInsideVisibleLeftSlot()
testExpandedStatusDotMovesLeftWithoutTouchingOpenShell()
testStatusDotUsesSoftGlowVisualContract()
testStatusDotUsesDirectionalTravelWithoutRebound()
testExpandedTopStatusBandDefinesPhysicalRegions()
testTopStatusBandKeepsGlanceableItemsInApprovedRegions()
testOverlayUsesTopStatusBandContractForTopLaneItems()
testIslandAnimationProfileUsesSingleExpansionRhythm()
testOverlayAndPanelUseUnifiedAnimationProfile()
testTaskActivityBreathingContracts()
testTaskActivityBreathingStaysInsideStatusDotClip()
testStatusDotHostViewUsesOnlySafeHaloFrame()
testAudioWaveformUsesMarkedExpandedRightInfoRegion()
testAudioWaveformUsesContinuousTraceStyle()
testAudioWaveformDefaultsToStaticLineWithoutAudio()
testDefaultAudioSnapshotIsIdleStaticLine()
testOverlayInitialAudioPlaybackIsIdle()
testAudioWaveformConsumesRealAudioLevels()
testMusicWaveformPathDoesNotKeepHeartbeatRendering()
testAudioWaveformUsesTimelineForContinuousMotion()
testAudioPlaybackStateControlsWaveformActivity()
testAudioPlaybackSnapshotSeparatesPresentationModeFromDetectedAudio()
testAudioPlaybackSourceFallsBackToStaticLineWithoutPlayerProcess()
testIslandOverlayPassesAudioPlaybackStateToWaveform()
testIslandOverlayPausesWaveformWhileCollapsed()
testPanelPollsAudioPlaybackStateSeparatelyFromTaskActivity()
testAudioPlaybackSourceDefaultsToPrivacyFriendlyPlayerStateMode()
testAudioPlaybackSourceCanUseCoreAudioProcessTapForRealSamples()
testAudioPlaybackSourceDoesNotAskToLocateMissingPlayers()
testAudioPlaybackSourceUsesScreenCaptureKitForRealSamples()
testAudioPlaybackSourceReadsActualPCMFormatAndLogsCaptureState()
testAudioPlaybackSourceRequestsScreenCaptureAccessBeforeStartingStream()
testAppBundleDeclaresAppleEventsUsageForMusicDetection()
testBuildScriptSignsAppBundleForTCCIdentity()
testExpandedContentStartsBelowCameraHousingBand()
testTaskActivityStateParsesOnlyExplicitDebugValues()
testPanelDefaultsToCodexTaskActivityState()
testCodexTaskActivityDataSourceKeepsFileOverride()
testCodexUsageDataSourceDoesNotMergeClaudeSessionLogs()
testCodexUsageDataSourcePrefersCCSwitchLedger()
testCCSwitchUsageDataSourceDefaultsToAllSources()
testDataPanelShowsTopRightCostBadge()
testCodexUsageSummaryComputesCachedInputHitRate()
testDataPanelOverviewShowsCacheHitRateInsteadOfEstimatedCostCard()
testTaskActivityUsesApprovedStatusDotAnimationKinds()
testCodexTaskActivityHeuristicUsesLifecycleEvents()
testCodexTaskActivityEventParsingReadsPayloadEventTypes()
testTaskActivityOverridePolicyOnlyUsesFreshManualState()
testDataPanelMVPUsesApprovedModesAndCadence()
testDataPanelTooltipPolicyUsesApprovedModes()
testDataPanelTooltipFormatsTrendAndCalendarDetails()
testDataPanelTooltipIgnoresPaddingCalendarCells()
testCalendarHeatmapVisualPolicyImprovesBlackBackgroundContrast()
testNearestTrendTooltipPointUsesHorizontalPosition()
testIslandFeatureUsesApprovedHierarchy()
testStatsTimeRangeUsesApprovedOrderAndNaturalDayStarts()
testCalendarHeatmapUsesRealSevenDayRangeWithWeekPadding()
testCalendarHeatmapTodayRangeUsesOneRealNaturalDate()
testCalendarHeatmapThirtyDayRangeUsesThirtyRealDates()
testCalendarHeatmapAllRangeUsesSixMonthWindow()
testUsageTrendTimelineTodayUsesHourlyBucketsFromMidnight()
testUsageTrendTimelineAllRangeUsesSixMonthDailyWindow()
testUsageTrendTimelineUsesDailyBucketsForThirtyDays()
testCodexUsageParserPrefersCumulativeTokenUsage()
testCodexUsageParserFallsBackToLastUsageWhenCumulativeIsEmpty()
testCodexUsageSummaryAggregatesRealDailyUsage()
testCodexUsageSummaryFiltersByStatsTimeRange()
testExpandedBottomChipsHugBottomInnerEdge()

print("IslandCoreChecks passed")
