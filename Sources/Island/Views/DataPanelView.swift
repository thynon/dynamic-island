import AppKit
import SwiftUI
import IslandCore

struct DataPanelView: View {
    @Binding var mode: DataPanelMode
    @State private var feature: IslandFeature = .defaultFeature
    @State private var statsTimeRange: StatsTimeRange = .today
    @State private var usageToday = Date()
    @State private var usageSummary: CodexUsageSummary = .empty
    @State private var isLoadingUsage = true
    @State private var isRefreshingUsage = false
    @State private var lastUsageRefreshDate: Date?
    @State private var trendTooltip: PanelTooltip?
    @State private var calendarTooltip: PanelTooltip?
    @State private var calendarHoverToken = UUID()
    @State private var pendingCalendarTooltipID: String?

    private let featureSwitcherReservedWidth: CGFloat = 150
    private let headerHeight: CGFloat = 28
    private let contentSpacing: CGFloat = 4
    private let secondaryControlHeight: CGFloat = 24
    private let costBadgeVerticalOffset: CGFloat = -30

    var body: some View {
        VStack(spacing: contentSpacing) {
            header

            featureContent
        }
        .task(id: usageRefreshLoopID) {
            await runUsageRefreshLoop()
        }
        .onChange(of: mode) { _, _ in
            clearTooltips()
        }
        .onChange(of: feature) { _, _ in
            clearTooltips()
        }
        .onChange(of: statsTimeRange) { _, _ in
            clearTooltips()
        }
        .onDisappear {
            clearTooltips()
            usageSummary = .empty
            lastUsageRefreshDate = nil
            isLoadingUsage = false
            Task {
                await CodexUsageDataSource.clearCache()
            }
        }
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 8) {
                if feature == .stats {
                    HStack(alignment: .center, spacing: 8) {
                        modeControl

                        HStack(spacing: 5) {
                            refreshCadenceBadge
                            usageRangeControl
                        }
                    }
                    .frame(height: secondaryControlHeight, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.trailing, featureSwitcherReservedWidth)

            FeatureSwitcher(selection: $feature)
                .frame(width: featureSwitcherReservedWidth, height: 28, alignment: .trailing)

            if feature == .stats {
                topRightCostBadge
                    .frame(width: featureSwitcherReservedWidth, height: 24, alignment: .trailing)
                    .offset(y: costBadgeVerticalOffset)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }
        }
        .frame(maxWidth: .infinity, minHeight: headerHeight, maxHeight: headerHeight, alignment: .top)
    }

