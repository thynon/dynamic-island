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

private func sourceSlice(_ contents: String, from startMarker: String, until endMarker: String) -> String {
    guard let startRange = contents.range(of: startMarker) else { return "" }
    let suffix = contents[startRange.lowerBound...]
    guard let endRange = suffix.range(of: endMarker) else { return "" }
    return String(suffix[..<endRange.lowerBound])
}

private func markersAppearInOrder(_ markers: [String], in contents: String) -> Bool {
    var searchStart = contents.startIndex
    for marker in markers {
        guard let range = contents.range(of: marker, range: searchStart..<contents.endIndex) else {
            return false
        }
        searchStart = range.upperBound
    }
    return true
}

private func islandOverlaySources() -> String {
    [
        "Sources/DynamicIsland/Views/IslandOverlayView.swift",
        "Sources/DynamicIsland/Views/IslandOverlayState.swift",
        "Sources/DynamicIsland/Views/IslandPrimaryFeature.swift",
        "Sources/DynamicIsland/Views/FileShelfActions.swift",
        "Sources/DynamicIsland/Views/CodexTasksContentView.swift",
        "Sources/DynamicIsland/Views/FilesPrimaryContentView.swift",
        "Sources/DynamicIsland/Views/DataPrimaryContentView.swift",
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
    let sessionProgress = source("Sources/DynamicIslandCore/CodexSessionProgress.swift")
    let adaptiveTasksLayout = source("Sources/DynamicIslandCore/CodexTasksAdaptiveLayout.swift")
    let topBandLayout = source("Sources/DynamicIslandCore/IslandTopStatusBandLayout.swift")
    let primaryContentLayout = source("Sources/DynamicIslandCore/IslandPrimaryContentLayout.swift")
    let signalSource = source("Sources/DynamicIsland/Support/CodexStatusSignalSource.swift")
    let dismissalStore = source("Sources/DynamicIsland/Support/CodexTaskDismissalStore.swift")
    let statusBarView = source("Sources/DynamicIsland/Views/CodexStatusBarView.swift")
    let tasksContentView = source("Sources/DynamicIsland/Views/CodexTasksContentView.swift")
    let approvalView = source("Sources/DynamicIsland/Views/CodexApprovalActionView.swift")
    let pixelPetView = source("Sources/DynamicIsland/Views/CodexPixelPetView.swift")
    let overlay = islandOverlaySources()
    let controller = source("Sources/DynamicIsland/Controllers/IslandPanelController.swift")
    let selectionSynchronization = sourceSlice(
        tasksContentView,
        from: "private func synchronizeSelection()",
        until: "private func reportExpansionHeight()"
    )
    let passivePresentationUpdate = sourceSlice(
        controller,
        from: "private func updatePassiveCodexApprovalPresentation",
        until: "private func handleCodexApprovalTransition"
    )
    let approvalTransition = sourceSlice(
        controller,
        from: "private func handleCodexApprovalTransition",
        until: "private func startTemporaryFileShelfPruning"
    )
    let approvalDecisionSubmission = sourceSlice(
        approvalView,
        from: "private func submit(_ decision: CodexApprovalDecision)",
        until: "private func retry()"
    )
    let approvalRetry = sourceSlice(
        approvalView,
        from: "private func retry()",
        until: "\n    }\n}"
    )
    let interactiveShellHitTest = sourceSlice(
        controller,
        from: "private func pointInsideInteractiveShell(_ mouseLocation: NSPoint)",
        until: "private func pointInsideBaseShell"
    )
    let approvalAttachmentHitTest = sourceSlice(
        controller,
        from: "private func pointInsideApprovalAttachment(_ mouseLocation: NSPoint)",
        until: "private func screenPointFromDraggingLocation"
    )
    let approvalAttachmentPresentation = sourceSlice(
        controller,
        from: "private func presentCodexApprovalAttachmentIfNeeded()",
        until: "private func dismissCodexApprovalAttachment"
    )
    let expandedWindowFrame = sourceSlice(
        controller,
        from: "private static func expandedWindowFrame(",
        until: "private static func windowFrame"
    )
    let rootViewUpdate = sourceSlice(
        controller,
        from: "private func updateRootView()",
        until: "private func dismissCodexTask"
    )
    let tasksContentMountSection = overlay
        .components(separatedBy: "CodexTasksContentView(")
        .dropFirst()
        .first?
        .components(separatedBy: "FilesPrimaryContentView(")
        .first ?? ".allowsHitTesting(false)"

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

    let startedProgress = CodexSessionProgressEvent(
        id: "started-1",
        kind: .started,
        occurredAt: 1_700_000_000
    )
    expectEqual(startedProgress.displayText, "开始处理会话", "session progress owns sanitized display copy")
    let toolTask = CodexTaskStatus(
        id: "thread",
        title: "Current thread",
        activityState: .runningTool,
        progressEvents: [startedProgress]
    )
    expectEqual(toolTask.companionState, .tool, "running tools select the terminal pet pose")
    expectEqual(toolTask.progressEvents, [startedProgress], "task snapshots carry bounded rollout progress")
    let nestedAgentTask = CodexTaskStatus(
        id: "agent",
        title: "Agent title",
        parentThreadID: "parent-agent",
        rootThreadID: "root-thread",
        agentNickname: "Feynman",
        agentDepth: 2
    )
    expectEqual(nestedAgentTask.isSubagent, true, "tasks identify subagents without relying on list position")
    expectEqual(nestedAgentTask.parentThreadID, "parent-agent", "subagents retain their immediate parent")
    expectEqual(nestedAgentTask.rootThreadID, "root-thread", "nested subagents retain their primary session")
    expectEqual(nestedAgentTask.agentDisplayName, "Feynman", "subagents prefer the sanitized Codex nickname")
    expectEqual(nestedAgentTask.agentDepth, 2, "nested subagents retain their hierarchy depth")
    expectEqual(
        CodexTaskStatus(id: "fallback-agent", title: "", parentThreadID: "root").agentDisplayName,
        "子代理",
        "subagents use a generic fallback instead of raw task instructions"
    )
    expectEqual(CodexTasksAdaptiveLayout.extraHeight(agentCount: 0), 0, "closed agent groups add no height")
    expectEqual(CodexTasksAdaptiveLayout.extraHeight(agentCount: 1), 36, "one agent adds spacing and one fixed row")
    expectEqual(CodexTasksAdaptiveLayout.extraHeight(agentCount: 5), 140, "five agents fill the adaptive shell budget")
    expectEqual(CodexTasksAdaptiveLayout.extraHeight(agentCount: 8), 140, "additional agents scroll instead of growing the shell")
    expectEqual(CodexTasksAdaptiveLayout.maximumExtraHeight, 140, "adaptive Tasks height has one explicit cap")
    expectEqual(
        CodexTaskStatus(id: "done", title: "Done thread", activityState: .idle).companionState,
        .done,
        "retained completed turns select the completion pet pose"
    )
    expectEqual(sessionProgress.contains("public struct CodexSessionProgressEvent"), true, "session progress has a focused Core model")
    expectEqual(sessionProgress.contains("public enum CodexCompanionState"), true, "pixel pet states stay UI-framework independent")
    expectEqual(sessionProgress.contains("arguments"), false, "session progress cannot carry raw command arguments")
    expectEqual(sessionProgress.contains("messageContent"), false, "session progress cannot carry raw conversation text")
    expectEqual(pixelPetView.contains("struct CodexPixelPetView"), true, "Tasks owns a focused code-native pixel pet view")
    expectEqual(pixelPetView.contains("Canvas"), true, "pixel pet renders through one lightweight Canvas")
    expectEqual(pixelPetView.contains("private let gridSize = 16"), true, "pixel pet uses a 16 by 16 logical grid")
    expectEqual(pixelPetView.contains("private let pixelScale: CGFloat = 2"), true, "expanded pet uses exact integer scaling")
    expectEqual(pixelPetView.contains(".frame(width: 32, height: 32)"), true, "expanded Tasks pet occupies exactly 32 points")
    expectEqual(pixelPetView.contains("case .tool:"), true, "pixel pet has a terminal tool pose")
    expectEqual(pixelPetView.contains("case .done:"), true, "pixel pet has a completion pose")
    expectEqual(pixelPetView.contains("accessibilityLabel"), true, "pixel pet exposes its current state without exposing individual pixels")
    expectEqual(pixelPetView.contains("TimelineView"), false, "pixel pet does not create a display-linked timeline")
    expectEqual(pixelPetView.contains("Timer"), false, "pixel pet does not create a timer")
    expectEqual(pixelPetView.contains("repeatForever"), false, "pixel pet does not run a continuous animation")

    expectEqual(topBandLayout.contains("codexStatusFrame"), false, "Codex status no longer lives in the top green safe region")
    expectEqual(primaryContentLayout.contains("public struct IslandPrimaryContentLayout"), true, "expanded shell exposes a primary content layout contract")
    expectEqual(primaryContentLayout.contains("tasksContentFrame"), true, "primary content layout exposes the white-box Tasks content frame")
    expectEqual(primaryContentLayout.contains("filesContentFrame"), true, "primary content layout exposes a Files content frame")
    expectEqual(primaryContentLayout.contains("metrics.closedHeight + contentTopInset"), true, "Tasks content starts below the top 32pt status band")
    expectEqual(primaryContentLayout.contains("let contentTopInset = CGFloat(8)"), true, "primary content layout keeps a named top inset after the status band")
    expectEqual(primaryContentLayout.contains("resolvedShellHeight - topY - contentTopInset"), true, "Files content uses equal top and bottom inset around the dashed regions")
    expectEqual(primaryContentLayout.contains("metrics.expandedHorizontalContentPadding"), true, "Tasks content avoids rounded top corners")
    let basePrimaryLayout = IslandPrimaryContentLayout(metrics: .preview14Inch)
    let tallerPrimaryLayout = IslandPrimaryContentLayout(
        metrics: .preview14Inch,
        shellHeight: NotchMetrics.preview14Inch.openHeight + CodexTasksAdaptiveLayout.maximumExtraHeight
    )
    expectEqual(
        tallerPrimaryLayout.tasksContentFrame.height - basePrimaryLayout.tasksContentFrame.height,
        CodexTasksAdaptiveLayout.maximumExtraHeight,
        "adaptive shell height flows into the Tasks content frame"
    )
    expectEqual(adaptiveTasksLayout.contains("public struct CodexTasksAdaptiveLayout"), true, "Tasks adaptive geometry stays in Core")

    let approvalLayout = CodexTasksApprovalLayout(metrics: .preview14Inch)
    expectEqual(approvalLayout.summaryFrame.minX, 290, "approval summary keeps the current detail origin")
    expectEqual(approvalLayout.summaryFrame.maxX, 829, "approval attachment starts at the current summary edge")
    expectEqual(approvalLayout.attachmentFrame.width, 124, "approval attachment has one centralized width")
    expectEqual(approvalLayout.additionalCanvasWidth, 103, "approval grows only the right canvas")
    expectEqual(approvalLayout.rejectButtonWidth, 42, "decline stays compact")
    expectEqual(approvalLayout.approveSplitButtonWidth, 68, "accept split button fits the attachment")

    let managedApproval = CodexApprovalRequest(
        requestID: .integer(61),
        threadID: "thread",
        turnID: "turn",
        itemID: "item",
        approvalID: nil,
        kind: .command,
        startedAtMilliseconds: 1,
        source: .managedAppServer,
        availableDecisions: [.decline, .accept, .acceptForSession],
        reviewSummary: "请求运行命令"
    )
    expectEqual(managedApproval.canRespondInline, true, "managed app-server approvals are actionable")
    expectEqual(CodexApprovalDecision.acceptForSession.rawValue, "acceptForSession", "session approval preserves the app-server wire value")

    let passiveApproval = CodexApprovalRequest.passive(
        threadID: "thread",
        turnID: "turn",
        kind: .command,
        startedAtMilliseconds: 1
    )
    expectEqual(passiveApproval.canRespondInline, false, "passive rollout detection never becomes an approval transport")

    func inlineEligibilityApproval(
        requestID: CodexJSONRPCRequestID?,
        kind: CodexApprovalKind,
        availableDecisions: [CodexApprovalDecision]
    ) -> CodexApprovalRequest {
        CodexApprovalRequest(
            requestID: requestID,
            threadID: "eligibility-thread",
            turnID: "eligibility-turn",
            itemID: "eligibility-item",
            approvalID: nil,
            kind: kind,
            startedAtMilliseconds: 1,
            source: .managedAppServer,
            availableDecisions: availableDecisions,
            reviewSummary: nil
        )
    }
    expectEqual(
        inlineEligibilityApproval(
            requestID: nil,
            kind: .command,
            availableDecisions: [.decline, .accept]
        ).canRespondInline,
        false,
        "managed approval without a request id is not actionable"
    )
    expectEqual(
        inlineEligibilityApproval(
            requestID: .integer(62),
            kind: .command,
            availableDecisions: [.decline]
        ).canRespondInline,
        false,
        "managed approval without accept is not actionable"
    )
    expectEqual(
        inlineEligibilityApproval(
            requestID: .integer(63),
            kind: .command,
            availableDecisions: [.accept]
        ).canRespondInline,
        false,
        "managed approval without decline is not actionable"
    )
    expectEqual(
        inlineEligibilityApproval(
            requestID: .integer(64),
            kind: .permissions,
            availableDecisions: [.decline, .accept]
        ).canRespondInline,
        false,
        "permissions approval remains non-actionable in V1"
    )

    let laterApproval = CodexApprovalRequest(
        requestID: .string("later"),
        threadID: "other-thread",
        turnID: "other-turn",
        itemID: "other-item",
        approvalID: nil,
        kind: .fileChange,
        startedAtMilliseconds: 2,
        source: .managedAppServer,
        availableDecisions: [.decline, .accept],
        reviewSummary: "请求修改文件"
    )
    var approvalInbox = CodexApprovalInbox()
    approvalInbox.upsert(laterApproval)
    approvalInbox.upsert(managedApproval)
    expectEqual(
        approvalInbox.orderedRequests.map(\.id),
        [managedApproval.id, laterApproval.id],
        "approval inbox orders requests by start time"
    )
    expectEqual(
        approvalInbox.presentation(for: managedApproval.id).pendingThreadIDs,
        Set(["thread", "other-thread"]),
        "approval presentation exposes every pending thread for row markers"
    )
    expectEqual(
        CodexTaskSelectionPolicy.resolvedSelection(
            selectedTaskID: "managed-child",
            visibleTaskIDs: ["root"],
            pendingApprovalThreadIDs: ["managed-child"],
            fallbackTaskID: "root"
        ),
        "managed-child",
        "managed approval selection survives until its task snapshot arrives"
    )
    expectEqual(
        CodexTaskSelectionPolicy.resolvedSelection(
            selectedTaskID: "managed-child",
            visibleTaskIDs: ["root", "managed-child"],
            pendingApprovalThreadIDs: ["managed-child"],
            fallbackTaskID: "root"
        ),
        "managed-child",
        "managed approval selection remains selected after its task snapshot arrives"
    )
    expectEqual(
        CodexTaskSelectionPolicy.resolvedSelection(
            selectedTaskID: "resolved-child",
            visibleTaskIDs: ["root"],
            pendingApprovalThreadIDs: [],
            fallbackTaskID: "root"
        ),
        "root",
        "missing resolved selections fall back to the first visible root"
    )
    expectEqual(
        approvalInbox.beginSubmitting(id: managedApproval.id, decision: .accept),
        true,
        "ready approval enters submitting"
    )
    expectEqual(
        approvalInbox.beginSubmitting(id: managedApproval.id, decision: .accept),
        false,
        "the same approval cannot submit twice"
    )
    let managedApprovalMetadataUpdate = CodexApprovalRequest(
        requestID: .integer(61),
        threadID: "thread",
        turnID: "updated-turn",
        itemID: "updated-item",
        approvalID: "updated-approval",
        kind: .fileChange,
        startedAtMilliseconds: 3,
        source: .managedAppServer,
        availableDecisions: [.decline, .accept],
        reviewSummary: "updated summary"
    )
    var managedIdentityInbox = CodexApprovalInbox()
    managedIdentityInbox.upsert(managedApproval)
    expectEqual(
        managedIdentityInbox.beginSubmitting(id: managedApproval.id, decision: .accept),
        true,
        "managed request starts its first submission"
    )
    managedIdentityInbox.upsert(managedApprovalMetadataUpdate)
    expectEqual(
        managedIdentityInbox.orderedRequests.count,
        1,
        "managed metadata updates keep one raw request entry"
    )
    expectEqual(
        managedIdentityInbox.beginSubmitting(id: managedApprovalMetadataUpdate.id, decision: .accept),
        false,
        "managed metadata updates cannot bypass once-only submission"
    )
    func equalTimeApproval(requestID: CodexJSONRPCRequestID) -> CodexApprovalRequest {
        CodexApprovalRequest(
            requestID: requestID,
            threadID: "equal-time-thread",
            turnID: "equal-time-turn",
            itemID: nil,
            approvalID: nil,
            kind: .command,
            startedAtMilliseconds: 10,
            source: .managedAppServer,
            availableDecisions: [.decline, .accept],
            reviewSummary: nil
        )
    }
    let integerTwoApproval = equalTimeApproval(requestID: .integer(2))
    let integerTenApproval = equalTimeApproval(requestID: .integer(10))
    let stringTenApproval = equalTimeApproval(requestID: .string("10"))
    let stringTwoApproval = equalTimeApproval(requestID: .string("2"))
    var equalTimeInbox = CodexApprovalInbox()
    equalTimeInbox.upsert(stringTwoApproval)
    equalTimeInbox.upsert(stringTenApproval)
    equalTimeInbox.upsert(integerTenApproval)
    equalTimeInbox.upsert(integerTwoApproval)
    expectEqual(
        equalTimeInbox.orderedRequests.compactMap(\.requestID),
        [
            CodexJSONRPCRequestID.integer(2),
            .integer(10),
            .string("10"),
            .string("2")
        ],
        "equal-time approvals use a stable type-preserving request id order"
    )
    var passiveApprovalInbox = CodexApprovalInbox()
    passiveApprovalInbox.upsert(passiveApproval)
    expectEqual(
        passiveApprovalInbox.beginSubmitting(id: passiveApproval.id, decision: .accept),
        false,
        "passive approval cannot enter inline submission"
    )
    var unsupportedDecisionInbox = CodexApprovalInbox()
    unsupportedDecisionInbox.upsert(laterApproval)
    expectEqual(
        unsupportedDecisionInbox.beginSubmitting(id: laterApproval.id, decision: .acceptForSession),
        false,
        "approval cannot submit a decision the server did not offer"
    )
    approvalInbox.markFailed(id: managedApproval.id, message: "connection closed")
    expectEqual(
        approvalInbox.presentation(for: managedApproval.id).submissionState,
        .failed("connection closed"),
        "approval failure stays attached to its request"
    )
    expectEqual(
        approvalInbox.presentation(for: laterApproval.id).submissionState,
        .ready,
        "approval failure does not change another request"
    )
    approvalInbox.resolve(requestID: .integer(61), threadID: "thread")
    expectEqual(
        approvalInbox.orderedRequests.map(\.id),
        [laterApproval.id],
        "approval resolve removes only the matching request"
    )
    expectEqual(CodexApprovalPresentation.hidden.request, nil, "hidden approval presentation carries no request")
    expectEqual(CodexApprovalPresentation.hidden.pendingCount, 0, "hidden approval presentation carries no pending count")
    expectEqual(overlay.contains("@Published var selectedCodexTaskID"), true, "controller owns approval-driven task selection")
    expectEqual(approvalTransition.isEmpty, false, "controller centralizes approval edge behavior in one bounded function")
    expectEqual(approvalTransition.contains("!overlayState.isShellHidden"), true, "approval transition itself cannot override explicit hidden state")
    expectEqual(
        markersAppearInOrder(
            [
                "let newKeys = keys.subtracting(lastObservedPassiveApprovalKeys)",
                "lastObservedPassiveApprovalKeys = keys",
                "guard !newKeys.isEmpty"
            ],
            in: approvalTransition
        ),
        true,
        "pending keys reset before the edge guard so the same key can trigger after an empty snapshot"
    )
    expectEqual(
        markersAppearInOrder(
            [
                "guard !newKeys.isEmpty",
                "!overlayState.isShellHidden",
                "else { return }",
                "overlayState.selectedCodexTaskID = task.id",
                "if overlayState.selectedPrimaryFeature == .files,",
                "overlayState.isFileShelfPinnedOpen",
                "return",
                "selectPrimaryFeature(.tasks)",
                "if !isExpanded {",
                "setExpanded(true)"
            ],
            in: approvalTransition
        ),
        true,
        "hidden guard precedes task selection, and pinned Files guard precedes feature switching and expansion"
    )
    expectEqual(tasksContentView.contains("selectedTaskID: Binding<String?>"), true, "Tasks accepts controller-owned selection")
    expectEqual(passivePresentationUpdate.contains("CodexApprovalRequest.passive("), true, "passive status is represented by the non-actionable approval model")
    expectEqual(
        markersAppearInOrder(
            [
                "case .pending, .pendingCommand:",
                "kind = .command",
                "case .pendingFileChange:",
                "kind = .fileChange",
                "case .pendingPermissions:",
                "kind = .permissions"
            ],
            in: passivePresentationUpdate
        ),
        true,
        "passive presentation maps every visible approval state to its safe kind"
    )

    expectEqual(signalSource.contains("final class CodexStatusSignalSource"), true, "app layer owns a reusable local Codex status reader")
    expectEqual(signalSource.contains("threadRefreshInterval: TimeInterval = 5"), true, "Codex status source keeps SQLite thread refreshes at five seconds")
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
    expectEqual(signalSource.contains("WITH RECURSIVE"), true, "Codex status source reconstructs nested agent ancestry")
    expectEqual(signalSource.contains("root_threads"), true, "Codex status source selects primary sessions before descendants")
    expectEqual(signalSource.contains("agent_tree"), true, "Codex status source keeps recursive subagent descendants together")
    expectEqual(signalSource.contains("thread_source"), true, "Codex status source distinguishes primary sessions from subagents")
    expectEqual(signalSource.contains("parent_thread_id"), true, "Codex status source reads each subagent's immediate parent")
    expectEqual(signalSource.contains("root_thread_id"), true, "Codex status source propagates the owning primary session")
    expectEqual(signalSource.contains("agent_nickname"), true, "Codex status source reads privacy-safe subagent names")
    expectEqual(signalSource.contains("LIMIT 8"), true, "Codex status source keeps eight recent primary sessions available")
    expectEqual(signalSource.contains("LIMIT 24"), true, "Codex status source bounds descendant rollout parsing")
    expectEqual(signalSource.contains("LIMIT 4"), false, "subagents cannot displace primary sessions through the old flat limit")
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
    expectEqual(signalSource.contains("progressEventLimit = 12"), true, "Codex rollout progress keeps a small bounded event buffer")
    expectEqual(signalSource.contains("private func appendProgressEvent"), true, "Codex rollout progress centralizes event deduplication")
    expectEqual(signalSource.contains("private func sanitizedToolProgressText"), true, "tool progress uses a privacy-safe display allowlist")
    expectEqual(signalSource.contains("case \"agent_reasoning\""), true, "reasoning events appear in session progress")
    expectEqual(signalSource.contains("case \"agent_message\""), true, "assistant response phases appear in session progress")
    expectEqual(signalSource.contains("case \"custom_tool_call\", \"function_call\""), true, "tool calls appear in session progress")
    expectEqual(signalSource.contains("progressEvents: rolloutState?.progressEvents ?? []"), true, "parsed rollout progress reaches the focused task snapshot")
    expectEqual(signalSource.contains("displayText: stringValue(payload[\"arguments\"])"), false, "timeline events never copy raw tool arguments")
    expectEqual(signalSource.contains("displayText: stringValue(payload[\"message\"])"), false, "timeline events never copy raw conversation messages")

    expectEqual(tasksContentView.contains("struct CodexTasksContentView"), true, "Tasks primary feature renders Codex task content in the main content area")
    expectEqual(tasksContentView.contains("summaryCardHeight: CGFloat = 54"), true, "Tasks reserves the approved 54pt identity summary tier")
    expectEqual(tasksContentView.contains("maxVisibleProgressEventCount = 3"), true, "Tasks shows only the newest three session progress events")
    expectEqual(tasksContentView.contains("suffix(maxVisibleProgressEventCount)"), true, "Tasks timeline selects recent progress instead of replaying old history")
    expectEqual(tasksContentView.contains("Text(\"会话进程\")"), true, "Tasks labels the realtime session timeline")
    expectEqual(tasksContentView.contains("Text(\"暂无会话进程\")"), true, "Tasks does not synthesize fake history when rollout progress is absent")
    expectEqual(tasksContentView.contains("formattedEventTime"), true, "timeline rows present local hour and minute copy")
    expectEqual(tasksContentView.contains("snapshot.tasks"), true, "Tasks content renders only currently visible Codex tasks")
    expectEqual(tasksContentView.contains("@Binding private var selectedTaskID"), true, "Tasks preserves a still-visible controller-owned session selection")
    expectEqual(selectionSynchronization.contains("let selectedTask = taskRows.first(where:"), true, "initial selection resolves the selected task row")
    expectEqual(selectionSynchronization.contains("selectedTask.isSubagent"), true, "initial subagent selection is detected")
    expectEqual(selectionSynchronization.contains("let rootThreadID = selectedTask.rootThreadID"), true, "subagent selection resolves its owning root")
    expectEqual(selectionSynchronization.contains("expandedRootID = rootThreadID"), true, "initial subagent selection reveals its row")
    expectEqual(selectionSynchronization.contains("CodexTaskSelectionPolicy.resolvedSelection"), true, "missing managed approval selections wait for their task snapshot")
    expectEqual(tasksContentView.contains(".onChange(of: selectedTaskID)"), true, "later controller-owned selection changes are synchronized")
    expectEqual(tasksContentView.contains(".onChange(of: approvalPresentation.pendingThreadIDs)"), true, "resolved managed approvals release a selection that never became visible")
    expectEqual(tasksContentView.contains("approvalPresentation.pendingThreadIDs.contains(task.id)"), true, "session row markers merge managed Inbox threads with passive approval state")
    expectEqual(tasksContentView.contains("@State private var expandedRootID"), true, "Tasks opens at most one primary session group")
    expectEqual(tasksContentView.contains("!$0.isSubagent"), true, "the primary session list excludes flat subagent rows")
    expectEqual(tasksContentView.contains("orderedAgents(for:"), true, "nested agents render below their owning primary session")
    expectEqual(tasksContentView.contains("agentDisplayName"), true, "subagent rows show privacy-safe Codex nicknames")
    expectEqual(tasksContentView.contains("chevron.down"), true, "primary sessions expose one disclosure control")
    expectEqual(tasksContentView.contains("ScrollView(.vertical"), true, "overflowing sessions remain reachable through local scrolling")
    expectEqual(tasksContentView.contains("CodexTasksAdaptiveLayout.extraHeight"), true, "the open group reports its bounded shell height contribution")
    expectEqual(tasksContentView.contains("onExpansionHeightChange"), true, "Tasks delegates shell geometry ownership to the panel controller")
    expectEqual(tasksContentView.contains("onChange(of: isActive)"), true, "leaving Tasks closes the open group and resets its height")
    expectEqual(tasksContentView.contains("selectedTaskID = root.id\n        withAnimation(disclosureAnimation)"), true, "opening a new group cannot leave a hidden agent selected from the previous group")
    expectEqual(tasksContentView.contains("dismissedTaskKeys"), true, "Tasks content keeps manually dismissed rows out of the current session")
    expectEqual(tasksContentView.contains("onDeleteTask"), true, "Tasks content delegates completed-row deletion to the controller")
    expectEqual(tasksContentView.contains("onUndoTask"), true, "Tasks content exposes a short undo action")
    expectEqual(tasksContentMountSection.contains(".allowsHitTesting(false)"), false, "Tasks keeps completed-task hover, delete, and undo controls reachable")
    expectEqual(tasksContentMountSection.contains(".opacity(state.selectedPrimaryFeature == .tasks ? 1 : 0)"), true, "Tasks stays mounted so its outgoing layer can fade below the incoming feature")
    expectEqual(tasksContentMountSection.contains(".offset(y: primaryContentOffset(for: .tasks))"), true, "Tasks selection changes follow the shared top-band source path")
    expectEqual(tasksContentMountSection.contains(".disabled(!isExpanded || state.selectedPrimaryFeature != .tasks)"), true, "hidden Tasks controls cannot retain keyboard activation")
    expectEqual(tasksContentMountSection.contains(".allowsHitTesting(isExpanded && state.selectedPrimaryFeature == .tasks)"), true, "only the selected expanded Tasks container accepts input during a primary-feature transition")
    expectEqual(tasksContentMountSection.contains(".accessibilityHidden(!isExpanded || state.selectedPrimaryFeature != .tasks)"), true, "hidden Tasks content does not remain in the accessibility tree")
    expectEqual(tasksContentMountSection.contains(".zIndex(state.selectedPrimaryFeature == .tasks ? 21 : 20)"), true, "outgoing Tasks drops below the selected content before its fade completes")
    expectEqual(tasksContentMountSection.contains(".transition(primaryContentTransition)"), true, "Tasks content enters from the shared top-band source transition")
    expectEqual(statusBarView.contains("!task.activityState.isWorking && task.approvalState == .none"), true, "only completed tasks can expose the delete control")
    expectEqual(tasksContentView.contains("guard !task.activityState.isWorking, task.approvalState == .none else { return }"), true, "Tasks rejects deletion for running or approval-bound tasks")
    expectEqual(controller.contains("guard !task.activityState.isWorking, task.approvalState == .none else { return }"), true, "controller repeats the completed-task deletion guard before persisting dismissal")
    expectEqual(dismissalStore.contains("codex-task-dismissals.json"), true, "task dismissal state uses a Dynamic Island-owned local file")
    expectEqual(dismissalStore.contains("retentionDuration: TimeInterval = 7 * 24 * 60 * 60"), true, "task dismissal state expires after a bounded retention period")
    expectEqual(dismissalStore.contains("try encoder.encode(dismissedAtByKey)"), true, "task dismissal state is persisted atomically")
    expectEqual(tasksContentView.contains("CodexTaskStatus("), false, "Tasks content does not synthesize a fake row after completed tasks expire")
    expectEqual(statusBarView.contains("lineLimit(1)"), true, "Tasks content truncates long task names instead of overflowing")
    expectEqual(statusBarView.contains("struct CodexStatusBarView"), true, "focused Codex summary rendering remains isolated")
    expectEqual(statusBarView.contains("let task: CodexTaskStatus?"), true, "Codex summary supports a real empty state without a fake task")
    expectEqual(statusBarView.contains("let totalTokens: Int"), true, "Codex summary receives the focused conversation token total")
    expectEqual(statusBarView.contains("let visibleTaskCount: Int"), true, "Codex summary retains awareness of additional visible sessions")
    expectEqual(statusBarView.contains("CodexPixelPetView"), true, "Codex summary leads with the approved pixel companion")
    expectEqual(statusBarView.contains("Text(\"Codex\")"), true, "Codex identity uses the approved product name")
    expectEqual(statusBarView.contains("Text(\"LIVE\")"), true, "working Codex sessions show a compact live label")
    expectEqual(statusBarView.contains("Text(\"TOTAL TOKENS\")"), true, "Codex summary labels cumulative conversation tokens")
    expectEqual(statusBarView.contains("CodexStatusBarSnapshot.formatTokenCount(totalTokens)"), true, "Codex summary formats the focused cumulative token total")
    expectEqual(statusBarView.contains("task?.agentDisplayName"), true, "focused subagents use their Codex nickname instead of repeated task instructions")
    expectEqual(statusBarView.contains("com.openai.codex"), true, "Codex identity resolves the installed app icon by bundle identifier")
    expectEqual(statusBarView.contains("private static let appIconTask"), true, "Codex app icon lookup starts outside the first Tasks render transaction")
    expectEqual(statusBarView.contains("Task.detached(priority: .utility)"), true, "Codex app icon LaunchServices work stays off the interaction-critical main thread")
    expectEqual(statusBarView.contains("private static let appIcon: NSImage?"), false, "Codex app icon is not synchronously initialized from the first view body")
    expectEqual(statusBarView.contains("terminal.fill"), true, "Codex identity has a local system-symbol fallback")
    expectEqual(statusBarView.contains(".onHover { isInside in"), true, "completed task rows track cursor entry and exit")
    expectEqual(statusBarView.contains("xmark.circle.fill"), true, "completed task rows show a compact corner delete icon")
    expectEqual(statusBarView.contains("TaskShatterEffectView"), true, "completed task deletion renders a shatter effect")
    expectEqual(statusBarView.contains("isShattering"), true, "task deletion keeps the row mounted during the shatter animation")
    expectEqual(statusBarView.contains("ProgressView"), false, "Codex status bar avoids an always-animating SwiftUI progress spinner")
    expectEqual(statusBarView.contains("repeatForever"), false, "Codex status bar avoids continuous SwiftUI animation")
    expectEqual(statusBarView.contains("formattedElapsedTime"), true, "Codex status bar uses the core elapsed-time formatter")
    expectEqual(statusBarView.contains("formatTokenCount(totalTokens)"), true, "Codex status bar uses the core token formatter")
    expectEqual(statusBarView.contains("approvalBadge"), true, "Codex status bar renders the reserved approval slot as a status badge")
    expectEqual(
        statusBarView.contains("approvalPresentation.pendingCount > 1"),
        true,
        "multiple pending approvals replace the focused-kind badge with a queue count"
    )
    expectEqual(
        statusBarView.contains("\\(approvalPresentation.pendingCount) 个待审批"),
        true,
        "multiple pending approvals expose the plan-required queue count copy"
    )
    expectEqual(statusBarView.contains("Button(action: beginDelete)"), true, "Codex status rows expose a delete action for completed tasks")
    expectEqual(statusBarView.contains("CodexApprovalTransport"), false, "Codex status bar does not directly own approval transport")
    expectEqual(approvalView.contains("let onDecision"), true, "approval attachment routes decisions through a callback")
    expectEqual(approvalView.contains("let onRetry"), true, "approval attachment delegates retry through an explicit callback")
    expectEqual(approvalView.contains("lastDecision"), false, "approval attachment never retains a decision across requests")
    expectEqual(approvalView.lowercased().contains("transport"), false, "approval attachment does not own a transport")
    expectEqual(approvalView.lowercased().contains("client"), false, "approval attachment does not own an approval client")
    expectEqual(approvalView.contains("Process"), false, "approval attachment does not launch a process")
    expectEqual(approvalView.contains("Button(\"拒绝\""), true, "approval attachment exposes decline")
    expectEqual(approvalView.contains("CodexApprovalDecision.acceptForSession"), true, "approve menu exposes session-scoped acceptance")
    expectEqual(approvalView.contains("ProgressView"), false, "approval submission does not add a continuous spinner")
    expectEqual(approvalView.contains("Timer("), false, "approval attachment does not create a timer")
    expectEqual(approvalView.contains("TimelineView"), false, "approval attachment does not create a display timeline")
    expectEqual(approvalView.contains("Text(\"提交中…\")"), true, "approval submission uses static progress copy")
    expectEqual(approvalView.contains("Button(\"前往 Codex\""), true, "passive approval routes users to Codex")
    expectEqual(approvalView.contains("repeatForever"), false, "approval attachment has no continuous animation")
    expectEqual(approvalDecisionSubmission.contains("onDecision(decision)"), true, "approval decision helper forwards the chosen decision")
    expectEqual(approvalRetry.contains("onRetry()"), true, "failed approval retry uses only the explicit retry callback")
    expectEqual(approvalRetry.contains("onDecision"), false, "failed retry cannot replay a locally retained decision")
    expectEqual(approvalRetry.contains("onOpenCodexApproval"), false, "failed retry does not silently become open Codex")
    expectEqual(overlay.contains("CodexApprovalActionView"), true, "approval attachment is mounted beside the clipped base shell")
    expectEqual(overlay.contains("onRetry: onRetryCodexApproval"), true, "overlay forwards retry across the approval boundary")
    expectEqual(rootViewUpdate.contains("onRetryCodexApproval: { [weak self] in"), true, "failed approval fallback routes to Codex without replaying a decision")
    expectEqual(overlay.contains("CodexTasksApprovalLayout(metrics: metrics, shellHeight: shellHeight)"), true, "approval attachment uses the centralized layout")
    expectEqual(statusBarView.contains("approvalTokenOffset: CGFloat = 10"), true, "pending approval shifts only the token summary by ten points")
    expectEqual(
        markersAppearInOrder(
            ["if pointInsideBaseShell(mouseLocation)", "return true", "return pointInsideApprovalAttachment(mouseLocation)"],
            in: interactiveShellHitTest
        ),
        true,
        "interactive shell hit testing unions the base shape and approval attachment"
    )
    expectEqual(approvalAttachmentHitTest.contains("CodexTasksApprovalLayout("), true, "attachment hit testing reads the centralized layout in its own helper")
    expectEqual(approvalAttachmentHitTest.contains("x: panel.frame.minX + attachmentFrame.minX"), true, "attachment hit testing offsets layout geometry from the fixed panel base")
    expectEqual(approvalAttachmentPresentation.contains("CodexTasksApprovalLayout("), true, "attachment presentation reads the centralized layout in its own helper")
    expectEqual(approvalAttachmentPresentation.contains("additionalRightWidth: layout.additionalCanvasWidth"), true, "attachment presentation grows the panel by the layout-owned width")
    expectEqual(expandedWindowFrame.contains("let baseX = screen.frame.midX - (metrics.openWidth / 2)"), true, "expanded panel helper keeps the base shell left edge fixed")
    expectEqual(expandedWindowFrame.contains("let width = metrics.openWidth + max(0, additionalRightWidth)"), true, "expanded panel helper adds width only on the right")
    expectEqual(expandedWindowFrame.contains("x: baseX"), true, "expanded panel helper uses the fixed base origin")
    expectEqual(statusBarView.contains("task.approvalState.displayText"), true, "approval badge text comes from the core task state")
    let activityIndex = statusBarView.range(of: "task.activityState.displayText")?.lowerBound
    let elapsedIndex = statusBarView.range(of: "task.formattedElapsedTime")?.lowerBound
    expectEqual(
        activityIndex != nil && elapsedIndex != nil && activityIndex! < elapsedIndex!,
        true,
        "status text starts with the activity so it is not the first part truncated"
    )

    expectEqual(overlay.contains("@Published var codexStatusBarSnapshot"), true, "overlay state publishes the Codex status bar snapshot")
    expectEqual(overlay.contains("@Published var dismissedCodexTaskKeys"), true, "overlay state publishes locally dismissed task keys")
    expectEqual(overlay.contains("@Published var codexTasksDetailExpansionHeight"), true, "overlay state publishes the controller-owned Tasks height contribution")
    expectEqual(overlay.contains("CodexTasksContentView"), true, "expanded Tasks feature renders the Codex task list")
    expectEqual(overlay.contains("onTasksExpansionHeightChange"), true, "Tasks reports disclosure height through the overlay boundary")
    expectEqual(overlay.contains("isActive: isExpanded && state.selectedPrimaryFeature == .tasks"), true, "only visible Tasks can retain an open agent group")
    expectEqual(overlay.contains("metrics.openHeight + state.codexTasksDetailExpansionHeight"), true, "the black shell extends downward by the bounded Tasks contribution")
    expectEqual(overlay.contains("IslandPrimaryContentLayout(metrics: metrics, shellHeight: shellHeight)"), true, "Tasks content receives the same adaptive shell height")
    expectEqual(overlay.contains("value: state.codexTasksDetailExpansionHeight"), true, "the shell animates only discrete disclosure height changes")
    expectEqual(overlay.contains("primaryContentFrame"), true, "Codex task list uses the primary content frame")
    expectEqual(overlay.contains("state.selectedPrimaryFeature == .tasks"), true, "Codex task list is scoped to the Tasks primary feature")
    expectEqual(overlay.contains("if isPrimaryContentEntranceActive {"), true, "Codex task list waits for the expanded shell to settle before rendering")
    expectEqual(overlay.contains("if isExpanded && isPrimaryContentEntranceActive && state.selectedPrimaryFeature == .tasks {"), false, "shell state does not remove Tasks before the content exit transaction owns its fade")
    expectEqual(overlay.contains("state.selectedPrimaryFeature == .tasks && state.isCalibrationOverlayVisible"), false, "Codex task list is not gated by the calibration layout overlay")
    expectEqual(overlay.contains("codexStatusFrame"), false, "Codex task list is not positioned in the top status band")

    expectEqual(controller.contains("startCodexStatusPolling"), true, "panel can poll local Codex status")
    expectEqual(controller.contains("startCodexStatusPolling()"), true, "panel starts Codex status polling outside calibration debug mode")
    expectEqual(controller.contains("if runtimeSettings.isCalibrationModeEnabled {\n            startCodexStatusPolling()\n        }"), false, "Codex status polling is not gated to calibration debug mode")
    expectEqual(controller.contains("stopCodexStatusPolling"), false, "unused Codex status polling stop path is removed")
    expectEqual(controller.contains("let codexStatusSignalSource = CodexStatusSignalSource()"), true, "panel reuses one Codex status source while polling")
    expectEqual(controller.contains("codexStatusSignalSource.currentSnapshot()"), true, "panel reads snapshots through the dedicated Codex status source")
    expectEqual(controller.contains("1_000_000_000"), true, "Codex status polling uses a conservative low-overhead interval")
    expectEqual(controller.contains("codexStatusBackgroundRefreshInterval: TimeInterval = 1"), true, "collapsed Codex approval detection refreshes about once per second")
    expectEqual(controller.contains("let isTasksVisible = isExpanded"), true, "visible Tasks keeps realtime status refresh")
    expectEqual(controller.contains("overlayState.selectedPrimaryFeature == .tasks"), true, "realtime status refresh is scoped to the Tasks surface")
    expectEqual(controller.contains("private func dismissCodexTask"), true, "panel owns the completed task dismissal callback")
    expectEqual(controller.contains("codex.task.dismissed"), true, "manual task dismissal is logged")
    expectEqual(controller.contains("private func restoreCodexTask"), true, "panel owns the completed task undo callback")
    expectEqual(controller.contains("codex.task.dismissed.undo"), true, "manual task dismissal undo is logged")
    expectEqual(controller.contains("CodexTaskDismissalStore"), true, "panel persists local task dismissal state without mutating Codex data")
    expectEqual(controller.contains("private func setCodexTasksDetailExpansionHeight"), true, "the controller owns Tasks panel resizing")
    expectEqual(controller.contains("CodexTasksAdaptiveLayout.maximumExtraHeight"), true, "the controller clamps untrusted UI height requests")
    expectEqual(controller.contains("tasksCanvasResizeWorkItem"), true, "panel shrinking waits for the shell transition to finish")
    expectEqual(controller.contains("expandedPanelFrame(\n                    shellHeight: targetShellHeight"), true, "open NSPanel sizing accepts the same adaptive shell height")
    expectEqual(controller.contains("metrics.openHeight + overlayState.codexTasksDetailExpansionHeight"), true, "precise hit testing follows the visible adaptive shell")
    expectEqual(controller.contains("setCodexTasksDetailExpansionHeight(0)"), true, "collapse and feature switching reset Tasks expansion")
    expectEqual(controller.contains("\"threadTitle\""), false, "Codex status logs do not write raw Codex thread titles")
}

private func testCodexAppServerApprovalContracts() {
    let client = source("Sources/DynamicIsland/Support/CodexAppServerApprovalClient.swift")
    let coordinator = source("Sources/DynamicIsland/Support/CodexApprovalCoordinator.swift")
    let controller = source("Sources/DynamicIsland/Controllers/IslandPanelController.swift")
    let approvalFlow = source("Sources/DynamicIslandCore/CodexApprovalFlow.swift")
    let statusSnapshot = source("Sources/DynamicIslandCore/CodexStatusBarSnapshot.swift")
    let tasksContent = source("Sources/DynamicIsland/Views/CodexTasksContentView.swift")
    let statusBar = source("Sources/DynamicIsland/Views/CodexStatusBarView.swift")
    let overlayView = source("Sources/DynamicIsland/Views/IslandOverlayView.swift")
    let approvalView = source("Sources/DynamicIsland/Views/CodexApprovalActionView.swift")
    let behaviorHarness = source("Tests/DynamicIslandApprovalChecks/main.swift")
    let behaviorRunner = source("script/run_codex_approval_checks.sh")
    let auditEventDefinition = sourceSlice(
        coordinator,
        from: "enum CodexApprovalAuditEvent",
        until: "@MainActor"
    )
    let auditLogMapping = sourceSlice(
        controller,
        from: "private func logCodexApprovalAuditEvent",
        until: "private func submitCodexApproval"
    )
    let openCodexSection = sourceSlice(
        controller,
        from: "private func openCodexApproval",
        until: "private func updateManagedCodexApprovalPresentation"
    )
    let safeApprovalSummary = sourceSlice(
        statusBar,
        from: "private var safeApprovalSummary",
        until: "private var tokenSummary"
    )
    let reviewSummaryInvalidation = sourceSlice(
        approvalView,
        from: ".onChange(of: presentation.request?.reviewSummary)",
        until: "    @ViewBuilder"
    )
    let coordinatorPresentationPublisher = sourceSlice(
        coordinator,
        from: "private func publishPresentation",
        until: "private static func latencyMilliseconds"
    )
    let managedPresentationUpdate = sourceSlice(
        controller,
        from: "private func updateManagedCodexApprovalPresentation",
        until: "private func dismissCodexTask"
    )
    let attachmentPresentation = sourceSlice(
        controller,
        from: "private func presentCodexApprovalAttachmentIfNeeded",
        until: "private func dismissCodexApprovalAttachment"
    )
    let passivePresentationUpdate = sourceSlice(
        controller,
        from: "private func updatePassiveCodexApprovalPresentation",
        until: "private func handleCodexApprovalTransition"
    )

    expectEqual(client.contains("protocol CodexApprovalConnection: Sendable"), true, "approval events and responses share one connection protocol")
    expectEqual(client.contains("var events: AsyncStream<CodexAppServerApprovalEvent> { get }"), true, "the connection protocol owns its event stream")
    expectEqual(client.contains("nonisolated let events: AsyncStream<CodexAppServerApprovalEvent>"), true, "app-server client exposes one event stream")
    expectEqual(client.contains("/Applications/ChatGPT.app/Contents/Resources/codex"), true, "resolver checks the bundled Codex executable first")
    expectEqual(client.contains("/opt/homebrew/bin/codex"), true, "resolver checks Apple Silicon Homebrew second")
    expectEqual(client.contains("/usr/local/bin/codex"), true, "resolver checks local Homebrew third")
    expectEqual(
        markersAppearInOrder(
            [
                "/Applications/ChatGPT.app/Contents/Resources/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex"
            ],
            in: client
        ),
        true,
        "Codex executable resolution preserves the approved order"
    )
    expectEqual(client.contains("experimentalApi"), false, "initialize stays on the stable app-server API")
    expectEqual(client.contains("item/commandExecution/requestApproval"), true, "client parses command approvals")
    expectEqual(client.contains("item/fileChange/requestApproval"), true, "client parses file-change approvals")
    expectEqual(client.contains("item/permissions/requestApproval"), true, "client parses permission approvals")
    expectEqual(client.contains("case \"item/started\", \"item/completed\":"), true, "file approval context comes from typed item lifecycle notifications")
    expectEqual(client.contains("item/fileChange/patchUpdated"), true, "file approval context also follows patch updates")
    expectEqual(client.contains("commandReviewSummary = Self.nonEmptyString(params[\"command\"])"), true, "command decisions require non-empty request context")
    expectEqual(client.contains("activeResponseCapabilities"), true, "responses require an active request from the current connection generation")
    expectEqual(client.contains("case requestUnavailable"), true, "unknown and stale request ids are rejected")
    expectEqual(client.contains("serverRequest/resolved"), true, "client parses server request resolution")
    expectEqual(client.contains("ManagedApprovalFingerprint"), true, "client deduplicates full managed envelopes privately")
    expectEqual(client.contains("case .integer(let value):"), true, "response encoder preserves integer request ids")
    expectEqual(client.contains("case .string(let value):"), true, "response encoder preserves string request ids")
    expectEqual(client.contains("\"decision\": decision.rawValue"), true, "command and file responses use the stable decision result")
    expectEqual(client.contains("IslandInteractionLogger"), false, "app-server transport never writes approval details to Island logs")

    expectEqual(coordinator.contains("final class CodexApprovalCoordinator"), true, "coordinator owns approval submission state")
    expectEqual(coordinator.contains("connection: any CodexApprovalConnection"), true, "coordinator receives one bound connection")
    expectEqual(coordinator.contains("responder: any"), false, "coordinator cannot split response ownership from events")
    expectEqual(coordinator.contains("private func receive(_ event: CodexAppServerApprovalEvent)"), true, "only the bound connection can feed coordinator events")
    expectEqual(coordinator.contains("ManagedApprovalFingerprint"), true, "coordinator checks full envelope context separately from routing identity")
    expectEqual(coordinator.contains("CodexApprovalInbox"), true, "coordinator consumes the reviewed Core inbox gate")
    expectEqual(coordinator.contains("for requestID: CodexApprovalRequest.ID"), true, "coordinator binds submission to the clicked request identity")
    expectEqual(coordinator.contains("confirmationTimeoutNanoseconds: UInt64 = 15_000_000_000"), true, "coordinator waits fifteen seconds for resolution")
    expectEqual(coordinator.contains("未确认，请在 Codex 中检查"), true, "unconfirmed submission uses honest fallback copy")
    expectEqual(coordinator.contains("case .disconnected:"), true, "disconnect clears stale managed capability")
    expectEqual(coordinator.contains("respond(to:"), true, "coordinator writes through the injected same-connection responder")
    expectEqual(coordinator.contains("retry"), false, "coordinator never retains a response replay path")
    expectEqual(coordinator.contains("IslandInteractionLogger"), false, "coordinator never logs approval payloads or ids")
    expectEqual(coordinator.contains("private var inbox = CodexApprovalInbox()"), true, "all managed requests share one Core inbox")
    expectEqual(coordinator.contains("var orderedRequests: [CodexApprovalRequest]"), true, "coordinator exposes the inbox display order to behavior tests")
    expectEqual(coordinator.contains("func selectRequest(threadID: String)"), true, "task selection can choose its own pending request")
    expectEqual(coordinator.contains("func selectRequest(threadID: String) -> Bool"), true, "managed selection miss explicitly allows passive fallback")
    expectEqual(coordinator.contains("var onNewRequest"), true, "new managed requests have a dedicated one-shot UI edge")
    expectEqual(coordinatorPresentationPublisher.contains(".presented"), false, "state publication never claims that UI was presented")
    expectEqual(coordinator.contains("var onAuditEvent"), true, "coordinator emits typed privacy-safe audit events")
    expectEqual(auditEventDefinition.isEmpty, false, "approval audit event has a reviewable typed definition")
    for forbidden in ["reviewSummary", "command", "cwd", "reason", "diff", "path", "itemID", "approvalID", "requestID"] {
        expectEqual(auditEventDefinition.contains(forbidden), false, "audit event cannot carry raw field \(forbidden)")
    }

    expectEqual(controller.contains("codexApprovalCoordinator: CodexApprovalCoordinator? = nil"), true, "production controller defaults to no managed app-server capability")
    expectEqual(controller.contains("CodexAppServerApprovalClient()"), false, "production controller never starts an empty app-server connection")
    expectEqual(controller.contains("onApprovalDecision:"), true, "approval decisions route through the controller capability gate")
    expectEqual(controller.contains("onOpenCodexApproval:"), true, "passive approvals route to Codex")
    expectEqual(controller.contains("withBundleIdentifier: \"com.openai.codex\""), true, "passive navigation targets the installed Codex application")
    expectEqual(controller.contains("updateManagedCodexApprovalPresentation(codexApprovalCoordinator.presentation)"), true, "controller immediately synchronizes an injected coordinator's current presentation")
    expectEqual(controller.contains("CodexApprovalAutoPresentationPolicy.action("), true, "passive and managed approvals share the hidden and Files-pinned priority policy")
    expectEqual(openCodexSection.contains("NSWorkspace.shared.openApplication"), true, "open Codex uses the public workspace activation API")
    expectEqual(openCodexSection.contains("completionHandler"), true, "open Codex reports activation failure asynchronously")
    expectEqual(openCodexSection.contains("无法打开 Codex"), true, "activation failure publishes static honest copy")
    expectEqual(openCodexSection.contains("URL(string:"), false, "open Codex does not invent a private deep link")
    expectEqual(openCodexSection.contains("NSAppleScript"), false, "open Codex never automates application UI")
    expectEqual(openCodexSection.contains("CodexApprovalApplicationOpenState"), true, "Codex activation uses request-bound attempt state")
    expectEqual(openCodexSection.contains("currentRequestID:"), true, "activation completion revalidates the current request identity")
    expectEqual(openCodexSection.contains("hasFailure(for:"), true, "same passive request preserves a static activation failure")
    expectEqual(controller.contains("private func handleManagedCodexApprovalRequest"), true, "only a new managed request edge may auto-locate Tasks")
    expectEqual(managedPresentationUpdate.contains("selectPrimaryFeature"), false, "managed state refresh cannot steal the visible feature")
    expectEqual(managedPresentationUpdate.contains("setExpanded"), false, "managed state refresh cannot re-expand the Island")
    expectEqual(passivePresentationUpdate.contains("presentation.pendingCount"), false, "other managed threads never globally block passive fallback")
    expectEqual(passivePresentationUpdate.contains("hasFailure(for:"), true, "passive polling derives failure state instead of resetting to ready")
    expectEqual(
        passivePresentationUpdate.contains("}) ?? pendingTasks.first"),
        false,
        "passive polling never mounts another pending request beside the selected task"
    )
    expectEqual(
        attachmentPresentation.components(separatedBy: "request.threadID == overlayState.selectedCodexTaskID").count >= 3,
        true,
        "attachment presentation validates selected thread before sizing and before mounting"
    )
    expectEqual(
        markersAppearInOrder(
            [
                "if state.isCodexApprovalAttachmentPresented",
                "let request = state.codexApprovalPresentation.request",
                "request.threadID == state.selectedCodexTaskID",
                "CodexApprovalActionView("
            ],
            in: overlayView
        ),
        true,
        "the approval view cannot render or receive clicks beside a different selected task"
    )
    expectEqual(attachmentPresentation.contains("logCodexApprovalPresentedIfNeeded"), true, "presented audit is emitted only from actual attachment mounting")
    expectEqual(approvalView.contains("(CodexApprovalDecision, CodexApprovalRequest.ID) -> Void"), true, "action buttons carry their rendered request identity")
    expectEqual(approvalView.contains("(CodexApprovalRequest.ID) -> Void"), true, "open and retry buttons carry their rendered request identity")
    expectEqual(controller.contains("codexApprovalCoordinator.submit(decision, for: requestID)"), true, "controller forwards the captured identity to the coordinator")

    for eventName in [
        "codex.approval.detected",
        "codex.approval.presented",
        "codex.approval.decision.sent",
        "codex.approval.resolved",
        "codex.approval.failed"
    ] {
        expectEqual(auditLogMapping.contains(eventName), true, "controller maps typed audit event \(eventName)")
    }
    for forbidden in ["command", "cwd", "reason", "diff", "path", "itemId", "approvalId", "requestID"] {
        expectEqual(auditLogMapping.contains("\"\(forbidden)\""), false, "approval log mapping excludes raw key \(forbidden)")
    }

    expectEqual(approvalFlow.contains("enum CodexApprovalAutoPresentationAction"), true, "Core owns the approval auto-presentation outcomes")
    expectEqual(approvalFlow.contains("enum CodexApprovalAutoPresentationPolicy"), true, "Core owns hidden and Files-pinned approval priority")
    expectEqual(statusSnapshot.contains("public var requiresManualApproval: Bool"), true, "manual approval filtering has one Core truth source")
    expectEqual(statusSnapshot.contains("\"审查中\""), true, "automatic review uses explicit in-progress copy")
    expectEqual(tasksContent.contains("let onTaskSelection: @MainActor (String) -> Void"), true, "Tasks forwards user selection to the approval coordinator")
    expectEqual(tasksContent.contains("if selectedTask.isSubagent"), true, "selected subagents expand their owning root group")
    expectEqual(tasksContent.contains("expandedRootID = rootThreadID"), true, "subagent approval selection reveals its root group")
    expectEqual(tasksContent.contains("task.approvalState.requiresManualApproval"), true, "session rows mark only manual approvals")
    expectEqual(overlayView.contains("hasManualCodexApproval"), true, "overlay derives one manual pending navigation signal")
    expectEqual(overlayView.contains("feature == .tasks"), true, "only Tasks receives the pending navigation dot")
    expectEqual(statusBar.contains("let approvalPresentation: CodexApprovalPresentation"), true, "summary card receives the selected approval presentation")
    expectEqual(safeApprovalSummary.isEmpty, false, "summary card defines privacy-safe kind copy")
    expectEqual(safeApprovalSummary.contains("reviewSummary"), false, "summary card never reads raw approval details")
    expectEqual(statusBar.contains("reviewSummary"), false, "raw details stay exclusively in the explicit approval popover")

    expectEqual(reviewSummaryInvalidation.isEmpty, false, "approval detail popover observes transient review content changes")
    expectEqual(reviewSummaryInvalidation.contains("approvalDetails = nil"), true, "review content changes immediately clear any visible stale details")
    expectEqual(approvalView.contains(".onChange(of: presentation.request?.id)"), true, "resolved or replaced requests clear approval details")

    expectEqual(behaviorHarness.contains("testFileContextBeforeAndAfterRequest"), true, "tracked behavior harness covers file context ordering")
    expectEqual(behaviorHarness.contains("testResolvedFileContextDoesNotCarryForward"), true, "tracked behavior harness rejects resolved file context reuse")
    expectEqual(behaviorHarness.contains("testConnectionBindingAndOnceOnlySubmission"), true, "tracked behavior harness covers connection ownership and once-only submission")
    expectEqual(behaviorHarness.contains("testMultipleRequestsKeepIndependentState"), true, "tracked behavior harness covers A/B selection and state isolation")
    expectEqual(behaviorHarness.contains("testSelectionMissLeavesManagedInboxAvailableForPassiveFallback"), true, "tracked behavior harness covers mixed managed/passive routing")
    expectEqual(behaviorHarness.contains("testManagedRequestPresentationHasOneNewRequestEdge"), true, "tracked behavior harness covers one-shot managed presentation edges")
    expectEqual(behaviorHarness.contains("testSubmissionStaysBoundToClickedRequest"), true, "tracked behavior harness binds clicks to request identity")
    expectEqual(behaviorHarness.contains("testApplicationOpenFailureLifecycle"), true, "tracked behavior harness covers request-bound activation failures")
    expectEqual(behaviorHarness.contains("testPrivacySafeAuditEvents"), true, "tracked behavior harness proves audit events carry no raw review fields")
    expectEqual(behaviorHarness.contains("testAutoPresentationPolicy"), true, "tracked behavior harness covers hidden, Files pinned, and auto review behavior")
    expectEqual(behaviorRunner.contains("Sources/DynamicIsland/Support/CodexAppServerApprovalClient.swift"), true, "approval runner compiles the real app-server client")
    expectEqual(behaviorRunner.contains("Sources/DynamicIsland/Support/CodexApprovalCoordinator.swift"), true, "approval runner compiles the real coordinator")
    expectEqual(behaviorRunner.contains("Tests/DynamicIslandApprovalChecks/main.swift"), true, "approval runner executes the tracked behavior harness")
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
    let animationProfileSource = source("Sources/DynamicIslandCore/IslandAnimationProfile.swift")
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
    let rectangleSelectionSection = controller
        .components(separatedBy: "private func selectTemporaryFiles")
        .dropFirst()
        .first?
        .components(separatedBy: "private func startTemporaryFileDrag")
        .first ?? ""
    let filesPrimaryFeatureButtonSection = overlay
        .components(separatedBy: "private struct FilesPrimaryFeatureButton")
        .dropFirst()
        .first?
        .components(separatedBy: "private struct MusicSkipGlyph")
        .first ?? ""
    let primaryFeatureSwitcherSection = overlay
        .components(separatedBy: "private struct PrimaryFeatureSwitcher")
        .dropFirst()
        .first?
        .components(separatedBy: "private struct FilesPrimaryFeatureButton")
        .first ?? ""
    let primaryFeatureSwitcherMountSection = overlay
        .components(separatedBy: "PrimaryFeatureSwitcher(")
        .dropFirst()
        .first?
        .components(separatedBy: "FilesPrimaryFeatureButton(")
        .first ?? ""
    let filesPrimaryFeatureMountSection = overlay
        .components(separatedBy: "FilesPrimaryFeatureButton(")
        .dropFirst()
        .first?
        .components(separatedBy: "if isPrimaryContentEntranceActive")
        .first ?? ""
    let filesPrimaryContentMountSection = overlay
        .components(separatedBy: "FilesPrimaryContentView(")
        .dropFirst()
        .first?
        .components(separatedBy: "if isExpanded, state.isFileShelfOverlayVisible")
        .first ?? ""
    let primaryContentMountSection = sourceSlice(
        overlay,
        from: "if isPrimaryContentEntranceActive {",
        until: "if isDataTimeRangeDrawerPresented {"
    )
    let fileShelfOverlayMountSection = overlay
        .components(separatedBy: "FileShelfOverlayView(")
        .dropFirst()
        .first?
        .components(separatedBy: "if showsMusicAccessories")
        .first ?? ""
    let temporaryFileDragSourceSection = shelfView
        .components(separatedBy: "private final class TemporaryFileDragSourceNSView")
        .dropFirst()
        .first ?? ""
    let temporaryFileTileSection = shelfView
        .components(separatedBy: "private func fileTile")
        .dropFirst()
        .first?
        .components(separatedBy: "private final class TemporaryFileIconCache")
        .first ?? ""
    let filesPrimaryDragSourceSection = filesContentView
        .components(separatedBy: "private final class FilesPrimaryDragSourceNSView")
        .dropFirst()
        .first ?? ""
    let trackingDragUpdateSection = trackingView
        .components(separatedBy: "override func draggingUpdated")
        .dropFirst()
        .first?
        .components(separatedBy: "override func draggingExited")
        .first ?? ""
    let filesAirDropTargetSection = filesContentView
        .components(separatedBy: "private final class FilesAirDropTargetNSView")
        .dropFirst()
        .first?
        .components(separatedBy: "private struct FilesPrimaryDragSourceView")
        .first ?? ""
    let filesAirDropUpdateSection = filesAirDropTargetSection
        .components(separatedBy: "override func draggingUpdated")
        .dropFirst()
        .first?
        .components(separatedBy: "override func draggingExited")
        .first ?? ""
    let filesPrimaryArtworkSection = filesContentView
        .components(separatedBy: "private func fileTileArtwork")
        .dropFirst()
        .first?
        .components(separatedBy: "private func fileSelectionIndicator")
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
    expectEqual(trackingView.contains("private var activeDragFileURLs: [URL] = []"), true, "shell drop validation caches decoded URLs for one drag session")
    expectEqual(trackingDragUpdateSection.contains("draggingPasteboard.fileURLs"), false, "pointer-frequency shell drag updates do not decode pasteboard URLs")
    expectEqual(trackingDragUpdateSection.contains("!activeDragFileURLs.isEmpty"), true, "shell drag updates reuse the entry-time URL cache")
    expectEqual(filesAirDropTargetSection.contains("private var activeDragItemIDs: [TemporaryShelfItem.ID] = []"), true, "Files AirDrop validation caches matched shelf IDs for one drag session")
    expectEqual(filesContentView.contains("nsView.setActive(isActive)"), true, "Files AirDrop registration follows the selected Files surface")
    expectEqual(filesAirDropTargetSection.contains("private func syncDragRegistration()"), true, "Files AirDrop centralizes active drag-type registration")
    expectEqual(filesAirDropTargetSection.contains("unregisterDraggedTypes()"), true, "hidden Files content unregisters its AppKit drag destination")
    expectEqual(filesAirDropTargetSection.contains("guard isActive else { return [] }"), true, "inactive Files AirDrop rejects entry before reading the pasteboard")
    expectEqual(filesAirDropUpdateSection.contains("filesPrimaryFileURLs"), false, "pointer-frequency AirDrop updates do not decode and rematch pasteboard URLs")
    expectEqual(filesAirDropUpdateSection.contains("!activeDragItemIDs.isEmpty"), true, "AirDrop updates reuse entry-time matched IDs")

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
    expectEqual(controller.contains("private func selectPrimaryFeature(_ feature: IslandPrimaryFeature)"), true, "controller owns right-side primary-feature selection")
    expectEqual(controller.contains("if overlayState.selectedPrimaryFeature == .files {\n            closeFilesPrimaryFeature()\n        }"), true, "leaving Files through the right navigation runs the canonical Files cleanup path")
    expectEqual(controller.contains("onPrimaryFeatureChange: { [weak self] feature in\n                self?.selectPrimaryFeature(feature)\n            }"), true, "overlay primary navigation delegates state changes to the controller")
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
    expectEqual(rectangleSelectionSection.contains("let nextSelectedItemIDs"), true, "rectangle selection computes the next set before publishing")
    expectEqual(rectangleSelectionSection.contains("guard nextSelectedItemIDs != currentSelectedItemIDs else { return }"), true, "rectangle selection skips identical pointer samples before state sync and logging")
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
    expectEqual(fileShelfOverlayMountSection.contains(".zIndex(22)"), true, "file shelf overlay draws above the Tasks content layer")
    expectEqual(overlay.contains("FilesPrimaryFeatureButton"), true, "overlay has a left safe-zone Files primary feature button")
    expectEqual(overlay.contains("fileShelfActions.onOpenFilesPrimaryFeature()"), true, "Files button delegates opening and pinning to the controller")
    expectEqual(overlay.contains("filesPrimaryFeatureFrame"), true, "Files primary feature uses the top status band layout instead of hand-written coordinates")
    expectEqual(overlay.contains("fileShelfButtonFrame(width: 30, height: 22)"), true, "Files primary feature button is compact because the label text is removed")
    expectEqual(filesPrimaryFeatureButtonSection.contains("Text(\"Files\")"), false, "Files primary feature button keeps only the icon and badge, not a text label")
    expectEqual(filesPrimaryFeatureButtonSection.contains("isSelected ? \"tray.full.fill\" : \"tray.full\""), false, "Files primary feature button does not abruptly swap icon names")
    expectEqual(filesPrimaryFeatureButtonSection.contains("badgeText"), true, "Files primary feature button renders the file count as a badge")
    expectEqual(overlay.contains("displayMode: state.filesDisplayMode"), true, "Files primary content receives the current display mode")
    expectEqual(overlay.contains("isActive: isExpanded && state.selectedPrimaryFeature == .files"), true, "Files primary content receives explicit active-state ownership")
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
    expectEqual(primaryFeatureSwitcherMountSection.contains(".disabled(!isExpanded)"), true, "collapsed primary navigation cannot retain keyboard activation")
    expectEqual(primaryFeatureSwitcherMountSection.contains(".allowsHitTesting(isExpanded)"), true, "collapsed primary navigation cannot retain pointer ownership")
    expectEqual(primaryFeatureSwitcherMountSection.contains(".accessibilityHidden(!isExpanded)"), true, "collapsed primary navigation leaves the accessibility tree")
    expectEqual(filesPrimaryFeatureMountSection.contains(".disabled(!isExpanded)"), true, "collapsed Files button cannot retain keyboard activation")
    expectEqual(filesPrimaryFeatureMountSection.contains(".allowsHitTesting(isExpanded)"), true, "collapsed Files button cannot retain pointer ownership")
    expectEqual(filesPrimaryFeatureMountSection.contains(".accessibilityHidden(!isExpanded)"), true, "collapsed Files button leaves the accessibility tree")
    expectEqual(overlay.contains("let onPrimaryFeatureChange: @MainActor (IslandPrimaryFeature) -> Void"), true, "overlay exposes a controller-owned primary-feature callback")
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
    expectEqual(overlay.contains("private var primaryFeatureEntranceLayer: some View"), false, "the obsolete coordinate-shifting entrance layer remains removed")
    expectEqual(overlay.contains("private var primaryFeatureEntranceClipShape: IslandShape"), false, "primary feature switcher does not keep the reverted external clipping shape")
    expectEqual(overlay.contains("selection: $state.selectedPrimaryFeature"), false, "primary feature switcher does not bypass controller-owned Files cleanup")
    expectEqual(overlay.contains("private var primaryFeatureSelection: Binding<IslandPrimaryFeature>"), true, "overlay wraps primary selection in a controller-routed Binding")
    expectEqual(
        markersAppearInOrder(
            ["setDataTimeRangeDrawerPresented(false)", "onPrimaryFeatureChange(feature)"],
            in: sourceSlice(
                overlay,
                from: "private var primaryFeatureSelection: Binding<IslandPrimaryFeature>",
                until: "private var hasManualCodexApproval"
            )
        ),
        true,
        "primary selection closes transient Data UI before writing through the controller callback"
    )
    expectEqual(overlay.contains("selection: primaryFeatureSelection"), true, "primary feature switcher uses the routed Binding")
    expectEqual(overlay.contains("ForEach(IslandPrimaryFeature.rightNavigationCases"), true, "right primary feature switcher renders only right safe-zone features in stable order")
    expectEqual(overlay.contains("IslandPrimaryFeature.rightNavigationCases.enumerated()"), false, "primary controls no longer need indices for staggered entrance timing")
    expectEqual(overlay.contains("private var primaryFeatureEntranceOffsetY: CGFloat"), false, "unused whole-group entrance offset remains removed")
    expectEqual(overlay.contains(".offset(y: isExpanded ? 0 : -primaryFeatureEntranceOffsetY)"), false, "top band energy effect does not move the primary feature group")
    expectEqual(overlay.contains(".offset(x: isExpanded ? 0 : -primaryFeatureEntranceOffset)"), false, "primary feature group no longer enters from the left")
    expectEqual(overlay.contains("private var primaryFeatureCanvasLayer: some View"), true, "top-band primary controls share one stable open-canvas coordinate layer")
    expectEqual(overlay.contains("private var primaryFeatureCanvasMask: some View"), true, "the stable primary layer remains visually clipped to the animated shell")
    expectEqual(overlay.contains("primaryFeatureCanvasLayer\n        }\n        .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)"), true, "the stable primary layer is mounted above the animated shell in the same canvas")
    expectEqual(overlay.contains(".frame(width: canvasWidth, height: metrics.expandedTopStatusBandLayout.bandHeight, alignment: .topLeading)"), true, "the primary layer uses the canonical top-band height without changing layout frames")
    expectEqual(overlay.contains(".animation(isExpanded ? expandAnimation : collapseAnimation, value: shellWidth)"), true, "the primary layer mask follows the shell geometry on expansion and collapse")
    expectEqual(overlay.contains(".mask {\n            primaryFeatureCanvasMask\n        }"), true, "the primary controls cannot float outside the collapsing shell")
    expectEqual(overlay.contains("primaryFeatureScreenXCompensation"), false, "primary controls do not introduce a second animated horizontal offset")
    expectEqual(primaryFeatureSwitcherSection.contains("private var entranceAnimation: Animation"), true, "right primary controls share one entrance animation")
    expectEqual(primaryFeatureSwitcherSection.contains("Animation.linear(duration: animationProfile.primaryFeatureEntranceDuration)"), true, "right primary controls use the requested linear entrance")
    expectEqual(primaryFeatureSwitcherSection.contains(".delay(animationProfile.primaryFeatureEntranceStartDelay)"), true, "right primary controls use the shared settled-shell delay")
    expectEqual(primaryFeatureSwitcherSection.contains(".animation(entranceAnimation, value: isExpanded)"), true, "right primary controls animate as one simultaneous group")
    expectEqual(primaryFeatureSwitcherSection.contains("featureEntranceAnimation(index:"), false, "right primary controls do not stagger internally")
    expectEqual(primaryFeatureSwitcherSection.contains("Animation.spring("), false, "right primary control entrance no longer uses spring timing")
    expectEqual(animationProfileSource.contains("public let primaryFeatureEntranceDuration: Double"), true, "primary feature linear duration lives in the shared profile")
    expectEqual(animationProfileSource.contains("primaryFeatureEntranceDuration: 0.18"), true, "primary feature linear entrance uses the approved 180ms budget")
    expectEqual(animationProfileSource.contains("primaryFeatureStaggerDelay"), false, "shared animation profile no longer exposes stagger timing")
    expectEqual(animationProfileSource.contains("primaryFeatureEntranceResponse"), false, "shared animation profile removes the obsolete entrance spring response")
    expectEqual(animationProfileSource.contains("primaryFeatureEntranceDampingFraction"), false, "shared animation profile removes the obsolete entrance spring damping")
    expectEqual(animationProfileSource.contains("primaryFeatureEntranceBlendDuration"), false, "shared animation profile removes the obsolete entrance spring blend")
    expectEqual(IslandAnimationProfile.default.primaryFeatureEntranceStartDelay >= IslandAnimationProfile.default.expandResponse * 0.85, true, "primary feature entrance waits until horizontal shell expansion is visually stable")
    expectEqual(animationProfileSource.contains("primaryContentEntranceDelay: 0.40"), true, "primary content follows the navigation layer after a short visual separation")
    expectEqual(animationProfileSource.contains("primaryContentTransitionDistance: 6"), true, "primary content travels only a restrained six points from its source")
    expectEqual(overlay.contains("@State private var isPrimaryContentEntranceActive = false"), true, "primary content stays absent until the expanded shell is visually stable")
    expectEqual(overlay.contains("@State private var mountedPrimaryFeatures: [IslandPrimaryFeature] = []"), true, "primary content tracks only features visited during the current expansion")
    expectEqual(primaryContentMountSection.contains("if mountedPrimaryFeatures.contains(.tasks)"), true, "Tasks mounts lazily on first selection and then stays alive for feature transitions")
    expectEqual(primaryContentMountSection.contains("if mountedPrimaryFeatures.contains(.files)"), true, "Files mounts lazily and preserves its icon cache while the island remains expanded")
    expectEqual(primaryContentMountSection.contains("if mountedPrimaryFeatures.contains(.data)"), true, "Data mounts lazily without joining an unrelated cold expansion")
    expectEqual(primaryContentMountSection.contains("switch state.selectedPrimaryFeature"), false, "feature switching retains visited content for explicit outgoing opacity and layer transitions")
    expectEqual(overlay.contains("mountPrimaryFeature(state.selectedPrimaryFeature)"), true, "cold entrance mounts only the currently selected primary content")
    expectEqual(overlay.contains("mountPrimaryFeature(feature)"), true, "selecting an unvisited feature mounts it without discarding previously visited content")
    expectEqual(overlay.contains("mountedPrimaryFeatures.removeAll()"), true, "a completed collapse releases visited primary content before the next cold entrance")
    expectEqual(overlay.contains("@State private var primaryContentExitDeadline: Date?"), true, "primary content remembers only the active exit window for reversible reopening")
    expectEqual(overlay.contains("private var primaryContentEntranceDelay: TimeInterval"), true, "primary content uses a named entrance delay")
    expectEqual(overlay.contains("accessibilityReduceMotion ? 0 : animationProfile.primaryContentEntranceDelay"), true, "normal content timing comes from the shared profile while Reduce Motion removes the delay")
    expectEqual(overlay.contains("private var isShellLayoutExpanded: Bool"), true, "reduced-motion content can fade before the shell layout snaps closed")
    expectEqual(overlay.contains("accessibilityReduceMotion ? state.usesOpenCanvas : isExpanded"), true, "only Reduce Motion keeps the open layout alive for the content fade window")
    expectEqual(controller.contains("let canvasDelay = prefersReducedMotion\n                ? animationProfile.reducedMotionFadeDuration\n                : animationProfile.collapseCanvasDelay"), true, "reduced-motion canvas collapse waits for the local opacity exit")
    expectEqual(overlay.contains("private var primaryContentTransition: AnyTransition"), true, "primary content owns one accessibility-aware transition")
    expectEqual(overlay.contains(".offset(y: -animationProfile.primaryContentTransitionDistance)"), true, "primary content enters from the top-band source")
    expectEqual(overlay.contains("private var primaryContentEntranceAnimation: Animation"), true, "primary content owns one interruptible entrance animation")
    expectEqual(overlay.contains("private var primaryContentExitAnimation: Animation"), true, "primary content has a symmetric fast exit")
    expectEqual(overlay.contains("DispatchQueue.main.asyncAfter(deadline: .now() + entranceDelay)"), true, "primary content waits before first mounting while reversible exits resume immediately")
    expectEqual(overlay.contains("withAnimation(primaryContentEntranceAnimation)"), true, "primary content mounts with the shared critically damped animation")
    expectEqual(overlay.contains("withAnimation(primaryContentExitAnimation)"), true, "primary content exits along the same source path")
    expectEqual(overlay.contains("let shouldReverseExit = primaryContentExitDeadline.map { Date() < $0 } ?? false"), true, "reopening during the active exit reverses from the current presentation state")
    expectEqual(overlay.contains("let entranceDelay = shouldReverseExit ? 0 : primaryContentEntranceDelay"), true, "only a completed content exit pays the first-entrance delay again")
    expectEqual(overlay.contains("guard !isPrimaryContentEntranceActive else { return }"), true, "already mounted content does not replay when accessibility settings change")
    expectEqual(overlay.contains("schedulePrimaryContentEntrance(expanded: isExpanded)"), true, "primary content entrance resets whenever the shell changes state")
    expectEqual(overlay.contains("if isExpanded && isPrimaryContentEntranceActive && state.selectedPrimaryFeature == .files {"), false, "shell state does not remove Files before the content exit transaction owns its fade")
    expectEqual(filesPrimaryFeatureButtonSection.contains("let animationProfile: IslandAnimationProfile"), true, "Files button receives the shared entrance profile")
    expectEqual(filesPrimaryFeatureButtonSection.contains("Animation.linear(duration: animationProfile.primaryFeatureEntranceDuration)"), true, "Files icon uses the same requested linear entrance")
    expectEqual(filesPrimaryFeatureButtonSection.contains(".delay(animationProfile.primaryFeatureEntranceStartDelay)"), true, "Files icon uses the same settled-shell delay as the right primary controls")
    expectEqual(filesPrimaryFeatureButtonSection.contains(".animation(entranceAnimation, value: isExpanded)"), true, "Files icon uses the shared simultaneous entrance timing")
    expectEqual(filesPrimaryFeatureButtonSection.contains("Animation.spring("), false, "Files icon entrance no longer uses spring timing")
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
    expectEqual(filesPrimaryFeatureButtonSection.contains(".animation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.18), value: isSelected)"), true, "Files primary button keeps icon motion only when the system permits it")
    expectEqual(filesPrimaryContentMountSection.contains(".opacity(state.selectedPrimaryFeature == .files ? 1 : 0)"), true, "Files stays mounted so its outgoing layer can fade below the incoming feature")
    expectEqual(filesPrimaryContentMountSection.contains(".offset(y: primaryContentOffset(for: .files))"), true, "Files selection changes follow the shared top-band source path")
    expectEqual(filesPrimaryContentMountSection.contains(".disabled(!isExpanded || state.selectedPrimaryFeature != .files)"), true, "hidden Files controls cannot retain keyboard activation")
    expectEqual(filesPrimaryContentMountSection.contains(".allowsHitTesting(isExpanded && state.selectedPrimaryFeature == .files)"), true, "only the selected expanded Files container accepts input during a primary-feature transition")
    expectEqual(filesPrimaryContentMountSection.contains(".accessibilityHidden(!isExpanded || state.selectedPrimaryFeature != .files)"), true, "hidden Files content does not remain in the accessibility tree")
    expectEqual(filesPrimaryContentMountSection.contains(".zIndex(state.selectedPrimaryFeature == .files ? 21 : 20)"), true, "incoming Files content layers above outgoing primary content")
    expectEqual(filesPrimaryContentMountSection.contains(".transition(primaryContentTransition)"), true, "Files primary content enters from the shared top-band source transition")
    expectEqual(overlay.contains(".animation(primaryContentEntranceAnimation, value: state.selectedPrimaryFeature)"), true, "expanded feature switching preserves motion feedback including a reduced-motion fade")

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
    expectEqual(filesContentView.contains("@State private var iconCache = FilesPrimaryIconCache()"), true, "Files primary preview keeps native icons for the view lifetime")
    expectEqual(filesPrimaryArtworkSection.contains("iconCache.icon(for: item)"), true, "Files tile redraws read through the view-lifetime icon cache")
    expectEqual(filesPrimaryArtworkSection.contains("NSWorkspace.shared.icon(forFile:"), false, "hidden or refreshed Files tiles do not repeat Launch Services icon lookup")
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
    expectEqual(filesPrimaryDragSourceSection.contains("x: bounds.midX"), false, "Files preview drag proxy does not jump to the tile center")
    expectEqual(filesPrimaryDragSourceSection.contains("x: currentLocation.x - (dragImageSize.width / 2)"), true, "Files preview drag proxy starts under the live pointer")
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
    expectEqual(shelfView.contains("@State private var iconCache = TemporaryFileIconCache()"), true, "temporary file shelf keeps a view-lifetime AppKit icon cache")
    expectEqual(temporaryFileTileSection.contains("iconCache.icon(for: item)"), true, "temporary file tiles read icons through the cache")
    expectEqual(temporaryFileTileSection.contains("NSWorkspace.shared.icon(forFile:"), false, "rectangle drag redraws do not query Launch Services from each tile")
    expectEqual(shelfView.contains("pasteboardWriter: shelfItem.fileURL as NSURL"), true, "temporary file shelf exports real file URL pasteboard writers")
    expectEqual(shelfView.contains("endedAt screenPoint: NSPoint, operation: NSDragOperation"), true, "temporary file shelf drag bridge detects successful external drops")
    expectEqual(temporaryFileDragSourceSection.contains("x: bounds.midX"), false, "temporary shelf drag proxy does not jump to the tile center")
    expectEqual(temporaryFileDragSourceSection.contains("x: currentLocation.x - (dragImageSize.width / 2)"), true, "temporary shelf drag proxy starts under the live pointer")
    expectEqual(temporaryFileDragSourceSection.contains("let dragIcon = NSWorkspace.shared.icon(forFile: draggedItems.first?.fileURL.path ?? item.fileURL.path)"), true, "temporary shelf multi-drag resolves one representative icon before mapping items")
    expectEqual(temporaryFileDragSourceSection.contains("contents: dragIcon"), true, "temporary shelf multi-drag reuses the representative icon for every pasteboard item")
    expectEqual(temporaryFileDragSourceSection.contains("let icon = NSWorkspace.shared.icon(forFile: shelfItem.fileURL.path)"), false, "temporary shelf drag start does not query Launch Services once per selected file")
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
    let overlayView = source("Sources/DynamicIsland/Views/IslandOverlayView.swift")
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
    let animationProfileSource = source("Sources/DynamicIslandCore/IslandAnimationProfile.swift")
    let pressButtonStyle = source("Sources/DynamicIsland/Views/IslandPressButtonStyle.swift")
    let fileShelfOverlayView = source("Sources/DynamicIsland/Views/FileShelfOverlayView.swift")
    let topBandEnergyEffect = source("Sources/DynamicIsland/Views/TopBandEnergyEffectView.swift")
    let buildScript = source("script/build_and_run.sh")
    let musicSignalScript = source("script/send_music_signal.sh")
    let islandShellFrameSection = sourceSlice(
        overlayView,
        from: "            islandShell\n",
        until: "\n\n            if state.isCodexApprovalAttachmentPresented,"
    )
    let controllerInitSection = controller
        .components(separatedBy: "    init(")
        .dropFirst()
        .first?
        .components(separatedBy: "    private static func displayLogMetadata")
        .first ?? "installPointerPassthroughMonitor()"
    let controllerHideSection = controller
        .components(separatedBy: "    func hide()")
        .dropFirst()
        .first?
        .components(separatedBy: "    func refreshForCurrentScreen()")
        .first ?? ""
    let setShellHiddenSection = controller
        .components(separatedBy: "    private func setShellHidden")
        .dropFirst()
        .first?
        .components(separatedBy: "    private func installHiddenScrollMonitor")
        .first ?? ""
    let pointerMonitorInstallSection = controller
        .components(separatedBy: "    private func installPointerPassthroughMonitor")
        .dropFirst()
        .first?
        .components(separatedBy: "    private func syncHoverWithPointer")
        .first ?? ""
    let pointerPassthroughSyncSection = controller
        .components(separatedBy: "    private func syncMouseEventPassthroughWithPointer")
        .dropFirst()
        .first?
        .components(separatedBy: "    private func pointerInsideInteractiveShell")
        .first ?? ""
    let hoverSyncSection = controller
        .components(separatedBy: "    private func syncHoverWithPointer")
        .dropFirst()
        .first?
        .components(separatedBy: "    private func collapseExpandedShellIfPointerLeavesInteractiveShell")
        .first ?? ""
    let musicSkipTrackingSection = controller
        .components(separatedBy: "case .tracking(let direction, let progress):")
        .dropFirst()
        .first?
        .components(separatedBy: "case .armed(let direction, let progress):")
        .first ?? ""
    let musicSkipArmedSection = controller
        .components(separatedBy: "case .armed(let direction, let progress):")
        .dropFirst()
        .first?
        .components(separatedBy: "case .cancelled(let direction):")
        .first ?? ""
    let topBandRendererInitSection = topBandEnergyEffect
        .components(separatedBy: "private final class TopBandEnergyRenderer")
        .dropFirst()
        .first?
        .components(separatedBy: "    func start()")
        .first ?? ""

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
    expectEqual(
        islandShellFrameSection.contains("alignment: .top\n                )"),
        true,
        "base shell stays centered while normal or approval-backed canvases expand and collapse"
    )
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
    expectEqual(overlay.contains("musicArtworkCenterX"), true, "overlay animates artwork between closed and expanded positions")
    expectEqual(overlay.contains("musicWaveformCenterX"), true, "overlay animates waveform between closed and expanded positions")
    expectEqual(overlay.contains("metrics.expandedMusicArtworkCenterX"), true, "expanded artwork uses its own left-header target position")
    expectEqual(overlay.contains("metrics.expandedMusicWaveformCenterX"), true, "expanded waveform uses its own left-header target position")
    expectEqual(overlay.contains("frame(width: metrics.closedMusicAccessorySize, height: metrics.closedMusicAccessorySize)"), true, "expanded music accessories keep the compact 18pt size")
    expectEqual(overlay.contains("private var musicAccessoryTransition: AnyTransition"), true, "compact music accessories have a dedicated accessibility-aware transition")
    expectEqual(overlay.contains(".opacity.combined(with: .scale(scale: 0.94))"), true, "normal-mode music accessories materialize from a nearby physical scale")
    expectEqual(overlay.contains("value: showsMusicAccessories"), true, "music accessory transition is keyed to visibility")
    expectEqual(overlay.contains("private func reducedMotionFade<Value: Equatable, Content: View>"), true, "reduced motion conditionally scopes a local content-only fade transaction")
    expectEqual(overlay.contains("reducedMotionFade(value: showsMusicAccessories)"), true, "reduced motion cross-fades music accessories without tweening shell width")
    expectEqual(overlay.contains("reducedMotionFade(value: showsTrackInfo)"), true, "reduced motion cross-fades track info without tweening shell height")
    expectEqual(overlay.contains(".animation(reducedMotionContentFadeAnimation"), false, "normal mode does not install a local nil animation that suppresses inherited transitions")
    expectEqual(overlay.contains("VStack(alignment: .center"), true, "track title and artist are centered")
    expectEqual(overlay.contains(".multilineTextAlignment(.center)"), true, "track title and artist text aligns centered")
    expectEqual(animationProfileSource.contains("public let musicAccessoryTransitionDuration: Double"), true, "music accessory timing lives in the shared animation profile")
    expectEqual(animationProfileSource.contains("musicAccessoryTransitionDuration: 0.22"), true, "music accessory transition keeps a short 220ms budget")
    expectEqual(animationProfileSource.contains("public let musicSkipFeedbackDismissDuration: Double"), true, "music skip dismissal timing lives in the shared animation profile")
    expectEqual(animationProfileSource.contains("public let trackInfoTransitionDuration: Double"), true, "track info timing lives in the shared animation profile")
    expectEqual(animationProfileSource.contains("public let hideTransitionDuration: Double"), true, "hide timing lives in the shared animation profile")
    expectEqual(IslandAnimationProfile.default.primaryFeatureSelectionResponse, 0.30, "primary feature selection uses the Apple-style default response")
    expectEqual(IslandAnimationProfile.default.primaryFeatureSelectionDamping, 1.0, "primary feature selection is critically damped without click-driven bounce")
    expectEqual(controller.contains(".easeIn("), false, "UI feedback never exits with a delaying ease-in curve")
    expectEqual(controller.contains(".linear(duration: 0.22)"), false, "track info does not use constant-speed motion")
    expectEqual(controller.contains("prefersReducedMotion ? nil : .easeOut(duration: animationProfile.trackInfoTransitionDuration)"), true, "track info uses the shared ease-out timing when motion is permitted")
    expectEqual(controller.contains("animationProfile.hideTransitionDuration * runtimeSettings.hideAnimationScale"), true, "runtime hide scaling starts from the shared duration token")
    expectEqual(overlay.contains(".animation(.easeInOut(duration: 0.22), value: state.isShellHidden)"), false, "hide visuals do not override the controller's runtime-scaled timing")
    expectEqual(overlay.contains(".animation(accessibilityReduceMotion ? nil : .easeOut(duration: animationProfile.musicAccessoryTransitionDuration), value: showsMusicAccessories)"), true, "music accessories use immediate ease-out feedback only when motion is permitted")
    expectEqual(overlay.contains("value: state.musicPlayback.isPlaying"), false, "music accessory visibility has one animation owner")
    expectEqual(animationProfileSource.contains("public let primaryFeatureButtonReleaseDuration: Double"), true, "button release timing lives in the shared animation profile")
    expectEqual(animationProfileSource.contains("primaryFeatureButtonReleaseDuration: 0.08"), true, "button release snaps faster than the deliberate press-in")
    expectEqual(pressButtonStyle.contains("struct IslandPressButtonStyle: ButtonStyle"), true, "custom island buttons share one pressed-state style")
    expectEqual(pressButtonStyle.contains("animationProfile.primaryFeatureButtonPressScale"), true, "shared button feedback uses the approved 0.96 press scale")
    expectEqual(pressButtonStyle.contains("animationProfile.primaryFeatureButtonReleaseDuration"), true, "shared button feedback uses asymmetric release timing")
    expectEqual(overlay.contains(".buttonStyle(.plain)"), false, "custom overlay, Files, and Tasks buttons retain visible pointer-down feedback")
    expectEqual(fileShelfOverlayView.contains(".buttonStyle(.plain)"), false, "temporary File Shelf buttons retain visible pointer-down feedback")
    expectEqual(overlay.contains(".scale(scale: 0.72"), false, "small controls do not appear from an implausibly tiny scale")
    expectEqual(overlay.contains(".scale(scale: 0.94"), true, "small controls appear from the 0.90-0.97 physical scale range")
    expectEqual(animationProfileSource.contains("public let reducedMotionFadeDuration: Double"), true, "reduced-motion feedback timing lives in the shared animation profile")
    expectEqual(animationProfileSource.contains("reducedMotionFadeDuration: 0.20"), true, "reduced-motion feedback uses the standard 200ms fade")
    expectEqual(overlay.contains("@Environment(\\.accessibilityReduceMotion)"), true, "SwiftUI motion surfaces observe the live Reduce Motion setting")
    expectEqual(overlay.contains("private var hoverShadowRadius: CGFloat"), true, "hover shadow geometry has an accessibility-aware owner")
    expectEqual(overlay.contains("accessibilityReduceMotion ? 6 : (showsHoverPreview ? 6 : 0)"), true, "Reduce Motion keeps hover shadow radius fixed while opacity changes")
    expectEqual(overlay.contains("private var hoverShadowYOffset: CGFloat"), true, "hover shadow vertical geometry has an accessibility-aware owner")
    expectEqual(overlay.contains("radius: hoverShadowRadius"), true, "shell shadow reads the fixed reduced-motion radius")
    expectEqual(overlay.contains("y: hoverShadowYOffset"), true, "shell shadow reads the fixed reduced-motion offset")
    expectEqual(overlay.contains("state.isTopBandEnergyEffectEnabled && isTopBandEnergyActive && !accessibilityReduceMotion"), true, "continuous top-band energy does not mount under Reduce Motion")
    expectEqual(overlay.contains("accessibilityReduceMotion ? 0 : NotchMetrics.musicSkipEdgeExpansionMax"), true, "reduced motion keeps skip feedback without moving the shell edge")
    expectEqual(controller.contains("NSWorkspace.shared.accessibilityDisplayShouldReduceMotion"), true, "AppKit-owned shell animations observe the live Reduce Motion setting")
    expectEqual(waveformView.contains("@Environment(\\.accessibilityReduceMotion)"), true, "compact waveform observes Reduce Motion")
    expectEqual(waveformView.contains("removeAnimation(forKey: \"waveform-scale\")"), true, "reduced motion removes the infinite waveform animation")
    expectEqual(overlay.contains("if isShattering && !accessibilityReduceMotion"), true, "task deletion skips particle motion when Reduce Motion is enabled")
    expectEqual(pressButtonStyle.contains("@Environment(\\.accessibilityReduceMotion)"), true, "button feedback substitutes a non-scaling reduced-motion response")
    expectEqual(pressButtonStyle.contains(".opacity(accessibilityReduceMotion && configuration.isPressed ? 0.72 : 1)"), true, "reduced-motion button presses keep opacity feedback")
    expectEqual(topBandEnergyEffect.contains("Timer(timeInterval: 1.0 / 12.0"), true, "normal-mode energy rendering keeps its deliberate low-frequency timer")
    expectEqual(topBandEnergyEffect.contains("final class TopBandEnergyPipelineCache"), true, "top-band energy caches immutable Metal pipeline resources")
    expectEqual(topBandEnergyEffect.contains("device.registryID"), true, "top-band energy keys cached resources by Metal device")
    expectEqual(controllerInitSection.contains("TopBandEnergyEffectResources.prewarm()"), true, "controller startup prewarms top-band Metal resources off the expansion path")
    expectEqual(topBandEnergyEffect.contains("prepareResources(for: device)"), true, "top-band shader compilation is isolated to background preparation")
    expectEqual(topBandEnergyEffect.contains("readyResources(for device: MTLDevice)"), true, "top-band UI code has a non-blocking ready-resource lookup")
    expectEqual(topBandRendererInitSection.contains("TopBandEnergyPipelineCache.shared.readyResources(for: device)"), true, "each energy renderer consumes only already prepared pipeline resources")
    expectEqual(topBandRendererInitSection.contains("makeLibrary(source:"), false, "energy renderer initialization does not compile inline Metal source on mount")
    expectEqual(topBandRendererInitSection.contains("makeRenderPipelineState"), false, "energy renderer initialization does not build a pipeline on mount")
    expectEqual(topBandEnergyEffect.contains("didPrepareNotification"), true, "an already-mounted energy view is notified after background preparation")
    expectEqual(topBandEnergyEffect.contains("configureMetalRendererIfReady()"), true, "energy view attaches Metal only after resources are ready")
    expectEqual(topBandEnergyEffect.contains("NSWindow.didChangeOcclusionStateNotification"), true, "energy rendering follows owning-panel visibility changes")
    expectEqual(topBandEnergyEffect.contains("window?.isVisible == true"), true, "energy timer requires a visible owning window")
    expectEqual(topBandEnergyEffect.contains("private var isWindowRenderable: Bool"), true, "energy rendering centralizes ordered and occluded window visibility")
    expectEqual(topBandEnergyEffect.contains("window.occlusionState.contains(.visible)"), true, "energy timer stops while its owning window is fully occluded")
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
    expectEqual(musicSkipTrackingSection.contains("withAnimation"), false, "live horizontal skip progress follows trackpad deltas without spring lag")
    expectEqual(musicSkipArmedSection.contains("overlayState.musicSkipGestureProgress = progress\n            withAnimation(.easeOut(duration: 0.10)) {\n                overlayState.isMusicSkipArmed = true"), true, "arming updates progress directly and animates only the ready-state emphasis")
    expectEqual(overlay.contains("value: state.musicSkipGestureProgress"), false, "overlay does not add a second animation to live gesture progress")
    expectEqual(overlay.contains("value: state.musicSkipFeedbackDirection"), false, "skip rollback and dismissal inherit their single controller-owned animation transaction")
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
    expectEqual(controller.contains("private var pointerPassthroughMonitor: Any?"), true, "panel retains a monitor for returning from transparent click-through")
    expectEqual(controller.contains("installPointerPassthroughMonitor()"), true, "panel installs the transparent-area pointer monitor")
    expectEqual(controller.contains("NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged])"), true, "transparent click-through keeps tracking pointer returns and file drags")
    expectEqual(controllerInitSection.contains("installPointerPassthroughMonitor()"), false, "pointer monitor is not active for the controller's full lifetime")
    expectEqual(controllerHideSection.contains("removePointerPassthroughMonitor()"), true, "menu hiding removes the global pointer monitor")
    expectEqual(setShellHiddenSection.contains("if hidden {\n            removePointerPassthroughMonitor()"), true, "gesture hiding removes the global pointer monitor")
    expectEqual(pointerMonitorInstallSection.contains("guard panel.isVisible, panel.ignoresMouseEvents, !overlayState.isShellHidden else { return }"), true, "pointer monitor only runs while a visible shell is passing mouse events through")
    expectEqual(pointerMonitorInstallSection.contains("Task { @MainActor"), false, "global mouse events do not create one MainActor task per event")
    expectEqual(pointerMonitorInstallSection.contains("DispatchSource.makeUserDataAddSource(queue: .main)"), true, "global mouse events use a main-queue coalescing source")
    expectEqual(pointerMonitorInstallSection.contains("syncSource.add(data: 1)"), true, "raw global mouse events only signal the coalescing source")
    expectEqual(pointerMonitorInstallSection.contains("MainActor.assumeIsolated"), true, "coalesced pointer synchronization runs on the main actor")
    expectEqual(pointerMonitorInstallSection.contains("guard let self, self.pointerPassthroughMonitor != nil else { return }"), true, "coalesced pointer events exit after the monitor is removed")
    expectEqual(pointerMonitorInstallSection.contains("guard self.panel.isVisible, self.panel.ignoresMouseEvents, !self.overlayState.isShellHidden else { return }"), true, "coalesced pointer events recheck visibility and pass-through state")
    expectEqual(controller.contains("pointerPassthroughSyncSource?.cancel()"), true, "controller cancels the pointer coalescing source during teardown")
    expectEqual(pointerPassthroughSyncSection.contains("if shouldIgnoreMouseEvents {\n            installPointerPassthroughMonitor()\n        } else {\n            removePointerPassthroughMonitor()"), true, "pointer monitor starts outside the shell and stops immediately on return")
    expectEqual(controller.contains("collapseExpandedShellIfPointerLeavesInteractiveShell(pointerInsideIsland)"), true, "expanded shell collapses when the pointer leaves the visible shell path")
    expectEqual(controller.contains("guard !isPointerInside, isExpanded, shouldCollapseOnMouseExit() else { return }"), true, "precise leave collapse preserves Files pinned display modes")
    expectEqual(pointerPassthroughSyncSection.contains("panel.ignoresMouseEvents = shouldIgnoreMouseEvents"), true, "transparent panel areas pass clicks to underlying windows")
    expectEqual(hoverSyncSection.contains("let shouldHover = pointerInsideIsland && !overlayState.isShellHidden"), true, "hover synchronization computes one boundary state per pointer sample")
    expectEqual(hoverSyncSection.contains("if overlayState.isHovered != shouldHover"), true, "hover synchronization republishes only when the boundary state changes")
    expectEqual(controller.contains("panel.orderFrontRegardless()\n        syncHoverWithPointer()"), true, "show synchronizes transparent click-through before the first click")
    expectEqual(controller.contains("overlayState.isShellHidden = hidden\n        }\n        if hidden"), true, "hidden restore changes state before re-synchronizing pointer pass-through")
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
    expectEqual(controller.contains("withAnimation(.easeOut(duration: animationDuration))"), true, "scroll hide/show responds immediately with the runtime-scaled transition")
    expectEqual(controller.contains("height: expandedShellHeight + NotchMetrics.defaultClosedCanvasBottomSlack"), true, "expanded canvas keeps the same bottom slack below the adaptive shell")
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

private func testDataPrimaryContentViewContracts() {
    let dataView = source("Sources/DynamicIsland/Views/DataPrimaryContentView.swift")
    let codexUsageSource = source("Sources/DynamicIsland/Support/CodexUsageSource.swift")
    let ccSwitchUsageSource = source("Sources/DynamicIsland/Support/CCSwitchUsageSource.swift")
    let triggerSection = sourceSlice(
        dataView,
        from: "private var timeRangeTrigger: some View",
        until: "private var refreshButton: some View"
    )
    let drawerContentSection = sourceSlice(
        dataView,
        from: "private var timeRangeDrawerContent: some View",
        until: "private func timeRangeOption"
    )
    let partialStateSection = sourceSlice(
        dataView,
        from: "private var isPartial: Bool",
        until: "private var showsFailure: Bool"
    )
    let snapshotHeaderSection = sourceSlice(
        dataView,
        from: "private func snapshotHeader",
        until: "private func metricGrid"
    )
    let metricGridSection = sourceSlice(
        dataView,
        from: "private func metricGrid",
        until: "private func metricColumns"
    )
    let metricCellSection = sourceSlice(
        dataView,
        from: "private func metricCell",
        until: "private func cacheHitFooter"
    )
    let cacheHitFooterSection = sourceSlice(
        dataView,
        from: "private func cacheHitFooter",
        until: "private var unavailableContent"
    )
    let unavailableContentSection = sourceSlice(
        dataView,
        from: "private var unavailableContent: some View",
        until: "private var controls: some View"
    )
    let selectSection = sourceSlice(
        dataView,
        from: "private func selectTimeRange",
        until: "private func refresh"
    )
    let refreshSection = sourceSlice(
        dataView,
        from: "private func refresh",
        until: "private func setDrawerPresented"
    )
    let drawerPresentationForwardingSection = sourceSlice(
        dataView,
        from: "private func setDrawerPresented",
        until: "private func formattedCost"
    )

    expectEqual(dataView.contains("struct DataPrimaryContentView: View"), true, "Data has one standalone primary content view")
    expectEqual(dataView.contains("let presentation: UsagePresentationState"), true, "Data view receives presentation state")
    expectEqual(dataView.contains("let selectedTimeRange: UsageTimeRange"), true, "Data view receives the selected natural-day range")
    expectEqual(dataView.contains("let isActive: Bool"), true, "Data view receives primary-feature activity")
    expectEqual(dataView.contains("let isTimeRangeDrawerPresented: Bool"), true, "drawer presentation is externally owned")
    expectEqual(dataView.contains("let onTimeRangeDrawerPresentationChange: @MainActor (Bool) -> Void"), true, "Data view reports drawer presentation changes")
    expectEqual(dataView.contains("let onSelectTimeRange: @MainActor (UsageTimeRange) -> Void"), true, "Data view reports range selection")
    expectEqual(dataView.contains("let onRefresh: @MainActor () -> Void"), true, "Data view reports manual refresh")
    expectEqual(dataView.contains("@State private var isTimeRangeDrawerPresented"), false, "drawer truth is not duplicated in local state")

    expectEqual(dataView.components(separatedBy: "private var timeRangeTrigger: some View").count - 1, 1, "Data renders one current-range trigger")
    expectEqual(dataView.contains("ForEach(UsageTimeRange.allCases)"), false, "Data does not render a horizontal all-ranges segment")
    expectEqual(dataView.contains(".pickerStyle(.segmented)"), false, "Data has no segmented range picker")
    expectEqual(triggerSection.contains("setDrawerPresented(!isTimeRangeDrawerPresented)"), true, "current range trigger only toggles drawer presentation")
    expectEqual(triggerSection.contains("onSelectTimeRange"), false, "opening the drawer does not select a range")
    expectEqual(triggerSection.contains("onRefresh"), false, "opening the drawer does not refresh usage")

    for forbidden in ["Chart", "LineMark", "AreaMark", "sourceFilter", "modelFilter", "clientFilter", "Timer", "TimelineView", "repeatForever"] {
        expectEqual(dataView.contains(forbidden), false, "Data view omits out-of-scope \(forbidden) behavior")
    }
    expectEqual(dataView.contains("proxy.size.width >= 560"), true, "Data chooses its grid only from available content width")
    expectEqual(dataView.contains("GridItem(.flexible(minimum: 128)"), true, "each Data metric column keeps a 128pt minimum")
    expectEqual(dataView.contains("count: usesFourColumnLayout ? 4 : 2"), true, "Data uses four columns at 560pt and a 2 by 2 grid below it")
    expectEqual(metricGridSection.contains(".frame(height: 58)"), true, "the 2 by 2 metric grid reserves enough height for two readable rows")
    expectEqual(dataView.contains(".monospacedDigit()"), true, "usage digits remain stable during refresh")
    expectEqual(dataView.contains("case .idle, .loading(previous: nil):"), true, "idle and initial loading show a static pending state")
    expectEqual(dataView.contains("case .loading(previous: .some(let snapshot))"), true, "refresh loading retains the previous trusted snapshot")
    expectEqual(dataView.contains("case .available(let snapshot), .empty(let snapshot), .partial(let snapshot):"), true, "terminal snapshot states render their trusted values")
    expectEqual(dataView.contains("case .failed:"), true, "failed usage has an explicit unavailable state")
    expectEqual(dataView.contains("正在统计…"), true, "initial loading uses static progress copy")
    expectEqual(dataView.contains("统计数据暂不可用"), true, "failed usage does not masquerade as zero")
    expectEqual(dataView.contains("不完整"), true, "partial usage exposes a low-emphasis completeness hint")
    expectEqual(dataView.contains("snapshot.cacheHitRate.map"), true, "empty cache-rate denominators remain N/A")
    expectEqual(partialStateSection.contains("displayedSnapshot?.completeness == .partial"), true, "partial presentation follows the displayed snapshot, including retained loading data")
    expectEqual(partialStateSection.contains("if case .partial = presentation"), false, "refreshing a partial snapshot does not lose its completeness hint")

    expectEqual(dataView.contains("private var titleForegroundColor: Color"), true, "Data centralizes title contrast")
    expectEqual(dataView.contains("private var secondaryForegroundColor: Color"), true, "Data centralizes secondary contrast")
    expectEqual(dataView.contains("private var tertiaryForegroundColor: Color"), true, "Data centralizes tertiary contrast")
    expectEqual(snapshotHeaderSection.contains(".foregroundStyle(titleForegroundColor)"), true, "statistics title uses the contrast-aware title color")
    expectEqual(snapshotHeaderSection.components(separatedBy: ".foregroundStyle(tertiaryForegroundColor)").count - 1 >= 2, true, "approximate total and request-cost copy use the contrast-aware tertiary color")
    expectEqual(metricCellSection.contains(".foregroundStyle(tertiaryForegroundColor)"), true, "metric labels use the contrast-aware tertiary color")
    expectEqual(cacheHitFooterSection.contains(".foregroundStyle(secondaryForegroundColor)"), true, "cache footer uses the contrast-aware secondary color")
    expectEqual(unavailableContentSection.contains(".foregroundStyle(titleForegroundColor)"), true, "unavailable title uses the contrast-aware title color")
    expectEqual(unavailableContentSection.components(separatedBy: ".foregroundStyle(secondaryForegroundColor)").count - 1 >= 2, true, "unavailable value and status copy use the contrast-aware secondary color")
    expectEqual(unavailableContentSection.contains(".foregroundStyle(tertiaryForegroundColor)"), true, "unavailable footer uses the contrast-aware tertiary color")

    expectEqual(dataView.contains("#if compiler(>=6.2)"), true, "native Liquid Glass has a compiler availability guard")
    expectEqual(dataView.contains("if #available(macOS 26.0, *), !accessibilityReduceTransparency"), true, "native Liquid Glass also has a runtime and transparency guard")
    expectEqual(dataView.contains("GlassEffectContainer(spacing: 0)"), true, "one zero-spacing glass container owns all Data controls")
    expectEqual(dataView.contains(".glassEffect(.regular.interactive(), in: Capsule"), true, "time trigger uses interactive capsule glass")
    expectEqual(dataView.contains("RoundedRectangle(cornerRadius: 12, style: .continuous)"), true, "drawer and fallback use the approved continuous radius")
    expectEqual(dataView.contains(".glassEffect(.regular.interactive(), in: drawerShape)"), true, "time drawer uses one interactive glass surface")
    expectEqual(dataView.contains("glassEffectID(DataGlassEffectID.trigger"), true, "time trigger owns a unique glass identity")
    expectEqual(dataView.contains("glassEffectID(DataGlassEffectID.drawer"), true, "time drawer owns a unique glass identity")
    expectEqual(dataView.contains("glassEffectID(DataGlassEffectID.refresh"), true, "refresh owns a unique glass identity")
    expectEqual(dataView.contains(".glassEffectTransition(accessibilityReduceMotion ? .identity : .matchedGeometry)"), true, "Reduce Motion replaces matched glass morphing with identity")
    expectEqual(dataView.contains("matchedGeometryEffect"), false, "Data does not substitute the traditional matched-geometry modifier")
    expectEqual(drawerContentSection.contains("glassEffect"), false, "drawer option rows do not stack a second glass layer")

    expectEqual(dataView.contains(".fill(.thinMaterial)"), true, "macOS 14 and 15 receive a system-material fallback")
    expectEqual(dataView.contains("accessibilityReduceTransparency"), true, "Data responds to Reduce Transparency")
    expectEqual(dataView.contains("colorSchemeContrast == .increased"), true, "Data strengthens its fallback under increased contrast")
    expectEqual(dataView.contains("@Environment(\\.accessibilityReduceMotion)"), true, "Data responds to Reduce Motion")
    expectEqual(dataView.contains("@Environment(\\.accessibilityReduceTransparency)"), true, "Data reads Reduce Transparency from the environment")
    expectEqual(dataView.contains("@Environment(\\.colorSchemeContrast)"), true, "Data reads increased contrast from the environment")
    expectEqual(dataView.contains("animationProfile.dataRangeDrawerResponse"), false, "Data child does not duplicate the parent-owned drawer animation response")
    expectEqual(dataView.contains("animationProfile.dataRangeDrawerDampingFraction"), false, "Data child does not duplicate the parent-owned drawer animation damping")
    expectEqual(dataView.contains(".spring(response: 0.30"), false, "Data view does not hard-code its drawer response")
    expectEqual(dataView.contains("dampingFraction: 0.80"), false, "Data view does not hard-code its drawer damping")
    expectEqual(dataView.contains("animationProfile.reducedMotionFadeDuration"), false, "Data child does not duplicate the parent-owned reduced-motion animation")
    expectEqual(drawerPresentationForwardingSection.contains("withAnimation"), false, "Data child forwards drawer presentation without creating a competing animation transaction")
    expectEqual(drawerPresentationForwardingSection.contains("onTimeRangeDrawerPresentationChange(isPresented)"), true, "Data child forwards drawer presentation to the state-owning parent")
    expectEqual(dataView.components(separatedBy: ".buttonStyle(IslandPressButtonStyle())").count - 1 >= 3, true, "trigger, drawer options, and refresh share interruptible press feedback")
    expectEqual(dataView.contains("isAnimating"), false, "drawer transitions do not lock rapid reversal input")

    expectEqual(dataView.contains(".zIndex(0)"), true, "statistics card owns layer zero")
    expectEqual(dataView.contains(".zIndex(1)"), true, "transparent close layer owns layer one")
    expectEqual(dataView.contains(".zIndex(2)"), true, "controls and drawer own the top Data layer")
    expectEqual(dataView.contains(".clipped()"), false, "the Data drawer is not clipped by the statistics card")
    expectEqual(markersAppearInOrder(["setDrawerPresented(false)", "onSelectTimeRange(range)"], in: selectSection), true, "range selection closes the drawer before publishing the new range")
    expectEqual(markersAppearInOrder(["setDrawerPresented(false)", "onRefresh()"], in: refreshSection), true, "manual refresh closes the drawer before refreshing")

    expectEqual(codexUsageSource.contains("actor CodexUsageSource"), true, "new usage source keeps the CodexUsageSource name")
    expectEqual(ccSwitchUsageSource.contains("actor CCSwitchUsageSource"), true, "new usage source keeps the CCSwitchUsageSource name")
    expectEqual(IslandAnimationProfile.default.dataRangeDrawerResponse, 0.30, "Data range drawer uses the approved Apple-style response")
    expectEqual(IslandAnimationProfile.default.dataRangeDrawerDampingFraction, 0.80, "Data range drawer uses the approved damping fraction")
}

private func testDataUsageOverlayAndControllerIntegrationContracts() {
    let overlayState = source("Sources/DynamicIsland/Views/IslandOverlayState.swift")
    let overlayView = source("Sources/DynamicIsland/Views/IslandOverlayView.swift")
    let controller = source("Sources/DynamicIsland/Controllers/IslandPanelController.swift")
    let primaryBindingSection = sourceSlice(
        overlayView,
        from: "private var primaryFeatureSelection: Binding<IslandPrimaryFeature>",
        until: "private var hasManualCodexApproval"
    )
    let primaryCanvasSection = sourceSlice(
        overlayView,
        from: "private var primaryFeatureCanvasLayer: some View",
        until: "var body: some View"
    )
    let dataMountSection = sourceSlice(
        overlayView,
        from: "DataPrimaryContentView(",
        until: "            if isDataTimeRangeDrawerPresented {\n                Color.clear"
    )
    let shellDrawerCloseLayerSection = sourceSlice(
        overlayView,
        from: "            if isDataTimeRangeDrawerPresented {\n                Color.clear",
        until: "            if isExpanded, state.isFileShelfOverlayVisible {"
    )
    let collapseDrawerCloseSection = sourceSlice(
        overlayView,
        from: ".onChange(of: isExpanded) { _, expanded in",
        until: ".onChange(of: state.selectedPrimaryFeature)"
    )
    let featureChangeDrawerCloseSection = sourceSlice(
        overlayView,
        from: ".onChange(of: state.selectedPrimaryFeature) { _, feature in",
        until: ".onChange(of: state.isShellHidden)"
    )
    let shellHiddenDrawerCloseSection = sourceSlice(
        overlayView,
        from: ".onChange(of: state.isShellHidden) { _, hidden in",
        until: ".onChange(of: state.isTopBandEnergyEffectEnabled)"
    )
    let escapeDrawerCloseSection = sourceSlice(
        overlayView,
        from: ".onExitCommand {",
        until: "    @MainActor\n    private func setDataTimeRangeDrawerPresented"
    )
    let drawerPresentationSection = sourceSlice(
        overlayView,
        from: "private func setDataTimeRangeDrawerPresented",
        until: "private func scheduleTopBandEnergyActivation"
    )
    let controllerInitSection = sourceSlice(
        controller,
        from: "    init(",
        until: "    private static func displayLogMetadata"
    )
    let controllerDeinitSection = sourceSlice(
        controller,
        from: "    deinit {",
        until: "    func show()"
    )
    let selectPrimaryFeatureSection = sourceSlice(
        controller,
        from: "private func selectPrimaryFeature",
        until: "private func closeFilesPrimaryFeature"
    )
    let dataRefreshSection = sourceSlice(
        controller,
        from: "private func selectDataUsageTimeRange",
        until: "private func closeFilesPrimaryFeature"
    )

    expectEqual(overlayState.contains("@Published var dataUsageTimeRange: UsageTimeRange = .today"), true, "Data defaults to today's local natural-day range")
    expectEqual(overlayState.contains("@Published var dataUsagePresentation: UsagePresentationState = .idle"), true, "Data defaults to an idle presentation")
    expectEqual(overlayState.contains("isDataTimeRangeDrawerPresented"), false, "drawer presentation does not leak into observable overlay state")
    expectEqual(overlayView.contains("@State private var isDataTimeRangeDrawerPresented = false"), true, "drawer presentation stays local to IslandOverlayView")
    expectEqual(overlayView.contains("let onDataUsageTimeRangeChange: @MainActor (UsageTimeRange) -> Void"), true, "overlay exposes the Data range callback")
    expectEqual(overlayView.contains("let onRefreshDataUsage: @MainActor () -> Void"), true, "overlay exposes the Data refresh callback")
    expectEqual(overlayView.contains("onDataUsageTimeRangeChange: @escaping @MainActor (UsageTimeRange) -> Void = { _ in }"), true, "Data range callback keeps a no-op initializer default")
    expectEqual(overlayView.contains("onRefreshDataUsage: @escaping @MainActor () -> Void = {}"), true, "Data refresh callback keeps a no-op initializer default")

    for marker in [
        ".frame(width: primaryContentFrame.width, height: primaryContentFrame.height)",
        ".position(x: primaryContentFrame.midX, y: primaryContentFrame.midY)",
        ".opacity(state.selectedPrimaryFeature == .data ? 1 : 0)",
        ".offset(y: primaryContentOffset(for: .data))",
        ".disabled(!isExpanded || state.selectedPrimaryFeature != .data)",
        ".allowsHitTesting(isExpanded && state.selectedPrimaryFeature == .data)",
        ".accessibilityHidden(!isExpanded || state.selectedPrimaryFeature != .data)",
        ".transition(primaryContentTransition)"
    ] {
        expectEqual(dataMountSection.contains(marker), true, "Data mount copies the primary content contract: \(marker)")
    }
    expectEqual(dataMountSection.contains(".zIndex(isDataTimeRangeDrawerPresented ? 24 : (state.selectedPrimaryFeature == .data ? 21 : 20))"), true, "Data rises from the normal primary layer to drawer layer 24")
    expectEqual(shellDrawerCloseLayerSection.contains(".zIndex(23)"), true, "the full-shell drawer close layer owns z-index 23")
    expectEqual(overlayView.contains(".zIndex(22)"), true, "File Shelf overlay keeps z-index 22")
    expectEqual(primaryCanvasSection.contains(".zIndex(4)"), true, "top primary navigation remains above the island-shell close layer")
    expectEqual(markersAppearInOrder(["setDataTimeRangeDrawerPresented(false)", "onPrimaryFeatureChange(feature)"], in: primaryBindingSection), true, "primary binding closes the drawer before forwarding every navigation click")
    expectEqual(markersAppearInOrder(["setDataTimeRangeDrawerPresented(false)", "fileShelfActions.onOpenFilesPrimaryFeature()"], in: primaryCanvasSection), true, "the independent Files action closes the drawer before forwarding")

    expectEqual(dataMountSection.contains("onTimeRangeDrawerPresentationChange: setDataTimeRangeDrawerPresented"), true, "Data reports drawer presentation into local overlay state")
    expectEqual(markersAppearInOrder(["setDataTimeRangeDrawerPresented(false)", "onDataUsageTimeRangeChange(range)"], in: dataMountSection), true, "range selection explicitly closes the drawer before refresh routing")
    expectEqual(markersAppearInOrder(["setDataTimeRangeDrawerPresented(false)", "onRefreshDataUsage()"], in: dataMountSection), true, "manual refresh explicitly closes the drawer before refresh routing")
    expectEqual(
        markersAppearInOrder(
            ["Color.clear", ".contentShape(Rectangle())", ".onTapGesture {", "setDataTimeRangeDrawerPresented(false)", ".zIndex(23)"],
            in: shellDrawerCloseLayerSection
        ),
        true,
        "drawer-open shell installs one transparent tap-to-close layer at z-index 23"
    )
    expectEqual(
        markersAppearInOrder(["if !expanded {", "setDataTimeRangeDrawerPresented(false)", "}"], in: collapseDrawerCloseSection),
        true,
        "collapsing the island closes the Data drawer inside the expansion-change guard"
    )
    expectEqual(
        markersAppearInOrder(["if feature != .data {", "setDataTimeRangeDrawerPresented(false)", "}"], in: featureChangeDrawerCloseSection),
        true,
        "leaving Data closes the drawer inside the primary-feature guard"
    )
    expectEqual(
        markersAppearInOrder(["if hidden {", "setDataTimeRangeDrawerPresented(false)", "}"], in: shellHiddenDrawerCloseSection),
        true,
        "hiding the shell closes the Data drawer inside the hidden-state guard"
    )
    expectEqual(
        markersAppearInOrder([".onExitCommand {", "setDataTimeRangeDrawerPresented(false)", "}"], in: escapeDrawerCloseSection),
        true,
        "Escape closes the drawer through its bounded SwiftUI command handler"
    )
    expectEqual(drawerPresentationSection.contains("if accessibilityReduceMotion"), true, "the state-owning drawer setter branches on Reduce Motion")
    expectEqual(drawerPresentationSection.contains(".easeOut(duration: animationProfile.reducedMotionFadeDuration)"), true, "the state-owning drawer setter uses the shared reduced-motion fade")
    expectEqual(drawerPresentationSection.contains(".spring("), true, "the state-owning drawer setter uses one interruptible spring for normal motion")
    expectEqual(drawerPresentationSection.contains("response: animationProfile.dataRangeDrawerResponse"), true, "the parent-owned drawer spring uses the shared response")
    expectEqual(drawerPresentationSection.contains("dampingFraction: animationProfile.dataRangeDrawerDampingFraction"), true, "the parent-owned drawer spring uses the shared damping")
    expectEqual(markersAppearInOrder(["withAnimation(drawerAnimation)", "isDataTimeRangeDrawerPresented = isPresented"], in: drawerPresentationSection), true, "every drawer state change is wrapped by the parent-owned animation transaction")
    expectEqual(overlayView.contains("NSEvent.addGlobalMonitorForEvents"), false, "Data drawer adds no global event monitor")
    expectEqual(controller.contains("addLocalMonitorForEvents(matching: .keyDown)"), false, "Data drawer adds no local keyboard monitor")
    expectEqual(controller.contains("addGlobalMonitorForEvents(matching: .keyDown)"), false, "Data drawer adds no global keyboard monitor")
    for forbiddenPermission in ["AXIsProcessTrusted", "CGRequestScreenCaptureAccess", "AVCaptureDevice.requestAccess"] {
        expectEqual((overlayView + controller).contains(forbiddenPermission), false, "Data integration adds no permission request: \(forbiddenPermission)")
    }

    expectEqual(controller.contains("private let usageSnapshotLoader: any UsageSnapshotLoading"), true, "controller owns an injectable usage loader")
    expectEqual(controllerInitSection.contains("usageSnapshotLoader: any UsageSnapshotLoading = UsageAggregationService.live()"), true, "controller defaults the loader to the live aggregation service")
    expectEqual(controllerInitSection.contains("self.usageSnapshotLoader = usageSnapshotLoader"), true, "controller stores the injected loader")
    expectEqual(controller.contains("private var dataUsageRefreshTask: Task<Void, Never>?"), true, "controller owns the in-flight Data refresh task")
    expectEqual(controller.contains("private var dataUsageRefreshGeneration = 0"), true, "controller owns a monotonic Data refresh generation")
    expectEqual(controllerDeinitSection.contains("dataUsageRefreshTask?.cancel()"), true, "controller cancels Data refresh in the existing deinit lifecycle")
    expectEqual(controller.contains("onDataUsageTimeRangeChange: { [weak self] range in"), true, "root view routes Data range selection to the controller")
    expectEqual(controller.contains("self?.selectDataUsageTimeRange(range)"), true, "range callback invokes the controller selection method")
    expectEqual(controller.contains("onRefreshDataUsage: { [weak self] in"), true, "root view routes manual Data refresh to the controller")
    expectEqual(controller.contains("self?.refreshDataUsage()"), true, "refresh callback invokes the controller refresh method")

    expectEqual(dataRefreshSection.contains("overlayState.dataUsageTimeRange = range\n        refreshDataUsage()"), true, "selecting even the current range refreshes without an equality guard")
    expectEqual(dataRefreshSection.contains("guard overlayState.dataUsageTimeRange != range"), false, "same-range selection is not suppressed")
    expectEqual(dataRefreshSection.components(separatedBy: "let now = Date()").count - 1, 1, "each refresh captures one wall-clock now")
    expectEqual(dataRefreshSection.components(separatedBy: "let timeZone = TimeZone.current").count - 1, 1, "each refresh captures one current time zone")
    expectEqual(dataRefreshSection.contains("let window = selectedRange.queryWindow(now: now, timeZone: timeZone)"), true, "the captured now and time zone define one immutable query window")
    expectEqual(dataRefreshSection.contains("dataUsageRefreshGeneration += 1"), true, "each refresh advances the publication generation")
    expectEqual(dataRefreshSection.contains("UsageRefreshRequestIdentity("), true, "controller uses the behavior-tested request identity")
    expectEqual(dataRefreshSection.contains("currentGeneration: self.dataUsageRefreshGeneration"), true, "publication checks the current generation")
    expectEqual(dataRefreshSection.contains("currentRange: self.overlayState.dataUsageTimeRange"), true, "publication checks the currently selected range")
    expectEqual(dataRefreshSection.contains("isCancelled: Task.isCancelled"), true, "publication checks task cancellation")
    expectEqual(dataRefreshSection.contains("$0.queryWindow.range == selectedRange ? $0 : nil"), true, "loading keeps a previous snapshot only for the same range")
    expectEqual(dataRefreshSection.contains("overlayState.dataUsagePresentation = .loading(previous: previous)"), true, "refresh publishes range-safe loading state")
    expectEqual(dataRefreshSection.contains("dataUsageRefreshTask?.cancel()"), true, "a new refresh cancels the previous task")
    expectEqual(selectPrimaryFeatureSection.contains("feature == .data, case .idle = overlayState.dataUsagePresentation"), true, "first idle Data entry refreshes automatically")
    expectEqual(selectPrimaryFeatureSection.contains("refreshDataUsage()"), true, "idle Data entry starts the one-shot refresh")
    expectEqual(dataRefreshSection.contains("case .cancelled:\n            return"), true, "cancelled aggregation is a no-op")
    expectEqual(dataRefreshSection.contains("snapshot.completeness == .partial"), true, "partial snapshots map to partial presentation")
    expectEqual(dataRefreshSection.contains("snapshot.tokens.realTotal == 0"), true, "complete zero snapshots map to empty presentation")
    expectEqual(dataRefreshSection.contains(".available(snapshot)"), true, "nonempty complete snapshots map to available presentation")
    expectEqual(dataRefreshSection.contains(".failed(warnings)"), true, "failed aggregation maps to failed presentation")

    for approvedMetadata in ["\"range\"", "\"totalTokens\"", "\"requestCount\"", "\"durationMs\"", "\"scannedFileCount\"", "\"completeness\"", "\"warnings\""] {
        expectEqual(dataRefreshSection.contains(approvedMetadata), true, "Data refresh logs approved aggregate metadata: \(approvedMetadata)")
    }
    expectEqual(dataRefreshSection.contains("map(\\.rawValue).sorted()"), true, "Data warning logs contain only sorted warning raw values")
    for forbiddenMetadata in ["path", "thread", "model", "provider", "prompt", "title", "SQL", "sql"] {
        expectEqual(dataRefreshSection.lowercased().contains(forbiddenMetadata.lowercased()), false, "Data refresh logging omits sensitive metadata: \(forbiddenMetadata)")
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

private func testUsageSQLiteSourceKeepsReadOnlyPrivacyContracts() {
    let runner = source("Sources/DynamicIsland/Support/UsageSQLiteQueryRunner.swift")
    let ccSwitch = source("Sources/DynamicIsland/Support/CCSwitchUsageSource.swift")
    let codex = source("Sources/DynamicIsland/Support/CodexUsageSource.swift")
    let aggregation = source("Sources/DynamicIsland/Support/UsageAggregationService.swift")
    let usageScript = source("script/run_usage_checks.sh")
    let usageChecks = source("Tests/DynamicIslandUsageChecks/main.swift")
    let supportSources = runner + "\n" + ccSwitch + "\n" + codex + "\n" + aggregation
    let cancellationInstall = sourceSlice(
        runner,
        from: "func install(process: Process, standardOutput: FileHandle) -> Bool",
        until: "func stopProcessIfCancelled()"
    )
    let cancellationStop = sourceSlice(
        runner,
        from: "func stopProcessIfCancelled()",
        until: "func markProcessExited()"
    )
    let cancellationCancel = sourceSlice(
        runner,
        from: "func cancel()",
        until: "func finish()"
    )
    let cancellationFinish = sourceSlice(
        runner,
        from: "func finish()",
        until: "private func terminateProcessLocked()"
    )

    expectEqual(runner.contains("process.arguments = [\"-batch\", \"-readonly\", \"-json\", databaseURL.path, sql]"), true, "sqlite runner uses only the required read-only sqlite flags")
    expectEqual(runner.contains("Task.detached(priority: .utility)"), true, "blocking Process IO runs in a detached utility task")
    expectEqual(runner.contains("withTaskCancellationHandler"), true, "sqlite runner installs a cancellation handler")
    expectEqual(runner.contains("terminate()"), true, "sqlite runner terminates an in-flight process when cancelled")
    for cancellationPath in [cancellationInstall, cancellationStop, cancellationCancel] {
        expectEqual(cancellationPath.contains("closeFile"), false, "cancellation paths never close a reader that detached IO may still be using")
        expectEqual(cancellationPath.contains("closeOutputLocked()"), false, "cancellation paths do not indirectly close the stdout reader")
    }
    expectEqual(cancellationFinish.contains("standardOutput?.closeFile()"), true, "finish closes stdout only after detached reader/wait cleanup begins")
    expectEqual(
        markersAppearInOrder(["readDataToEndOfFile()", "waitUntilExit()"], in: runner),
        true,
        "sqlite runner drains stdout before waiting for process exit"
    )
    expectEqual(runner.contains("standardError = FileHandle.nullDevice"), true, "sqlite runner does not surface database paths, SQL, or stderr text")

    for contract in ["PRAGMA query_only=ON;", "BEGIN;", "COMMIT;", "lower(app_type) <> 'codex'", "CAST(total_cost_usd AS TEXT)"] {
        expectEqual(ccSwitch.contains(contract), true, "CC Switch query keeps read-only contract: \(contract)")
    }
    expectEqual(ccSwitch.components(separatedBy: "lower(app_type) <> 'codex'").count - 1, 2, "coverage and data rows share the non-Codex predicate")
    expectEqual(ccSwitch.contains("usage_daily_rollups"), false, "CC Switch source reads raw requests rather than rollups")

    for writeStatement in ["INSERT ", "UPDATE ", "DELETE ", "CREATE ", "DROP "] {
        expectEqual(supportSources.uppercased().contains(writeStatement), false, "usage support does not contain write SQL: \(writeStatement)")
    }
    for forbiddenField in ["prompt", "title", "request_body", "requestBody"] {
        expectEqual(supportSources.contains(forbiddenField), false, "usage support does not select sensitive field: \(forbiddenField)")
    }
    expectEqual(supportSources.contains("Timer("), false, "usage sources do not add polling timers")
    expectEqual(supportSources.contains("scheduledTimer"), false, "usage sources do not schedule background polling")

    expectEqual(usageScript.contains("Sources/DynamicIslandCore/*.swift"), true, "usage checks compile the Core module")
    expectEqual(usageScript.contains("Sources/DynamicIsland/Support/UsageSQLiteQueryRunner.swift"), true, "usage checks compile the sqlite runner explicitly")
    expectEqual(usageScript.contains("Sources/DynamicIsland/Support/CCSwitchUsageSource.swift"), true, "usage checks compile the CC Switch source explicitly")
    expectEqual(usageScript.contains("Sources/DynamicIsland/Support/CodexUsageSource.swift"), true, "usage checks compile the Codex source explicitly")
    expectEqual(usageScript.contains("Sources/DynamicIsland/Support/UsageAggregationService.swift"), true, "usage checks compile the aggregation service explicitly")
    expectEqual(usageScript.contains("Tests/DynamicIslandUsageChecks/main.swift"), true, "usage checks compile their dedicated entry point")
    expectEqual(usageScript.components(separatedBy: "$repo_root/Sources/DynamicIsland/Support/").count - 1, 4, "usage checks compile only the four approved support files")
    expectEqual(usageScript.contains("Sources/DynamicIsland/Views/"), false, "usage checks do not compile production views")
    expectEqual(usageScript.contains("Sources/DynamicIsland/Controllers/"), false, "usage checks do not compile production controllers")
    expectEqual(usageScript.contains(".cc-switch"), false, "usage checks never reference the production CC Switch database")
    expectEqual(usageScript.contains("sqlite3"), false, "usage check script never queries a database directly")
    expectEqual(usageScript.contains("\"$build_dir/DynamicIslandUsageChecks\" \"$@\""), true, "usage checks forward all command arguments to the binary")
    expectEqual(usageChecks.contains("usageCheckMode(arguments: CommandLine.arguments.dropFirst())"), true, "usage checks classify arguments before selecting fixture or live mode")
    expectEqual(usageChecks.contains("case .invalid:"), true, "usage checks keep an explicit invalid-argument branch")
    expectEqual(usageChecks.contains("Foundation.exit(2)"), true, "unknown usage-check arguments exit nonzero")
    expectEqual(usageChecks.contains("arguments.elementsEqual([\"--live\"])"), true, "only the exact --live argument enables real data access")

    expectEqual(aggregation.contains("protocol UsageSnapshotLoading: Sendable"), true, "aggregation exposes the loader boundary used by the controller")
    expectEqual(aggregation.contains("case cancelled"), true, "aggregation exposes cancellation as a distinct terminal outcome")
    expectEqual(aggregation.contains("catch is CancellationError"), true, "aggregation distinguishes cancellation from source failures")
    expectEqual(aggregation.contains("return .cancelled"), true, "aggregation preserves source cancellation without a warning category")
    expectEqual(aggregation.components(separatedBy: "async let").count - 1, 2, "aggregation starts both usage sources concurrently")
    expectEqual(aggregation.contains("UsageRefreshRequestIdentity"), true, "aggregation defines the stale-publication identity guard")
    expectEqual(aggregation.contains("currentGeneration == generation"), true, "publication requires the current generation")
    expectEqual(aggregation.contains("currentRange == range"), true, "publication requires the current range")
    expectEqual(aggregation.contains("!isCancelled"), true, "publication rejects cancelled requests")
    expectEqual(aggregation.contains("Timer"), false, "aggregation does not create a refresh timer")
    expectEqual(aggregation.contains("IslandOverlayState"), false, "aggregation does not read UI state")
    expectEqual(aggregation.contains("UsageAggregationService.live()"), false, "aggregation does not create recursive live services")

    expectEqual(codex.contains("sessions"), true, "Codex usage scans active sessions")
    expectEqual(codex.contains("archived_sessions"), true, "Codex usage scans archived sessions")
    expectEqual(codex.contains("65_536"), true, "Codex rollout reads use the required 64KiB chunk")
    expectEqual(codex.contains("FileHandle(forReadingFrom:"), true, "Codex rollout opens files through FileHandle")
    expectEqual(codex.contains("read(upToCount: 65_536)"), true, "Codex rollout uses bounded FileHandle reads")
    expectEqual(codex.contains("Data(contentsOf:"), false, "Codex rollout does not load whole files into memory")
    expectEqual(codex.contains("try Task.checkCancellation()"), true, "Codex rollout checks cancellation in read loops")
    expectEqual(codex.contains("FileSignature"), true, "Codex rollout cache uses a file signature")
    expectEqual(codex.contains("modificationDate"), true, "Codex rollout cache signature includes modification time")
    expectEqual(codex.contains("codexRolloutConflict"), true, "Codex fallback selection exposes conflicts")
    expectEqual(codex.contains("rollout_path"), true, "Codex state query reads the canonical rollout path")
    expectEqual(codex.contains("didFinishReadAttempt"), true, "Codex rollout exposes the post-EOF test hook")
    expectEqual(codex.contains("errorHandler:"), true, "Codex root enumeration records recursive errors")
    expectEqual(codex.contains("hasEnumerationError"), true, "Codex root result distinguishes enumeration errors")
    expectEqual(codex.contains("canOpenForReading"), true, "old canonical rollouts are probed before skipping body reads")
    expectEqual(codex.contains("UUID(uuidString:"), true, "fallback candidates require a canonical UUID")
    expectEqual(codex.contains("catch is CancellationError"), true, "Codex file I/O preserves cancellation")
    expectEqual(codex.contains("recursiveError = true\n                    return true"), true, "Codex enumeration continues after a recursive sibling error")
    expectEqual(codex.contains("canonicalThreadID"), true, "state UUIDs use the same canonical identity as rollout candidates")
    expectEqual(codex.contains("cached.result.threadID == threadID"), true, "a URL cache hit cannot reuse a parse result for another canonical thread")
    expectEqual(codex.contains("shouldFailRead"), true, "usage checks can inject deterministic non-cancellation file read failures")
}

private func fixedDate(
    _ value: String,
    timeZone: TimeZone
) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    guard let date = formatter.date(from: value) else {
        fatalError("Unable to build fixed test date: \(value)")
    }
    return date
}

private func testUsageTimeRangeUsesCapturedLocalNaturalDays() {
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    let now = fixedDate("2026-07-19 11:00", timeZone: shanghai)

    let today = UsageTimeRange.today.queryWindow(now: now, timeZone: shanghai)
    let threeDays = UsageTimeRange.threeDays.queryWindow(now: now, timeZone: shanghai)

    expectEqual(today.startUTC, fixedDate("2026-07-19 00:00", timeZone: shanghai), "today starts at the captured local day boundary")
    expectEqual(threeDays.startUTC, fixedDate("2026-07-17 00:00", timeZone: shanghai), "three days uses local natural days")
    expectEqual(today.endUTC, now, "today ends at the captured now")
    expectEqual(threeDays.endUTC, now, "three days ends at the captured now")
    expectEqual(today.timeZoneIdentifier, "Asia/Shanghai", "query window records its captured time zone")
}

private func testUsageTimeRangeHandlesDSTAndHalfOpenBounds() {
    let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    let now = fixedDate("2026-03-09 11:00", timeZone: losAngeles)
    let window = UsageTimeRange.threeDays.queryWindow(now: now, timeZone: losAngeles)

    expectEqual(window.startUTC, fixedDate("2026-03-07 00:00", timeZone: losAngeles), "three natural days crosses DST by calendar days")
    expectEqual(window.contains(window.startUTC), true, "half-open window includes its start")
    expectEqual(window.contains(window.endUTC), false, "half-open window excludes its end")
}

private func testUsageCumulativeCountersDiffNormalResetAndNoChange() {
    let previous = UsageCumulativeCounters(input: 100, cachedInput: 40, output: 20, cacheCreation: 10)
    let increased = UsageCumulativeCounters(input: 150, cachedInput: 70, output: 35, cacheCreation: 15)
    let reset = UsageCumulativeCounters(input: 20, cachedInput: 5, output: 4, cacheCreation: 1)

    expectEqual(increased.delta(from: previous), UsageCumulativeCounters(input: 50, cachedInput: 30, output: 15, cacheCreation: 5), "cumulative fields diff independently when increasing")
    expectEqual(reset.delta(from: increased), reset, "cumulative resets use the current value independently")
    expectEqual(increased.delta(from: increased), UsageCumulativeCounters(input: 0, cachedInput: 0, output: 0, cacheCreation: 0), "unchanged cumulative values produce zero deltas")

    let mixedReset = UsageCumulativeCounters(input: 180, cachedInput: 5, output: 45, cacheCreation: 2)
    expectEqual(
        mixedReset.delta(from: increased),
        UsageCumulativeCounters(input: 30, cachedInput: 5, output: 10, cacheCreation: 2),
        "each cumulative field independently distinguishes normal growth from reset"
    )

    let validCodexDelta = UsageCumulativeCounters(input: 100, cachedInput: 40, output: 20, cacheCreation: 0).normalizedCodexDelta()
    expectEqual(validCodexDelta, UsageTokenCounts(freshInput: 60, output: 20, cacheCreation: 0, cacheRead: 40), "valid Codex delta normalizes cache-inclusive input")
    expectEqual(UsageCumulativeCounters(input: 20, cachedInput: 21, output: 0, cacheCreation: 0).normalizedCodexDelta(), nil, "Codex cached input above input is unconfirmed")
    expectEqual(UsageCumulativeCounters(input: 20, cachedInput: 0, output: 0, cacheCreation: 1).normalizedCodexDelta(), nil, "Codex cache creation has unknown input semantics")
}

private func parseCodexRolloutFixture(
    _ fixture: String,
    threadID: String
) -> CodexRolloutParseResult {
    var parser = CodexRolloutUsageParser(threadID: threadID)
    var completeByteCount: Int64 = 0
    let lines = fixture.split(separator: "\n", omittingEmptySubsequences: false)

    for line in lines.dropLast() {
        let completeLine = Data((String(line) + "\n").utf8)
        completeByteCount += Int64(completeLine.count)
        parser.consumeCompleteLine(completeLine, endingByteOffset: completeByteCount)
    }

    return parser.finish(completeByteCount: completeByteCount)
}

private func testCodexRolloutParserCountsFirstValidSampleInsideWindow() {
    let fixture = """
    {"timestamp":"2026-07-19T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":1,"reasoning_output_tokens":0}}}}
    """ + "\n"
    let result = parseCodexRolloutFixture(fixture, threadID: "thread-first")
    let window = UsageQueryWindow(
        range: .today,
        startUTC: ISO8601DateFormatter().date(from: "2026-07-19T00:00:00Z")!,
        endUTC: ISO8601DateFormatter().date(from: "2026-07-20T00:00:00Z")!,
        timeZoneIdentifier: "GMT"
    )

    expectEqual(result.samples.map(\.startsNewBaseline), [false], "the first valid sample is not a damage-recovery baseline")
    expectEqual(
        result.entries(in: window).entries.map(\.tokens),
        [UsageTokenCounts(freshInput: 8, output: 1, cacheCreation: 0, cacheRead: 2)],
        "the first valid in-window sample is differenced from nil and counted"
    )
}

private func testCodexRolloutParserDefersInitialEmptyUsageUntilZeroBaseline() {
    let fixture = """
    {"timestamp":"2026-07-19T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":null}}
    {"timestamp":"2026-07-19T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0}}}}
    {"timestamp":"2026-07-19T00:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":12,"cached_input_tokens":3,"output_tokens":2,"reasoning_output_tokens":1}}}}
    """ + "\n"
    let result = parseCodexRolloutFixture(fixture, threadID: "thread-initial-empty")
    let explicitZeroCacheCreationResult = parseCodexRolloutFixture(
        """
        {"timestamp":"2026-07-19T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":null}}
        {"timestamp":"2026-07-19T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"cache_creation_input_tokens":0}}}}
        """ + "\n",
        threadID: "thread-initial-empty-explicit-cache-zero"
    )
    let withoutInitialEmpty = parseCodexRolloutFixture(
        fixture.split(separator: "\n").dropFirst().joined(separator: "\n") + "\n",
        threadID: "thread-initial-empty"
    )
    let window = UsageQueryWindow(
        range: .today,
        startUTC: ISO8601DateFormatter().date(from: "2026-07-19T00:00:00Z")!,
        endUTC: ISO8601DateFormatter().date(from: "2026-07-20T00:00:00Z")!,
        timeZoneIdentifier: "GMT"
    )

    expectEqual(result.warnings.contains(.codexRolloutUnreadable), false, "an initial empty token event followed by a zero baseline is harmless")
    expectEqual(
        result.samples.map(\.counters),
        [
            UsageCumulativeCounters(input: 0, cachedInput: 0, output: 0, cacheCreation: 0),
            UsageCumulativeCounters(input: 12, cachedInput: 3, output: 2, cacheCreation: 0)
        ],
        "the confirmed zero baseline and later cumulative sample are retained"
    )
    expectEqual(result.samples.map(\.startsNewBaseline), [false, false], "the confirmed initialization does not create a damage-recovery baseline")
    expectEqual(explicitZeroCacheCreationResult.warnings.contains(.codexRolloutUnreadable), false, "an explicit zero cache-creation counter also confirms the harmless initialization")
    expectEqual(explicitZeroCacheCreationResult.samples.map(\.startsNewBaseline), [false], "an explicit zero cache-creation counter keeps the zero sample as an ordinary baseline")
    expectEqual(
        result.entries(in: window).entries.map(\.tokens),
        [UsageTokenCounts(freshInput: 9, output: 2, cacheCreation: 0, cacheRead: 3)],
        "the zero baseline creates no request and only the later real increment is counted"
    )
    expectEqual(result.tokenEventFingerprint == withoutInitialEmpty.tokenEventFingerprint, false, "the deferred initial event remains part of the rollout fingerprint")
}

private func testCodexRolloutParserRejectsNonExplicitInitialEmptyInfo() {
    let initialLines = [
        ("missing info", #"{"timestamp":"2026-07-19T00:00:00Z","type":"event_msg","payload":{"type":"token_count"}}"#),
        ("empty info", #"{"timestamp":"2026-07-19T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{}}}"#),
        ("null usage", #"{"timestamp":"2026-07-19T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":null}}}"#)
    ]
    let validTail = """
    {"timestamp":"2026-07-19T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0}}}}
    {"timestamp":"2026-07-19T00:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":12,"cached_input_tokens":3,"output_tokens":2,"reasoning_output_tokens":1}}}}
    """
    let tailOnly = parseCodexRolloutFixture(validTail + "\n", threadID: "thread-non-explicit-empty")
    let window = UsageQueryWindow(
        range: .today,
        startUTC: ISO8601DateFormatter().date(from: "2026-07-19T00:00:00Z")!,
        endUTC: ISO8601DateFormatter().date(from: "2026-07-20T00:00:00Z")!,
        timeZoneIdentifier: "GMT"
    )

    for (name, initialLine) in initialLines {
        let result = parseCodexRolloutFixture(
            initialLine + "\n" + validTail + "\n",
            threadID: "thread-non-explicit-empty"
        )

        expectEqual(result.warnings.contains(.codexRolloutUnreadable), true, "\(name) is not treated as a safe initialization event")
        expectEqual(result.samples.map(\.startsNewBaseline), [true, false], "\(name) makes the next valid sample a recovery baseline")
        expectEqual(
            result.entries(in: window).entries.map(\.tokens),
            [UsageTokenCounts(freshInput: 9, output: 2, cacheCreation: 0, cacheRead: 3)],
            "\(name) does not create a delta across the damaged segment"
        )
        expectEqual(result.tokenEventFingerprint == tailOnly.tokenEventFingerprint, false, "\(name) remains part of the rollout fingerprint")
    }
}

private func testCodexRolloutParserRequiresCompleteStandardZeroCountersAfterInitialNull() {
    let incompleteZeroLines = [
        ("cached input", #"{"timestamp":"2026-07-19T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0}}}}"#),
        ("reasoning output", #"{"timestamp":"2026-07-19T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0}}}}"#),
        ("input", #"{"timestamp":"2026-07-19T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0}}}}"#),
        ("output", #"{"timestamp":"2026-07-19T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":0,"cached_input_tokens":0,"reasoning_output_tokens":0}}}}"#)
    ]
    let initialNull = #"{"timestamp":"2026-07-19T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":null}}"#
    let nextValid = #"{"timestamp":"2026-07-19T00:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":12,"cached_input_tokens":3,"output_tokens":2,"reasoning_output_tokens":1}}}}"#
    let window = UsageQueryWindow(
        range: .today,
        startUTC: ISO8601DateFormatter().date(from: "2026-07-19T00:00:00Z")!,
        endUTC: ISO8601DateFormatter().date(from: "2026-07-20T00:00:00Z")!,
        timeZoneIdentifier: "GMT"
    )

    for (missingCounter, incompleteZero) in incompleteZeroLines {
        let result = parseCodexRolloutFixture(
            initialNull + "\n" + incompleteZero + "\n" + nextValid + "\n",
            threadID: "thread-incomplete-zero"
        )

        expectEqual(result.warnings.contains(.codexRolloutUnreadable), true, "a zero confirmation missing \(missingCounter) is unreadable")
        expectEqual(result.samples.map(\.startsNewBaseline), [true], "a zero confirmation missing \(missingCounter) leaves the next complete sample as the recovery baseline")
        expectEqual(result.entries(in: window).entries, [], "a zero confirmation missing \(missingCounter) cannot bridge a usage delta")
    }
}

private func testCodexRolloutParserKeepsPendingInitialNullDamageProtection() {
    let initialNull = #"{"timestamp":"2026-07-19T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":null}}"#
    let nonzero = #"{"timestamp":"2026-07-19T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":12,"cached_input_tokens":3,"output_tokens":2,"reasoning_output_tokens":1}}}}"#
    let later = #"{"timestamp":"2026-07-19T00:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20,"cached_input_tokens":5,"output_tokens":4,"reasoning_output_tokens":2}}}}"#
    let zero = #"{"timestamp":"2026-07-19T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0,"cache_creation_input_tokens":0}}}}"#
    let window = UsageQueryWindow(
        range: .today,
        startUTC: ISO8601DateFormatter().date(from: "2026-07-19T00:00:00Z")!,
        endUTC: ISO8601DateFormatter().date(from: "2026-07-20T00:00:00Z")!,
        timeZoneIdentifier: "GMT"
    )

    let nonzeroResult = parseCodexRolloutFixture(
        initialNull + "\n" + nonzero + "\n" + later + "\n",
        threadID: "thread-null-nonzero"
    )
    expectEqual(nonzeroResult.warnings.contains(.codexRolloutUnreadable), true, "an initial null followed by nonzero counters remains unreadable")
    expectEqual(nonzeroResult.samples.map(\.startsNewBaseline), [true, false], "nonzero counters become the recovery baseline after an initial null")
    expectEqual(
        nonzeroResult.entries(in: window).entries.map(\.tokens),
        [UsageTokenCounts(freshInput: 6, output: 2, cacheCreation: 0, cacheRead: 2)],
        "no delta crosses from the initial null into nonzero cumulative counters"
    )

    let unfinishedResult = parseCodexRolloutFixture(initialNull + "\n", threadID: "thread-null-eof")
    expectEqual(unfinishedResult.warnings.contains(.codexRolloutUnreadable), true, "an unresolved initial null at EOF remains unreadable")
    expectEqual(unfinishedResult.samples, [], "an unresolved initial null does not invent a sample")

    let repeatedNullResult = parseCodexRolloutFixture(
        initialNull + "\n" + initialNull + "\n" + zero + "\n" + later + "\n",
        threadID: "thread-null-repeated"
    )
    expectEqual(repeatedNullResult.warnings.contains(.codexRolloutUnreadable), true, "a second empty event invalidates the pending initialization")
    expectEqual(repeatedNullResult.samples.map(\.startsNewBaseline), [true, false], "the first complete sample after repeated empty events is a recovery baseline")
    expectEqual(
        repeatedNullResult.entries(in: window).entries.map(\.tokens),
        [UsageTokenCounts(freshInput: 15, output: 4, cacheCreation: 0, cacheRead: 5)],
        "repeated empty events do not create a cross-damage delta"
    )
}

private func testCodexRolloutParserIgnoresUnstructuredTokenCountText() {
    let firstTokenLine = """
    {"timestamp":"2026-07-19T03:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":1,"reasoning_output_tokens":0}}}}
    """
    let secondTokenLine = """
    {"timestamp":"2026-07-19T03:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20,"cached_input_tokens":4,"output_tokens":2,"reasoning_output_tokens":0}}}}
    """
    let cleanFixture = firstTokenLine + "\n" + secondTokenLine + "\n"
    let noisyFixture = firstTokenLine + """

    ordinary text containing "type" : "token_count" is not a JSON key
    not-json {"type":"token_count_extra"}
    {"timestamp":"2026-07-19T03:00:10Z","type":"event_msg","payload":{"type":"other","message":"token_count"}}
    {"timestamp":"2026-07-19T03:00:20Z","type":"event_msg","payload":{"type":"other","metadata":{"type":"token_count"}}}
    """ + "\n" + secondTokenLine + "\n"
    let clean = parseCodexRolloutFixture(cleanFixture, threadID: "thread-marker")
    let noisy = parseCodexRolloutFixture(noisyFixture, threadID: "thread-marker")
    let window = UsageQueryWindow(
        range: .today,
        startUTC: ISO8601DateFormatter().date(from: "2026-07-19T00:00:00Z")!,
        endUTC: ISO8601DateFormatter().date(from: "2026-07-20T00:00:00Z")!,
        timeZoneIdentifier: "GMT"
    )

    expectEqual(noisy.warnings, [], "unstructured or unrelated token_count text does not create warnings")
    expectEqual(noisy.samples.map(\.startsNewBaseline), [false, false], "unrelated token_count text does not break the cumulative baseline")
    expectEqual(noisy.tokenEventFingerprint, clean.tokenEventFingerprint, "only confirmed payload token events affect the fingerprint")
    expectEqual(noisy.entries(in: window).entries.map(\.tokens.realTotal), [11, 11], "unrelated token_count text does not suppress the next valid delta")
}

private func testCodexRolloutParserRecognizesWhitespaceStructuredMalformedMarker() {
    let fixture = """
    {"timestamp":"2026-07-19T04:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":1,"reasoning_output_tokens":0}}}}
    {"timestamp":"2026-07-19T04:00:30Z","type":"event_msg","payload":{"type" \t : \t "token_count","info":
    {"timestamp":"2026-07-19T04:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20,"cached_input_tokens":4,"output_tokens":2,"reasoning_output_tokens":0}}}}
    """ + "\n"
    let result = parseCodexRolloutFixture(fixture, threadID: "thread-marker-whitespace")
    let cleanFixture = fixture
        .split(separator: "\n", omittingEmptySubsequences: false)
        .enumerated()
        .filter { $0.offset != 1 }
        .map { String($0.element) }
        .joined(separator: "\n")
    let clean = parseCodexRolloutFixture(cleanFixture, threadID: "thread-marker-whitespace")

    expectEqual(result.warnings.contains(.codexRolloutUnreadable), true, "a malformed structured token marker with JSON whitespace is unreadable")
    expectEqual(result.samples.map(\.startsNewBaseline), [false, true], "a structured malformed token marker breaks the next cumulative baseline")
    expectEqual(result.tokenEventFingerprint == clean.tokenEventFingerprint, false, "a structured malformed token marker participates in the fingerprint")
}

private func testCodexRolloutParserRejectsNormalizedInvalidCalendarDates() {
    let fixture = """
    {"timestamp":"2026-02-28T10:00:00.123Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":1,"reasoning_output_tokens":0}}}}
    {"timestamp":"2026-02-30T10:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20,"cached_input_tokens":4,"output_tokens":2,"reasoning_output_tokens":0}}}}
    {"timestamp":"2026-03-01T18:00:00+08:00","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":30,"cached_input_tokens":6,"output_tokens":3,"reasoning_output_tokens":0}}}}
    """ + "\n"
    let result = parseCodexRolloutFixture(fixture, threadID: "thread-date")
    let window = UsageQueryWindow(
        range: .threeDays,
        startUTC: ISO8601DateFormatter().date(from: "2026-02-28T00:00:00Z")!,
        endUTC: ISO8601DateFormatter().date(from: "2026-03-03T00:00:00Z")!,
        timeZoneIdentifier: "GMT"
    )

    expectEqual(result.samples.count, 2, "an impossible calendar date is not retained as a token sample")
    expectEqual(result.samples.map(\.startsNewBaseline), [false, true], "an impossible calendar date breaks the next valid sample baseline")
    expectEqual(result.warnings.contains(.codexRolloutUnreadable), true, "an impossible calendar date produces an unreadable rollout warning")
    expectEqual(result.entries(in: window).entries.map(\.tokens.realTotal), [11], "no delta crosses an impossible calendar date")
    expectEqual(result.lastTokenEventAt, ISO8601DateFormatter().date(from: "2026-03-01T10:00:00Z"), "a valid timezone offset remains supported after strict validation")
}

private func testCodexRolloutParserDiffsCompleteSequenceBeforeFilteringWindow() {
    let fixture = """
    {"timestamp":"2026-07-18T23:59:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20,"reasoning_output_tokens":5,"cache_creation_input_tokens":0}}}}
    {"timestamp":"2026-07-19T00:05:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":60,"output_tokens":30,"reasoning_output_tokens":8,"cache_creation_input_tokens":0}}}}
    {"timestamp":"2026-07-19T00:06:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":60,"output_tokens":30,"reasoning_output_tokens":999,"cache_creation_input_tokens":0}}}}
    {"timestamp":"2026-07-19T00:07:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":180,"cached_input_tokens":5,"output_tokens":40,"reasoning_output_tokens":1000,"cache_creation_input_tokens":0}}}}
    {"timestamp":"2026-07-19T00:07:30Z","type":"event_msg","payload":{"type":"other"}}
    {"broken":
    {"timestamp":"2026-07-19T00:08:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":10,"output_tokens":45,"reasoning_output_tokens":1001,"cache_creation_input_tokens":4}}}}
    {"timestamp":"2026-07-19T00:09:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":230,"cached_input_tokens":20,"output_tokens":50,"reasoning_output_tokens":1002,"cache_creation_input_tokens":4}}}}
    {"timestamp":"2026-07-19T00:10:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":240,"cached_input_tokens":22,"output_tokens":52,"reasoning_output_tokens":1003,"cache_creation_input_tokens":4}}}}
    {"timestamp":"2026-07-19T00:11:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":999
    """
    let result = parseCodexRolloutFixture(fixture, threadID: "thread-window")
    let window = UsageQueryWindow(
        range: .today,
        startUTC: ISO8601DateFormatter().date(from: "2026-07-19T00:00:00Z")!,
        endUTC: ISO8601DateFormatter().date(from: "2026-07-19T00:10:00Z")!,
        timeZoneIdentifier: "GMT"
    )
    let replayed = result.entries(in: window)
    let repeatedParse = parseCodexRolloutFixture(fixture, threadID: "thread-window")
    let emptyFingerprint = CodexRolloutUsageParser(threadID: "empty").finish(completeByteCount: 0).tokenEventFingerprint

    expectEqual(result.threadID, "thread-window", "rollout parse result retains its thread id")
    expectEqual(result.samples.count, 7, "parser stores only valid cumulative token samples")
    expectEqual(result.samples.first?.startsNewBaseline, false, "an undamaged first cumulative sample is eligible for delta-from-nil counting")
    expectEqual(result.firstTokenEventAt, ISO8601DateFormatter().date(from: "2026-07-18T23:59:00Z"), "first token event records the pre-window baseline")
    expectEqual(result.lastTokenEventAt, ISO8601DateFormatter().date(from: "2026-07-19T00:10:00Z"), "last complete token event excludes the partial tail")
    expectEqual(result.lastCumulativeCounters, UsageCumulativeCounters(input: 240, cachedInput: 22, output: 52, cacheCreation: 4), "last cumulative counters come from the last complete token event")
    expectEqual(result.completeByteCount > 0, true, "parse result records the complete byte prefix")
    expectEqual(result.completeByteCount < Int64(fixture.utf8.count), true, "the final incomplete line is outside the parser's complete byte prefix")
    expectEqual(result.tokenEventFingerprint == repeatedParse.tokenEventFingerprint, true, "the same complete token event lines produce a stable fingerprint")
    expectEqual(result.tokenEventFingerprint != emptyFingerprint, true, "token event lines update the FNV-1a fingerprint")
    expectEqual(result.warnings.contains(.codexRolloutUnreadable), true, "positive cache creation marks token completeness as uncertain")
    expectEqual(replayed.entries.count, 3, "same snapshots, cache creation, non-token lines, bad non-token JSON, and the end bound do not create requests")
    expectEqual(replayed.entries[0].tokens, UsageTokenCounts(freshInput: 30, output: 10, cacheCreation: 0, cacheRead: 20), "pre-window cumulative counters are differenced before window filtering")
    expectEqual(replayed.entries[0].tokens.realTotal, 60, "window entry uses only the 50 input and 10 output increment, not cumulative totals")
    expectEqual(replayed.entries[1].tokens, UsageTokenCounts(freshInput: 25, output: 10, cacheCreation: 0, cacheRead: 5), "a single cached-input reset is handled independently")
    expectEqual(replayed.entries[2].tokens, UsageTokenCounts(freshInput: 20, output: 5, cacheCreation: 0, cacheRead: 10), "positive cache creation updates the baseline before the next supported delta")
    expectEqual(replayed.entries[0].requestCount, 1, "each positive normalized delta counts as one request")
    expectEqual(replayed.entries[0].estimatedCostUSD, nil, "Codex parser does not invent a price")
    expectEqual(replayed.entries[0].id, "thread-window:\(result.samples[1].endingByteOffset)", "entry identity uses thread and ending byte offset")
    expectEqual(replayed.warnings, result.warnings, "window replay preserves parse warnings")
    expectEqual(result.entries(in: window), replayed, "cached parse results replay deterministically")
}

private func testCodexRolloutParserBreaksBaselineAcrossUnreadableTokenEvents() {
    let fixture = """
    {"timestamp":"2026-07-19T01:00:00.123Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":1,"reasoning_output_tokens":0}}}}
    {"timestamp":"2026-07-19T01:01:00Z","type":"event_msg","payload":{"type":"token_count","info":
    {"timestamp":"2026-07-19T01:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":50,"cached_input_tokens":10,"output_tokens":5,"reasoning_output_tokens":1}}}}
    {"timestamp":"2026-07-19T01:03:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":-1,"cached_input_tokens":10,"output_tokens":6,"reasoning_output_tokens":2}}}}
    {"timestamp":"2026-07-19T01:04:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10,"reasoning_output_tokens":3}}}}
    {"timestamp":"2026-07-19T01:05:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":130,"cached_input_tokens":25,"output_tokens":15,"reasoning_output_tokens":5000}}}}
    """ + "\n"
    let result = parseCodexRolloutFixture(fixture, threadID: "thread-break")
    let window = UsageQueryWindow(
        range: .today,
        startUTC: ISO8601DateFormatter().date(from: "2026-07-19T00:00:00Z")!,
        endUTC: ISO8601DateFormatter().date(from: "2026-07-20T00:00:00Z")!,
        timeZoneIdentifier: "GMT"
    )
    let entries = result.entries(in: window)

    expectEqual(result.samples.count, 4, "malformed and negative token events are not retained as samples")
    expectEqual(result.samples.map(\.startsNewBaseline), [false, true, true, false], "only unreadable token events make the next valid sample a new baseline")
    expectEqual(result.warnings.contains(.codexRolloutUnreadable), true, "malformed and negative token events warn about incomplete usage")
    expectEqual(entries.entries.count, 2, "the first sample is counted while no delta crosses either malformed token segment")
    expectEqual(entries.entries[0].tokens, UsageTokenCounts(freshInput: 8, output: 1, cacheCreation: 0, cacheRead: 2), "the first valid in-window sample is counted from zero")
    expectEqual(entries.entries[1].tokens, UsageTokenCounts(freshInput: 25, output: 5, cacheCreation: 0, cacheRead: 5), "only the valid post-break delta is emitted and reasoning is not counted twice")
    expectEqual(result.entries(in: window), entries, "cached damaged parse results replay with identical baseline breaks")
}

private func testCodexRolloutParserDecodesLargeIntegerCountersExactly() {
    let fixture = """
    {"timestamp":"2026-07-19T02:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":9007199254740993,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0}}}}
    {"timestamp":"2026-07-19T02:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":9007199254740994,"cached_input_tokens":0,"output_tokens":0,"reasoning_output_tokens":0}}}}
    """ + "\n"
    let result = parseCodexRolloutFixture(fixture, threadID: "thread-int64")
    let window = UsageQueryWindow(
        range: .today,
        startUTC: ISO8601DateFormatter().date(from: "2026-07-19T00:00:00Z")!,
        endUTC: ISO8601DateFormatter().date(from: "2026-07-20T00:00:00Z")!,
        timeZoneIdentifier: "GMT"
    )

    expectEqual(result.entries(in: window).entries.map(\.tokens.realTotal), [9_007_199_254_740_993, 1], "the first large sample is counted and the next delta remains exact above Double precision")
}

private func testUsageTokenNormalizationAvoidsCacheDoubleCounting() {
    let normalized = UsageTokenCounts.normalized(
        input: 100,
        output: 20,
        cacheCreation: 0,
        cacheRead: 40,
        semantics: .includesCacheRead
    )

    expectEqual(normalized.freshInput, 60, "cache read is removed from cache-inclusive input")
    expectEqual(normalized.cacheRead, 40, "cache read is retained separately")
    expectEqual(normalized.output, 20, "output is retained once")
    expectEqual(normalized.realTotal, 120, "real total avoids cache double counting and reasoning output duplication")
    expectEqual(normalized.cacheCreation, 0, "cache creation remains separate")

    let readInclusiveWithCreation = UsageTokenCounts.normalized(
        input: 100,
        output: 0,
        cacheCreation: 10,
        cacheRead: 40,
        semantics: .includesCacheRead
    )
    expectEqual(readInclusiveWithCreation.freshInput, 60, "cache-read-inclusive input does not also subtract cache creation")
    expectEqual(readInclusiveWithCreation.cacheCreation, 10, "cache creation remains independently counted for cache-read semantics")
    expectEqual(readInclusiveWithCreation.realTotal, 110, "cache-read semantics retains cache creation outside input")

    let readAndCreationInclusive = UsageTokenCounts.normalized(
        input: 100,
        output: 20,
        cacheCreation: 10,
        cacheRead: 40,
        semantics: .includesCacheReadAndCreation
    )
    expectEqual(readAndCreationInclusive, UsageTokenCounts(freshInput: 50, output: 20, cacheCreation: 10, cacheRead: 40), "cache-read-and-creation input removes both cache subsets once")

    let cacheHit = UsageTokenCounts(freshInput: 60, output: 20, cacheCreation: 10, cacheRead: 30)
    let window = UsageTimeRange.today.queryWindow(now: Date(timeIntervalSince1970: 1_000), timeZone: .gmt)
    let snapshot = UsageSnapshot(
        tokens: cacheHit,
        requestCount: 1,
        estimatedCostUSD: .zero,
        coverageStart: nil,
        coverageEnd: nil,
        scannedFileCount: 0,
        refreshedAt: window.endUTC,
        queryWindow: window,
        completeness: .complete,
        warnings: []
    )
    expectNearly(snapshot.cacheHitRate!, 0.3, "cache hit rate includes fresh, creation, and read input")
    expectEqual(UsageSnapshot(
        tokens: UsageTokenCounts(freshInput: 0, output: 1, cacheCreation: 0, cacheRead: 0),
        requestCount: 1,
        estimatedCostUSD: .zero,
        coverageStart: nil,
        coverageEnd: nil,
        scannedFileCount: 0,
        refreshedAt: window.endUTC,
        queryWindow: window,
        completeness: .complete,
        warnings: []
    ).cacheHitRate, nil, "cache hit rate is unavailable without input tokens")
}

private func testUsageAggregatorCalculatesRequestsCoverageCostAndCompleteness() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let window = UsageTimeRange.today.queryWindow(now: now, timeZone: .gmt)
    let entry = UsageEntry(
        id: "inside",
        occurredAt: window.startUTC,
        tokens: UsageTokenCounts(freshInput: 100, output: 20, cacheCreation: 0, cacheRead: 40),
        requestCount: 2,
        estimatedCostUSD: Decimal(string: "1.25")
    )
    let excludedAtEnd = UsageEntry(
        id: "at-end",
        occurredAt: window.endUTC,
        tokens: UsageTokenCounts(freshInput: 1, output: 0, cacheCreation: 0, cacheRead: 0),
        requestCount: 1,
        estimatedCostUSD: Decimal(string: "0.01")
    )
    let completeBatch = UsageSourceBatch(
        entries: [entry, excludedAtEnd],
        coverageStart: window.startUTC,
        coverageEnd: window.endUTC,
        warnings: [],
        scannedFileCount: 3
    )
    let complete = UsageAggregator.snapshot(batches: [completeBatch], window: window, refreshedAt: now)
    expectEqual(complete.tokens.realTotal, 160, "aggregator includes only in-window positive-token entries")
    expectEqual(complete.requestCount, 2, "aggregator sums accepted requests")
    expectEqual(complete.estimatedCostUSD, Decimal(string: "1.25"), "aggregator sums priced accepted usage")
    expectEqual(complete.coverageStart, window.startUTC, "aggregator preserves known coverage start")
    expectEqual(complete.coverageEnd, window.endUTC, "aggregator preserves known coverage end")
    expectEqual(complete.scannedFileCount, 3, "aggregator sums scanned files")
    expectEqual(complete.completeness, .complete, "full coverage without semantic warnings is complete")

    let secondEntry = UsageEntry(
        id: "second",
        occurredAt: window.startUTC.addingTimeInterval(1),
        tokens: UsageTokenCounts(freshInput: 10, output: 0, cacheCreation: 0, cacheRead: 0),
        requestCount: 3,
        estimatedCostUSD: Decimal(string: "0.50")
    )
    let summedAcrossBatches = UsageAggregator.snapshot(
        batches: [
            UsageSourceBatch(entries: [entry], coverageStart: window.startUTC.addingTimeInterval(-10), coverageEnd: window.startUTC.addingTimeInterval(10), warnings: [], scannedFileCount: 2),
            UsageSourceBatch(entries: [secondEntry], coverageStart: window.startUTC, coverageEnd: window.endUTC, warnings: [], scannedFileCount: 4)
        ],
        window: window,
        refreshedAt: now
    )
    expectEqual(summedAcrossBatches.tokens.realTotal, 170, "aggregator sums real tokens across entries and batches")
    expectEqual(summedAcrossBatches.requestCount, 5, "aggregator sums requests across entries and batches")
    expectEqual(summedAcrossBatches.estimatedCostUSD, Decimal(string: "1.75"), "aggregator sums costs across entries and batches")
    expectEqual(summedAcrossBatches.coverageStart, window.startUTC.addingTimeInterval(-10), "aggregator takes the earliest known batch coverage")
    expectEqual(summedAcrossBatches.coverageEnd, window.endUTC, "aggregator takes the latest known batch coverage")

    let overflowEntry = UsageEntry(
        id: "overflow-one",
        occurredAt: window.startUTC,
        tokens: UsageTokenCounts(freshInput: .max, output: 0, cacheCreation: 0, cacheRead: 0),
        requestCount: .max,
        estimatedCostUSD: .zero
    )
    let overflowNextEntry = UsageEntry(
        id: "overflow-two",
        occurredAt: window.startUTC.addingTimeInterval(1),
        tokens: UsageTokenCounts(freshInput: 1, output: 0, cacheCreation: 0, cacheRead: 0),
        requestCount: 1,
        estimatedCostUSD: .zero
    )
    let overflow = UsageAggregator.snapshot(
        batches: [
            UsageSourceBatch(entries: [overflowEntry], coverageStart: window.startUTC, coverageEnd: window.endUTC, warnings: [], scannedFileCount: .max),
            UsageSourceBatch(entries: [overflowNextEntry], coverageStart: window.startUTC, coverageEnd: window.endUTC, warnings: [], scannedFileCount: 1)
        ],
        window: window,
        refreshedAt: now
    )
    expectEqual(overflow.tokens.freshInput, .max, "token aggregation saturates Int64 overflow")
    expectEqual(overflow.requestCount, .max, "request aggregation saturates Int64 overflow")
    expectEqual(overflow.scannedFileCount, .max, "scanned-file aggregation saturates overflow")
    expectEqual(overflow.warnings.contains(.numericOverflow), true, "aggregation records numeric overflow")

    let crossCategoryOverflowEntry = UsageEntry(
        id: "cross-category-overflow",
        occurredAt: window.startUTC,
        tokens: UsageTokenCounts(freshInput: .max - 2, output: 1, cacheCreation: 1, cacheRead: 1),
        requestCount: 1,
        estimatedCostUSD: .zero
    )
    let crossCategoryOverflow = UsageAggregator.snapshot(
        batches: [
            UsageSourceBatch(
                entries: [crossCategoryOverflowEntry],
                coverageStart: window.startUTC,
                coverageEnd: window.endUTC,
                warnings: [],
                scannedFileCount: 1
            )
        ],
        window: window,
        refreshedAt: now
    )
    expectEqual(crossCategoryOverflow.tokens, crossCategoryOverflowEntry.tokens, "cross-category overflow leaves each independently valid token subtotal unchanged")
    expectEqual(crossCategoryOverflow.tokens.realTotal, .max, "cross-category token totals still saturate safely")
    expectEqual(crossCategoryOverflow.warnings.contains(.numericOverflow), true, "cross-category token-total overflow is reported")
    expectEqual(crossCategoryOverflow.completeness, .partial, "cross-category token-total overflow makes completeness partial")
    expectEqual(crossCategoryOverflow.estimatedCostUSD, nil, "cross-category token-total overflow suppresses estimated cost")

    let partialBatch = UsageSourceBatch(
        entries: [entry],
        coverageStart: window.startUTC.addingTimeInterval(1),
        coverageEnd: window.endUTC,
        warnings: [.unpricedUsage],
        scannedFileCount: 1
    )
    let partial = UsageAggregator.snapshot(batches: [partialBatch], window: window, refreshedAt: now)
    expectEqual(partial.completeness, .partial, "late coverage makes token completeness partial")
    expectEqual(partial.warnings.contains(.insufficientCoverage), true, "late coverage warns explicitly")
    expectEqual(partial.estimatedCostUSD, nil, "unpriced usage omits estimated cost")

    let unpricedOnly = UsageAggregator.snapshot(
        batches: [UsageSourceBatch(entries: [entry], coverageStart: window.startUTC, coverageEnd: window.endUTC, warnings: [.unpricedUsage], scannedFileCount: 1)],
        window: window,
        refreshedAt: now
    )
    expectEqual(unpricedOnly.completeness, .complete, "unpriced usage alone does not make token completeness partial")
    expectEqual(unpricedOnly.estimatedCostUSD, nil, "unpriced usage has no cost estimate")

    let completeEmpty = UsageAggregator.snapshot(
        batches: [UsageSourceBatch(entries: [], coverageStart: window.startUTC, coverageEnd: window.endUTC, warnings: [.unpricedUsage], scannedFileCount: 1)],
        window: window,
        refreshedAt: now
    )
    expectEqual(completeEmpty.completeness, .complete, "unpriced warning does not make an empty token result partial")
    expectEqual(completeEmpty.estimatedCostUSD, .zero, "complete empty results report zero estimated cost")
}

private func testUsageSnapshotFormattingAndCacheHitRate() {
    expectEqual(UsageTokenFormatter.exact(982_233), "982,233", "exact formatter uses stable grouping")
    expectEqual(UsageTokenFormatter.approximate(982_233), "≈98.22万", "approximate formatter uses Chinese ten-thousand units")
    expectEqual(UsageTokenFormatter.compact(145_000), "14.5万", "compact formatter uses concise ten-thousand units")
    expectEqual(UsageTokenFormatter.exact(1_332), "1,332", "exact formatter groups four-digit values")
    expectEqual(UsageTokenFormatter.approximate(5_941_400_123), "≈59.41亿", "approximate formatter uses Chinese hundred-million units")
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
testCodexAppServerApprovalContracts()
testTemporaryFileShelfExpandedDropIntegration()
testInteractionLoggingContract()
testCurrentShellSourceContracts()
testRemovedFeatureFilesAreGone()
testDataPrimaryContentViewContracts()
testDataUsageOverlayAndControllerIntegrationContracts()
testBuildScriptStillPackagesSignedApp()
testUsageSQLiteSourceKeepsReadOnlyPrivacyContracts()
testUsageTimeRangeUsesCapturedLocalNaturalDays()
testUsageTimeRangeHandlesDSTAndHalfOpenBounds()
testUsageCumulativeCountersDiffNormalResetAndNoChange()
testCodexRolloutParserCountsFirstValidSampleInsideWindow()
testCodexRolloutParserDefersInitialEmptyUsageUntilZeroBaseline()
testCodexRolloutParserRejectsNonExplicitInitialEmptyInfo()
testCodexRolloutParserRequiresCompleteStandardZeroCountersAfterInitialNull()
testCodexRolloutParserKeepsPendingInitialNullDamageProtection()
testCodexRolloutParserIgnoresUnstructuredTokenCountText()
testCodexRolloutParserRecognizesWhitespaceStructuredMalformedMarker()
testCodexRolloutParserRejectsNormalizedInvalidCalendarDates()
testCodexRolloutParserDiffsCompleteSequenceBeforeFilteringWindow()
testCodexRolloutParserBreaksBaselineAcrossUnreadableTokenEvents()
testCodexRolloutParserDecodesLargeIntegerCountersExactly()
testUsageTokenNormalizationAvoidsCacheDoubleCounting()
testUsageAggregatorCalculatesRequestsCoverageCostAndCompleteness()
testUsageSnapshotFormattingAndCacheHitRate()

print("DynamicIslandCoreChecks passed")
