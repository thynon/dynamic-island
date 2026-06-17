import Foundation

public struct UsageTrendRecord: Equatable, Sendable {
    public let timestamp: Date
    public let tokens: Double
    public let cost: Double
    public let requests: Double

    public init(timestamp: Date, tokens: Double, cost: Double, requests: Double) {
        self.timestamp = timestamp
        self.tokens = tokens
        self.cost = cost
        self.requests = requests
    }
}

public struct UsageTrendPoint: Equatable, Identifiable, Sendable {
    public let id: Date
    public let timestamp: Date
    public let tokens: Double
    public let cost: Double
    public let requests: Double

    public init(timestamp: Date, tokens: Double, cost: Double, requests: Double) {
        self.id = timestamp
        self.timestamp = timestamp
        self.tokens = tokens
        self.cost = cost
        self.requests = requests
    }
}

public enum UsageTrendTimeline {
    public static func points(
        range: StatsTimeRange,
        today: Date,
        calendar inputCalendar: Calendar,
        records: [UsageTrendRecord]
    ) -> [UsageTrendPoint] {
        var calendar = inputCalendar
        calendar.timeZone = inputCalendar.timeZone

        let end = bucketStart(for: today, range: range, records: records, calendar: calendar)
        let start = startDate(for: range, today: today, records: records, calendar: calendar)
        let component = bucketComponent(for: range, start: start, end: end, calendar: calendar)
        let bucketStartDate = floor(start, component: component, calendar: calendar)
        let bucketEndDate = floor(end, component: component, calendar: calendar)
        let aggregates = aggregate(records: records, component: component, calendar: calendar, start: bucketStartDate, end: bucketEndDate)

        var output: [UsageTrendPoint] = []
        var cursor = bucketStartDate

        while cursor <= bucketEndDate {
            let usage = aggregates[cursor] ?? TrendAggregate()
            output.append(
                UsageTrendPoint(
                    timestamp: cursor,
                    tokens: usage.tokens,
                    cost: usage.cost,
                    requests: usage.requests
                )
            )
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else {
                break
            }
            cursor = next
        }

        return output
    }

    public static func axisLabels(
        points: [UsageTrendPoint],
        maxCount: Int,
        calendar: Calendar
    ) -> [String] {
        guard !points.isEmpty, maxCount > 0 else {
            return []
        }

        let indices = sampledIndices(count: points.count, maxCount: maxCount)
        let formatter = axisLabelFormatter(for: points, calendar: calendar)
        return indices.map { formatter.string(from: points[$0].timestamp) }
    }
}

private struct TrendAggregate {
    var tokens: Double = 0
    var cost: Double = 0
    var requests: Double = 0

    mutating func add(_ record: UsageTrendRecord) {
        tokens += record.tokens
        cost += record.cost
        requests += record.requests
    }
}

private extension UsageTrendTimeline {
    static func startDate(
        for range: StatsTimeRange,
        today: Date,
        records: [UsageTrendRecord],
        calendar: Calendar
    ) -> Date {
        range.startDate(today: today, calendar: calendar)
    }

    static func bucketStart(
        for today: Date,
        range: StatsTimeRange,
        records: [UsageTrendRecord],
        calendar: Calendar
    ) -> Date {
        let start = startDate(for: range, today: today, records: records, calendar: calendar)
        let component = bucketComponent(for: range, start: start, end: today, calendar: calendar)
        return floor(today, component: component, calendar: calendar)
    }

    static func bucketComponent(
        for range: StatsTimeRange,
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> Calendar.Component {
        let daySpan = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
        if daySpan == 0 {
            return .hour
        }

        return .day
    }

    static func floor(_ date: Date, component: Calendar.Component, calendar: Calendar) -> Date {
        switch component {
        case .hour:
            let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return calendar.date(from: parts) ?? date
        default:
            return calendar.startOfDay(for: date)
        }
    }

    static func aggregate(
        records: [UsageTrendRecord],
        component: Calendar.Component,
        calendar: Calendar,
        start: Date,
        end: Date
    ) -> [Date: TrendAggregate] {
        records.reduce(into: [Date: TrendAggregate]()) { result, record in
            let bucket = floor(record.timestamp, component: component, calendar: calendar)
            guard bucket >= start, bucket <= end else { return }
            result[bucket, default: TrendAggregate()].add(record)
        }
    }

    static func sampledIndices(count: Int, maxCount: Int) -> [Int] {
        guard count > maxCount, maxCount > 1 else {
            return Array(0..<count)
        }

        let step = Double(count - 1) / Double(maxCount - 1)
        var indices = (0..<maxCount).map { Int(round(Double($0) * step)) }
        indices[0] = 0
        indices[indices.count - 1] = count - 1
        return indices
    }

    static func axisLabelFormatter(for points: [UsageTrendPoint], calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")

        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }
}
