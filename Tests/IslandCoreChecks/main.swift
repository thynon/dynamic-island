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
    expectEqual(running.minScale, 1.0, "running glow does not shrink into an expanding pulse")
    expectEqual(running.maxScale, 1.0, "running glow keeps a fixed halo size")
    expectEqual(running.minOpacity, 0, "running breathing fully fades out at the low point")
    expectEqual(running.maxOpacity, 1.0, "running breathing keeps the approved bright peak")
    expectEqual(running.minBlurRadius, running.maxBlurRadius, "running breathing keeps blur static for low CPU")
    expectEqual(running.maxBlurRadius, 2.5, "running breathing uses the approved static blur")
    expectEqual(running.duration, 1.8, "running breathing half-cycle matches the approved version")

    expectEqual(thinking, running, "thinking uses running active breathing")
    expectEqual(compacting, running, "context compaction uses running active breathing")

    expectEqual(warning.isActive, true, "warning task state breathes")
    expectEqual(warning.minScale, 1.0, "warning glow does not shrink into an expanding pulse")
    expectEqual(warning.maxScale, 1.0, "warning glow keeps a fixed halo size")
    expectEqual(warning.minOpacity, 0, "warning breathing fully fades out at the low point")
    expectEqual(warning.minBlurRadius, warning.maxBlurRadius, "warning breathing keeps blur static for low CPU")
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
        expectEqual(profile.maxScale <= 1.0, true, "\(state) glow radius stays inside halo")
        expectEqual(profile.maxBlurRadius <= 2.6, true, "\(state) breathing blur remains restrained")
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

private func testTaskActivityUsesApprovedStatusDotAnimationKinds() {
    expectEqual(TaskActivityState.idle.statusDotAnimationKind, .hidden, "idle hides the status dot")
    expectEqual(TaskActivityState.thinking.statusDotAnimationKind, .breathingGlow, "thinking uses green breathing glow")
    expectEqual(TaskActivityState.running.statusDotAnimationKind, .breathingGlow, "running uses green breathing glow")
    expectEqual(TaskActivityState.compacting.statusDotAnimationKind, .breathingGlow, "compacting uses green breathing glow")
    expectEqual(TaskActivityState.warning.statusDotAnimationKind, .breathingGlow, "warning uses yellow breathing glow")
    expectEqual(TaskActivityState.error.statusDotAnimationKind, .fastPulse, "error uses fast red pulse")
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

private func testCodexUsageParserReadsTokenCountLastUsage() {
    let line = """
    {"timestamp":"2026-06-10T01:24:33.917Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"cached_input_tokens":100,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":320},"last_token_usage":{"input_tokens":200,"cached_input_tokens":40,"output_tokens":10,"reasoning_output_tokens":3,"total_tokens":210},"model_context_window":950000}}}
    """
    let parsed = CodexSessionLogParser.parseLine(line)

    guard case let .token(event)? = parsed else {
        fputs("FAIL: expected token usage event\n", stderr)
        Foundation.exit(1)
    }

    expectEqual(event.usage.inputTokens, 200, "parser uses last input tokens")
    expectEqual(event.usage.cachedInputTokens, 40, "parser uses last cached tokens")
    expectEqual(event.usage.outputTokens, 10, "parser uses last output tokens")
    expectEqual(event.usage.reasoningOutputTokens, 3, "parser uses last reasoning tokens")
    expectEqual(event.usage.totalTokens, 210, "parser uses last total tokens")
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
testTaskActivityBreathingContracts()
testTaskActivityBreathingStaysInsideStatusDotClip()
testStatusDotHostViewUsesOnlySafeHaloFrame()
testExpandedContentStartsBelowCameraHousingBand()
testTaskActivityStateParsesOnlyExplicitDebugValues()
testTaskActivityUsesApprovedStatusDotAnimationKinds()
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
testCodexUsageParserReadsTokenCountLastUsage()
testCodexUsageSummaryAggregatesRealDailyUsage()
testCodexUsageSummaryFiltersByStatsTimeRange()
testExpandedBottomChipsHugBottomInnerEdge()

print("IslandCoreChecks passed")
