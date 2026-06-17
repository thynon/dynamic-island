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
    expectEqual(metrics.closedShellWidth, 195, "closed shell width")
    expectEqual(metrics.musicClosedShellWidth, 260, "music closed shell width")
    expectEqual(metrics.closedTopCornerRadius, 16, "closed top corner radius")
    expectEqual(metrics.closedBottomCornerRadius, 16, "closed bottom corner radius")
    expectEqual(metrics.closedMusicAccessoryGuardInset, 2, "closed music accessory guard inset")
    expectEqual(metrics.closedMusicAccessorySize, 17.5, "closed music accessory size")
    expectEqual(
        metrics.closedLeftMusicAccessoryCenterX - (metrics.closedMusicAccessorySize / 2) >= metrics.closedTopCornerRadius + metrics.closedMusicAccessoryGuardInset,
        true,
        "left music accessory keeps a guard from the closed shell curved edge"
    )
    expectEqual(
        metrics.closedLeftMusicAccessoryCenterX + (metrics.closedMusicAccessorySize / 2) <= metrics.musicCameraHousingLeftEdgeX - metrics.closedMusicAccessoryGuardInset,
        true,
        "left music accessory keeps a guard from the physical camera housing"
    )
    expectEqual(
        metrics.closedRightMusicAccessoryCenterX - (metrics.closedMusicAccessorySize / 2) >= metrics.musicCameraHousingRightEdgeX + metrics.closedMusicAccessoryGuardInset,
        true,
        "right music accessory keeps a guard from the physical camera housing"
    )
    expectEqual(
        metrics.closedRightMusicAccessoryCenterX + (metrics.closedMusicAccessorySize / 2) <= metrics.musicClosedShellWidth - metrics.closedTopCornerRadius - metrics.closedMusicAccessoryGuardInset,
        true,
        "right music accessory keeps a guard from the closed shell curved edge"
    )
    expectEqual(metrics.openWidth, 650, "open width")
    expectEqual(metrics.openHeight, 230, "open height")
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
    expectEqual(profile.metrics.closedShellWidth, 195, "display profile derives closed shell width")
    expectEqual(profile.metrics.openWidth, 650, "display profile derives open shell width")
    expectEqual(profile.metrics.openHeight, 230, "display profile derives open shell height")
    expectEqual(profile.matches(signature), true, "display profile matches the same signature")
}

