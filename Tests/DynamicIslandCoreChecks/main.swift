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

private func islandOverlaySources() -> String {
    [
        "Sources/DynamicIsland/Views/IslandOverlayView.swift",
        "Sources/DynamicIsland/Views/IslandOverlayState.swift",
        "Sources/DynamicIsland/Views/IslandPrimaryFeature.swift",
        "Sources/DynamicIsland/Views/FileShelfActions.swift",
        "Sources/DynamicIsland/Views/CodexTasksContentView.swift",
        "Sources/DynamicIsland/Views/FilesPrimaryContentView.swift",
        "Sources/DynamicIsland/Views/CodexStatusBarView.swift"
    ].map(source).joined(separator: "\n")
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
    expectEqual(metrics.contentBoundaryInset, 5, "shared content boundary inset")
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
    expectEqual(metrics.openWidth, 850, "open width")
    expectEqual(metrics.openHeight, 200, "open height")
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

    let navigationFrame = layout.primaryNavigationFrame(width: 168, height: 22)
    expectEqual(navigationFrame.maxX, layout.rightInfoRegion.maxX, "primary navigation is right-aligned in the safe region")
    expectEqual(navigationFrame.minX >= layout.rightInfoRegion.minX, true, "primary navigation avoids the camera housing")
    expectEqual(navigationFrame.minY >= layout.rightInfoRegion.minY, true, "primary navigation keeps the top boundary")
    expectEqual(navigationFrame.maxY <= layout.rightInfoRegion.maxY, true, "primary navigation keeps the bottom boundary")
}

private func testCalibrationLayoutMarksSafeAndCameraRegions() {
    let metrics = NotchMetrics.preview14Inch
    let layout = IslandCalibrationLayout(metrics: metrics, hasCameraHousing: true)

    expectEqual(layout.shellBounds.width, metrics.openWidth, "calibration shell width")
    expectEqual(layout.shellBounds.height, metrics.openHeight, "calibration shell height")
    expectEqual(layout.contentBoundaryFrame.minX, 5, "calibration left content boundary")
    expectEqual(layout.contentBoundaryFrame.minY, 5, "calibration top content boundary")
    expectEqual(layout.contentBoundaryFrame.maxX, metrics.openWidth - 5, "calibration right content boundary")
    expectEqual(layout.contentBoundaryFrame.maxY, metrics.openHeight - 5, "calibration bottom content boundary")
    expectEqual(layout.cameraHousingForbiddenRegion, metrics.expandedTopStatusBandLayout.cameraHousingRegion, "notched displays expose the camera forbidden region")
    expectEqual(layout.leftSafeRegion, metrics.expandedTopStatusBandLayout.leftStatusRegion, "calibration left safe region")
    expectEqual(layout.rightSafeRegion, metrics.expandedTopStatusBandLayout.rightInfoRegion, "calibration right safe region")

    let nonNotchedLayout = IslandCalibrationLayout(metrics: metrics, hasCameraHousing: false)
    expectEqual(nonNotchedLayout.cameraHousingForbiddenRegion, nil, "non-notch displays do not mark a physical camera forbidden region")
}

private func testMusicSkipGestureStateMachineLocksDirectionAndCancelsRollback() {
    var gesture = MusicSkipGestureStateMachine(commitDistance: 50, cancelDistance: 38)

    expectEqual(
        gesture.update(accumulatedDeltaX: 20),
        .tracking(direction: .next, progress: 0.4),
        "right swipe starts next tracking"
    )
    expectEqual(
        gesture.update(accumulatedDeltaX: 55),
        .armed(direction: .next, progress: 1),
        "right swipe arms at commit distance"
    )
    expectEqual(
        gesture.update(accumulatedDeltaX: 34),
        .cancelled(direction: .next),
        "rollback cancels the armed next swipe"
    )
    expectEqual(
        gesture.update(accumulatedDeltaX: -70),
        .cancelled(direction: .next),
        "same gesture cannot flip to previous after rollback"
    )
    expectEqual(
        gesture.finish(shouldCommit: true),
        .cancelled(direction: .next),
        "cancelled gesture does not commit at finish"
    )

    gesture.reset()
    expectEqual(
        gesture.update(accumulatedDeltaX: -55),
        .armed(direction: .previous, progress: 1),
        "left swipe arms previous"
    )
    expectEqual(
        gesture.finish(shouldCommit: true),
        .committed(direction: .previous),
        "armed previous commits only at finish"
    )
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
    expectEqual(profile.metrics.openWidth, 850, "display profile derives open shell width")
    expectEqual(profile.metrics.openHeight, 200, "display profile derives open shell height")
    expectEqual(profile.matches(signature), true, "display profile matches the same signature")

    let moreSpaceSignature = DisplaySignature(
        frameWidth: 1800,
        frameHeight: 1169,
        safeAreaTopInset: 32,
        auxiliaryTopLeftWidth: 807,
        auxiliaryTopRightWidth: 808,
        backingScaleFactor: 2
    )
    let moreSpaceProfile = DisplayProfile(signature: moreSpaceSignature, measuredAt: Date(timeIntervalSince1970: 0))
    expectEqual(moreSpaceProfile.displayKind, .notchedLarge, "Apple more-space scaling uses the larger notched profile")
    expectEqual(moreSpaceProfile.metrics.openWidth, 850, "more-space scaling uses the requested expanded width")
    expectEqual(moreSpaceProfile.metrics.openHeight, 200, "more-space scaling uses the requested expanded height")
    expectEqual(moreSpaceProfile.matches(moreSpaceSignature), true, "more-space profile is cached by its exact display signature")
}

private func testReleaseDisplayAdaptationMatrixAndLeanContracts() {
    let compactAirSignature = DisplaySignature(
        frameWidth: 1470,
        frameHeight: 956,
        safeAreaTopInset: 32,
        auxiliaryTopLeftWidth: 642,
        auxiliaryTopRightWidth: 643,
        backingScaleFactor: 2
    )
    let compactAirProfile = DisplayProfile(signature: compactAirSignature, measuredAt: Date(timeIntervalSince1970: 0))
    expectEqual(compactAirProfile.displayKind, .notchedCompact, "13/15-inch Air style notch uses compact profile")
    expectEqual(compactAirProfile.metrics.cameraHousingWidth, 185, "compact notched displays preserve camera housing width")
    expectEqual(compactAirProfile.metrics.openWidth, 850, "compact notched displays use the requested expanded width")
    expectEqual(compactAirProfile.metrics.openHeight, 200, "compact notched displays use the requested expanded height")

    let sixteenInchSignature = DisplaySignature(
        frameWidth: 1728,
        frameHeight: 1117,
        safeAreaTopInset: 32,
        auxiliaryTopLeftWidth: 771,
        auxiliaryTopRightWidth: 772,
        backingScaleFactor: 2
    )
    let sixteenInchProfile = DisplayProfile(signature: sixteenInchSignature, measuredAt: Date(timeIntervalSince1970: 0))
    expectEqual(sixteenInchProfile.displayKind, .notchedLarge, "16-inch notch uses the larger notched profile")
    expectEqual(sixteenInchProfile.metrics.cameraHousingWidth, 185, "16-inch notch preserves the camera housing width")
    expectEqual(sixteenInchProfile.metrics.openWidth, 850, "16-inch notch uses the requested expanded width")
    expectEqual(sixteenInchProfile.metrics.openHeight, 200, "16-inch notch uses the requested expanded height")

    let standardDisplaySignature = DisplaySignature(
        frameWidth: 1440,
        frameHeight: 900,
        safeAreaTopInset: 0,
        auxiliaryTopLeftWidth: nil,
        auxiliaryTopRightWidth: nil,
        backingScaleFactor: 2
    )
    let standardDisplayProfile = DisplayProfile(signature: standardDisplaySignature, measuredAt: Date(timeIntervalSince1970: 0))
    expectEqual(standardDisplayProfile.displayKind, .standardDisplay, "non-notch displays use the standard display profile")
    expectEqual(standardDisplayProfile.metrics.closedHeight, 32, "non-notch displays keep a stable closed height")
    expectEqual(standardDisplayProfile.metrics.openWidth, 560, "standard displays use a compact expanded width")
    expectEqual(standardDisplayProfile.metrics.openHeight, 210, "standard displays use a compact expanded height")

    let notchMetrics = source("Sources/DynamicIslandCore/NotchMetrics.swift")
    let screenMetricsProvider = source("Sources/DynamicIsland/Support/ScreenMetricsProvider.swift")
    let displayProfileStore = source("Sources/DynamicIsland/Support/DisplayProfileStore.swift")
    expectEqual(notchMetrics.contains("overshootWidth"), false, "release metrics do not keep unused overshoot width state")
    expectEqual(notchMetrics.contains("overshootHeight"), false, "release metrics do not keep unused overshoot height state")
    expectEqual(notchMetrics.contains("expandedContentTopSpacerHeight"), false, "release metrics remove unused expanded content spacer state")
    expectEqual(notchMetrics.contains("defaultExpandedContentTopSpacerHeight"), false, "release metrics remove unused expanded content constants")
    expectEqual(notchMetrics.contains("closedWindowSize"), false, "release metrics remove unused closed window size helper")
    expectEqual(notchMetrics.contains("openWindowSize"), false, "release metrics remove unused open window size helper")
    expectEqual(screenMetricsProvider.contains("shouldShowCalibrationCaption"), false, "screen metrics provider does not keep unused calibration caption state")
    expectEqual(screenMetricsProvider.contains("let freshProfile = DisplayProfile(signature: signature)"), true, "screen metrics provider derives a fresh profile for cache compatibility checks")
    expectEqual(screenMetricsProvider.contains("cachedProfile.metrics == freshProfile.metrics"), true, "screen metrics provider invalidates cached display profiles when sizing policy changes")
    expectEqual(screenMetricsProvider.contains("store.save(freshProfile)"), true, "screen metrics provider refreshes stale cached display profiles")
    expectEqual(displayProfileStore.contains("currentProfile()"), false, "display profile store does not keep unused profile reader API")
}

private func testTemporaryFileShelfCoreModel() {
    let core = source("Sources/DynamicIslandCore/TemporaryFileShelf.swift")

    expectEqual(core.contains("import AppKit"), false, "temporary file shelf core has no AppKit dependency")
    expectEqual(core.contains("import SwiftUI"), false, "temporary file shelf core has no SwiftUI dependency")

    let now = Date(timeIntervalSince1970: 1_000)
    let old = Date(timeIntervalSince1970: 0)
    let expiredItem = TemporaryShelfItem(
        fileURL: URL(fileURLWithPath: "/tmp/expired.pdf"),
        addedAt: old,
        expiresAt: old.addingTimeInterval(1)
    )
    var shelf = TemporaryFileShelf(items: [expiredItem], now: now)

    expectEqual(shelf.items.isEmpty, true, "temporary file shelf prunes expired files at init")

    shelf.addFileURLs([
        URL(fileURLWithPath: "/tmp/photo.PNG"),
        URL(fileURLWithPath: "/tmp/notes.md"),
        URL(fileURLWithPath: "/tmp/budget.xlsx"),
        URL(fileURLWithPath: "/tmp/deck.key"),
        URL(fileURLWithPath: "/tmp/archive.zip")
    ], now: now)

    expectEqual(shelf.items.count, 5, "temporary file shelf stores dropped files in memory")
    expectEqual(shelf.items.map(\.category), [.images, .documents, .spreadsheets, .presentations, .other], "temporary file shelf classifies common file extensions")
    expectEqual(TemporaryShelfFileCategory.from(fileExtension: "png"), .images, "png is classified as Images")
    expectEqual(TemporaryShelfFileCategory.from(fileExtension: "pdf"), .documents, "pdf is classified as Documents")
    expectEqual(TemporaryShelfFileCategory.from(fileExtension: "md"), .documents, "md is classified as Documents")
    expectEqual(TemporaryShelfFileCategory.from(fileExtension: "xlsx"), .spreadsheets, "xlsx is classified as Spreadsheets")
    expectEqual(TemporaryShelfFileCategory.from(fileExtension: "csv"), .spreadsheets, "csv is classified as Spreadsheets")
    expectEqual(TemporaryShelfFileCategory.from(fileExtension: "pptx"), .presentations, "pptx is classified as Presentations")
    expectEqual(TemporaryShelfFileCategory.from(fileExtension: "key"), .presentations, "key is classified as Presentations")
    expectEqual(TemporaryShelfFileCategory.from(fileExtension: "unknown"), .other, "unknown extensions are classified as Other")

    shelf.addFileURLs([URL(fileURLWithPath: "/tmp/photo.PNG")], now: now.addingTimeInterval(10))
    expectEqual(shelf.items.count, 5, "temporary file shelf replaces duplicate file URLs instead of duplicating")
    expectEqual(shelf.items(filteredBy: .all).count, 5, "all filter returns every temporary file")
    expectEqual(shelf.items(filteredBy: .images).map(\.displayName), ["photo.PNG"], "image filter returns image files only")
    expectEqual(shelf.items(filteredBy: .documents).map(\.displayName), ["notes.md"], "documents filter returns document files only")
    expectEqual(shelf.items(filteredBy: .spreadsheets).map(\.displayName), ["budget.xlsx"], "spreadsheets filter returns spreadsheet files only")
    expectEqual(shelf.items(filteredBy: .presentations).map(\.displayName), ["deck.key"], "presentations filter returns presentation files only")
    expectEqual(shelf.items(filteredBy: .other).map(\.displayName), ["archive.zip"], "other filter returns unmatched files only")
    var selection = TemporaryFileShelfSelection()
    selection.selectOnly("/tmp/photo.PNG")
    selection.select(["/tmp/photo.PNG", "/tmp/missing.txt"])
    selection.retainOnly(itemIDs: shelf.items.map(\.id))
    expectEqual(selection.selectedItemIDs, ["/tmp/photo.PNG"], "temporary file shelf selection drops stale IDs")
    selection.toggle("/tmp/notes.md")
    expectEqual(selection.selectedItemIDs, ["/tmp/photo.PNG", "/tmp/notes.md"], "temporary file shelf selection can add an item")
    selection.toggle("/tmp/photo.PNG")
    expectEqual(selection.selectedItemIDs, ["/tmp/notes.md"], "temporary file shelf selection can remove a toggled item")

    shelf.removeItems(ids: ["/tmp/photo.PNG", "/tmp/notes.md"])
    selection.retainOnly(itemIDs: shelf.items.map(\.id))
    expectEqual(shelf.items.map(\.displayName), ["budget.xlsx", "deck.key", "archive.zip"], "temporary file shelf can remove several files at once")
    expectEqual(selection.selectedItemIDs, [], "temporary file shelf selection drops IDs removed by batch deletion")
}

