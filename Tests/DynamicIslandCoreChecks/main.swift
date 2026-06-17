import Foundation
import DynamicIslandCore

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

private func expectNearly(
    _ actual: Double,
    _ expected: Double,
    tolerance: Double = 0.0001,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard abs(actual - expected) <= tolerance else {
        fputs("FAIL: \(message). Expected \(expected), got \(actual) at \(file):\(line)\n", stderr)
        Foundation.exit(1)
    }
}

private func projectRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func source(_ path: String) -> String {
    (try? String(contentsOf: projectRoot().appendingPathComponent(path), encoding: .utf8)) ?? ""
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
    expectEqual(metrics.closedShellWidth, 260, "closed shell width")
    expectEqual(metrics.musicClosedShellWidth, 350, "music closed shell width")
    expectEqual(metrics.musicTrackInfoShellHeight, 72, "music track info shell height")
    expectEqual(metrics.closedTopCornerRadius, 30, "closed outer corner radius")
    expectEqual(metrics.closedConcaveTopRadius, 18, "closed concave top radius")
    expectEqual(metrics.closedBottomCornerRadius, 7, "closed inner corner radius")
    expectEqual(metrics.closedStatusDotGuardInset, 5, "closed status dot guard inset")
    expectEqual(metrics.closedMusicAccessoryGuardInset, 5, "closed music accessory guard inset")
    expectEqual(metrics.expandedContentGuardInset, 5, "expanded content guard inset")
    expectEqual(metrics.expandedContentBottomEdgeInset, 5, "expanded bottom edge inset")
    expectEqual(metrics.expandedContentBottomCornerClearance, 5, "expanded bottom corner clearance")
    expectEqual(metrics.expandedContentBottomGuard, 5, "expanded bottom guard")
    expectEqual(metrics.expandedHorizontalContentPadding, 21, "expanded horizontal content padding avoids rounded top corners")
    expectNearly(Double(metrics.closedMusicAccessorySize), 18, "closed music accessory size")
    expectEqual(metrics.expandedMusicArtworkCenterX, 48, "expanded music artwork center x")
    expectEqual(metrics.expandedMusicWaveformCenterX, 90, "expanded music waveform center x")
    expectEqual(metrics.expandedMusicAccessoryCenterY, 16, "expanded music accessory center y")
    let hasClosedMusicAccessory = metrics.closedMusicAccessorySize > 0
    expectEqual(
        !hasClosedMusicAccessory || Double(metrics.closedLeftMusicAccessoryCenterX - (metrics.closedMusicAccessorySize / 2)) + 0.0001 >= Double(metrics.closedTopCornerRadius + metrics.closedMusicAccessoryGuardInset),
        true,
        "left music accessory keeps a guard from the closed shell curved edge"
    )
    expectEqual(
        !hasClosedMusicAccessory || Double(metrics.closedLeftMusicAccessoryCenterX + (metrics.closedMusicAccessorySize / 2)) <= Double(metrics.musicCameraHousingLeftEdgeX - metrics.closedMusicAccessoryGuardInset) + 0.0001,
        true,
        "left music accessory keeps a guard from the physical camera housing"
    )
    expectEqual(
        !hasClosedMusicAccessory || Double(metrics.closedRightMusicAccessoryCenterX - (metrics.closedMusicAccessorySize / 2)) + 0.0001 >= Double(metrics.musicCameraHousingRightEdgeX + metrics.closedMusicAccessoryGuardInset),
        true,
        "right music accessory keeps a guard from the physical camera housing"
    )
    expectEqual(
        !hasClosedMusicAccessory || Double(metrics.closedRightMusicAccessoryCenterX + (metrics.closedMusicAccessorySize / 2)) <= Double(metrics.musicClosedShellWidth - metrics.closedTopCornerRadius - metrics.closedMusicAccessoryGuardInset) + 0.0001,
        true,
        "right music accessory keeps a guard from the closed shell curved edge"
    )
    expectEqual(metrics.openWidth, 650, "open width")
    expectEqual(metrics.openHeight, 230, "open height")
}