private func testKeepsExpandableEmptyShellOnly() {
    let overlay = source("Sources/Island/Views/IslandOverlayView.swift")
    let controller = source("Sources/Island/Controllers/IslandPanelController.swift")
    let appDelegate = source("Sources/Island/Controllers/AppDelegate.swift")
    let trackingView = source("Sources/Island/Views/IslandTrackingHostingView.swift")
    let musicSource = source("Sources/Island/Support/MusicPlaybackDataSource.swift")
    let avatarView = source("Sources/Island/Views/ClosedMusicAvatarView.swift")
    let waveformView = source("Sources/Island/Views/ClosedMusicWaveformView.swift")
    let buildScript = source("script/build_and_run.sh")

    expectEqual(overlay.contains("Color.white"), true, "overlay uses a white shell fill")
    expectEqual(overlay.contains("Color.black"), false, "overlay no longer uses a black shell fill")
    expectEqual(overlay.contains("onExpansionChange(true)"), true, "overlay tap can expand the shell")
    expectEqual(overlay.contains("isHovered"), true, "overlay tracks hover state for the subtle preview effect")
    expectEqual(overlay.contains("hoverPreviewScale"), true, "overlay uses a subtle hover scale")
    expectEqual(overlay.contains(".shadow("), true, "overlay keeps a faint hover shadow")
    expectEqual(overlay.contains("showsHoverPreview ? 0.12 : 0"), true, "overlay uses a lighter native-like hover shadow opacity")
    expectEqual(overlay.contains("showsHoverPreview ? 6 : 0"), true, "overlay uses a tighter native-like hover shadow radius")
    expectEqual(overlay.contains("showsHoverPreview ? 1 : 0"), true, "overlay keeps the hover shadow close to the shell")
    expectEqual(overlay.contains("state.musicPlayback.isPlaying && !isExpanded"), true, "overlay shows compact music accessories only while music is playing in the closed state")
    expectEqual(overlay.contains("metrics.musicClosedShellWidth"), true, "overlay animates the closed shell to the wider music width only while music is playing")
    expectEqual(overlay.contains("value: state.musicPlayback.isPlaying"), true, "overlay syncs shell width animation with music playback state")
    expectEqual(overlay.contains("ClosedMusicAvatarView(artworkData: state.musicPlayback.artworkData)"), true, "overlay passes album artwork to the rotating compact music avatar")
    expectEqual(overlay.contains("ClosedMusicWaveformView"), true, "overlay renders the compact music waveform")
    expectEqual(musicSource.contains("artworkData"), true, "music source carries artwork data for the compact avatar")
    expectEqual(musicSource.contains("artwork url of current track"), true, "music source can read Spotify artwork URL")
    expectEqual(musicSource.contains("data of artwork 1 of current track"), true, "music source can read Music artwork data")
    expectEqual(avatarView.contains("Image(nsImage:"), true, "compact avatar renders real artwork when available")
    expectEqual(avatarView.contains("Color.black"), true, "compact avatar fallback uses black contrast on the white shell")
    expectEqual(avatarView.contains("AngularGradient"), false, "compact avatar fallback no longer uses a colored gradient")
    expectEqual(avatarView.contains("closedMusicAccessoryGuardInset"), false, "avatar view does not own layout guard math")
    expectEqual(waveformView.contains("Canvas"), true, "compact waveform uses a polished canvas renderer")
    expectEqual(waveformView.contains(".color(.black)"), true, "compact waveform uses black contrast on the white shell")
    expectEqual(waveformView.contains("ForEach(0..<4"), false, "compact waveform is no longer the simple four-bar placeholder")
    expectEqual(avatarView.contains("Text("), false, "compact avatar contains no text that can touch guard bounds")
    expectEqual(waveformView.contains("Text("), false, "compact waveform contains no text that can touch guard bounds")
    expectEqual(controller.contains("onMouseEntered = { [weak self] in"), true, "panel still listens for mouse enter")
    expectEqual(controller.contains("onMouseEntered = { [weak self] in\n            self?.setExpanded(true)\n        }"), false, "panel does not auto-expand on mouse enter")
    expectEqual(controller.contains("onMouseExited = { [weak self] in"), true, "panel still listens for mouse exit")
    expectEqual(controller.contains("guard !usesOpenCanvas else { return metrics.openCompletionFeedbackWindowSize }"), true, "expanded canvas still uses the open shell size")
    expectEqual(controller.contains("metrics.musicClosedShellWidth + Self.closedHoverHorizontalSlack"), true, "closed canvas keeps horizontal room for music width and hover scale")
    expectEqual(controller.contains("metrics.closedHeight + Self.closedHoverBottomSlack"), true, "closed canvas keeps bottom room for hover shadow")
    expectEqual(controller.contains("startMusicPlaybackPolling"), true, "panel polls supported music players for compact accessories")
    expectEqual(controller.contains("ScreenMetricsProvider.profile"), true, "panel keeps display-aware shell sizing")
    expectEqual(appDelegate.contains("Show Island"), true, "status menu can show the shell")
    expectEqual(appDelegate.contains("Hide Island"), true, "status menu can hide the shell")
    expectEqual(appDelegate.contains("Quit Island"), true, "status menu can quit the app")
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
        "Sources/Island/Views/StatusDotView.swift",
        "Sources/Island/Views/AudioWaveformView.swift",
        "Sources/Island/Views/DataPanelView.swift",
        "Sources/Island/Views/TemporaryFileShelfView.swift",
        "Sources/Island/Support/AudioPlaybackDataSource.swift",
        "Sources/Island/Support/TaskActivityDataSource.swift",
        "Sources/Island/Support/TemporaryFileShelfStore.swift",
        "Sources/Island/Support/CodexUsageDataSource.swift",
        "Sources/Island/Support/CCSwitchUsageDataSource.swift"
    ]

    for path in removedFiles {
        expectEqual(FileManager.default.fileExists(atPath: projectRoot().appendingPathComponent(path).path), false, "\(path) is removed from the empty-shell app")
    }
}

private func testBuildScriptStillPackagesSignedApp() {
    let buildScript = source("script/build_and_run.sh")

    expectEqual(buildScript.contains("swift build --product \"$APP_NAME\""), true, "build script compiles Island product")
    expectEqual(buildScript.contains("codesign --force --deep --sign"), true, "build script signs the app bundle")
    expectEqual(buildScript.contains("/usr/bin/open -n \"$APP_BUNDLE\""), true, "build script can launch the packaged app")
    expectEqual(buildScript.contains("--verify"), true, "build script keeps verification mode")
}

testDerivesApprovedFourteenInchNotchMetrics()
testDisplayProfileDerivesMetricsFromScreenSignature()
testKeepsExpandableEmptyShellOnly()
testRemovedFeatureFilesAreGone()
testBuildScriptStillPackagesSignedApp()

print("IslandCoreChecks passed")