private func testCodexReasoningEffortParsingAndTriggerPolicy() {
    let codexConfig = """
    model_provider = "custom"
    model = "gpt-5.5"
    model_reasoning_effort = "xhigh"
    """
    expectEqual(
        CodexReasoningEffort.fromCodexConfig(codexConfig),
        .xhigh,
        "Codex config parser reads xhigh model reasoning effort"
    )
    expectEqual(
        CodexReasoningEffort.fromCodexConfig("model_reasoning_effort = \"high\"")?.triggersEnergyTail,
        false,
        "high reasoning does not trigger the top-band energy tail"
    )
    expectEqual(
        CodexReasoningEffort.fromCodexConfig("model_reasoning_effort = \"max\"")?.triggersEnergyTail,
        true,
        "max reasoning triggers the top-band energy tail"
    )
    expectEqual(
        CodexReasoningEffort.fromCodexConfig("model_reasoning_effort = \"x-high\""),
        .xhigh,
        "Codex config parser accepts the x-high spelling"
    )

    let ccSwitchSettingsConfig = """
    {
      "auth": {"OPENAI_API_KEY": "redacted"},
      "config": "model_provider = \\"custom\\"\\nmodel_reasoning_effort = \\"xhigh\\"\\n"
    }
    """
    expectEqual(
        CodexReasoningEffort.fromCcSwitchProviderSettingsConfig(ccSwitchSettingsConfig),
        .xhigh,
        "CcSwitch provider settings parser reads the embedded Codex config"
    )
    expectEqual(
        CodexReasoningEffort.fromReasoningEffortValue("X High"),
        .xhigh,
        "reasoning effort parser accepts UI-style X High spelling"
    )
    expectEqual(
        CodexReasoningEffort.fromReasoningEffortValue("off")?.triggersEnergyTail,
        nil,
        "disabled realtime reasoning effort does not parse as an active effort"
    )
}

private func testCodexStatusBarContracts() {
    let snapshot = source("Sources/DynamicIslandCore/CodexStatusBarSnapshot.swift")
    let topBandLayout = source("Sources/DynamicIslandCore/IslandTopStatusBandLayout.swift")
    let primaryContentLayout = source("Sources/DynamicIslandCore/IslandPrimaryContentLayout.swift")
    let signalSource = source("Sources/DynamicIsland/Support/CodexStatusSignalSource.swift")
    let dismissalStore = source("Sources/DynamicIsland/Support/CodexTaskDismissalStore.swift")
    let statusBarView = source("Sources/DynamicIsland/Views/CodexStatusBarView.swift")
    let tasksContentView = source("Sources/DynamicIsland/Views/CodexTasksContentView.swift")
    let overlay = islandOverlaySources()
    let controller = source("Sources/DynamicIsland/Controllers/IslandPanelController.swift")

    expectEqual(snapshot.contains("public struct CodexStatusBarSnapshot"), true, "Codex status bar snapshot lives in the core layer")
    expectEqual(snapshot.contains("public struct CodexTaskStatus"), true, "Codex task rows have a core snapshot model")
    expectEqual(snapshot.contains("public enum ActivityState"), true, "Codex status bar snapshot models visible activity states")
    expectEqual(snapshot.contains("public enum ApprovalState"), true, "Codex task rows model right-side approval state")
    expectEqual(snapshot.contains("public let approvalState: ApprovalState"), true, "Codex task rows carry approval state for the reserved right slot")
    expectEqual(snapshot.contains("public let turnID: String?"), true, "Codex task rows carry a turn identity for dismissal")
    expectEqual(snapshot.contains("public var dismissalKey: String"), true, "Codex task rows derive a stable local dismissal key")
    expectEqual(snapshot.contains("public let tasks: [CodexTaskStatus]"), true, "Codex status snapshot can carry several Codex tasks")
    expectEqual(snapshot.contains("formattedElapsedTime"), true, "Codex status snapshot owns elapsed-time formatting")
    expectEqual(snapshot.contains("formattedTokenCount"), true, "Codex status snapshot owns token-count formatting")
    expectEqual(snapshot.contains("runningTasksText"), true, "Codex status snapshot owns running task copy")

    expectEqual(topBandLayout.contains("codexStatusFrame"), false, "Codex status no longer lives in the top green safe region")
    expectEqual(primaryContentLayout.contains("public struct IslandPrimaryContentLayout"), true, "expanded shell exposes a primary content layout contract")
    expectEqual(primaryContentLayout.contains("tasksContentFrame"), true, "primary content layout exposes the white-box Tasks content frame")
    expectEqual(primaryContentLayout.contains("filesContentFrame"), true, "primary content layout exposes a Files content frame")
    expectEqual(primaryContentLayout.contains("metrics.closedHeight + contentTopInset"), true, "Tasks content starts below the top 32pt status band")
    expectEqual(primaryContentLayout.contains("let contentTopInset = CGFloat(8)"), true, "primary content layout keeps a named top inset after the status band")
    expectEqual(primaryContentLayout.contains("metrics.openHeight - topY - contentTopInset"), true, "Files content uses equal top and bottom inset around the dashed regions")
    expectEqual(primaryContentLayout.contains("metrics.expandedHorizontalContentPadding"), true, "Tasks content avoids rounded top corners")

    expectEqual(signalSource.contains("final class CodexStatusSignalSource"), true, "app layer owns a reusable local Codex status reader")
    expectEqual(signalSource.contains("threadRefreshInterval"), true, "Codex status source does not spawn sqlite for every UI poll")
    expectEqual(signalSource.contains("completedTaskRetentionDuration: TimeInterval = 10"), true, "completed Codex tasks stay visible for only 10 seconds")
    expectEqual(signalSource.contains("rolloutFastTailMaximumBytes"), true, "Codex status source keeps a small fast rollout tail read")
    expectEqual(signalSource.contains("rolloutExpandedTailMaximumBytes"), true, "Codex status source can expand the rollout tail when task boundaries are missing")
    expectEqual(signalSource.contains("needsExpandedTailRead"), true, "Codex status source detects active-looking tails without task boundaries")
    expectEqual(signalSource.contains("readRecentLines(from: url, maximumBytes:"), true, "Codex status source passes an explicit rollout tail byte budget")
    expectEqual(signalSource.contains("cachedRolloutStates"), true, "Codex status source caches parsed rollout state between file changes")
    expectEqual(signalSource.contains("rolloutFileSignature"), true, "Codex status source keys rollout cache by file size and modification time")
    expectEqual(signalSource.contains("cachedGlobalStateSignature"), true, "Codex status source caches global approval state by file signature")
    expectEqual(signalSource.contains("cachedGlobalStateThreadIDs"), true, "Codex status source invalidates global approval cache when visible threads change")
    expectEqual(signalSource.contains("cachedGlobalStateSignature == signature"), true, "Codex status source avoids rescanning unchanged global approval state")
    expectEqual(signalSource.contains(".codex/state_5.sqlite"), true, "Codex status source reads Codex's local thread database")
    expectEqual(signalSource.contains("tokens_used"), true, "Codex status source reads stored thread token totals")
    expectEqual(signalSource.contains("LIMIT 4"), true, "Codex status source reads a bounded set of recent tasks")
    expectEqual(signalSource.contains("token_count"), true, "Codex status source reads rollout token_count events")
    expectEqual(signalSource.contains("task_started"), true, "Codex status source detects active Codex turns")
    expectEqual(signalSource.contains("task_complete"), true, "Codex status source detects completed Codex turns")
    expectEqual(signalSource.contains("case \"turn_aborted\""), true, "Codex status source treats aborted turns as terminal")
    expectEqual(signalSource.contains("case \"turn_failed\", \"turn_cancelled\""), true, "Codex status source treats failed and cancelled turns as terminal")
    expectEqual(signalSource.contains("case \"turn/completed\", \"turn/aborted\", \"turn/cancelled\", \"turn/failed\""), true, "Codex status source handles app-server terminal turn notifications")
    expectEqual(signalSource.contains("private func completeTurn"), true, "Codex status source centralizes terminal turn handling")
    expectEqual(signalSource.contains("staleTaskTimeoutDuration: TimeInterval = 60"), true, "Codex status source hides sessions that stop emitting events")
    expectEqual(signalSource.contains("rolloutState?.isRunning"), true, "Codex status source uses explicit rollout lifecycle state")
    expectEqual(signalSource.contains("item/commandExecution/requestApproval"), true, "Codex status source detects command approval requests")
    expectEqual(signalSource.contains("item/fileChange/requestApproval"), true, "Codex status source detects file-change approval requests")
    expectEqual(signalSource.contains("item/permissions/requestApproval"), true, "Codex status source detects permission approval requests")
    expectEqual(signalSource.contains("waitingOnApproval"), true, "Codex status source can read persisted active approval flags")
    expectEqual(signalSource.contains("isTaskVisible"), true, "Codex status source filters expired completed tasks")
    expectEqual(signalSource.contains("now.timeIntervalSince1970 - completedAt <= completedTaskRetentionDuration"), true, "completed task visibility uses the 10-second retention window")
    expectEqual(signalSource.contains("threadTitle"), true, "Codex status source keeps thread title for debug-only UI")

    expectEqual(tasksContentView.contains("struct CodexTasksContentView"), true, "Tasks primary feature renders Codex task content in the main content area")
    expectEqual(tasksContentView.contains("approvalSlotWidth"), true, "task rows reserve right-side space for future approval controls")
    expectEqual(tasksContentView.contains("statusColumnWidth"), true, "task rows keep a stable status column")
    expectEqual(tasksContentView.contains("statusColumnWidth: CGFloat = 260"), true, "status column is wide enough to show Running tool without truncation")
    expectEqual(tasksContentView.contains("approvalSlotWidth: CGFloat = 68"), true, "approval placeholder stays reserved without squeezing status text")
    expectEqual(tasksContentView.contains("rowHeight"), true, "task rows adapt height for one, two, or several tasks")
    expectEqual(tasksContentView.contains("prefix(maxVisibleTaskCount)"), true, "Tasks content caps visible rows to prevent overflow")
    expectEqual(tasksContentView.contains("snapshot.tasks"), true, "Tasks content renders only currently visible Codex tasks")
    expectEqual(tasksContentView.contains("dismissedTaskKeys"), true, "Tasks content keeps manually dismissed rows out of the current session")
    expectEqual(tasksContentView.contains("onDeleteTask"), true, "Tasks content delegates completed-row deletion to the controller")
    expectEqual(tasksContentView.contains("onUndoTask"), true, "Tasks content exposes a short undo action")
    expectEqual(dismissalStore.contains("codex-task-dismissals.json"), true, "task dismissal state uses a Dynamic Island-owned local file")
    expectEqual(dismissalStore.contains("retentionDuration: TimeInterval = 7 * 24 * 60 * 60"), true, "task dismissal state expires after a bounded retention period")
    expectEqual(dismissalStore.contains("try encoder.encode(dismissedAtByKey)"), true, "task dismissal state is persisted atomically")
    expectEqual(tasksContentView.contains("CodexTaskStatus("), false, "Tasks content does not synthesize a fake row after completed tasks expire")
    expectEqual(statusBarView.contains("lineLimit(1)"), true, "Tasks content truncates long task names instead of overflowing")
    expectEqual(statusBarView.contains("struct CodexStatusBarView"), true, "single task row rendering remains isolated")
    expectEqual(statusBarView.contains(".onHover { isInside in"), true, "completed task rows track cursor entry and exit")
    expectEqual(statusBarView.contains("xmark.circle.fill"), true, "completed task rows show a compact corner delete icon")
    expectEqual(statusBarView.contains("TaskShatterEffectView"), true, "completed task deletion renders a shatter effect")
    expectEqual(statusBarView.contains("isShattering"), true, "task deletion keeps the row mounted during the shatter animation")
    expectEqual(statusBarView.contains("ProgressView"), false, "Codex status bar avoids an always-animating SwiftUI progress spinner")
    expectEqual(statusBarView.contains("repeatForever"), false, "Codex status bar avoids continuous SwiftUI animation")
    expectEqual(statusBarView.contains("formattedElapsedTime"), true, "Codex status bar uses the core elapsed-time formatter")
    expectEqual(statusBarView.contains("formattedTokenCount"), true, "Codex status bar uses the core token formatter")
    expectEqual(statusBarView.contains("approvalBadge"), true, "Codex status bar renders the reserved approval slot as a status badge")
    expectEqual(statusBarView.contains("Button(action: beginDelete)"), true, "Codex status rows expose a delete action for completed tasks")
    expectEqual(statusBarView.contains("Button(action: approve"), false, "Codex approval hook does not approve from the island")
    expectEqual(statusBarView.contains("task.approvalState.displayText"), true, "approval badge text comes from the core task state")
    expectEqual(statusBarView.contains("return 9.5"), true, "status text uses compact type so Running tool fits in the status column")
    let activityIndex = statusBarView.range(of: "task.activityState.displayText")?.lowerBound
    let elapsedIndex = statusBarView.range(of: "task.formattedElapsedTime")?.lowerBound
    expectEqual(
        activityIndex != nil && elapsedIndex != nil && activityIndex! < elapsedIndex!,
        true,
        "status text starts with the activity so it is not the first part truncated"
    )

    expectEqual(overlay.contains("@Published var codexStatusBarSnapshot"), true, "overlay state publishes the Codex status bar snapshot")
    expectEqual(overlay.contains("@Published var dismissedCodexTaskKeys"), true, "overlay state publishes locally dismissed task keys")
    expectEqual(overlay.contains("CodexTasksContentView"), true, "expanded Tasks feature renders the Codex task list")
    expectEqual(overlay.contains("primaryContentFrame"), true, "Codex task list uses the primary content frame")
    expectEqual(overlay.contains("state.selectedPrimaryFeature == .tasks"), true, "Codex task list is scoped to the Tasks primary feature")
    expectEqual(overlay.contains("if isExpanded && state.selectedPrimaryFeature == .tasks {"), true, "Codex task list renders in normal expanded Tasks mode")
    expectEqual(overlay.contains("state.selectedPrimaryFeature == .tasks && state.isCalibrationOverlayVisible"), false, "Codex task list is not gated by the calibration layout overlay")
    expectEqual(overlay.contains("codexStatusFrame"), false, "Codex task list is not positioned in the top status band")

    expectEqual(controller.contains("startCodexStatusPolling"), true, "panel can poll local Codex status")
    expectEqual(controller.contains("startCodexStatusPolling()"), true, "panel starts Codex status polling outside calibration debug mode")
    expectEqual(controller.contains("if runtimeSettings.isCalibrationModeEnabled {\n            startCodexStatusPolling()\n        }"), false, "Codex status polling is not gated to calibration debug mode")
    expectEqual(controller.contains("stopCodexStatusPolling"), false, "unused Codex status polling stop path is removed")
    expectEqual(controller.contains("let codexStatusSignalSource = CodexStatusSignalSource()"), true, "panel reuses one Codex status source while polling")
    expectEqual(controller.contains("codexStatusSignalSource.currentSnapshot()"), true, "panel reads snapshots through the dedicated Codex status source")
    expectEqual(controller.contains("1_000_000_000"), true, "Codex status polling uses a conservative low-overhead interval")
    expectEqual(controller.contains("codexStatusBackgroundRefreshInterval: TimeInterval = 5"), true, "collapsed Codex status reads are throttled")
    expectEqual(controller.contains("let isTasksVisible = isExpanded"), true, "visible Tasks keeps realtime status refresh")
    expectEqual(controller.contains("overlayState.selectedPrimaryFeature == .tasks"), true, "realtime status refresh is scoped to the Tasks surface")
    expectEqual(controller.contains("private func dismissCodexTask"), true, "panel owns the completed task dismissal callback")
    expectEqual(controller.contains("codex.task.dismissed"), true, "manual task dismissal is logged")
    expectEqual(controller.contains("private func restoreCodexTask"), true, "panel owns the completed task undo callback")
    expectEqual(controller.contains("codex.task.dismissed.undo"), true, "manual task dismissal undo is logged")
    expectEqual(controller.contains("CodexTaskDismissalStore"), true, "panel persists local task dismissal state without mutating Codex data")
    expectEqual(controller.contains("\"threadTitle\""), false, "Codex status logs do not write raw Codex thread titles")
}

