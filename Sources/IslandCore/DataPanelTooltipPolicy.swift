import Foundation

public struct DataPanelTooltipRow: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct DataPanelTooltipContent: Equatable, Sendable {
    public let title: String
    public let subtitle: String?
    public let rows: [DataPanelTooltipRow]

    public init(title: String, subtitle: String? = nil, rows: [DataPanelTooltipRow] = []) {
        self.title = title
        self.subtitle = subtitle
        self.rows = rows
    }
}

public enum DataPanelTooltipPolicy {
    public static let calendarTooltipDelaySeconds = 3

    public static func isTrendTooltipEnabled(in mode: DataPanelMode) -> Bool {
        mode == .trends
    }

    public static func isCalendarTooltipEnabled(in mode: DataPanelMode) -> Bool {
        mode == .overview
    }

    public static func nearestTrendPointIndex(
        points: [UsageTrendPoint],
        x: Double,
        plotMinX: Double,
        plotMaxX: Double
    ) -> Int? {
        guard !points.isEmpty else {
            return nil
        }

        guard points.count > 1, plotMaxX > plotMinX else {
            return 0
        }

        let clampedX = min(max(x, plotMinX), plotMaxX)
        let step = (plotMaxX - plotMinX) / Double(points.count - 1)
        let index = Int(round((clampedX - plotMinX) / step))
        return min(max(index, 0), points.count - 1)
    }

    public static func trendTooltip(for point: UsageTrendPoint, calendar: Calendar) -> DataPanelTooltipContent {
        DataPanelTooltipContent(
            title: trendFormatter(calendar: calendar).string(from: point.timestamp),
            rows: [
                DataPanelTooltipRow(label: "Tokens", value: formatCompact(point.tokens)),
                DataPanelTooltipRow(label: "Cost", value: formatCost(point.cost)),
                DataPanelTooltipRow(label: "Requests", value: formatCompact(point.requests))
            ]
        )
    }

    public static func calendarTooltip(
        for cell: CalendarHeatmapCell,
        calendar: Calendar
    ) -> DataPanelTooltipContent? {
        guard let date = cell.date else {
            return nil
        }

        return DataPanelTooltipContent(
            title: calendarFormatter(calendar: calendar).string(from: date),
            subtitle: "\(formatCompact(cell.tokens)) tokens"
        )
    }
}

private extension DataPanelTooltipPolicy {
    static func trendFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }

    static func calendarFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }

    static func formatCompact(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if absValue >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    static func formatCost(_ value: Double) -> String {
        if value < 0.01 {
            return "$0"
        }

        if value < 10 {
            return String(format: "$%.2f", value)
        }

        return String(format: "$%.0f", value)
    }
}