private func testTopStatusBandUsesFivePointBoundary() {
    let metrics = NotchMetrics.preview14Inch
    let layout = metrics.expandedTopStatusBandLayout

    expectEqual(layout.guardInset, 5, "top band guard inset")
    expectEqual(layout.leftStatusRegion.minX, metrics.openTopCornerRadius + 5, "left region avoids rounded top corner")
    expectEqual(layout.leftStatusRegion.minY, 5, "left region top boundary")
    expectEqual(layout.leftStatusRegion.maxY, metrics.closedHeight - 5, "left region bottom boundary")
    expectEqual(layout.rightInfoRegion.maxX, metrics.openWidth - metrics.openTopCornerRadius - 5, "right region avoids rounded top corner")
    expectEqual(layout.rightInfoRegion.minY, 5, "right region top boundary")
    expectEqual(layout.rightInfoRegion.maxY, metrics.closedHeight - 5, "right region bottom boundary")
}

private func testDisplayProfileDerivesMetricsFromScreenSignature() {
    let signature = DisplaySignature(
        frameWidth: 1512,
        frameHeight: 982,
        safeAreaTopInset: 32,
        auxiliaryTopLeftWidth: 663,
        auxiliaryTopRightWidth: 664,
        backingScaleFactor: 2
    )
    let profile = DisplayProfile(signature: signature, measuredAt: Date(timeIntervalSince1970: 0))

    expectEqual(profile.displayKind, .notchedCompact, "fourteen-inch style display uses compact notched profile")
    expectEqual(profile.metrics.cameraHousingWidth, 185, "display profile derives camera housing width")
    expectEqual(profile.metrics.closedShellWidth, 260, "display profile derives closed shell width")
    expectEqual(profile.metrics.openWidth, 650, "display profile derives open shell width")
    expectEqual(profile.metrics.openHeight, 230, "display profile derives open shell height")
    expectEqual(profile.matches(signature), true, "display profile matches the same signature")
}