private func testTemporaryFileShelfExpandedDropIntegration() {
    let overlay = islandOverlaySources()
    let controller = source("Sources/DynamicIsland/Controllers/IslandPanelController.swift")
    let trackingView = source("Sources/DynamicIsland/Views/IslandTrackingHostingView.swift")
    let shelfView = source("Sources/DynamicIsland/Views/FileShelfOverlayView.swift")
    let filesContentView = source("Sources/DynamicIsland/Views/FilesPrimaryContentView.swift")
    let shelfStore = source("Sources/DynamicIsland/Support/TemporaryFileShelfStore.swift")
    let topBandLayout = source("Sources/DynamicIslandCore/IslandTopStatusBandLayout.swift")
    let topBandEnergyEffect = source("Sources/DynamicIsland/Views/TopBandEnergyEffectView.swift")
    let reasoningSignal = source("Sources/DynamicIsland/Support/CodexReasoningEffortSignalSource.swift")
    let reasoningEffort = source("Sources/DynamicIslandCore/CodexReasoningEffort.swift")
    let handleFileDropSection = controller
        .components(separatedBy: "private func handleFileDrop")
        .dropFirst()
        .first?
        .components(separatedBy: "private func selectTemporaryFile")
        .first ?? ""
    let fileDropTargetedSection = controller
        .components(separatedBy: "private func setFileDropTargeted")
        .dropFirst()
        .first?
        .components(separatedBy: "private func handleScroll")
        .first ?? ""
    let debugFileShelfLoadSection = controller
        .components(separatedBy: "private func loadDebugTemporaryFileShelfIfNeeded")
        .dropFirst()
        .first?
        .components(separatedBy: "private func startDebugPrimaryFeatureFrameCaptureIfNeeded")
        .first ?? ""
    let airDropTemporaryFilesSection = controller
        .components(separatedBy: "private func airDropTemporaryFiles")
        .dropFirst()
        .first?
        .components(separatedBy: "private func completeAirDropTemporaryFiles")
        .first ?? ""
    let filesPrimaryFeatureButtonSection = overlay
        .components(separatedBy: "private struct FilesPrimaryFeatureButton")
        .dropFirst()
        .first?
        .components(separatedBy: "private struct MusicSkipGlyph")
        .first ?? ""
    let filesPrimaryContentMountSection = overlay
        .components(separatedBy: "if isExpanded && state.selectedPrimaryFeature == .files")
        .dropFirst()
        .first?
        .components(separatedBy: "if isExpanded, state.isFileShelfOverlayVisible")
        .first ?? ""

    expectEqual(shelfStore.contains("@MainActor"), true, "temporary file shelf store stays on the main actor for UI state")
    expectEqual(shelfStore.contains("final class TemporaryFileShelfStore"), true, "temporary file shelf uses a dedicated in-memory app store")
    expectEqual(shelfStore.contains("@Published private(set) var shelf"), true, "temporary file shelf store publishes shelf state")
    expectEqual(shelfStore.contains("addFileURLs"), true, "temporary file shelf store accepts dropped file URLs")
    expectEqual(shelfStore.contains("removeItem"), true, "temporary file shelf store removes one item")
    expectEqual(shelfStore.contains("removeItems"), true, "temporary file shelf store removes several items")
    expectEqual(shelfStore.contains("clear()"), true, "temporary file shelf store clears all files")
    expectEqual(shelfStore.contains("pruneExpired"), true, "temporary file shelf store exposes an expiry cleanup entry point")
    expectEqual(shelfStore.contains("JSONEncoder"), false, "temporary file shelf store does not persist files")
    expectEqual(shelfStore.contains("write(to:"), false, "temporary file shelf store does not write persisted state")
    expectEqual(shelfStore.contains("Application Support"), false, "temporary file shelf store does not copy files into app support")
    expectEqual(shelfStore.contains("FileManager.default.copyItem"), false, "temporary file shelf store does not copy real files")

    expectEqual(trackingView.contains("var canAcceptFileDrop"), true, "tracking view asks the controller whether the current drop is valid")
    expectEqual(trackingView.contains("var onFileDrop"), true, "tracking view reports file URL drops")
    expectEqual(trackingView.contains("var onFileDropTargetedChange"), true, "tracking view reports visual drop targeting")
    expectEqual(trackingView.contains("registerForDraggedTypes([.fileURL])"), true, "tracking view registers for Finder file URL drags")
    expectEqual(trackingView.contains("override func draggingEntered"), true, "tracking view handles file drag entry")
    expectEqual(trackingView.contains("override func performDragOperation"), true, "tracking view performs file drop operations")
    expectEqual(trackingView.contains("draggingPasteboard.fileURLs"), true, "tracking view reads file URLs from the dragging pasteboard")

    expectEqual(controller.contains("TemporaryFileShelfStore"), true, "controller owns the temporary file shelf store")
    expectEqual(controller.contains("actions.onRemoveItems"), true, "controller wires the Files selected-item delete action")
    expectEqual(controller.contains("private func removeTemporaryFiles(ids itemIDs: [TemporaryShelfItem.ID])"), true, "controller exposes a selected-item removal entry point")
    expectEqual(controller.contains("let itemIDSet = Set(itemIDs)"), true, "selected-item deletion removes only the supplied IDs")
    expectEqual(controller.contains("file.shelf.removeMany"), true, "selected-item deletion is logged as temporary shelf removal")
    expectEqual(controller.contains("hostingView.canAcceptFileDrop"), true, "controller gates drag acceptance")
    expectEqual(controller.contains("hostingView.onFileDrop"), true, "controller receives dropped file URLs")
    expectEqual(controller.contains("handleFileDrop"), true, "controller routes dropped files through one handler")
    expectEqual(controller.contains("guard !overlayState.isShellHidden else { return false }"), true, "controller accepts file drags in visible closed or expanded shell states")
    expectEqual(controller.contains("isExpanded && !overlayState.isShellHidden"), false, "controller no longer restricts file drops to the expanded shell")
    expectEqual(controller.contains("pointerInsideInteractiveShell()"), true, "controller uses the precise island hit test for drop gating")
    expectEqual(controller.contains("screenPointFromDraggingLocation"), true, "controller converts AppKit dragging locations from window coordinates")
    expectEqual(controller.contains("panel.convertPoint(toScreen: dropPoint)"), true, "controller avoids double-converting dragging locations through the hosting view")
    expectEqual(handleFileDropSection.contains("setExpanded(true)"), false, "controller stages file drops without auto-expanding the island")
    expectEqual(handleFileDropSection.contains("overlayState.selectedPrimaryFeature = .files"), false, "controller does not auto-open Files after a file drop")
    expectEqual(fileDropTargetedSection.contains("overlayState.selectedPrimaryFeature = .files"), false, "hovering a file drag over the island does not auto-switch to Files")
    expectEqual(debugFileShelfLoadSection.contains("overlayState.selectedPrimaryFeature = .files"), false, "debug shelf preload does not auto-open Files")
    expectEqual(controller.contains("private func openFilesPrimaryFeature()"), true, "controller has an explicit user-click entry point for the Files feature")
    expectEqual(controller.contains("if overlayState.selectedPrimaryFeature == .files {\n            closeFilesPrimaryFeature()\n            return\n        }"), true, "Files button toggles off when Files is already open")
    expectEqual(controller.contains("private var lastNonFilesPrimaryFeature: IslandPrimaryFeature = .tasks"), true, "controller remembers the last non-Files primary feature")
    expectEqual(controller.contains("lastNonFilesPrimaryFeature = overlayState.selectedPrimaryFeature"), true, "controller captures the current primary feature before opening Files")
    expectEqual(controller.contains("private func closeFilesPrimaryFeature()"), true, "controller can close the Files primary feature from the Files button")
    expectEqual(controller.contains("overlayState.selectedPrimaryFeature = lastNonFilesPrimaryFeature\n        overlayState.isFileShelfOverlayVisible = false\n        overlayState.isFileShelfPinnedOpen = false"), true, "closing Files returns to the last non-Files primary feature and releases the pinned state")
    expectEqual(controller.contains("\"restoredPrimaryFeature\": lastNonFilesPrimaryFeature.rawValue"), true, "Files close logging records the restored primary feature")
    expectEqual(controller.contains("file.files.closed"), true, "Files close action is logged")
    expectEqual(controller.contains("overlayState.selectedPrimaryFeature = .files\n        overlayState.isFileShelfOverlayVisible = false\n        syncFilesPinnedOpenState()"), true, "explicit Files opening selects Files and syncs persistence from the display mode")
    expectEqual(controller.contains("actions.onOpenFilesPrimaryFeature"), true, "controller wires the Files button to the explicit opener")
    expectEqual(controller.contains("actions.onSetFilesDisplayMode"), true, "controller wires Files display mode changes")
    expectEqual(controller.contains("private func setFilesDisplayMode(_ mode: FilesDisplayMode)"), true, "controller has a dedicated Files display mode setter")
    expectEqual(controller.contains("private func shouldCollapseOnMouseExit()"), true, "controller centralizes the mouse-exit collapse decision")
    expectEqual(controller.contains("case .auto:\n            return true"), true, "auto display mode collapses Files on mouse exit")
    expectEqual(controller.contains("case .pinned:\n            return false"), true, "pinned display mode keeps Files expanded on mouse exit")
    expectEqual(controller.contains("case .untilEmpty:\n            return !temporaryFileShelfStore.shelf.hasItems"), true, "until-empty display mode keeps Files expanded only while files remain")
    expectEqual(controller.contains("airDropTemporaryFiles"), true, "controller can send staged files through AirDrop")
    expectEqual(controller.contains("private func airDropTemporaryFiles(ids requestedItemIDs: [TemporaryShelfItem.ID])"), true, "AirDrop receives concrete staged file IDs")
    expectEqual(controller.contains("let requestedItemIDSet = Set(requestedItemIDs)"), true, "AirDrop honors files dragged or selected for transfer")
    expectEqual(controller.contains("NSSharingService(named: .sendViaAirDrop)"), true, "AirDrop uses the macOS sharing service from the app layer")
    expectEqual(airDropTemporaryFilesSection.contains("removeTemporaryFiles"), false, "AirDrop does not remove files when the share panel merely opens")
    expectEqual(controller.contains("pendingAirDropItemIDs"), true, "controller tracks AirDrop item IDs so the drag completion path cannot remove them early")
    expectEqual(controller.contains("let externalItemIDs = itemIDs.subtracting(pendingAirDropItemIDs)"), true, "external drag completion ignores files currently pending AirDrop")
    expectEqual(controller.contains("AirDropSharingDelegate"), true, "AirDrop keeps a sharing delegate alive for success or cancellation callbacks")
    expectEqual(controller.contains("sharingService.delegate = delegate"), true, "AirDrop registers the delegate before opening the share panel")
    expectEqual(controller.contains("func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any])"), true, "AirDrop receives a successful share callback")
    expectEqual(controller.contains("completeAirDropTemporaryFiles"), true, "AirDrop success callback removes files automatically")
    expectEqual(controller.contains("removeTemporaryFiles(ids: itemIDs)"), true, "AirDrop success removes the staged files")
    expectEqual(controller.contains("\"undoAvailable\": true"), true, "AirDrop success exposes a short undo affordance")
    expectEqual(controller.contains("private func undoAirDropRemoval()"), true, "AirDrop removal can be restored with undo")
    expectEqual(controller.contains("temporaryFileShelfStore.addFileURLs(fileURLs)"), true, "AirDrop undo restores removed file references")
    expectEqual(controller.contains("pendingAirDropItemIDs.subtract(itemIDs)"), true, "AirDrop cancellation clears the pending marker")
    expectEqual(controller.contains("file.airdrop.cancelled"), true, "AirDrop cancellation is logged without removing staged files")
    expectEqual(controller.contains("startTemporaryFileShelfPruning"), true, "controller prunes expired temporary files on a low-frequency timer")
    expectEqual(controller.contains("60_000_000_000"), true, "temporary file shelf pruning runs every 60 seconds instead of high-frequency polling")
    expectEqual(controller.contains("ISLAND_DEBUG_FILE_SHELF_URLS"), true, "debug visual QA can preload temporary file references without cursor control")
    expectEqual(controller.contains("loadDebugTemporaryFileShelfIfNeeded"), true, "debug file shelf preload is isolated behind an explicit environment check")
    expectEqual(controller.contains("overlayState.temporaryFileShelf"), true, "controller syncs temporary file shelf state into the overlay")
    expectEqual(controller.contains("temporaryFileShelfSelection"), true, "controller owns temporary file shelf selection state")
    expectEqual(controller.contains("openTemporaryFileShelfOverlay"), true, "controller has a dedicated Files button overlay opener")
    expectEqual(controller.contains("closeTemporaryFileShelfOverlay"), true, "controller has a Done action that closes without clearing files")
    expectEqual(controller.contains("setTemporaryFileShelfFilter"), true, "controller updates file shelf filtering without mutating shelf data")
    expectEqual(controller.contains("selectTemporaryFile"), true, "controller handles temporary file selection")
    expectEqual(controller.contains("selectTemporaryFiles"), true, "controller handles temporary file rectangle selection")
    expectEqual(controller.contains("completeTemporaryFileDrag"), true, "controller handles external temporary file drag completion")
    expectEqual(controller.contains("removeTemporaryFiles(ids:"), true, "controller can remove multiple temporary files after successful drag")
    expectEqual(controller.contains("retainOnly(itemIDs:"), true, "controller keeps selection in sync with remaining shelf items")

    expectEqual(overlay.contains("@Published var temporaryFileShelf"), true, "overlay state publishes temporary file shelf contents")
    expectEqual(overlay.contains("@Published var temporaryFileShelfSelectedItemIDs"), true, "overlay state publishes selected temporary files")
    expectEqual(overlay.contains("@Published var airDropUndoItemCount"), true, "overlay state publishes AirDrop undo availability")
    expectEqual(overlay.contains("@Published var isFileShelfOverlayVisible"), true, "overlay state publishes whether the independent file shelf overlay is visible")
    expectEqual(overlay.contains("@Published var isFileShelfPinnedOpen"), true, "overlay state publishes whether the file shelf overlay is pinned")
    expectEqual(overlay.contains("@Published var isFileDropTargetActive"), true, "overlay state publishes active file drop targeting")
    expectEqual(overlay.contains("enum FilesDisplayMode"), true, "overlay models Files display modes")
    expectEqual(overlay.contains("@Published var filesDisplayMode: FilesDisplayMode = .pinned"), true, "Files opens in a persistent display mode by default")
    expectEqual(overlay.contains("@Published var temporaryFileShelfFilter"), true, "overlay state publishes file shelf filter state")
    expectEqual(overlay.contains("enum IslandPrimaryFeature"), true, "overlay models the expanded shell's top-level features")
    expectEqual(overlay.contains("case files"), true, "Files is a real primary feature selection")
    expectEqual(overlay.contains("rightNavigationCases"), true, "Files stays out of the right-side Tasks/Data/Tools/Settings switcher")
    expectEqual(overlay.contains("@Published var selectedPrimaryFeature: IslandPrimaryFeature = .tasks"), true, "overlay state publishes the selected top-level feature")
    expectEqual(overlay.contains("@Published var isTopBandEnergyEffectEnabled = false"), true, "overlay state gates the top-band energy effect from Codex reasoning effort")
    expectEqual(overlay.contains("state.isFileDropTargetActive && !isExpanded"), true, "closed shell uses drop targeting for hover-like file drag feedback")
    expectEqual(overlay.contains("FileShelfOverlayView"), true, "expanded overlay renders the file shelf as an independent overlay")
    expectEqual(overlay.contains("state.isFileShelfOverlayVisible"), true, "file shelf is not always mounted in expanded content")
    expectEqual(overlay.contains("FilesPrimaryFeatureButton"), true, "overlay has a left safe-zone Files primary feature button")
    expectEqual(overlay.contains("fileShelfActions.onOpenFilesPrimaryFeature()"), true, "Files button delegates opening and pinning to the controller")
    expectEqual(overlay.contains("filesPrimaryFeatureFrame"), true, "Files primary feature uses the top status band layout instead of hand-written coordinates")
    expectEqual(overlay.contains("fileShelfButtonFrame(width: 30, height: 22)"), true, "Files primary feature button is compact because the label text is removed")
    expectEqual(filesPrimaryFeatureButtonSection.contains("Text(\"Files\")"), false, "Files primary feature button keeps only the icon and badge, not a text label")
    expectEqual(filesPrimaryFeatureButtonSection.contains("isSelected ? \"tray.full.fill\" : \"tray.full\""), false, "Files primary feature button does not abruptly swap icon names")
    expectEqual(filesPrimaryFeatureButtonSection.contains("badgeText"), true, "Files primary feature button renders the file count as a badge")
    expectEqual(overlay.contains("displayMode: state.filesDisplayMode"), true, "Files primary content receives the current display mode")
    expectEqual(overlay.contains("onDisplayModeChange: fileShelfActions.onSetFilesDisplayMode"), true, "Files primary content can change the display mode")
    expectEqual(overlay.contains("airDropUndoItemCount: state.airDropUndoItemCount"), true, "Files primary content receives AirDrop undo availability")
    expectEqual(overlay.contains("onUndoAirDrop: fileShelfActions.onUndoAirDropItems"), true, "Files primary content can undo AirDrop auto-removal")
    expectEqual(overlay.contains("filesPrimaryContentFrame"), true, "Files primary content has its own balanced content frame")
    expectEqual(overlay.contains("metrics.expandedPrimaryContentLayout.filesContentFrame"), true, "Files primary content uses the core balanced content frame")
    expectEqual(overlay.contains("state.selectedPrimaryFeature == .files"), true, "Files content is scoped to the Files primary feature")
    expectEqual(overlay.contains("FilesPrimaryContentView"), true, "Files primary feature renders a dedicated staging content view")
    expectEqual(topBandLayout.contains("primaryNavigationFrame"), true, "top status band exposes a frame for the primary feature switcher")
    expectEqual(topBandLayout.contains("rightInfoRegion.maxX - resolvedWidth"), true, "primary feature switcher is anchored in the blue right safe region")
    expectEqual(overlay.contains("PrimaryFeatureSwitcher"), true, "expanded overlay renders the primary feature switcher")
    expectEqual(overlay.contains("TopBandEnergyEffectView"), true, "expanded overlay renders the energy effect in the top status band")
    expectEqual(overlay.contains("@State private var isTopBandEnergyActive = false"), true, "top band energy effect is delayed until expansion settles")
    expectEqual(overlay.contains("if isExpanded && state.isTopBandEnergyEffectEnabled && isTopBandEnergyActive"), true, "top band energy effect is not mounted unless xhigh reasoning is active and expansion has settled")
    expectEqual(overlay.contains("scheduleTopBandEnergyActivation"), true, "top band energy effect uses a dedicated activation delay")
    expectEqual(overlay.contains("topBandEnergyFrame"), true, "top band energy effect uses a dedicated top status band frame")
    expectEqual(overlay.contains("layout.rightInfoRegion.minX"), true, "top band energy effect starts at the debug blue right safe region")
    expectEqual(overlay.contains("metrics.openWidth - layout.rightInfoRegion.minX"), true, "top band energy effect fills the whole area to the right edge")
    expectEqual(overlay.contains(".allowsHitTesting(false)"), true, "top band energy effect does not intercept primary feature clicks")
    expectEqual(topBandEnergyEffect.contains("MTKView"), true, "top band energy effect uses a Metal view for the pixel field")
    expectEqual(topBandEnergyEffect.contains("preferredFramesPerSecond = 12"), true, "top band energy effect keeps animation cadence modest")
    expectEqual(topBandEnergyEffect.contains("metalView.isPaused = true"), true, "top band energy effect avoids an always-on Metal display link")
    expectEqual(topBandEnergyEffect.contains("renderTimer"), true, "top band energy effect uses an explicit low-frequency render timer")
    expectEqual(topBandEnergyEffect.contains("override func hitTest"), true, "top band energy effect refuses AppKit hit testing")
    expectEqual(topBandEnergyEffect.contains("cornerRadius"), false, "top band energy effect does not add its own rounded ends")
    expectEqual(topBandEnergyEffect.contains("trackHostView.layer?.masksToBounds = true"), true, "top band energy effect clips to the rectangular right region")
    expectEqual(topBandEnergyEffect.contains("metalView.layer?.masksToBounds = true"), true, "top band energy Metal layer clips to the rectangular right region")
    expectEqual(topBandEnergyEffect.contains("energyTailOriginX = 1.0"), true, "top band energy effect keeps the bright origin on the right side")
    expectEqual(topBandEnergyEffect.contains("didFireInitialBurst"), true, "top band energy effect defers the first burst until layout resolves")
    expectEqual(topBandEnergyEffect.contains("cssSize.x > 8"), true, "top band energy effect does not fire particles while the view still has its default tiny size")
    expectEqual(topBandEnergyEffect.contains("guard didFireInitialBurst else { return }"), true, "top band energy effect does not run auto bursts before the right-side first burst")
    expectEqual(topBandEnergyEffect.contains("v_uv.x / max(u_pos * resolution.x"), true, "top band energy effect fades from right to left")
    expectEqual(reasoningEffort.contains("public enum CodexReasoningEffort"), true, "Codex reasoning effort parsing is kept in the core layer")
    expectEqual(reasoningEffort.contains("fromCodexConfig"), true, "core parser can read model_reasoning_effort from Codex TOML")
    expectEqual(reasoningEffort.contains("fromCcSwitchProviderSettingsConfig"), true, "core parser can read CcSwitch provider settings without exposing auth data")
    expectEqual(reasoningSignal.contains("CodexReasoningEffortSignalSource"), true, "app layer owns the local CcSwitch/config file reader")
    expectEqual(reasoningSignal.contains("ccSwitchRealtimeSignalRelativePath"), true, "reasoning source checks the CcSwitch realtime request signal first")
    expectEqual(reasoningSignal.contains("realtimeSignalMaximumAge"), true, "reasoning source ignores stale realtime request signals")
    expectEqual(reasoningSignal.contains("func currentRealtimeSignal()"), true, "reasoning source exposes realtime reads without fallback sqlite work")
    expectEqual(reasoningSignal.contains("func currentFallbackSignal()"), true, "reasoning source keeps slower fallback reads isolated")
    expectEqual(reasoningSignal.contains("CodexReasoningEffort.fromReasoningEffortValue"), true, "reasoning source parses per-request effort values from realtime JSON")
    expectEqual(reasoningSignal.contains("active == false"), true, "inactive realtime request signals turn off the energy effect")
    expectEqual(reasoningSignal.contains("codexStateDatabaseRelativePath"), true, "reasoning source reads the Codex local thread database")
    expectEqual(reasoningSignal.contains(".codex/state_5.sqlite"), true, "reasoning source uses Codex's real state database")
    expectEqual(reasoningSignal.contains("reasoning_effort"), true, "reasoning source reads the persisted Codex thread effort")
    expectEqual(reasoningSignal.contains(".codexState"), true, "reasoning source reports when Codex state provides the effort signal")
    expectEqual(reasoningSignal.contains(".cc-switch/cc-switch.db"), true, "reasoning source checks the local CcSwitch database first")
    expectEqual(reasoningSignal.contains(".codex/config.toml"), true, "reasoning source falls back to the Codex config file last")
    expectEqual(reasoningSignal.contains("json_extract(settings_config, '$.config')"), true, "reasoning source queries only the embedded provider config from CcSwitch")
    expectEqual(controller.contains("startCodexReasoningEffortPolling"), true, "panel polls Codex reasoning effort at low frequency")
    expectEqual(controller.contains("overlayState.isTopBandEnergyEffectEnabled = signal.triggersEnergyTail"), true, "panel toggles the energy effect from xhigh/max reasoning")
    expectEqual(controller.contains("200_000_000"), true, "panel polls realtime Codex reasoning signal responsively without a display-link loop")
    expectEqual(controller.contains("codexReasoningFallbackRefreshInterval"), true, "panel throttles slower reasoning fallback reads separately from realtime polling")
    expectEqual(controller.contains("currentRealtimeSignal()"), true, "panel checks realtime reasoning signal every fast poll")
    expectEqual(controller.contains("currentFallbackSignal()"), true, "panel only runs slower fallback reasoning reads after the fallback interval")
    expectEqual(overlay.contains("private var primaryFeatureEntranceLayer: some View"), false, "primary feature switcher stays inside the shell instead of using an external stable layer")
    expectEqual(overlay.contains("private var primaryFeatureEntranceClipShape: IslandShape"), false, "primary feature switcher does not keep the reverted external clipping shape")
    expectEqual(overlay.contains("selection: $state.selectedPrimaryFeature"), true, "primary feature switcher stays a pure button group")
    expectEqual(overlay.contains("IslandPrimaryFeature.rightNavigationCases.enumerated()"), true, "right primary feature switcher renders only right safe-zone features in stable order")
    expectEqual(overlay.contains("private var primaryFeatureEntranceOffsetY: CGFloat"), false, "unused whole-group entrance offset remains removed")
    expectEqual(overlay.contains(".offset(y: isExpanded ? 0 : -primaryFeatureEntranceOffsetY)"), false, "top band energy effect does not move the primary feature group")
    expectEqual(overlay.contains(".offset(x: isExpanded ? 0 : -primaryFeatureEntranceOffset)"), false, "primary feature group no longer enters from the left")
    expectEqual(overlay.contains(".opacity(isExpanded ? 1 : 0)"), true, "primary feature group fades as one unit")
    expectEqual(overlay.contains(".animation(featureEntranceAnimation(index: index), value: isExpanded)"), true, "primary feature buttons use per-button staggered entrance animation")
    expectEqual(overlay.contains("featureFadeAnimation(index:"), false, "primary feature buttons do not stagger internally")
    expectEqual(overlay.contains("primaryFeatureFadeStaggerDelay"), false, "primary feature animation does not keep obsolete fade timing")
    expectEqual(overlay.contains("Animation.spring("), true, "primary feature entrance uses a spring for subtle rebound")
    expectEqual(overlay.contains("animationProfile.primaryFeatureEntranceResponse"), true, "primary feature spring response comes from the shared animation profile")
    expectEqual(overlay.contains("animationProfile.primaryFeatureEntranceDampingFraction"), true, "primary feature damping comes from the shared animation profile")
    expectEqual(overlay.contains("animationProfile.primaryFeatureEntranceBlendDuration"), true, "primary feature spring blend duration comes from the shared animation profile")
    expectEqual(overlay.contains("animationProfile.primaryFeatureEntranceDuration"), false, "primary feature entrance no longer uses a plain duration-only ease")
    expectEqual(overlay.contains("animationProfile.primaryFeatureEntranceStartDelay"), true, "primary feature entrance delay comes from the shared animation profile")
    expectEqual(IslandAnimationProfile.default.primaryFeatureEntranceStartDelay >= IslandAnimationProfile.default.expandResponse * 0.85, true, "primary feature entrance waits until horizontal shell expansion is visually stable")
    expectEqual(overlay.contains("primaryNavigationFrame"), true, "primary feature switcher uses the top status band layout")
    expectEqual(overlay.contains("Tasks"), true, "primary feature switcher includes Tasks")
    expectEqual(overlay.contains("Data"), true, "primary feature switcher includes Data")
    expectEqual(overlay.contains("Tools"), true, "primary feature switcher includes Tools")
    expectEqual(overlay.contains("Settings"), true, "primary feature switcher includes Settings")
    expectEqual(overlay.contains("private var expandedTemporaryShelfWidth: CGFloat {\n        metrics.openWidth\n    }"), true, "expanded temporary shelf receives the full shell width so its own 5pt boundary is explicit")
    expectEqual(overlay.contains("contentBoundaryInset: metrics.expandedContentGuardInset"), true, "expanded temporary shelf receives the canonical 5pt boundary from NotchMetrics")
    expectEqual(overlay.contains("topBoundaryInset: metrics.expandedHorizontalContentPadding"), true, "expanded temporary shelf header receives the corner-aware top boundary from NotchMetrics")
    expectEqual(overlay.contains(".position(x: metrics.openWidth / 2, y: expandedTemporaryShelfCenterY)"), true, "expanded temporary shelf stays centered inside the shell before applying its internal 5pt boundary")
    expectEqual(overlay.contains("onRemoveItem"), true, "expanded overlay can remove one temporary file")
    expectEqual(overlay.contains("onRemoveItems: fileShelfActions.onRemoveItems"), true, "Files primary content can remove selected temporary files")
    expectEqual(filesPrimaryContentMountSection.contains("onSelectItems: fileShelfActions.onSelectItems"), false, "Files primary toolbar does not auto-select batches for the user")
    expectEqual(overlay.contains("onClearItems"), true, "expanded overlay can clear temporary files")
    expectEqual(overlay.contains("onSelectItem"), true, "expanded overlay can select temporary files")
    expectEqual(overlay.contains("onSelectItems"), true, "expanded overlay can select several temporary files from rectangle selection")
    expectEqual(overlay.contains("onDragCompleted"), true, "expanded overlay can complete an external file drag")
    expectEqual(filesPrimaryFeatureButtonSection.contains("Image(systemName: \"tray.full\")"), true, "Files primary button keeps the closed icon available for cross-fade")
    expectEqual(filesPrimaryFeatureButtonSection.contains("Image(systemName: \"tray.full.fill\")"), true, "Files primary button keeps the opened icon available for cross-fade")
    expectEqual(filesPrimaryFeatureButtonSection.contains(".opacity(isSelected ? 0 : 1)"), true, "Files primary button fades out the closed icon when opened")
    expectEqual(filesPrimaryFeatureButtonSection.contains(".opacity(isSelected ? 1 : 0)"), true, "Files primary button fades in the opened icon when opened")
    expectEqual(filesPrimaryFeatureButtonSection.contains(".animation(.easeInOut(duration: 0.18), value: isSelected)"), true, "Files primary button animates the icon state change")
    expectEqual(filesPrimaryContentMountSection.contains(".transition(.opacity)"), true, "Files primary content fades in and out with the feature state")
    expectEqual(overlay.contains(".animation(.easeInOut(duration: 0.18), value: state.selectedPrimaryFeature)"), true, "primary feature content changes are animated, not just the Files icon")

    expectEqual(filesContentView.contains("struct FilesPrimaryContentView"), true, "Files primary feature has a dedicated content view")
    expectEqual(filesContentView.contains("let onAirDrop: ([TemporaryShelfItem.ID]) -> Void"), true, "Files primary feature exposes an ID-scoped AirDrop action")
    expectEqual(filesContentView.contains("let onRemoveItems: ([TemporaryShelfItem.ID]) -> Void"), true, "Files primary feature exposes selected-item deletion")
    expectEqual(filesContentView.contains("let onSelectItems: ([TemporaryShelfItem.ID], Bool) -> Void"), false, "Files primary feature does not expose a select-all toolbar action")
    expectEqual(filesContentView.contains("airDropZone"), true, "Files primary feature renders the left AirDrop zone")
    expectEqual(filesContentView.contains("previewZone"), true, "Files primary feature renders the right file preview zone")
    expectEqual(filesContentView.contains("GeometryReader"), true, "Files primary feature sizes dashed zones to the full content area")
    expectEqual(filesContentView.contains("airDropZoneWidth(for: proxy.size.width)"), true, "AirDrop width adapts to the available content width")
    expectEqual(filesContentView.contains("contentWidth * 0.30"), true, "AirDrop width keeps the preview usable on compact displays")
    expectEqual(filesContentView.contains("height: proxy.size.height"), true, "file preview dashed zone fills its whole right area")
    expectEqual(filesContentView.contains("Color.gray.opacity"), true, "Files primary feature uses gray dashed rounded regions")
    expectEqual(filesContentView.contains("dash: [5, 5]"), true, "Files primary feature emphasizes the AirDrop and preview areas with dashed borders")
    expectEqual(filesContentView.contains("ScrollView(.horizontal"), true, "Files primary preview scrolls left and right")
    expectEqual(filesContentView.contains("ScrollView(.vertical"), false, "Files primary preview does not use vertical scrolling")
    expectEqual(filesContentView.contains("LazyHGrid"), true, "Files primary preview lays files out in a horizontal multi-row grid")
    expectEqual(filesContentView.contains("GridItem(.adaptive(minimum: fileTileHeight"), true, "Files primary preview adapts rows inside the horizontal scroll area")
    expectEqual(filesContentView.contains("previewHorizontalInset"), true, "Files primary preview uses explicit left and right spacing")
    expectEqual(filesContentView.contains("fileTileSpacing"), true, "Files primary preview uses explicit spacing between file tiles")
    expectEqual(filesContentView.contains("previewToolbar"), true, "Files primary preview has a compact top-right toolbar")
    expectEqual(filesContentView.contains("FilesMultiSelectionButton"), true, "Files primary preview exposes a multi-select mode button before delete")
    expectEqual(filesContentView.contains("@State private var isMultiSelectionEnabled = false"), true, "Files primary preview stores multi-select mode locally")
    expectEqual(filesContentView.contains("onToggle: { isMultiSelectionEnabled.toggle() }"), true, "Files multi-select button toggles mode instead of selecting every file")
    expectEqual(filesContentView.contains("onSelectItems([], false)"), false, "Files multi-select button does not clear selection as a bulk action")
    expectEqual(filesContentView.contains("onSelectItems(shelf.items.map(\\.id), false)"), false, "Files multi-select button does not select every staged file")
    expectEqual(filesContentView.contains("fileSelectionIndicator(isSelected:"), true, "Files primary tiles show selectable indicators in multi-select mode")
    expectEqual(filesContentView.contains("let extendingSelection = isMultiSelectionEnabled ||"), true, "Files tile clicks toggle individual files while multi-select mode is enabled")
    expectEqual(filesContentView.contains("FilesDeleteSelectionButton"), true, "Files primary preview exposes a selected-item delete button")
    expectEqual(filesContentView.contains("selectedCount: selectedItemIDs.count"), true, "Files delete button is driven by selected file count")
    expectEqual(filesContentView.contains("onRemoveItems(Array(selectedItemIDs))"), true, "Files delete button removes only selected files")
    expectEqual(filesContentView.contains(".disabled(!isEnabled)"), true, "Files delete button is disabled when no files are selected")
    expectEqual(filesContentView.contains("FilesDisplayModeControl"), true, "Files primary preview exposes display persistence controls")
    expectEqual(filesContentView.contains("airDropUndoControl"), true, "Files AirDrop zone exposes an undo control after automatic removal")
    expectEqual(filesContentView.contains("Button(action: onUndoAirDrop)"), true, "Files AirDrop undo is a single action, not a manual confirmation step")
    expectEqual(filesContentView.contains("NSWorkspace.shared.icon"), true, "Files primary preview uses native file icons for non-image files")
    expectEqual(filesContentView.contains("NSImage(contentsOf: item.fileURL)"), false, "Files primary grid avoids synchronous image loading for every staged file")
    expectEqual(filesContentView.contains("FilesAirDropTargetView"), true, "Files primary feature accepts staged-file drops on the AirDrop zone")
    expectEqual(filesContentView.contains("override func performDragOperation"), true, "Files AirDrop zone performs real file URL drop operations")
    expectEqual(filesContentView.contains("matchedItemIDs"), true, "Files AirDrop zone maps dropped file URLs back to staged file IDs")
    expectEqual(filesContentView.contains("onAirDrop?(itemIDs)"), true, "Files AirDrop zone sends the dragged staged files")
    expectEqual(filesContentView.contains("FilesPrimaryDragSourceView"), true, "Files preview zone has its own AppKit drag source")
    expectEqual(filesContentView.contains("NSDraggingSource"), true, "Files preview drag source reports external drag completion")
    expectEqual(filesContentView.contains("NSDraggingItem"), true, "Files preview drag source creates real file drag items")
    expectEqual(filesContentView.contains("pasteboardWriter: shelfItem.fileURL as NSURL"), true, "Files preview drag source exports real file URL pasteboard writers")
    expectEqual(filesContentView.contains("let dragIcon = NSWorkspace.shared.icon"), true, "Files preview drag source reuses one drag icon to reduce drag-start work")
    expectEqual(filesContentView.contains("return [item]"), true, "Files preview defaults to dragging only the current preview item unless selection is active")
    expectEqual(filesContentView.contains("private func isExternalSuccessfulDrag"), true, "Files preview only removes files after successful external drops")
    expectEqual(filesContentView.contains("window?.frame.contains(screenPoint) == true"), true, "Files preview does not treat drops back inside the island as sent")

    expectEqual(shelfView.contains("struct FileShelfOverlayView"), true, "temporary file shelf view is implemented as an independent overlay view")
    expectEqual(shelfView.contains("TemporaryFileShelf"), true, "temporary file shelf view receives the core shelf model")
    expectEqual(shelfView.contains("TemporaryFileShelfFilter"), true, "temporary file shelf view receives filter state")
    expectEqual(shelfView.contains("selectedItemIDs"), true, "temporary file shelf view receives selection state")
    expectEqual(shelfView.contains("isDropTargetActive"), true, "temporary file shelf view shows drag target state")
    expectEqual(shelfView.contains("onFilterChange"), true, "temporary file shelf view exposes filter changes")
    expectEqual(shelfView.contains("onDone"), true, "temporary file shelf view exposes a Done action")
    expectEqual(shelfView.contains("onClearSelection"), true, "temporary file shelf view can clear selection from blank space")
    expectEqual(shelfView.contains("onSelectItem"), true, "temporary file shelf view exposes item selection")
    expectEqual(shelfView.contains("onSelectItems"), true, "temporary file shelf view exposes rectangle-selected items")
    expectEqual(shelfView.contains("onRemoveItem"), true, "temporary file shelf view exposes single-item removal")
    expectEqual(shelfView.contains("onClear"), true, "temporary file shelf view exposes clear-all")
    expectEqual(shelfView.contains("onDragCompleted"), true, "temporary file shelf view reports completed drag sessions")
    expectEqual(shelfView.contains("TemporaryFileDragSourceView"), true, "temporary file shelf view uses an AppKit drag source bridge")
    expectEqual(shelfView.contains("NSDraggingSource"), true, "temporary file shelf drag bridge receives external drag completion operations")
    expectEqual(shelfView.contains("NSDraggingItem"), true, "temporary file shelf drag bridge creates real file drag items")
    expectEqual(shelfView.contains("private let selectionDragThreshold: CGFloat = 5"), true, "temporary file shelf rectangle selection waits for a 5pt drag")
    expectEqual(shelfView.contains("temporaryFileTileFramePreferenceKey"), true, "temporary file shelf collects visible tile frames for rectangle selection")
    expectEqual(shelfView.contains("selectionRect"), true, "temporary file shelf draws and uses a selection rectangle")
    expectEqual(shelfView.contains("intersects(selectionRect)"), true, "temporary file shelf selects visible items whose frames intersect the rectangle")
    expectEqual(shelfView.contains("pasteboardWriter: shelfItem.fileURL as NSURL"), true, "temporary file shelf exports real file URL pasteboard writers")
    expectEqual(shelfView.contains("endedAt screenPoint: NSPoint, operation: NSDragOperation"), true, "temporary file shelf drag bridge detects successful external drops")
    expectEqual(shelfView.contains("private func isExternalSuccessfulDrag"), true, "temporary file shelf only removes files after an external successful drop")
    expectEqual(shelfView.contains("window?.frame.contains(screenPoint) == true"), true, "temporary file shelf treats drops back inside the island as cancelled")
    expectEqual(shelfView.contains("onDragCompleted?(activeDragItemIDs, operation != [])"), false, "temporary file shelf does not delete files just because AppKit returned a non-empty operation")
    expectEqual(shelfView.contains("ScrollView"), true, "temporary file shelf view can fit several files without growing beyond the shell")
    expectEqual(shelfView.contains("TemporaryFileShelfFilter.allCases"), true, "temporary file shelf renders a stable filter bar")
    expectEqual(shelfView.contains("private var visibleItems: [TemporaryShelfItem]"), true, "temporary file shelf uses a compact visible item list for the limited island height")
    expectEqual(shelfView.contains("shelf.items(filteredBy: filter)"), true, "temporary file shelf filters through the core filtering API")
    expectEqual(shelfView.contains("Text(item.category.title)"), true, "temporary file shelf keeps category information inside compact file tiles")
    expectEqual(shelfView.contains("Done"), true, "temporary file shelf Done closes the overlay without clearing files")
    expectEqual(shelfView.contains("Clear"), true, "temporary file shelf Clear is the destructive action")
    expectEqual(shelfView.contains("let contentBoundaryInset: CGFloat"), true, "temporary file shelf receives an explicit boundary inset instead of inventing one")
    expectEqual(shelfView.contains("let topBoundaryInset: CGFloat"), true, "temporary file shelf receives a corner-aware top boundary inset")
    expectEqual(shelfView.contains("private var shellContentInset: CGFloat"), true, "temporary file shelf resolves one safe inset for rounded shell content")
    expectEqual(shelfView.contains("max(contentBoundaryInset, topBoundaryInset)"), true, "temporary file shelf never uses less than the 5pt guard or rounded-corner guard")
    expectEqual(shelfView.contains("header\n                .padding(.horizontal, shellContentInset)"), true, "temporary file shelf header avoids the expanded shell's rounded top corners")
    expectEqual(shelfView.contains("filterBar\n                    .padding(.horizontal, shellContentInset)"), true, "temporary file shelf filters avoid left-edge clipping")
    expectEqual(shelfView.contains("groupedShelfBody\n                    .padding(.horizontal, shellContentInset)"), true, "temporary file shelf populated area avoids clipping while respecting the 5pt guard")
    expectEqual(shelfView.contains("emptyDropBody\n                    .frame(height: emptyShelfBodyHeight)\n                    .padding(.horizontal, shellContentInset)"), true, "temporary file shelf empty drop area avoids clipping while respecting the 5pt guard")
    expectEqual(shelfView.contains(".strokeBorder("), true, "temporary file shelf boundary strokes are drawn inside the 5pt guard")
    expectEqual(shelfView.contains(".stroke(\n                    .white.opacity(isDropTargetActive"), false, "temporary file shelf drop boundary does not draw half a stroke outside the 5pt guard")
    expectEqual(shelfView.contains("horizontalInset"), false, "temporary file shelf does not add an arbitrary second horizontal boundary")
    expectEqual(shelfView.contains("CGFloat = 24"), false, "temporary file shelf does not hard-code the rejected 24pt visual boundary patch")
    expectEqual(shelfView.contains("private let emptyShelfBodyHeight: CGFloat = 86"), true, "temporary file shelf empty state does not stretch into an oversized dashed panel")
    expectEqual(shelfView.contains("private let filterBarHeight: CGFloat = 20"), true, "temporary file shelf filter bar is compact enough for the island height")
    expectEqual(shelfView.contains(".frame(width: 16, height: 16)"), true, "temporary file shelf header icon has stable bounds and cannot be clipped by symbol bearings")
    expectEqual(shelfView.contains("Spacer(minLength: 0)"), true, "temporary file shelf leaves unused empty-state space unframed")
    expectEqual(shelfView.contains("GridItem(.adaptive(minimum: 112, maximum: 150), spacing: 6)"), true, "temporary file shelf uses denser adaptive columns to show more files")
    expectEqual(shelfView.contains(".frame(height: 38)"), true, "temporary file shelf tiles are compact enough to show more rows")
    expectEqual(shelfView.contains(".frame(width: 18, height: 18)"), true, "temporary file shelf icons are compact but still recognizable")
    expectEqual(shelfView.contains("LazyVStack(alignment: .leading, spacing: 10)"), false, "temporary file shelf no longer wastes height on stacked group sections")
    expectEqual(shelfView.contains(".frame(height: 52)"), false, "temporary file shelf no longer uses the old tall file tiles")
    expectEqual(shelfView.contains(".font(.system(size: 30, weight: .medium))"), true, "temporary file shelf empty state is visually balanced without explanatory text")
    expectEqual(shelfView.contains("NSWorkspace.shared.icon"), true, "temporary file shelf view uses native file icons")
}

