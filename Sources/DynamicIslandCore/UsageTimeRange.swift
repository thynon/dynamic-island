import Foundation

public enum UsageTimeRange: String, CaseIterable, Identifiable, Sendable {
    case today
    case threeDays
    case sevenDays
    case thirtyDays

    public var id: String { rawValue }

    public var dayCount: Int {
        switch self {
        case .today: 1
        case .threeDays: 3
        case .sevenDays: 7
        case .thirtyDays: 30
        }
    }

    public var displayName: String {
        switch self {
        case .today: "今日"
        case .threeDays: "3天"
        case .sevenDays: "一周"
        case .thirtyDays: "30天"
        }
    }

    public func queryWindow(now: Date, timeZone: TimeZone) -> UsageQueryWindow {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let todayStart = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: todayStart) ?? todayStart

        return UsageQueryWindow(
            range: self,
            startUTC: start,
            endUTC: now,
            timeZoneIdentifier: timeZone.identifier
        )
    }
}

public struct UsageQueryWindow: Equatable, Sendable {
    public let range: UsageTimeRange
    public let startUTC: Date
    public let endUTC: Date
    public let timeZoneIdentifier: String

    public init(range: UsageTimeRange, startUTC: Date, endUTC: Date, timeZoneIdentifier: String) {
        self.range = range
        self.startUTC = startUTC
        self.endUTC = endUTC
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public func contains(_ date: Date) -> Bool {
        date >= startUTC && date < endUTC
    }
}