private func testKeepsExpandableEmptyShellOnly() {
    let overlay = source("Sources/DynamicIsland/Views/IslandOverlayView.swift")
    let controller = source("Sources/DynamicIsland/Controllers/IslandPanelController.swift")
    let appDelegate = source("Sources/DynamicIsland/Controllers/AppDelegate.swift")
    let trackingView = source("Sources/DynamicIsland/Views/IslandTrackingHostingView.swift")
    let musicSource = source("Sources/DynamicIsland/Support/MusicPlaybackDataSource.swift")
    let avatarView = source("Sources/DynamicIsland/Views/ClosedMusicAvatarView.swift")
    let waveformView = source("Sources/DynamicIsland/Views/ClosedMusicWaveformView.swift")
    let islandShape = source("Sources/DynamicIsland/Views/IslandShape.swift")
    let buildScript = source("script/build_and_run.sh")

    expectEqual(overlay.contains("Color.white"), true, "overlay keeps the default shell fill white")
    expectEqual(overlay.contains("onExpansionChange(true)"), true, "overlay tap can expand the shell")
    expectEqual(overlay.contains("isShellHidden"), true, "overlay can visually hide the shell while keeping the tracking zone alive")
    expectEqual(overlay.contains("isTrackInfoPresented"), true, "overlay can present transient track info")
    expectEqual(overlay.contains("musicSkipFeedbackDirection"), false, "overlay no longer presents horizontal skip feedback")
    expectEqual(overlay.contains("musicSkipGestureProgress"), false, "overlay no longer tracks horizontal skip progress")
    expectEqual(overlay.contains("musicTrackInfoShellHeight"), true, "overlay expands the music shell downward for track info")
    expectEqual(overlay.contains("musicArtworkSize"), true, "overlay enlarges album artwork for track info")
    expectEqual(overlay.contains("trackTitleText"), true, "overlay renders track title text")
    expectEqual(overlay.contains("trackArtistText"), true, "overlay renders track artist text")
    expectEqual(overlay.contains("hiddenShellHorizontalScale"), true, "overlay squeezes the shell horizontally during hide/show transition")
    expectEqual(overlay.contains("state.isShellHidden ? 0.04 : 1"), true, "hidden shell closes from both sides toward the center")
    expectEqual(overlay.contains("hiddenShellOpacity"), true, "overlay fades the shell during hide/show transition")
    expectEqual(overlay.contains("scaleEffect(x: hiddenShellHorizontalScale, y: 1, anchor: .top)"), true, "hide/show animation expands and collapses horizontally from the center")
    expectEqual(overlay.contains("isHovered"), true, "overlay tracks hover state for the subtle preview effect")
    expectEqual(overlay.contains("hoverPreviewScale"), true, "overlay uses a subtle hover scale")
    expectEqual(overlay.contains(".shadow("), true, "overlay keeps a faint hover shadow")
    expectEqual(overlay.contains("showsHoverPreview ? 0.12 : 0"), true, "overlay uses a lighter native-like hover shadow opacity")
    expectEqual(overlay.contains("showsHoverPreview ? 6 : 0"), true, "overlay uses a tighter native-like hover shadow radius")
    expectEqual(overlay.contains("showsHoverPreview ? 1 : 0"), true, "overlay keeps the hover shadow close to the shell")
    expectEqual(overlay.contains("state.musicPlayback.isPlaying && !state.isShellHidden"), true, "overlay keeps music accessories visible while playing unless the shell is hidden")
    expectEqual(overlay.contains("metrics.closedMusicAccessorySize > 0"), true, "overlay does not animate zero-size compact music accessories")
    expectEqual(overlay.contains("metrics.musicClosedShellWidth"), true, "overlay animates the closed shell to the wider music width only while music is playing")
    expectEqual(overlay.contains("value: state.musicPlayback.isPlaying"), true, "overlay syncs shell width animation with music playback state")
    expectEqual(overlay.contains("musicArtworkCenterX"), true, "overlay animates artwork between closed and expanded positions")
    expectEqual(overlay.contains("musicWaveformCenterX"), true, "overlay animates waveform between closed and expanded positions")
    expectEqual(overlay.contains("metrics.expandedMusicArtworkCenterX"), true, "expanded artwork uses its own left-header target position")
    expectEqual(overlay.contains("metrics.expandedMusicWaveformCenterX"), true, "expanded waveform uses its own left-header target position")
    expectEqual(overlay.contains("frame(width: metrics.closedMusicAccessorySize, height: metrics.closedMusicAccessorySize)"), true, "expanded music accessories keep the compact 18pt size")
    expectEqual(overlay.contains(".transition(.opacity.combined(with: .scale(scale: 0.72)))"), true, "compact music accessories transition instead of snapping in")
    expectEqual(overlay.contains("value: showsMusicAccessories"), true, "music accessory transition is keyed to visibility")
    expectEqual(overlay.contains("VStack(alignment: .center"), true, "track title and artist are centered")
    expectEqual(overlay.contains(".multilineTextAlignment(.center)"), true, "track title and artist text aligns centered")
    expectEqual(overlay.contains(".linear(duration: 0.22)"), true, "track info uses linear animation")
    expectEqual(overlay.contains("skip.forward.fill"), false, "right swipe feedback icon is removed")
    expectEqual(overlay.contains("skip.backward.fill"), false, "left swipe feedback icon is removed")
    expectEqual(overlay.contains("musicSkipFeedbackIcon"), false, "skip feedback view is removed")
    expectEqual(overlay.contains("musicSkipStyleIsActive"), false, "skip feedback shell style gate is removed")
    expectEqual(overlay.contains("NSColor.systemPink"), false, "skip feedback waveform tint is removed")
    expectEqual(overlay.contains("concaveTopRadius:"), true, "overlay passes a separate concave top radius to the shell shape")
    expectEqual(overlay.contains("cameraCutoutWidth:"), false, "default shell stays as one continuous shape instead of cutting out the camera housing")
    expectEqual(islandShape.contains("var concaveTopRadius: CGFloat"), true, "island shape owns a separate concave top radius")
    expectEqual(islandShape.contains("var cameraCutoutWidth: CGFloat"), false, "island shape does not own a camera cutout width")
    expectEqual(islandShape.contains("addClosedSideSlot"), false, "island shape does not split the default shell into side slots")
    expectEqual(islandShape.contains("resolvedBaseHeight / 2"), false, "closed outer corner radius can exceed half the shell height when paired with a small inner radius")
    expectEqual(islandShape.contains("radiusScale"), false, "island shape keeps radius resolution simple")
    expectEqual(overlay.contains("private var bottomCornerRadius"), false, "overlay avoids trivial one-line radius wrappers")
    expectEqual(overlay.contains("ClosedMusicAvatarView(artworkData: state.musicPlayback.artworkData)"), true, "overlay passes album artwork to the rotating compact music avatar")
    expectEqual(overlay.contains("ClosedMusicWaveformView"), true, "overlay renders the compact music waveform")
    expectEqual(overlay.contains("barColor:"), false, "overlay no longer tints compact waveform bars for skip feedback")
    expectEqual(musicSource.contains("artworkData"), true, "music source carries artwork data for the compact avatar")
    expectEqual(musicSource.contains("title: String"), true, "music source carries the track title")
    expectEqual(musicSource.contains("artist: String"), true, "music source carries the track artist")
    expectEqual(musicSource.contains("trackIdentity"), true, "music source exposes a stable track identity")
    expectEqual(musicSource.contains("cacheDuration: TimeInterval = 1.5"), true, "music source keeps short caching while allowing timely track-change detection")
    expectEqual(musicSource.contains("artwork url of current track"), true, "music source can read Spotify artwork URL")
    expectEqual(musicSource.contains("data of artwork 1 of current track"), true, "music source can read Music artwork data")
    expectEqual(musicSource.contains("name of current track"), true, "music source reads track title from Music")
    expectEqual(musicSource.contains("artist of current track"), true, "music source reads track artist from Music")
    expectEqual(avatarView.contains("Image(nsImage:"), true, "compact avatar renders real artwork when available")
    expectEqual(avatarView.contains("TimelineView"), false, "compact avatar does not run a continuous rotation timeline")
    expectEqual(avatarView.contains("RoundedRectangle"), true, "compact avatar uses rounded album artwork")
    expectEqual(avatarView.contains("repeatForever"), false, "compact avatar stays static")
    expectEqual(avatarView.contains("rotationEffect"), false, "compact avatar does not rotate")
    expectEqual(avatarView.contains("Color.black"), true, "compact avatar fallback uses black contrast on the white shell")
    expectEqual(avatarView.contains(".stroke("), false, "compact avatar avoids an extra outline box around real artwork")
    expectEqual(avatarView.contains(".shadow("), false, "compact avatar avoids an extra square shadow around real artwork")
    expectEqual(avatarView.contains("AngularGradient"), false, "compact avatar fallback no longer uses a colored gradient")
    expectEqual(avatarView.contains("closedMusicAccessoryGuardInset"), false, "avatar view does not own layout guard math")
    expectEqual(waveformView.contains("Canvas"), false, "compact waveform avoids continuous canvas redraws")
    expectEqual(waveformView.contains("TimelineView"), false, "compact waveform does not run a continuous timeline in the closed shell")
    expectEqual(waveformView.contains("CABasicAnimation"), true, "compact waveform bars animate through Core Animation")
    expectEqual(waveformView.contains("transform.scale.y"), true, "compact waveform animates bar height on layers")
    expectEqual(waveformView.contains("NSColor.black"), true, "compact waveform uses black contrast on the white shell")
    expectEqual(waveformView.contains("barColor: NSColor"), false, "compact waveform has no unused skip tint API")
    expectEqual(waveformView.contains("ForEach(0..<4"), false, "compact waveform is no longer the simple four-bar placeholder")
    expectEqual(avatarView.contains("Text("), false, "compact avatar contains no text that can touch guard bounds")
    expectEqual(waveformView.contains("Text("), false, "compact waveform contains no text that can touch guard bounds")
    expectEqual(controller.contains("onMouseEntered = { [weak self] in"), true, "panel still listens for mouse enter")
    expectEqual(controller.contains("onMouseEntered = { [weak self] in\n            self?.setExpanded(true)\n        }"), false, "panel does not auto-expand on mouse enter")
    expectEqual(controller.contains("onMouseExited = { [weak self] in"), true, "panel still listens for mouse exit")
    expectEqual(trackingView.contains("override func scrollWheel"), true, "tracking view handles notch scroll gestures")
    expectEqual(trackingView.contains("onScroll?"), true, "tracking view forwards scroll delta to the controller")
    expectEqual(trackingView.contains("onScroll?(event.scrollingDeltaY)"), true, "tracking view forwards only vertical scroll delta")
    expectEqual(trackingView.contains("scrollingDeltaX"), false, "tracking view no longer forwards horizontal scroll delta")
    expectEqual(controller.contains("onScroll = { [weak self] deltaY in"), true, "panel installs a vertical scroll gesture callback")
    expectEqual(controller.contains("scrollActivationThreshold: CGFloat = 0.8"), true, "scroll hide/show uses a low trackpad activation threshold")
    expectEqual(controller.contains("horizontalStartThreshold"), false, "horizontal skip threshold is removed")
    expectEqual(controller.contains("horizontalCommitThreshold"), false, "horizontal skip commit threshold is removed")
    expectEqual(controller.contains("gestureResetDelay"), false, "horizontal gesture reset delay is removed")
    expectEqual(controller.contains("enum ActiveScrollGesture"), false, "scroll axis lock is removed with horizontal skip")
    expectEqual(controller.contains("case horizontal"), false, "horizontal gesture lock case is removed")
    expectEqual(controller.contains("accumulatedScrollDeltaX"), false, "horizontal scroll accumulation is removed")
    expectEqual(controller.contains("accumulatedScrollDeltaY"), false, "vertical scroll accumulation is no longer needed")
    expectEqual(controller.contains("hasTriggeredHorizontalSkip"), false, "one-shot horizontal skip state is removed")
    expectEqual(controller.contains("gestureResetWorkItem"), false, "horizontal gesture reset work item is removed")
    expectEqual(controller.contains("handleScroll(deltaY: deltaY)"), true, "scroll handling is centralized for vertical hide/show")
    expectEqual(controller.contains("let pointerInsideIsland = panel.frame.contains(NSEvent.mouseLocation)"), true, "all scroll gestures first verify the pointer is inside the island tracking zone")
    expectEqual(controller.contains("guard pointerInsideIsland else"), true, "scroll gestures outside the island tracking zone are ignored")
    expectEqual(controller.contains("if overlayState.isShellHidden"), true, "hidden state has first priority in scroll handling")
    expectEqual(controller.contains("deltaY < -Self.scrollActivationThreshold"), true, "natural trackpad upward scroll hides the shell with a short gesture")
    expectEqual(controller.contains("deltaY > Self.scrollActivationThreshold"), true, "natural trackpad downward scroll restores the hidden shell")
    expectEqual(controller.contains("performMusicSkip"), false, "panel no longer commits horizontal music skip")
    expectEqual(controller.contains("setShellHidden(false)"), true, "natural trackpad downward scroll restores the hidden shell")
    expectEqual(controller.contains("overlayState.isHovered = panel.frame.contains(NSEvent.mouseLocation)"), true, "restored shell immediately reflects hover when the pointer is still over the notch zone")
    expectEqual(overlay.contains("!state.isShellHidden"), true, "hidden shell does not reveal hover or accept expansion taps")
    expectEqual(overlay.contains(".allowsHitTesting(!state.isShellHidden)"), true, "hidden shell disables SwiftUI hit testing")
    expectEqual(controller.contains("panel.ignoresMouseEvents = hidden"), true, "hidden shell lets hover and click events pass through")
    expectEqual(controller.contains("NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel)"), true, "hidden shell keeps only a transparent scroll restore monitor")
    expectEqual(controller.contains("panel.frame.contains(NSEvent.mouseLocation)"), true, "hidden restore only responds inside the notch tracking zone")
    expectEqual(controller.contains("withAnimation(.easeInOut(duration: 0.22))"), true, "scroll hide/show uses a smooth transition")
    expectEqual(controller.contains("guard !usesOpenCanvas else { return metrics.openCompletionFeedbackWindowSize }"), true, "expanded canvas still uses the open shell size")
    expectEqual(controller.contains("metrics.musicClosedShellWidth + Self.closedHoverHorizontalSlack"), true, "closed canvas keeps horizontal room for music width and hover scale")
    expectEqual(controller.contains("(showsTrackInfo ? metrics.musicTrackInfoShellHeight : metrics.closedHeight) + Self.closedHoverBottomSlack"), true, "closed canvas expands only while track info is visible")
    expectEqual(controller.contains("startMusicPlaybackPolling"), true, "panel polls supported music players for compact accessories")
    expectEqual(controller.contains("2_000_000_000"), true, "panel uses a modest music polling interval")
    expectEqual(controller.contains("trackInfoDismissDelay: TimeInterval = 2.5"), true, "track info auto-dismisses after 2.5 seconds")
    expectEqual(controller.contains("lastPresentedTrackIdentity"), true, "panel detects song changes")
    expectEqual(controller.contains("trackInfoDismissWorkItem"), true, "panel cancels stale track info dismissals")
    expectEqual(controller.contains("overlayState.isTrackInfoPresented = true"), true, "panel shows track info when the song changes")
    expectEqual(controller.contains("overlayState.isTrackInfoPresented = false"), true, "panel restores default music state after track info")
    expectEqual(controller.contains("musicSkipFeedbackDirection"), false, "panel no longer presents directional skip feedback")
    expectEqual(musicSource.contains("enum MusicSkipDirection"), false, "music source no longer models skip directions")
    expectEqual(musicSource.contains("func skipTrack"), false, "music source no longer performs skip commands")
    expectEqual(musicSource.contains("next track"), false, "music source no longer sends next-track AppleScript")
    expectEqual(musicSource.contains("previous track"), false, "music source no longer sends previous-track AppleScript")
    expectEqual(controller.contains("ScreenMetricsProvider.profile"), true, "panel keeps display-aware shell sizing")
    expectEqual(appDelegate.contains("Show Dynamic Island"), true, "status menu can show the shell")
    expectEqual(appDelegate.contains("Hide Dynamic Island"), true, "status menu can hide the shell")
    expectEqual(appDelegate.contains("Quit Dynamic Island"), true, "status menu can quit the app")
    expectEqual(buildScript.contains("NSAppleEventsUsageDescription"), true, "app declares Apple Events usage for music playback detection")

    let removedActiveReferences = [
        "StatusDotView",
        "AudioWaveformView",
        "DataPanelView",
        "TemporaryFileShelfView",
        "taskActivityDataSource",
        "audioPlaybackDataSource",
        "TemporaryFileShelfStore",
        "startTaskActivityPolling",
        "startAudioPlaybackPolling",
        "startTemporaryFileShelfPruning",
        "Preview Completion Bounce",
        "registerForDraggedTypes",
        "NSScreenCaptureUsageDescription"
    ]

    for reference in removedActiveReferences {
        expectEqual(overlay.contains(reference), false, "overlay does not reference \(reference)")
        expectEqual(controller.contains(reference), false, "controller does not reference \(reference)")
        expectEqual(appDelegate.contains(reference), false, "app delegate does not reference \(reference)")
        expectEqual(trackingView.contains(reference), false, "tracking view does not reference \(reference)")
        expectEqual(buildScript.contains(reference), false, "build script does not reference \(reference)")
    }
}