private func testInteractionLoggingContract() {
    let logger = source("Sources/DynamicIsland/Support/IslandInteractionLogger.swift")
    let controller = source("Sources/DynamicIsland/Controllers/IslandPanelController.swift")

    expectEqual(logger.contains("final class IslandInteractionLogger"), true, "interaction logging uses a dedicated logger")
    expectEqual(logger.contains("Library/Logs/DynamicIsland"), true, "interaction logs are written to the app log directory")
    expectEqual(logger.contains("sessionID"), true, "interaction logs include a per-launch session identifier")
    expectEqual(logger.contains("encoderDateFormatter.timeZone = .current"), true, "interaction log timestamps use the local machine time zone")
    expectEqual(logger.contains(".withFractionalSeconds"), true, "interaction log timestamps include subsecond precision")
    expectEqual(logger.contains("JSONSerialization.data"), true, "interaction logs are JSONL records")
    expectEqual(logger.contains("FileHandle(forWritingTo:"), true, "interaction logger appends records efficiently")
    expectEqual(logger.contains("static func sanitizedFileMetadata"), true, "interaction logger exposes sanitized file metadata")
    expectEqual(logger.contains("pathFingerprint"), true, "interaction logger keeps a stable path fingerprint without writing full paths")
    expectEqual(logger.contains("fileURL.path"), true, "interaction logger may read file paths to create sanitized metadata")
    expectEqual(logger.contains("\"path\""), false, "interaction logger does not write a raw path field")
    expectEqual(logger.contains("\"fileName\""), false, "interaction logger does not write raw file names")
    expectEqual(logger.contains("\"displayName\""), false, "interaction logger does not write display names from file paths")
    expectEqual(logger.contains("\"nameLength\""), true, "interaction logger keeps only coarse name metadata")

    expectEqual(controller.contains("IslandInteractionLogger"), true, "panel owns the interaction logger")
    expectEqual(controller.contains("interactionLogger.log(\"app.launch\""), true, "panel logs app launch")
    expectEqual(controller.contains("displayLogMetadata"), true, "panel builds sanitized display metadata for release diagnostics")
    expectEqual(controller.contains("interactionLogger.log(\"display.metrics.changed\""), true, "panel logs display metric changes for notch and scaling diagnostics")
    expectEqual(controller.contains("\"hasCameraHousing\""), true, "display diagnostics record whether the current screen has a camera housing")
    expectEqual(controller.contains("\"safeAreaTopInset\""), true, "display diagnostics record the top safe-area inset")
    expectEqual(controller.contains("\"screenWidth\""), true, "display diagnostics record logical screen width")
    expectEqual(controller.contains("interactionLogger.log(\"panel.show\""), true, "panel logs show requests")
    expectEqual(controller.contains("interactionLogger.log(\"panel.hide\""), true, "panel logs hide requests")
    expectEqual(controller.contains("interactionLogger.log(\"shell.expanded\""), true, "panel logs expand and collapse transitions")
    expectEqual(controller.contains("interactionLogger.log(\"shell.hidden\""), true, "panel logs scroll hide/show transitions")
    expectEqual(controller.contains("interactionLogger.log(\"scroll.gesture.locked\""), true, "panel logs scroll gesture axis locks")
    expectEqual(controller.contains("interactionLogger.log(\"music.skip.commit\""), true, "panel logs committed music skip gestures")
    expectEqual(controller.contains("interactionLogger.log(\"music.playback.changed\""), true, "panel logs music playback changes")
    expectEqual(controller.contains("\"title\": snapshot.title"), false, "music playback logs do not write raw track titles")
    expectEqual(controller.contains("\"artist\": snapshot.artist"), false, "music playback logs do not write raw artist names")
    expectEqual(controller.contains("\"titleLength\": snapshot.title.count"), true, "music playback logs keep only title length")
    expectEqual(controller.contains("\"artistLength\": snapshot.artist.count"), true, "music playback logs keep only artist length")
    expectEqual(controller.contains("\"title\": signal.title"), false, "debug music logs do not write raw track titles")
    expectEqual(controller.contains("\"artist\": signal.artist"), false, "debug music logs do not write raw artist names")
    expectEqual(controller.contains("interactionLogger.log(\"file.drop.accepted\""), true, "panel logs accepted file drops")
    expectEqual(controller.contains("IslandInteractionLogger.sanitizedFileMetadata"), true, "file drop logs use sanitized metadata")
    expectEqual(controller.contains("interactionLogger.log(\"file.shelf.select\""), true, "panel logs file shelf selection")
    expectEqual(controller.contains("interactionLogger.log(\"file.drag.start\""), true, "panel logs external file drag starts")
    expectEqual(controller.contains("interactionLogger.log(\"file.drag.completed\""), true, "panel logs external file drag completion")
    expectEqual(controller.contains("interactionLogger.log(\"file.shelf.remove\""), true, "panel logs single file removal")
    expectEqual(controller.contains("interactionLogger.log(\"file.shelf.clear\""), true, "panel logs clearing the shelf")
    expectEqual(controller.contains("interactionLogger.log(\"file.shelf.done\""), true, "panel logs Done overlay closes")
    expectEqual(controller.contains("interactionLogger.log(\"file.shelf.filter\""), true, "panel logs file shelf filter changes")
}