    private var featureContent: some View {
        Group {
            switch feature {
            case .status:
                emptyFeaturePlaceholder(title: "Status", subtitle: "No active status panel yet")
            case .stats:
                statsContent
            case .tools:
                emptyFeaturePlaceholder(title: "Tools", subtitle: "No tools panel yet")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var statsContent: some View {
        ZStack {
            if mode.showsTrendLayer {
                trendLayer
                    .transition(.opacity)
            }

            if mode.showsOverviewLayer {
                overviewLayer
                    .opacity(mode == .all ? 0.86 : 1)
                    .transition(.opacity)
            }
        }
    }

    private func emptyFeaturePlaceholder(title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))

            Text(subtitle)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.40))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.025, green: 0.028, blue: 0.034))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }

    private var modeControl: some View {
        HStack(spacing: 3) {
            ForEach(DataPanelMode.allCases, id: \.self) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        mode = item
                    }
                } label: {
                    Text(item.label)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(mode == item ? .black : .white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: item.controlWidth, height: 18)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(mode == item ? Color.white.opacity(0.88) : Color.white.opacity(0.09))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
                }
        }
    }

    private var usageRangeControl: some View {
        HStack(spacing: 2) {
            ForEach(StatsTimeRange.allCases, id: \.self) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        statsTimeRange = item
                        usageToday = Date()
                    }
                } label: {
                    Text(item.label)
                        .font(.system(size: 8.6, weight: .bold, design: .rounded))
                        .foregroundStyle(statsTimeRange == item ? Color(red: 0.22, green: 0.52, blue: 1.0) : .white.opacity(0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: item.controlWidth, height: 18)
                        .background {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(statsTimeRange == item ? Color.white.opacity(0.075) : Color.clear)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
    }

    private var refreshCadenceBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 8.8, weight: .bold))
            Text("30s")
                .font(.system(size: 8.6, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white.opacity(isLoadingUsage ? 0.42 : 0.62))
        .frame(width: 42, height: 24)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
    }

    private var topRightCostBadge: some View {
        HStack(spacing: 0) {
            Text(formattedHeaderCost)
                .font(.system(size: 10.2, weight: .heavy, design: .rounded))
                .foregroundStyle(rangedUsageSummary.costSource == .ledger ? Color(red: 0.34, green: 0.78, blue: 0.52) : .white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            rangedUsageSummary.costSource == .ledger
                            ? Color(red: 0.34, green: 0.78, blue: 0.52).opacity(0.24)
                            : Color.white.opacity(0.12),
                            lineWidth: 1
                        )
                }
        }
    }

    private var stats: [(String, String)] {
        let summary = rangedUsageSummary
        return [
            ("TOKENS", formatTokens(summary.totalTokens)),
            ("CACHE HIT", formatCacheHitRate(summary.cachedInputHitRate)),
            ("REQ", formatCount(summary.requestCount)),
            ("MODEL", summary.favoriteModel)
        ]
    }

    private var trendLayer: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let points = usageTrendPoints
            let plotRect = trendPlotRect(in: size)
            let tokenMax = chartMaximum(points.map(\.tokens))
            let costMax = chartMaximum(points.map(\.cost))
            let requestMax = chartMaximum(points.map(\.requests))
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.025, green: 0.028, blue: 0.034))

                if mode == .trends {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Usage trends")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.82))
                                Text("tokens / cost / requests")
                                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.42))
                            }
                            Spacer()
                            Text(rangeCaption(for: points))
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.48))
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)

                        Spacer()
                    }
                }

                trendGrid(in: plotRect, tokenMax: tokenMax, costMax: costMax)
                trendArea(points: points, metric: \.tokens, maxValue: tokenMax, in: plotRect)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.purple.opacity(mode == .all ? 0.24 : 0.30),
                                Color.purple.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                trendLine(points: points, metric: \.cost, maxValue: costMax, in: plotRect)
                    .stroke(
                        Color(red: 1.0, green: 0.32, blue: 0.42).opacity(0.92),
                        style: StrokeStyle(lineWidth: mode == .all ? 1.2 : 1.5, lineCap: .round, lineJoin: .round, dash: [3, 3])
                    )

                trendLine(points: points, metric: \.tokens, maxValue: tokenMax, in: plotRect)
                    .stroke(
                        Color(red: 0.60, green: 0.30, blue: 1.0).opacity(0.94),
                        style: StrokeStyle(lineWidth: mode == .all ? 1.6 : 2.0, lineCap: .round, lineJoin: .round)
                    )

                trendLine(points: points, metric: \.requests, maxValue: requestMax, in: plotRect)
                    .stroke(
                        Color(red: 0.20, green: 0.46, blue: 1.0).opacity(0.92),
                        style: StrokeStyle(lineWidth: mode == .all ? 1.1 : 1.35, lineCap: .round, lineJoin: .round)
                    )

                if mode == .trends {
                    xAxisLabels(points: points, in: plotRect)
                }

                if mode == .trends, let trendTooltip {
                    trendTooltipMarker(trendTooltip, in: plotRect)
                    tooltipBubble(trendTooltip, in: size)
                }
            }
            .overlay {
                if DataPanelTooltipPolicy.isTrendTooltipEnabled(in: mode) {
                    ZStack {
                        HoverTrackingView(
                            onMoved: { location in
                                updateTrendTooltip(at: location, points: points, plotRect: plotRect, tokenMax: tokenMax)
                            },
                            onEnded: {
                                trendTooltip = nil
                            }
                        )

                        Color.clear
                            .contentShape(Rectangle())
                            .onContinuousHover(coordinateSpace: .local) { phase in
                                switch phase {
                                case .active(let location):
                                    updateTrendTooltip(at: location, points: points, plotRect: plotRect, tokenMax: tokenMax)
                                case .ended:
                                    trendTooltip = nil
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                    .onChanged { value in
                                        updateTrendTooltip(at: value.location, points: points, plotRect: plotRect, tokenMax: tokenMax)
                                    }
                            )
                    }
                    .frame(width: size.width, height: size.height)
                }
            }
        }
    }

    private func trendTooltipMarker(_ tooltip: PanelTooltip, in rect: CGRect) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: tooltip.anchor.x, y: rect.minY))
                path.addLine(to: CGPoint(x: tooltip.anchor.x, y: rect.maxY))
            }
            .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 5, height: 5)
                .overlay {
                    Circle()
                        .stroke(Color(red: 0.60, green: 0.30, blue: 1.0).opacity(0.75), lineWidth: 2)
                }
                .shadow(color: Color(red: 0.60, green: 0.30, blue: 1.0).opacity(0.42), radius: 4)
                .position(tooltip.anchor)
        }
        .allowsHitTesting(false)
    }

    private func trendGrid(in rect: CGRect, tokenMax: Double, costMax: Double) -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                let progress = CGFloat(index) / 4
                let y = rect.maxY - (rect.height * progress)
                Path { path in
                    path.move(to: CGPoint(x: rect.minX, y: y))
                    path.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
                .stroke(Color.white.opacity(0.055), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

                if mode == .trends {
                    Text(formatAxisTokens(tokenMax * Double(progress)))
                        .font(.system(size: 7.2, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.36))
                        .frame(width: 34, alignment: .trailing)
                        .position(x: rect.minX - 20, y: y)

                    Text(formatAxisCost(costMax * Double(progress)))
                        .font(.system(size: 7.2, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.36))
                        .frame(width: 26, alignment: .leading)
                        .position(x: rect.maxX + 17, y: y)
                }
            }
        }
    }

    private func trendLine(
        points: [UsageTrendPoint],
        metric: KeyPath<UsageTrendPoint, Double>,
        maxValue: Double,
        in rect: CGRect
    ) -> Path {
        smoothedPath(from: chartCoordinates(points: points, metric: metric, maxValue: maxValue, in: rect))
    }

    private func trendArea(
        points: [UsageTrendPoint],
        metric: KeyPath<UsageTrendPoint, Double>,
        maxValue: Double,
        in rect: CGRect
    ) -> Path {
        let coordinates = chartCoordinates(points: points, metric: metric, maxValue: maxValue, in: rect)
        var path = smoothedPath(from: coordinates)
        guard let first = coordinates.first, let last = coordinates.last else {
            return path
        }

        path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    private func chartCoordinates(
        points: [UsageTrendPoint],
        metric: KeyPath<UsageTrendPoint, Double>,
        maxValue: Double,
        in rect: CGRect
    ) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let step = rect.width / CGFloat(max(1, points.count - 1))
        return points.enumerated().map { index, point in
            let value = max(0, min(1, point[keyPath: metric] / maxValue))
            return CGPoint(
                x: rect.minX + CGFloat(index) * step,
                y: rect.maxY - (rect.height * CGFloat(value))
            )
        }
    }

    private func smoothedPath(from points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)

            guard points.count > 1 else { return }
            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let midpoint = CGPoint(
                    x: (previous.x + current.x) / 2,
                    y: (previous.y + current.y) / 2
                )
                path.addQuadCurve(to: midpoint, control: previous)
                if index == points.count - 1 {
                    path.addQuadCurve(to: current, control: current)
                }
            }
        }
    }

    private func xAxisLabels(points: [UsageTrendPoint], in rect: CGRect) -> some View {
        let indices = axisLabelIndices(count: points.count, maxCount: 5)
        return ZStack {
            ForEach(indices, id: \.self) { index in
                let denominator = max(1, points.count - 1)
                let x = rect.minX + (rect.width * CGFloat(index) / CGFloat(denominator))
                Text(formatTrendAxisDate(points[index].timestamp, points: points))
                    .font(.system(size: 6.8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 82)
                    .position(x: x, y: rect.maxY + 14)
            }
        }
    }

    private var overviewLayer: some View {
        VStack(spacing: 4) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4),
                spacing: 4
            ) {
                ForEach(stats, id: \.0) { stat in
                    statCard(label: stat.0, value: stat.1)
                }
            }

            heatmap
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(mode == .all ? 0.26 : 0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                }
        }
    }

    private func statCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 5.8, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)

            Text(value)
                .font(.system(size: 9.4, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 23, alignment: .center)
        .padding(.horizontal, 5)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(mode == .all ? 0.12 : 0.16))
        }
    }

    private var heatmap: some View {
        GeometryReader { proxy in
            let weeks = calendarHeatmapWeeks
            let columns = max(1, weeks.count)
            let rows = CalendarHeatmap.rowsPerWeek
            let gap: CGFloat = 3
            let availableWidth = max(1, proxy.size.width - CGFloat(columns - 1) * gap)
            let availableHeight = max(1, proxy.size.height - CGFloat(rows - 1) * gap)
            let cell = max(1, floor(min(
                availableWidth / CGFloat(columns),
                availableHeight / CGFloat(rows)
            )))
            let cellCornerRadius = min(2.5, cell / 3)
            let gridWidth = CGFloat(columns) * cell + CGFloat(columns - 1) * gap
            let gridHeight = CGFloat(rows) * cell + CGFloat(rows - 1) * gap
            let originX = max(0, (proxy.size.width - gridWidth) / 2)
            let originY = max(0, proxy.size.height - gridHeight)
            let positionedCells = positionedHeatmapCells(
                weeks: weeks,
                cellSize: cell,
                gap: gap,
                originX: originX,
                originY: originY
            )

            ZStack(alignment: .topLeading) {
                ForEach(positionedCells) { item in
                    RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
                        .fill(heatmapColor(for: item.cell))
                        .overlay {
                            RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
                                .strokeBorder(heatmapBorderColor(for: item.cell), lineWidth: 0.6)
                        }
                        .frame(width: cell, height: cell)
                        .position(item.anchor)
                        .allowsHitTesting(false)
                }

                if DataPanelTooltipPolicy.isCalendarTooltipEnabled(in: mode) {
                    ZStack {
                        HoverTrackingView(
                            onMoved: { location in
                                updateCalendarTooltipHover(
                                    at: location,
                                    positionedCells: positionedCells,
                                    cellSize: cell
                                )
                            },
                            onEnded: {
                                cancelCalendarTooltip()
                            }
                        )

                        Color.clear
                            .contentShape(Rectangle())
                            .onContinuousHover(coordinateSpace: .local) { phase in
                                switch phase {
                                case .active(let location):
                                    updateCalendarTooltipHover(
                                        at: location,
                                        positionedCells: positionedCells,
                                        cellSize: cell
                                    )
                                case .ended:
                                    cancelCalendarTooltip()
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                    .onChanged { value in
                                        updateCalendarTooltipHover(
                                            at: value.location,
                                            positionedCells: positionedCells,
                                            cellSize: cell
                                        )
                                    }
                            )
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }

                if mode == .overview, let calendarTooltip {
                    tooltipBubble(calendarTooltip, in: proxy.size)
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottom
            )
        }
    }

    private func tooltipBubble(_ tooltip: PanelTooltip, in containerSize: CGSize) -> some View {
        TooltipBubbleView(content: tooltip.content)
            .frame(width: tooltip.size.width)
            .position(tooltipPosition(for: tooltip, in: containerSize))
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .allowsHitTesting(false)
    }

    private func positionedHeatmapCells(
        weeks: [CalendarHeatmapWeek],
        cellSize: CGFloat,
        gap: CGFloat,
        originX: CGFloat,
        originY: CGFloat
    ) -> [PositionedHeatmapCell] {
        var items: [PositionedHeatmapCell] = []
        items.reserveCapacity(weeks.count * CalendarHeatmap.rowsPerWeek)

        for (weekIndex, week) in weeks.enumerated() {
            for (dayIndex, cell) in week.cells.enumerated() {
                let anchor = CGPoint(
                    x: originX + CGFloat(weekIndex) * (cellSize + gap) + cellSize / 2,
                    y: originY + CGFloat(dayIndex) * (cellSize + gap) + cellSize / 2
                )
                items.append(PositionedHeatmapCell(cell: cell, anchor: anchor))
            }
        }

        return items
    }

    private func updateTrendTooltip(
        at location: CGPoint,
        points: [UsageTrendPoint],
        plotRect: CGRect,
        tokenMax: Double
    ) {
        guard let index = DataPanelTooltipPolicy.nearestTrendPointIndex(
            points: points,
            x: Double(location.x),
            plotMinX: Double(plotRect.minX),
            plotMaxX: Double(plotRect.maxX)
        ) else {
            trendTooltip = nil
            return
        }

        let point = points[index]
        let denominator = max(1, points.count - 1)
        let x = plotRect.minX + (plotRect.width * CGFloat(index) / CGFloat(denominator))
        let value = max(0, min(1, point.tokens / tokenMax))
        let y = plotRect.maxY - (plotRect.height * CGFloat(value))

        trendTooltip = PanelTooltip(
            id: "trend-\(point.timestamp.timeIntervalSinceReferenceDate)",
            content: DataPanelTooltipPolicy.trendTooltip(for: point, calendar: heatmapCalendar),
            anchor: CGPoint(x: x, y: y),
            size: CGSize(width: 128, height: 78)
        )
    }

    private func scheduleCalendarTooltip(for cell: CalendarHeatmapCell, anchor: CGPoint) {
        guard
            DataPanelTooltipPolicy.isCalendarTooltipEnabled(in: mode),
            let content = DataPanelTooltipPolicy.calendarTooltip(for: cell, calendar: heatmapCalendar)
        else {
            return
        }

        let token = UUID()
        calendarHoverToken = token
        pendingCalendarTooltipID = cell.id
        calendarTooltip = nil

        DispatchQueue.main.asyncAfter(
            deadline: .now() + .seconds(DataPanelTooltipPolicy.calendarTooltipDelaySeconds)
        ) {
            guard
                calendarHoverToken == token,
                pendingCalendarTooltipID == cell.id,
                DataPanelTooltipPolicy.isCalendarTooltipEnabled(in: mode)
            else {
                return
            }

            withAnimation(.easeOut(duration: 0.12)) {
                calendarTooltip = PanelTooltip(
                    id: "calendar-\(cell.id)",
                    content: content,
                    anchor: anchor,
                    size: CGSize(width: 112, height: 42)
                )
            }
        }
    }

    private func updateCalendarTooltipHover(
        at location: CGPoint,
        positionedCells: [PositionedHeatmapCell],
        cellSize: CGFloat
    ) {
        guard DataPanelTooltipPolicy.isCalendarTooltipEnabled(in: mode) else {
            cancelCalendarTooltip()
            return
        }

        let hitRadius = max(7, cellSize * 0.85)
        let nearest = positionedCells
            .filter { !$0.cell.isPadding }
            .compactMap { item -> (PositionedHeatmapCell, CGFloat)? in
                let dx = abs(location.x - item.anchor.x)
                let dy = abs(location.y - item.anchor.y)
                guard dx <= hitRadius, dy <= hitRadius else {
                    return nil
                }
                return (item, hypot(dx, dy))
            }
            .min { lhs, rhs in
                lhs.1 < rhs.1
            }

        guard let item = nearest?.0 else {
            cancelCalendarTooltip()
            return
        }

        if pendingCalendarTooltipID == item.cell.id {
            return
        }

        scheduleCalendarTooltip(for: item.cell, anchor: item.anchor)
    }

    private func cancelCalendarTooltip(for cellID: String? = nil) {
        if let cellID, pendingCalendarTooltipID != cellID {
            return
        }

        calendarHoverToken = UUID()
        pendingCalendarTooltipID = nil
        withAnimation(.easeOut(duration: 0.10)) {
            calendarTooltip = nil
        }
    }

    private func clearTooltips() {
        trendTooltip = nil
        cancelCalendarTooltip()
    }

    private func tooltipPosition(for tooltip: PanelTooltip, in containerSize: CGSize) -> CGPoint {
        let margin: CGFloat = 6
        let halfWidth = tooltip.size.width / 2
        let halfHeight = tooltip.size.height / 2
        let preferredX = tooltip.anchor.x + halfWidth + 10
        let minX = halfWidth + margin
        let maxX = max(minX, containerSize.width - halfWidth - margin)
        let x = min(max(preferredX, minX), maxX)

        let upperY = tooltip.anchor.y - halfHeight - 12
        let lowerY = tooltip.anchor.y + halfHeight + 12
        let preferredY = upperY >= halfHeight + margin ? upperY : lowerY
        let minY = halfHeight + margin
        let maxY = max(minY, containerSize.height - halfHeight - margin)
        let y = min(max(preferredY, minY), maxY)

        return CGPoint(x: x, y: y)
    }

    private var calendarHeatmapWeeks: [CalendarHeatmapWeek] {
        CalendarHeatmap.weeks(
            range: statsTimeRange,
            today: usageToday,
            calendar: heatmapCalendar,
            records: usageSummary.heatmapRecords
        )
    }

    private var heatmapCalendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    private var usageTrendPoints: [UsageTrendPoint] {
        UsageTrendTimeline.points(
            range: statsTimeRange,
            today: usageToday,
            calendar: heatmapCalendar,
            records: usageSummary.trendRecords
        )
    }

    private var rangedUsageSummary: CodexUsageSummary {
        usageSummary.filtered(
            range: statsTimeRange,
            today: usageToday,
            calendar: heatmapCalendar
        )
    }

    private var usageRefreshLoopID: String {
        "\(feature.rawValue):\(mode.rawValue)"
    }

    @MainActor
    private func runUsageRefreshLoop() async {
        guard feature == .stats else {
            return
        }

        await refreshUsageIfNeeded(force: lastUsageRefreshDate == nil)

        while !Task.isCancelled {
            let refreshCadence = UInt64(max(5, mode.refreshCadenceSeconds))
            try? await Task.sleep(nanoseconds: refreshCadence * 1_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            await refreshUsageIfNeeded()
        }
    }

    @MainActor
    private func refreshUsageIfNeeded(force: Bool = false) async {
        guard feature == .stats else {
            return
        }

        if !force, let lastUsageRefreshDate {
            let elapsedSeconds = Date().timeIntervalSince(lastUsageRefreshDate)
            guard mode.shouldRefreshUsage(elapsedSeconds: elapsedSeconds) else {
                return
            }
        }

        await refreshUsage()
    }

    @MainActor
    private func refreshUsage() async {
        guard !isRefreshingUsage else {
            return
        }

        isRefreshingUsage = true
        defer {
            isRefreshingUsage = false
        }
        isLoadingUsage = true
        let calendar = heatmapCalendar
        let summary = await CodexUsageDataSource.loadSummary(calendar: calendar)
        let now = Date()
        usageSummary = summary
        usageToday = now
        lastUsageRefreshDate = now
        isLoadingUsage = false
    }

    private func heatmapColor(for cell: CalendarHeatmapCell) -> Color {
        guard !cell.isPadding else {
            return .clear
        }

        guard cell.intensity > 0 else {
            return Color(red: 0.40, green: 0.46, blue: 0.54)
                .opacity(CalendarHeatmapVisualPolicy.emptyCellOpacity(mode: mode))
        }

        return Color(red: 0.16, green: 0.50, blue: 1.0)
            .opacity(CalendarHeatmapVisualPolicy.dataCellOpacity(intensity: cell.intensity, mode: mode))
    }

    private func heatmapBorderColor(for cell: CalendarHeatmapCell) -> Color {
        guard !cell.isPadding else {
            return .clear
        }

        return Color(red: 0.76, green: 0.84, blue: 0.95).opacity(
            CalendarHeatmapVisualPolicy.cellBorderOpacity(isActive: cell.intensity > 0, mode: mode)
        )
    }

    private func formatTokens(_ value: Int) -> String {
        formatCompact(Double(value))
    }

    private func formatCount(_ value: Int) -> String {
        formatCompact(Double(value))
    }

    private func formatCost(_ value: Double) -> String {
        if value < 0.01 {
            return "$0"
        }

        if value < 10 {
            return String(format: "$%.2f", value)
        }

        return String(format: "$%.0f", value)
    }

    private func formatCacheHitRate(_ value: Double) -> String {
        String(format: "%.1f%%", min(1, max(0, value)) * 100)
    }

    private var formattedHeaderCost: String {
        let cost = max(0, rangedUsageSummary.estimatedCost)
        if rangedUsageSummary.costSource == .ledger {
            return String(format: "$%.4f", cost)
        }

        return String(format: "$%.2f", cost)
    }

    private func formatCompact(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if absValue >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    private func trendPlotRect(in size: CGSize) -> CGRect {
        let top: CGFloat = mode == .trends ? 40 : 16
        let left: CGFloat = mode == .trends ? 42 : 14
        let right: CGFloat = mode == .trends ? 32 : 14
        let bottom: CGFloat = mode == .trends ? 24 : 16
        return CGRect(
            x: left,
            y: top,
            width: max(1, size.width - left - right),
            height: max(1, size.height - top - bottom)
        )
    }

    private func chartMaximum(_ values: [Double]) -> Double {
        let maxValue = values.max() ?? 0
        guard maxValue > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(maxValue)))
        let normalized = maxValue / magnitude
        let step: Double
        if normalized <= 2 {
            step = 2
        } else if normalized <= 5 {
            step = 5
        } else {
            step = 10
        }
        return step * magnitude
    }

    private func axisLabelIndices(count: Int, maxCount: Int) -> [Int] {
        guard count > 0 else { return [] }
        guard count > maxCount, maxCount > 1 else {
            return Array(0..<count)
        }

        let step = Double(count - 1) / Double(maxCount - 1)
        var indices = (0..<maxCount).map { Int(round(Double($0) * step)) }
        indices[0] = 0
        indices[indices.count - 1] = count - 1
        return indices
    }

    private func rangeCaption(for points: [UsageTrendPoint]) -> String {
        if isSameDayRange(points) {
            return "Today"
        }

        return statsTimeRange.label
    }

    private func formatTrendAxisDate(_ date: Date, points: [UsageTrendPoint]) -> String {
        let formatter = DateFormatter()
        formatter.calendar = heatmapCalendar
        formatter.timeZone = heatmapCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private func isSameDayRange(_ points: [UsageTrendPoint]) -> Bool {
        guard let first = points.first?.timestamp, let last = points.last?.timestamp else {
            return true
        }
        return heatmapCalendar.isDate(first, inSameDayAs: last)
    }

    private func formatAxisTokens(_ value: Double) -> String {
        if value >= 1_000_000 {
            return "\(Int(round(value / 1_000_000)))M"
        }
        if value >= 1_000 {
            return "\(Int(round(value / 1_000)))K"
        }
        return "\(Int(round(value)))"
    }

    private func formatAxisCost(_ value: Double) -> String {
        "$\(Int(round(value)))"
    }
}

private struct PanelTooltip: Equatable {
    let id: String
    let content: DataPanelTooltipContent
    let anchor: CGPoint
    let size: CGSize
}

private struct PositionedHeatmapCell: Identifiable, Equatable {
    let cell: CalendarHeatmapCell
    let anchor: CGPoint

    var id: String {
        cell.id
    }
}

private struct TooltipBubbleView: View {
    let content: DataPanelTooltipContent

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(content.title)
                .font(.system(size: 8.4, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let subtitle = content.subtitle {
                Text(subtitle)
                    .font(.system(size: 7.2, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.38, green: 0.64, blue: 1.0).opacity(0.90))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if !content.rows.isEmpty {
                VStack(spacing: 3) {
                    ForEach(content.rows, id: \.label) { row in
                        HStack(spacing: 6) {
                            Text(row.label)
                                .font(.system(size: 6.8, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.46))
                            Spacer(minLength: 4)
                            Text(row.value)
                                .font(.system(size: 7.3, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white.opacity(0.90))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.035, green: 0.040, blue: 0.050).opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.42), radius: 10, y: 6)
    }
}

private struct HoverTrackingView: NSViewRepresentable {
    let onMoved: (CGPoint) -> Void
    let onEnded: () -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMoved = onMoved
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onMoved = onMoved
        nsView.onEnded = onEnded
    }

    final class TrackingView: NSView {
        var onMoved: ((CGPoint) -> Void)?
        var onEnded: (() -> Void)?

        private var trackingArea: NSTrackingArea?

        override var isFlipped: Bool {
            true
        }

        override func updateTrackingAreas() {
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }

            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area

            super.updateTrackingAreas()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func mouseEntered(with event: NSEvent) {
            onMoved?(convert(event.locationInWindow, from: nil))
        }

        override func mouseMoved(with event: NSEvent) {
            onMoved?(convert(event.locationInWindow, from: nil))
        }

        override func mouseDragged(with event: NSEvent) {
            onMoved?(convert(event.locationInWindow, from: nil))
        }

        override func mouseDown(with event: NSEvent) {
            onMoved?(convert(event.locationInWindow, from: nil))
        }

        override func mouseExited(with event: NSEvent) {
            onEnded?()
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }
    }
}

private struct FeatureSwitcher: View {
    @Binding var selection: IslandFeature

    var body: some View {
        HStack(spacing: 3) {
            ForEach(IslandFeature.allCases, id: \.self) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selection = item
                    }
                } label: {
                    Text(item.label)
                        .font(.system(size: 9.6, weight: .heavy, design: .rounded))
                        .foregroundStyle(selection == item ? .black : .white.opacity(0.66))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(width: item.controlWidth, height: 20)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selection == item ? Color.white.opacity(0.90) : Color.white.opacity(0.045))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                }
        }
    }
}

private extension DataPanelMode {
    var controlWidth: CGFloat {
        switch self {
        case .trends:
            return 43
        case .overview:
            return 55
        case .all:
            return 34
        }
    }
}

private extension IslandFeature {
    var controlWidth: CGFloat {
        switch self {
        case .status:
            return 48
        case .stats:
            return 42
        case .tools:
            return 42
        }
    }
}

private extension StatsTimeRange {
    var controlWidth: CGFloat {
        switch self {
        case .today:
            return 42
        case .sevenDays:
            return 28
        case .thirtyDays:
            return 34
        case .all:
            return 28
        }
    }

    var compactControlWidth: CGFloat {
        switch self {
        case .today:
            return 36
        case .sevenDays:
            return 24
        case .thirtyDays:
            return 30
        case .all:
            return 23
        }
    }
}