private func testRemovedFeatureFilesAreGone() {
    let removedFiles = [
        "Sources/DynamicIsland/Views/StatusDotView.swift",
        "Sources/DynamicIsland/Views/AudioWaveformView.swift",
        "Sources/DynamicIsland/Views/DataPanelView.swift",
        "Sources/DynamicIsland/Views/TemporaryFileShelfView.swift",
        "Sources/DynamicIsland/Support/AudioPlaybackDataSource.swift",
        "Sources/DynamicIsland/Support/TaskActivityDataSource.swift",
        "Sources/DynamicIsland/Support/TemporaryFileShelfStore.swift",
        "Sources/DynamicIsland/Support/CodexUsageDataSource.swift",
        "Sources/DynamicIsland/Support/CCSwitchUsageDataSource.swift"
    ]

    for path in removedFiles {
        expectEqual(FileManager.default.fileExists(atPath: projectRoot().appendingPathComponent(path).path), false, "\(path) is removed from the empty-shell app")
    }
}

private func testBuildScriptStillPackagesSignedApp() {
    let buildScript = source("script/build_and_run.sh")

    expectEqual(buildScript.contains("swift build --product \"$APP_PRODUCT_NAME\""), true, "build script compiles Dynamic Island product")
    expectEqual(buildScript.contains("codesign --force --deep --sign"), true, "build script signs the app bundle")
    expectEqual(buildScript.contains("/usr/bin/open -n \"$APP_BUNDLE\""), true, "build script can launch the packaged app")
    expectEqual(buildScript.contains("--verify"), true, "build script keeps verification mode")
}

testDerivesApprovedFourteenInchNotchMetrics()
testTopStatusBandUsesFivePointBoundary()
testDisplayProfileDerivesMetricsFromScreenSignature()
testKeepsExpandableEmptyShellOnly()
testRemovedFeatureFilesAreGone()
testBuildScriptStillPackagesSignedApp()

print("DynamicIslandCoreChecks passed")