private func testCurrentShellSourceContracts() {
    let overlay = islandOverlaySources()
    let controller = source("Sources/DynamicIsland/Controllers/IslandPanelController.swift")
    let metrics = source("Sources/DynamicIslandCore/NotchMetrics.swift")
    let appDelegate = source("Sources/DynamicIsland/Controllers/AppDelegate.swift")
    let runtimeSettings = source("Sources/DynamicIsland/Support/IslandRuntimeSettings.swift")
    let settingsView = source("Sources/DynamicIsland/Views/IslandSettingsView.swift")
    let trackingView = source("Sources/DynamicIsland/Views/IslandTrackingHostingView.swift")
    let musicSource = source("Sources/DynamicIsland/Support/MusicPlaybackDataSource.swift")
    let debugMusicSignal = source("Sources/DynamicIsland/Support/DebugMusicSignal.swift")
    let avatarView = source("Sources/DynamicIsland/Views/ClosedMusicAvatarView.swift")
    let waveformView = source("Sources/DynamicIsland/Views/ClosedMusicWaveformView.swift")
    let islandShape = source("Sources/DynamicIsland/Views/IslandShape.swift")
    let topBandLayout = source("Sources/DynamicIslandCore/IslandTopStatusBandLayout.swift")
    let calibrationLayout = source("Sources/DynamicIslandCore/IslandCalibrationLayout.swift")
    let skipGestureMachine = source("Sources/DynamicIslandCore/MusicSkipGestureStateMachine.swift")
    let buildScript = source("script/build_and_run.sh")
    let musicSignalScript = source("script/send_music_signal.sh")

    expectEqual(calibrationLayout.contains("contentBoundaryFrame"), true, "core calibration layout exposes the 5pt content boundary frame")
    expectEqual(runtimeSettings.contains("final class IslandRuntimeSettings"), true, "runtime settings use an in-memory observable object")
    expectEqual(runtimeSettings.contains("@Published var isFileShelfEnabled = true"), true, "runtime settings can disable the temporary file shelf")
    expectEqual(runtimeSettings.contains("@Published var isMusicModeEnabled = true"), true, "runtime settings can disable music mode")
    expectEqual(runtimeSettings.contains("@Published var isCalibrationModeEnabled"), true, "runtime settings can toggle calibration debug mode")
    expectEqual(runtimeSettings.contains("@Published var gestureSensitivity"), true, "runtime settings expose gesture sensitivity")
    expectEqual(runtimeSettings.contains("@Published var hideAnimationStrength"), true, "runtime settings expose hide animation strength")
    expectEqual(runtimeSettings.contains("UserDefaults"), false, "runtime settings are not persisted with UserDefaults")
    expectEqual(settingsView.contains("struct IslandSettingsView"), true, "status menu settings page uses a SwiftUI view")
    expectEqual(settingsView.contains("文件架"), true, "settings page exposes File Shelf toggle in Chinese")
    expectEqual(settingsView.contains("音乐状态"), true, "settings page exposes music mode toggle in Chinese")
    expectEqual(settingsView.contains("调试模式"), true, "settings page exposes calibration debug mode in Chinese")
    expectEqual(settingsView.contains("手势灵敏度"), true, "settings page exposes gesture sensitivity in Chinese")
    expectEqual(settingsView.contains("隐藏动画速度"), true, "settings page exposes hide animation speed in Chinese")
    expectEqual(settingsView.contains("重置显示器适配"), true, "settings page exposes display adaptation reset in Chinese")
    expectEqual(settingsView.contains("UserDefaults"), false, "settings page does not persist settings")
    expectEqual(appDelegate.contains("设置"), true, "status menu exposes the settings page in Chinese")
    expectEqual(appDelegate.contains("NSPopover"), true, "settings page opens as a small menu bar popover")
    expectEqual(appDelegate.contains("IslandSettingsView"), true, "status menu hosts the SwiftUI settings page")
    expectEqual(appDelegate.contains("resetDisplayAdaptation"), true, "settings page can reset display adaptation")
    expectEqual(appDelegate.contains("UserDefaults"), false, "app delegate does not persist runtime settings")
    expectEqual(overlay.contains("shellFillColor"), true, "overlay routes shell fill through a dedicated style property")
    expectEqual(overlay.contains("private var shellFillColor: Color {\n        .black\n    }"), true, "overlay uses a black shell fill")
    expectEqual(overlay.contains("private var foregroundContentColor: Color {\n        .white\n    }"), true, "overlay uses white foreground content on the black shell")
    expectEqual(overlay.contains("onExpansionChange(true)"), true, "overlay tap can expand the shell")
    expectEqual(overlay.contains("isShellHidden"), true, "overlay can visually hide the shell while keeping the tracking zone alive")
    expectEqual(overlay.contains("isTrackInfoPresented"), true, "overlay can present transient track info")
    expectEqual(overlay.contains("musicSkipFeedbackDirection"), true, "overlay presents horizontal skip feedback inside the shell")
    expectEqual(overlay.contains("musicSkipGestureProgress"), true, "overlay drives horizontal skip feedback from gesture progress")
    expectEqual(overlay.contains("@Published var isMusicSkipArmed = false"), true, "overlay state tracks whether a horizontal skip is armed")
    expectEqual(overlay.contains("@Published var isCalibrationOverlayVisible = false"), true, "overlay state can show the hidden calibration overlay")
    expectEqual(overlay.contains("@Published var calibrationHasCameraHousing = false"), true, "overlay state knows whether calibration is marking a physical camera housing")
    expectEqual(overlay.contains("musicTrackInfoShellHeight"), true, "overlay expands the music shell downward for track info")
    expectEqual(overlay.contains("musicArtworkSize"), true, "overlay enlarges album artwork for track info")
    expectEqual(overlay.contains("trackTitleText"), true, "overlay renders track title text")
    expectEqual(overlay.contains("trackArtistText"), true, "overlay renders track artist text")
    expectEqual(overlay.contains("private let trackInfoTextCenterY: CGFloat = 55"), true, "track info text is lowered below the camera housing haze")
    expectEqual(overlay.contains("showsTrackInfo ? 50 : musicAccessoryCenterY"), true, "track info artwork is lowered with the expanded music shell")
    expectEqual(overlay.contains("y: trackInfoTextCenterY"), true, "track info text position uses the lowered safe constant")
    expectEqual(overlay.contains("y: 49"), false, "track info text no longer sits at the old notch-overlapping height")
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
    expectEqual(overlay.contains("closedShellWidth + musicSkipEdgeExpansion"), true, "skip feedback expands the visible shell only during the gesture")
    expectEqual(overlay.contains("musicSkipEdgeExpansionMax"), true, "overlay has a bounded one-sided skip expansion amount")
    expectEqual(overlay.contains("private var shellHorizontalOffset"), true, "skip feedback offsets the shell to keep the opposite side fixed")
    expectEqual(overlay.contains("private var shellHorizontalScale"), true, "skip feedback accounts for hover scale when pinning the opposite edge")
    expectEqual(overlay.contains("let scaledExpansion = musicSkipEdgeExpansion * shellHorizontalScale"), true, "skip feedback uses scaled expansion for edge pinning")
    expectEqual(overlay.contains("direction == .next ? scaledExpansion / 2 : -scaledExpansion / 2"), true, "right swipe keeps the left edge fixed and left swipe keeps the right edge fixed")
    expectEqual(overlay.contains("private var contentOriginShiftX"), true, "left-side expansion keeps the existing album and waveform positions stable")
    expectEqual(overlay.contains("contentPinningCorrectionX"), false, "skip feedback never moves the base music content to correct shell-edge pixels")
    expectEqual(overlay.contains("case .previous:\n            musicSkipEdgeExpansion"), true, "left skip shifts content only to pin the existing controls while the left edge expands")
    expectEqual(overlay.contains("case .next:\n            0"), true, "right skip keeps album artwork and waveform at their base positions")
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
    expectEqual(overlay.contains("MusicSkipGlyph"), true, "skip feedback uses a visible in-app glyph instead of relying on a system symbol")
    expectEqual(overlay.contains("Image(systemName: direction == .next ? \"forward.end.fill\" : \"backward.end.fill\")"), true, "skip feedback uses Apple-style media control SF Symbols")
    expectEqual(overlay.contains("TriangleSkipSegment"), false, "skip feedback no longer uses hand-drawn triangle media glyphs")
    expectEqual(overlay.contains("musicSkipFeedbackIcon"), true, "skip feedback uses a dedicated in-shell icon view")
    expectEqual(overlay.contains("state.isMusicSkipArmed ? 1 : progress"), true, "armed skip feedback gives a clear ready-to-commit visual")
    expectEqual(overlay.contains("state.isMusicSkipArmed ? 1.08"), true, "armed skip feedback lightly grows the in-shell icon")
    expectEqual(overlay.contains("musicSkipEdgeExpansion - minimumCenterX"), true, "right skip icon rides the expanding shell edge")
    expectEqual(overlay.contains("case .previous:\n            return minimumCenterX"), true, "left skip icon rides the expanding shell edge")
    expectEqual(overlay.contains("min(1, max(0, state.musicSkipGestureProgress))"), true, "skip feedback clamps gesture progress")
    expectEqual(overlay.contains("if let direction = state.musicSkipFeedbackDirection"), true, "skip feedback is rendered in the shell content stack")
    expectEqual(overlay.contains("musicSkipFeedbackIcon(direction)"), true, "skip feedback icon is inside the clipped island shell")
    expectEqual(overlay.contains("CalibrationOverlayView"), true, "overlay can render the hidden calibration overlay")
    expectEqual(overlay.contains("IslandCalibrationLayout(metrics: metrics, hasCameraHousing: state.calibrationHasCameraHousing)"), true, "calibration overlay uses core layout and physical housing state")
    expectEqual(overlay.contains("cameraHousingForbiddenRegion"), true, "calibration overlay marks the camera forbidden region when present")
    expectEqual(overlay.contains("calibrationBoundaryRect(contentBoundaryFrame"), true, "calibration overlay draws the 5pt boundary as a dedicated top-level guide")
    expectEqual(overlay.contains(".strokeBorder("), true, "calibration overlay draws guide strokes inside their frames instead of centering them on the boundary")
    expectEqual(overlay.contains("private let calibrationSafeRegionYOffset: CGFloat = 2"), true, "calibration overlay offsets top safe regions so they do not cover the yellow 5pt boundary")
    expectEqual(overlay.contains("5pt content boundary"), true, "calibration overlay labels the yellow boundary explicitly")
    expectEqual(overlay.contains("NSPopover"), false, "skip feedback is not implemented as an external popover")
    expectEqual(overlay.contains("floating"), false, "skip feedback is not implemented as a floating HUD")
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
    expectEqual(musicSource.contains("struct MusicWaveformSnapshot"), true, "music source owns the app-local waveform snapshot")
    expectEqual(musicSource.contains("AudioPlaybackSnapshot"), false, "music source no longer depends on removed core audio playback state")
    expectEqual(waveformView.contains("MusicWaveformSnapshot"), true, "compact waveform view uses the app-local waveform snapshot")
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
    expectEqual(avatarView.contains("Color.white"), true, "compact avatar fallback stays visible on the black shell")
    expectEqual(avatarView.contains(".stroke("), false, "compact avatar avoids an extra outline box around real artwork")
    expectEqual(avatarView.contains(".shadow("), false, "compact avatar avoids an extra square shadow around real artwork")
    expectEqual(avatarView.contains("AngularGradient"), false, "compact avatar fallback no longer uses a colored gradient")
    expectEqual(avatarView.contains("closedMusicAccessoryGuardInset"), false, "avatar view does not own layout guard math")
    expectEqual(waveformView.contains("Canvas"), false, "compact waveform avoids continuous canvas redraws")
    expectEqual(waveformView.contains("TimelineView"), false, "compact waveform does not run a continuous timeline in the closed shell")
    expectEqual(waveformView.contains("CABasicAnimation"), true, "compact waveform bars animate through Core Animation")
    expectEqual(waveformView.contains("transform.scale.y"), true, "compact waveform animates bar height on layers")
    expectEqual(waveformView.contains("NSColor.white"), true, "compact waveform uses white contrast on the black shell")
    expectEqual(waveformView.contains("barColor: NSColor"), false, "compact waveform has no unused skip tint API")
    expectEqual(waveformView.contains("ForEach(0..<4"), false, "compact waveform is no longer the simple four-bar placeholder")
    expectEqual(avatarView.contains("Text("), false, "compact avatar contains no text that can touch guard bounds")
    expectEqual(waveformView.contains("Text("), false, "compact waveform contains no text that can touch guard bounds")
    expectEqual(controller.contains("onMouseEntered = { [weak self] in"), true, "panel still listens for mouse enter")
    expectEqual(controller.contains("onMouseEntered = { [weak self] in\n            self?.setExpanded(true)\n        }"), false, "panel does not auto-expand on mouse enter")
    expectEqual(trackingView.contains("var onMouseMoved"), true, "tracking view reports cursor movement within the transparent panel")
    expectEqual(trackingView.contains(".mouseMoved"), true, "tracking area receives real cursor movement updates")
    expectEqual(controller.contains("onMouseMoved = { [weak self] in"), true, "panel continuously syncs hover with the precise shell path")
    expectEqual(controller.contains("onMouseExited = { [weak self] in"), true, "panel still listens for mouse exit")
    expectEqual(trackingView.contains("override func scrollWheel"), true, "tracking view handles notch scroll gestures")
    expectEqual(trackingView.contains("onScroll?"), true, "tracking view forwards scroll delta to the controller")
    expectEqual(trackingView.contains("onScroll?(event.scrollingDeltaX, event.scrollingDeltaY, event.phase, event.momentumPhase)"), true, "tracking view forwards scroll delta with real trackpad phase data")
    expectEqual(controller.contains("onScroll = { [weak self] deltaX, deltaY, phase, momentumPhase in"), true, "panel installs a phase-aware two-axis scroll gesture callback")
    expectEqual(controller.contains("gestureAxisLockThreshold: CGFloat = 6"), true, "scroll gestures require a deliberate real-user movement before locking an axis")
    expectEqual(controller.contains("scrollActivationThreshold: CGFloat = 6"), true, "vertical hide/show requires deliberate trackpad movement")
    expectEqual(controller.contains("horizontalCommitDistance: CGFloat = 50"), true, "horizontal skip progress commits at 50pt")
    expectEqual(controller.contains("horizontalCancelDistance: CGFloat = 38"), true, "horizontal skip has a smaller cancel boundary after arming")
    expectEqual(controller.contains("gestureResetDelay"), true, "scroll gestures reset shortly after events stop")
    expectEqual(controller.contains("enum ActiveScrollGesture"), true, "scroll sequences lock to one gesture axis")
    expectEqual(controller.contains("case horizontal"), true, "horizontal gesture lock supports skip")
    expectEqual(controller.contains("accumulatedScrollDeltaX"), true, "horizontal scroll delta is accumulated for progress")
    expectEqual(controller.contains("MusicSkipGestureStateMachine"), true, "horizontal skip is owned by a single core state machine")
    expectEqual(controller.contains("horizontalMusicSkipGesture.update(accumulatedDeltaX: accumulatedScrollDeltaX)"), true, "controller feeds accumulated horizontal delta into the state machine")
    expectEqual(controller.contains("horizontalMusicSkipGesture.finish(shouldCommit: shouldCommitPendingSkip)"), true, "controller commits or cancels through the state machine at gesture finish")
    expectEqual(controller.contains("private var horizontalSkipGestureDirection"), false, "controller no longer keeps a separate horizontal skip direction variable")
    expectEqual(controller.contains("private var pendingHorizontalSkipDirection"), false, "controller no longer keeps a separate pending skip direction variable")
    expectEqual(controller.contains("private var isHorizontalSkipArmed"), false, "controller no longer keeps a separate armed boolean")
    expectEqual(controller.contains("scrollGestureUsesExplicitPhase"), true, "trackpad gestures with NSEvent phases are tracked separately from wheel fallback gestures")
    expectEqual(controller.contains("(phase.contains(.began) || phase.contains(.mayBegin)) && !scrollGestureUsesExplicitPhase"), true, "explicit trackpad gestures do not repeatedly reset after the first phase event")
    expectEqual(controller.contains("scrollPhaseDescription"), true, "scroll gesture logs include phase diagnostics for real touchpad validation")
    expectEqual(controller.contains("\"phase\": Self.scrollPhaseDescription(phase)"), true, "axis lock logs record the NSEvent phase")
    expectEqual(controller.contains("\"usesExplicitPhase\": scrollGestureUsesExplicitPhase"), true, "axis lock logs record whether phase-aware commit mode is active")
    expectEqual(controller.contains("overlayState.isMusicSkipArmed = true"), true, "controller exposes armed skip state to the overlay")
    expectEqual(controller.contains("overlayState.isMusicSkipArmed = false"), true, "controller clears armed skip state on cancel, reset, commit, or hide")
    expectEqual(controller.contains("hasTriggeredHorizontalSkip"), true, "horizontal skip triggers only once per gesture")
    expectEqual(controller.contains("commitPendingHorizontalMusicSkipIfNeeded"), true, "horizontal skip commits only when the gesture ends or resets")
    expectEqual(controller.contains("logHorizontalMusicSkipCancelled"), true, "horizontal skip can be cancelled by reversing into the cancel boundary")
    expectEqual(controller.contains("finalizeScrollGesture(shouldCommitPendingSkip: scrollGestureEnded)"), true, "trackpad phase end is the explicit commit point for armed horizontal skips")
    expectEqual(controller.contains("if !scrollGestureUsesExplicitPhase {\n            scheduleGestureReset()\n        }"), true, "phase-aware trackpad gestures do not commit from an idle timer while the finger may still be down")
    expectEqual(controller.contains("resetScrollGesture(shouldCommitPendingSkip: Bool = true)"), true, "gesture reset can distinguish commit from cancellation")
    expectEqual(controller.contains("commitPendingHorizontalMusicSkipIfNeeded(shouldCommitPendingSkip: shouldCommitPendingSkip)"), true, "cancelled gestures cannot commit an armed skip")
    expectEqual(controller.contains("interactionLogger.log(\"music.skip.armed\""), true, "panel logs when a horizontal skip reaches the commit boundary")
    expectEqual(controller.contains("interactionLogger.log(\"music.skip.cancelled\""), true, "panel logs when an armed horizontal skip is cancelled")
    expectEqual(controller.contains("gestureResetWorkItem"), true, "horizontal gesture reset work item is used")
    expectEqual(controller.contains("scrollSuppressionAfterExpansionDuration: TimeInterval = 0.35"), true, "expanded shell suppresses stale scroll events briefly after opening")
    expectEqual(controller.contains("private var scrollSuppressionUntil: Date?"), true, "panel tracks a temporary scroll suppression deadline")
    expectEqual(controller.contains("scrollSuppressionUntil = Date().addingTimeInterval(Self.scrollSuppressionAfterExpansionDuration)"), true, "expanding the shell arms the stale-scroll suppression window")
    expectEqual(controller.contains("Date() < scrollSuppressionUntil"), true, "scroll handling ignores events that arrive during the post-expansion suppression window")
    expectEqual(controller.contains("handleScroll(deltaX: deltaX, deltaY: deltaY, phase: phase, momentumPhase: momentumPhase)"), true, "scroll handling is centralized for phase-aware gestures")
    expectEqual(controller.contains("pointerInsideInteractiveShell()"), true, "all scroll gestures first verify the pointer is inside the visible shell, not the transparent panel")
    expectEqual(controller.contains("currentShellFrameInScreenCoordinates"), true, "panel derives an accurate shell hit-test frame in screen coordinates")
    expectEqual(controller.contains("currentShellPathForHitTesting"), true, "pointer hit testing uses the actual IslandShape path, not only a rectangle")
    expectEqual(controller.contains("IslandShape("), true, "controller reuses the shell shape for precise hit testing")
    expectEqual(controller.contains("panel.frame.contains(NSEvent.mouseLocation)"), false, "pointer hit testing no longer uses the oversized transparent panel frame")
    expectEqual(controller.contains("momentumPhase.isEmpty"), true, "trackpad momentum events do not start new gestures")
    expectEqual(controller.contains("guard pointerInsideIsland else"), true, "scroll gestures outside the island tracking zone are ignored")
    expectEqual(controller.contains("if overlayState.isShellHidden"), true, "hidden state has first priority in scroll handling")
    expectEqual(controller.contains("private var canHandleVerticalHideShow"), true, "controller has a dedicated gate for vertical hide/show gestures")
    expectEqual(controller.contains("!isExpanded\n            && !overlayState.isShellHidden"), true, "expanded shell does not support upward hide or downward expand gestures")
    expectEqual(controller.contains("guard canHandleVerticalHideShow else {\n            resetScrollGesture(shouldCommitPendingSkip: false)\n            return\n        }"), true, "visible vertical gestures are ignored while expanded")
    expectEqual(controller.contains("let activationThreshold = scaledGestureThreshold(Self.scrollActivationThreshold)"), true, "natural trackpad vertical gestures use runtime sensitivity")
    expectEqual(controller.contains("accumulatedScrollDeltaY < -activationThreshold"), true, "natural trackpad upward scroll hides the shell with a short gesture")
    expectEqual(controller.contains("accumulatedScrollDeltaY > activationThreshold"), true, "natural trackpad downward scroll restores the hidden shell")
    expectEqual(skipGestureMachine.contains("accumulatedDeltaX < 0 ? .previous : .next"), true, "horizontal skip direction follows the user's natural trackpad direction")
    expectEqual(skipGestureMachine.contains("accumulatedDeltaX < 0 ? .next : .previous"), false, "horizontal skip direction is no longer reversed")
    expectEqual(skipGestureMachine.contains("lockedDirection"), true, "state machine keeps reverse movement from flipping to the opposite icon")
    expectEqual(skipGestureMachine.contains("case cancelled(direction: MusicSkipDirection)"), true, "state machine has a terminal cancelled state for the current gesture")
    expectEqual(skipGestureMachine.contains("case committed(direction: MusicSkipDirection)"), true, "state machine has an explicit committed state")
    expectEqual(controller.contains("applyHorizontalMusicSkipGestureState"), true, "controller applies state-machine output to overlay feedback")
    expectEqual(controller.contains("pendingHorizontalSkipDirection != direction"), false, "rollback cancellation does not switch to the opposite skip direction")
    expectEqual(controller.contains("guard progress >= 1, !hasTriggeredHorizontalSkip else { return }"), false, "horizontal skip no longer commits immediately while the user may still cancel")
    expectEqual(controller.contains("performMusicSkip(direction)"), true, "panel commits horizontal music skip")
    expectEqual(controller.contains("setShellHidden(false)"), true, "natural trackpad downward scroll restores the hidden shell")
    expectEqual(controller.contains("syncHoverWithPointer()"), true, "restored shell immediately reflects hover using the accurate shell hit test")
    expectEqual(overlay.contains("!state.isShellHidden"), true, "hidden shell does not reveal hover or accept expansion taps")
    expectEqual(overlay.contains(".allowsHitTesting(!state.isShellHidden)"), true, "hidden shell disables SwiftUI hit testing")
    expectEqual(controller.contains("panel.ignoresMouseEvents = hidden"), true, "hidden shell lets hover and click events pass through")
    expectEqual(controller.contains("NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel)"), true, "hidden shell keeps only a transparent scroll restore monitor")
    expectEqual(controller.contains("guard self.pointerInsideInteractiveShell() else { return }"), true, "hidden restore only responds inside the precise shell tracking zone")
    expectEqual(controller.contains("withAnimation(.easeInOut(duration: animationDuration))"), true, "scroll hide/show uses a runtime-scaled smooth transition")
    expectEqual(controller.contains("guard !usesOpenCanvas else { return metrics.openCanvasWindowSize }"), true, "expanded canvas still uses the open shell size")
    expectEqual(metrics.contains("CompletionFeedback"), false, "notch metrics names no longer refer to removed completion feedback behavior")
    expectEqual(metrics.contains("StatusDotSoftGlowStyle"), false, "notch metrics no longer owns removed status dot rendering style")
    expectEqual(metrics.contains("closedStatusDot"), false, "notch metrics no longer exposes status-dot-specific geometry")
    expectEqual(topBandLayout.contains("statusDotFrame"), false, "top band layout no longer exposes removed status dot frames")
    expectEqual(topBandLayout.contains("audioWaveformFrame"), false, "top band layout no longer exposes removed audio waveform frames")
    expectEqual(topBandLayout.contains("costBadgeFrame"), false, "top band layout no longer exposes removed usage badge frames")
    expectEqual(controller.contains("metrics.musicClosedShellWidth + NotchMetrics.closedCanvasHorizontalSlack"), true, "closed canvas keeps horizontal room for hover and one-sided skip expansion")
    expectEqual(controller.contains("(showsTrackInfo ? metrics.musicTrackInfoShellHeight : metrics.closedHeight) + NotchMetrics.closedHoverBottomSlack"), true, "closed canvas expands only while track info is visible")
    expectEqual(controller.contains("startMusicPlaybackPolling"), true, "panel polls supported music players for compact accessories")
    expectEqual(controller.contains("runtimeSettings.isMusicModeEnabled"), true, "controller gates music mode through runtime settings")
    expectEqual(controller.contains("runtimeSettings.isFileShelfEnabled"), true, "controller gates file shelf through runtime settings")
    expectEqual(controller.contains("runtimeSettings.isCalibrationModeEnabled = Self.shouldShowCalibrationOverlay"), true, "debug calibration launch seeds the runtime setting")
    expectEqual(controller.contains("overlayState.isCalibrationOverlayVisible = calibrationModeEnabled"), true, "controller toggles calibration overlay from runtime settings")
    expectEqual(controller.contains("\"calibrationModeEnabled\": calibrationModeEnabled"), true, "settings logs include calibration debug mode")
    expectEqual(controller.contains("runtimeSettings.gestureThresholdMultiplier"), true, "controller scales gesture thresholds from runtime settings")
    expectEqual(controller.contains("runtimeSettings.hideAnimationScale"), true, "controller scales hide animation from runtime settings")
    expectEqual(controller.contains("resetDisplayAdaptation"), true, "controller can reset display adaptation from settings")
    expectEqual(controller.contains("Publishers.CombineLatest3"), true, "controller observes feature runtime settings after they change")
    expectEqual(controller.contains("Publishers.CombineLatest(featureSettings, tuningSettings)"), true, "controller observes all published runtime setting groups after they change")
    expectEqual(controller.contains("runtimeSettings.objectWillChange"), false, "controller does not read stale pre-change runtime settings")
    expectEqual(controller.contains("UserDefaults"), false, "controller does not persist runtime settings")
    expectEqual(controller.contains("2_000_000_000"), true, "panel uses a modest music polling interval")
    expectEqual(appDelegate.contains("NSApplication.didChangeScreenParametersNotification"), true, "app listens for Apple display scaling and screen parameter changes")
    expectEqual(appDelegate.contains("screenConfigurationDidChange"), true, "app routes display changes through a dedicated handler")
    expectEqual(appDelegate.contains("panelController?.refreshForCurrentScreen()"), true, "display scaling changes refresh island metrics and position")
    expectEqual(controller.contains("trackInfoDismissDelay: TimeInterval = 2.5"), true, "track info auto-dismisses after 2.5 seconds")
    expectEqual(controller.contains("lastPresentedTrackIdentity"), true, "panel detects song changes")
    expectEqual(controller.contains("trackInfoDismissWorkItem"), true, "panel cancels stale track info dismissals")
    expectEqual(controller.contains("overlayState.isTrackInfoPresented = true"), true, "panel shows track info when the song changes")
    expectEqual(controller.contains("overlayState.isTrackInfoPresented = false"), true, "panel restores default music state after track info")
    expectEqual(controller.contains("overlayState.musicSkipFeedbackDirection = direction"), true, "panel presents directional skip feedback")
    expectEqual(controller.contains("overlayState.musicSkipGestureProgress = 0"), true, "panel dismisses skip feedback after gesture end")
    expectEqual(controller.contains("startDebugMusicSignalPolling"), true, "panel can poll an explicit debug music signal")
    expectEqual(controller.contains("ISLAND_DEBUG_MUSIC_SIGNAL_FILE"), true, "debug music signal requires an explicit environment variable")
    expectEqual(controller.contains("ISLAND_DEBUG_EXPANDED_ON_LAUNCH"), true, "debug visual QA can launch directly into the expanded shell without cursor control")
    expectEqual(controller.contains("ISLAND_DEBUG_FILE_SHELF_URLS"), true, "debug visual QA can launch with visible file shelf contents")
    expectEqual(controller.contains("ISLAND_DEBUG_CALIBRATION"), true, "debug calibration requires an explicit environment variable")
    expectEqual(controller.contains("ISLAND_DEBUG_PRIMARY_FEATURE_FRAME_CAPTURE_DIR"), true, "debug visual QA can export primary feature opening frames explicitly")
    expectEqual(controller.contains("startDebugPrimaryFeatureFrameCaptureIfNeeded"), true, "primary feature frame capture is isolated behind an explicit debug path")
    expectEqual(controller.contains("captureDebugPrimaryFeatureFrame"), true, "primary feature visual QA captures the actual hosting view")
    expectEqual(controller.contains("cacheDisplay(in: bounds, to: bitmap)"), true, "primary feature visual QA renders frames from the app view instead of relying on screen recording")
    expectEqual(controller.contains("frame-%03d.png"), true, "primary feature visual QA writes ordered PNG frames")
    expectEqual(controller.contains("shouldShowCalibrationOverlay"), true, "debug calibration launch is isolated behind an explicit environment check")
    expectEqual(controller.contains("runtimeSettings.isCalibrationModeEnabled = Self.shouldShowCalibrationOverlay"), true, "debug calibration launch seeds runtime calibration mode")
    expectEqual(controller.contains("overlayState.isCalibrationOverlayVisible = runtimeSettings.isCalibrationModeEnabled"), true, "panel exposes initial calibration mode through the runtime setting")
    expectEqual(controller.contains("overlayState.calibrationHasCameraHousing"), true, "panel passes physical camera housing detection to calibration overlay")
    expectEqual(controller.contains("shouldStartExpandedForDebug"), true, "debug expanded launch is isolated behind an explicit environment check")
    expectEqual(controller.contains("160_000_000"), true, "debug music signal polling uses a conservative low-overhead interval")
    expectEqual(skipGestureMachine.contains("enum MusicSkipDirection"), true, "core models previous and next skip directions")
    expectEqual(musicSource.contains("import DynamicIslandCore"), true, "music source uses the core skip direction model")
    expectEqual(musicSource.contains("func skipTrack(_ direction: MusicSkipDirection) async -> Bool"), true, "music source performs skip commands")
    expectEqual(musicSource.contains("next track"), true, "music source sends next-track AppleScript")
    expectEqual(musicSource.contains("previous track"), true, "music source sends previous-track AppleScript")
    expectEqual(debugMusicSignal.contains("struct DebugMusicSignal"), true, "debug music signal is parsed by a dedicated support type")
    expectEqual(debugMusicSignal.contains("JSONDecoder"), true, "debug music signal uses structured JSON parsing")
    expectEqual(musicSignalScript.contains("ISLAND_DEBUG_MUSIC_SIGNAL_FILE"), true, "debug music signal sender targets the explicit signal file")
    expectEqual(buildScript.contains("--debug-calibration"), true, "build script can launch the hidden calibration overlay")
    expectEqual(buildScript.contains("--env ISLAND_DEBUG_CALIBRATION=1"), true, "debug calibration mode passes the explicit environment flag")
    expectEqual(controller.contains("ScreenMetricsProvider.metrics(for:"), true, "panel keeps display-aware shell sizing")
    expectEqual(appDelegate.contains("Show Dynamic Island"), true, "status menu can show the shell")
    expectEqual(appDelegate.contains("Hide Dynamic Island"), true, "status menu can hide the shell")
    expectEqual(appDelegate.contains("Quit Dynamic Island"), true, "status menu can quit the app")
    expectEqual(buildScript.contains("NSAppleEventsUsageDescription"), true, "app declares Apple Events usage for music playback detection")

    let removedActiveReferences = [
        "StatusDotView",
        "AudioWaveformView",
        "DataPanelView",
        "taskActivityDataSource",
        "audioPlaybackDataSource",
        "startTaskActivityPolling",
        "startAudioPlaybackPolling",
        "Preview Completion Bounce",
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
        "Sources/DynamicIslandCore/CalendarHeatmap.swift",
        "Sources/DynamicIslandCore/CalendarHeatmapVisualPolicy.swift",
        "Sources/DynamicIslandCore/CodexUsage.swift",
        "Sources/DynamicIslandCore/DataPanelMode.swift",
        "Sources/DynamicIslandCore/DataPanelTooltipPolicy.swift",
        "Sources/DynamicIslandCore/IslandFeature.swift",
        "Sources/DynamicIslandCore/AudioPlaybackState.swift",
        "Sources/DynamicIslandCore/TaskActivityState.swift",
        "Sources/DynamicIslandCore/UsageTrendTimeline.swift",
        "Sources/DynamicIsland/Views/StatusDotView.swift",
        "Sources/DynamicIsland/Views/AudioWaveformView.swift",
        "Sources/DynamicIsland/Views/DataPanelView.swift",
        "Sources/DynamicIsland/Support/AudioPlaybackDataSource.swift",
        "Sources/DynamicIsland/Support/TaskActivityDataSource.swift",
        "Sources/DynamicIsland/Support/CodexUsageDataSource.swift",
        "Sources/DynamicIsland/Support/CCSwitchUsageDataSource.swift",
        "script/set_task_activity.sh"
    ]

    for path in removedFiles {
        expectEqual(FileManager.default.fileExists(atPath: projectRoot().appendingPathComponent(path).path), false, "\(path) is removed from the current Dynamic Island app")
    }
}

