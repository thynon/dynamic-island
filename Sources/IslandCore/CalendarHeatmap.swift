import Foundation

public enum StatsTimeRange: String, CaseIterable, Equatable, Sendable {
    case today
    case sevenDays
    case thirtyDays
    case all

    public var label: String {
        switch self {
        case .today:
            return "Today"
        case .sevenDays:
            return "7d"
        case .thirtyDays:
            return "30d"
        case .all:
            return "All"
        }
    }

    public func startDate(today: Date, calendar inputCalendar: Calendar) -> Date {
        var calendar = inputCalendar
        calendar.timeZone = inputCalendar.timeZone
        let todayStart = calendar.startOfDay(for: today)

        switch self {
        case .today:
            return todayStart
        case .sevenDays:
            return calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
        case .all:
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: todayStart) ?? todayStart
            return calendar.date(byAdding: .day, value: 1, to: sixMonthsAgo) ?? sixMonthsAgo
        }
    }
}

public typealias UsageHeatmapRange = StatsTimeRange

public struct UsageHeatmapRecord: Equatable, Sendable {
    public let date: Date
    public let tokens: Double
    public let cost: Double
    public let requests: Double

    public init(date: Date, tokens: Double, cost: Double, requests: Double) {
        self.date = date
        self.tokens = tokens
        self.cost = cost
        self.requests = requests
    }
}

public struct CalendarHeatmapCell: Equatable, Identifiable, Sendable {
    public let id: String
    public let date: Date?
    public let tokens: Double
    public let cost: Double
    public let requests: Double
    public let intensity: Double

    public init(
        id: String,
        date: Date?,
        tokens: Double,
        cost: Double,
        requests: Double,
        intensity: Double
    ) {
        self.id = id
        self.date = date
        self.tokens = tokens
        self.cost = cost
        self.requests = requests
        self.intensity = intensity
    }

    public var isPadding: Bool {
        date == nil
    }
}

public struct CalendarHeatmapWeek: Equatable, Identifiable, Sendable {
    public let id: Date
    public let cells: [CalendarHeatmapCell]
}

public enum CalendarHeatmap {
    public static let rowsPerWeek = 7

    public static func weeks(
        range: StatsTimeRange,
        today: Date,
        calendar inputCalendar: Calendar,
        records: [UsageHeatmapRecord]
    ) -> [CalendarHeatmapWeek] {
        var calendar = inputCalendar
        calendar.timeZone = inputCalendar.timeZone

        let todayStart = startOfDay(today, calendar: calendar)
        let aggregates = aggregate(records: records, calendar: calendar, today: todayStart)
        let rangeStart = range.startDate(today: todayStart, calendar: calendar)
        let weekStart = addingDays(-weekdayOffset(for: rangeStart, calendar: calendar), to: rangeStart, calendar: calendar)
        let weekEnd = addingDays(6 - weekdayOffset(for: todayStart, calendar: calendar), to: todayStart, calendar: calendar)
        let maxima = maxima(from: aggregates, start: rangeStart, end: todayStart)

        var weeks: [CalendarHeatmapWeek] = []
        var currentWeekStart = weekStart

        while currentWeekStart <= weekEnd {
            let cells = (0..<rowsPerWeek).map { weekdayIndex in
                let date = addingDays(weekdayIndex, to: currentWeekStart, calendar: calendar)
                let isInsideRange = date >= rangeStart && date <= todayStart

                guard isInsideRange else {
                    return CalendarHeatmapCell(
                        id: "padding-\(currentWeekStart.timeIntervalSinceReferenceDate)-\(weekdayIndex)",
                        date: nil,
                        tokens: 0,
                        cost: 0,
                        requests: 0,
                        intensity: 0
                    )
                }

                let usage = aggregates[date] ?? UsageAggregate()
                return CalendarHeatmapCell(
                    id: "date-\(date.timeIntervalSinceReferenceDate)",
                    date: date,
                    tokens: usage.tokens,
                    cost: usage.cost,
                    requests: usage.requests,
                    intensity: intensity(for: usage, maxima: maxima)
                )
            }

            weeks.append(CalendarHeatmapWeek(id: currentWeekStart, cells: cells))
            currentWeekStart = addingDays(rowsPerWeek, to: currentWeekStart, calendar: calendar)
        }

        return weeks
    }
}

private struct UsageAggregate {
    var tokens: Double = 0
    var cost: Double = 0
    var requests: Double = 0

    mutating func add(_ record: UsageHeatmapRecord) {
        tokens += record.tokens
        cost += record.cost
        requests += record.requests
    }
}

private extension CalendarHeatmap {
    static func startOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    static func addingDays(_ days: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func weekdayOffset(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday - calendar.firstWeekday + rowsPerWeek) % rowsPerWeek
    }

    static func aggregate(
        records: [UsageHeatmapRecord],
        calendar: Calendar,
        today: Date
    ) -> [Date: UsageAggregate] {
        records.reduce(into: [Date: UsageAggregate]()) { result, record in
            let date = startOfDay(record.date, calendar: calendar)
            guard date <= today else { return }
            result[date, default: UsageAggregate()].add(record)
        }
    }

    static func maxima(from aggregates: [Date: UsageAggregate], start: Date, end: Date) -> UsageAggregate {
        aggregates.reduce(into: UsageAggregate()) { result, element in
            let (date, usage) = element
            guard date >= start, date <= end else { return }
            result.tokens = max(result.tokens, usage.tokens)
            result.cost = max(result.cost, usage.cost)
            result.requests = max(result.requests, usage.requests)
        }
    }

    static func intensity(for usage: UsageAggregate, maxima: UsageAggregate) -> Double {
        let tokenIntensity = maxima.tokens > 0 ? usage.tokens / maxima.tokens : 0
        let costIntensity = maxima.cost > 0 ? usage.cost / maxima.cost : 0
        let requestIntensity = maxima.requests > 0 ? usage.requests / maxima.requests : 0
        return min(1, max(0, max(tokenIntensity, costIntensity, requestIntensity)))
    }
}