private func testBuildScriptStillPackagesSignedApp() {
    let buildScript = source("script/build_and_run.sh")

    expectEqual(buildScript.contains("swift build --product \"$APP_PRODUCT_NAME\""), true, "build script compiles Dynamic Island product")
    expectEqual(buildScript.contains("codesign --force --deep --sign"), true, "build script signs the app bundle")
    expectEqual(buildScript.contains("/usr/bin/open -n \"$APP_BUNDLE\""), true, "build script can launch the packaged app")
    expectEqual(buildScript.contains("--debug-music-signal"), true, "build script can launch the app with an explicit debug music signal file")
    expectEqual(buildScript.contains("--env ISLAND_DEBUG_MUSIC_SIGNAL_FILE="), true, "debug music signal mode passes the signal path through LaunchServices")
    expectEqual(buildScript.contains("--verify"), true, "build script keeps verification mode")
}

testDerivesApprovedFourteenInchNotchMetrics()
testTopStatusBandUsesFivePointBoundary()
testCalibrationLayoutMarksSafeAndCameraRegions()
testMusicSkipGestureStateMachineLocksDirectionAndCancelsRollback()
testDisplayProfileDerivesMetricsFromScreenSignature()
testReleaseDisplayAdaptationMatrixAndLeanContracts()
testTemporaryFileShelfCoreModel()
testCodexReasoningEffortParsingAndTriggerPolicy()
testCodexStatusBarContracts()
testTemporaryFileShelfExpandedDropIntegration()
testInteractionLoggingContract()
testCurrentShellSourceContracts()
testRemovedFeatureFilesAreGone()
testBuildScriptStillPackagesSignedApp()

print("DynamicIslandCoreChecks passed")
