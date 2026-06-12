import Foundation

public struct CodexTokenUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
    public let reasoningOutputTokens: Int
    public let totalTokens: Int

    public init(
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        reasoningOutputTokens: Int,
        totalTokens: Int
    ) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }
}

public struct CodexUsageEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let usage: CodexTokenUsage
    public let model: String?

    public init(timestamp: Date, usage: CodexTokenUsage, model: String? = nil) {
        self.timestamp = timestamp
        self.usage = usage
        self.model = model
    }
}

public struct CodexSessionMetadata: Equatable, Sendable {
    public let id: String?
    public let model: String?

    public init(id: String?, model: String?) {
        self.id = id
        self.model = model
    }
}

public enum CodexSessionLogLine: Equatable, Sendable {
    case metadata(CodexSessionMetadata)
    case token(CodexUsageEvent)
}

public enum CodexSessionLogParser {
    private nonisolated(unsafe) static let fractionalTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let timestampFormatter = ISO8601DateFormatter()

    public static func parseLine(_ line: String) -> CodexSessionLogLine? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if containsStringValue("session_meta", forKey: "type", in: trimmed) {
            return .metadata(
                CodexSessionMetadata(
                    id: stringValue(forKey: "id", in: trimmed),
                    model: stringValue(forKey: "model", in: trimmed)
                        ?? stringValue(forKey: "model_provider", in: trimmed)
                )
            )
        }

        guard
            containsStringValue("token_count", forKey: "type", in: trimmed),
            let timestampText = stringValue(forKey: "timestamp", in: trimmed),
            let timestamp = parseTimestamp(timestampText),
            let usageObject = objectSubstring(forKey: "last_token_usage", in: trimmed)
        else {
            return nil
        }

        return .token(
            CodexUsageEvent(
                timestamp: timestamp,
                usage: CodexTokenUsage(
                    inputTokens: intValue(forKey: "input_tokens", in: usageObject) ?? 0,
                    cachedInputTokens: intValue(forKey: "cached_input_tokens", in: usageObject) ?? 0,
                    outputTokens: intValue(forKey: "output_tokens", in: usageObject) ?? 0,
                    reasoningOutputTokens: intValue(forKey: "reasoning_output_tokens", in: usageObject) ?? 0,
                    totalTokens: intValue(forKey: "total_tokens", in: usageObject) ?? 0
                )
            )
        )
    }

    private static func parseTimestamp(_ text: String) -> Date? {
        if let date = fractionalTimestampFormatter.date(from: text) {
            return date
        }

        return timestampFormatter.date(from: text)
    }

    private static func containsStringValue(_ expectedValue: String, forKey key: String, in text: String) -> Bool {
        let keyPattern = #"""# + key + #"""#
        var searchStart = text.startIndex

        while searchStart < text.endIndex,
              let keyRange = text[searchStart...].range(of: keyPattern) {
            if stringValue(after: keyRange.upperBound, in: text) == expectedValue {
                return true
            }
            searchStart = keyRange.upperBound
        }

        return false
    }

    private static func stringValue(forKey key: String, in text: String) -> String? {
        let keyPattern = #"""# + key + #"""#
        guard let keyRange = text.range(of: keyPattern) else {
            return nil
        }

        return stringValue(after: keyRange.upperBound, in: text)
    }

    private static func stringValue(after keyEndIndex: String.Index, in text: String) -> String? {
        guard let colonIndex = text[keyEndIndex...].firstIndex(of: ":") else {
            return nil
        }

        var valueStart = text.index(after: colonIndex)
        skipWhitespace(in: text, from: &valueStart)
        guard valueStart < text.endIndex, text[valueStart] == "\"" else {
            return nil
        }

        let stringStart = text.index(after: valueStart)
        var current = stringStart
        var hasEscape = false

        while current < text.endIndex {
            let character = text[current]
            if character == "\\" {
                hasEscape = true
                current = text.index(after: current)
                if current < text.endIndex {
                    current = text.index(after: current)
                }
                continue
            }

            if character == "\"" {
                let rawValue = text[stringStart..<current]
                guard hasEscape else {
                    return String(rawValue)
                }

                return unescapedJSONString(rawValue)
            }

            current = text.index(after: current)
        }

        return nil
    }

    private static func intValue(forKey key: String, in text: Substring) -> Int? {
        let keyPattern = #"""# + key + #"""#
        guard let keyRange = text.range(of: keyPattern),
              let colonIndex = text[keyRange.upperBound...].firstIndex(of: ":")
        else {
            return nil
        }

        var valueStart = text.index(after: colonIndex)
        skipWhitespace(in: text, from: &valueStart)

        var valueEnd = valueStart
        if valueEnd < text.endIndex, text[valueEnd] == "-" {
            valueEnd = text.index(after: valueEnd)
        }

        while valueEnd < text.endIndex, text[valueEnd].isNumber {
            valueEnd = text.index(after: valueEnd)
        }

        guard valueEnd > valueStart else {
            return nil
        }

        return Int(text[valueStart..<valueEnd])
    }

    private static func objectSubstring(forKey key: String, in text: String) -> Substring? {
        let keyPattern = #"""# + key + #"""#
        guard let keyRange = text.range(of: keyPattern),
              let openingBrace = text[keyRange.upperBound...].firstIndex(of: "{")
        else {
            return nil
        }

        var current = openingBrace
        var depth = 0

        while current < text.endIndex {
            let character = text[current]

            if character == "\"" {
                current = indexAfterJSONString(startingAt: current, in: text) ?? text.index(after: current)
                continue
            }

            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return text[openingBrace...current]
                }
            }

            current = text.index(after: current)
        }

        return nil
    }

    private static func indexAfterJSONString(startingAt quoteIndex: String.Index, in text: String) -> String.Index? {
        guard quoteIndex < text.endIndex, text[quoteIndex] == "\"" else {
            return nil
        }

        var current = text.index(after: quoteIndex)
        while current < text.endIndex {
            let character = text[current]
            if character == "\\" {
                current = text.index(after: current)
                if current < text.endIndex {
                    current = text.index(after: current)
                }
                continue
            }

            if character == "\"" {
                return text.index(after: current)
            }

            current = text.index(after: current)
        }

        return nil
    }

    private static func skipWhitespace<T: StringProtocol>(in text: T, from index: inout T.Index) {
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
    }

    private static func unescapedJSONString(_ value: Substring) -> String? {
        let wrapped = "\"" + String(value) + "\""
        guard let data = wrapped.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(String.self, from: data)
    }
}

public struct CodexUsageCostEstimator: Equatable, Sendable {
    public let inputPerMillion: Double
    public let cachedInputPerMillion: Double
    public let outputPerMillion: Double

    public static let zero = CodexUsageCostEstimator(
        inputPerMillion: 0,
        cachedInputPerMillion: 0,
        outputPerMillion: 0
    )

    public static let localEstimate = CodexUsageCostEstimator(
        inputPerMillion: 1.25,
        cachedInputPerMillion: 0.125,
        outputPerMillion: 10
    )

    public init(inputPerMillion: Double, cachedInputPerMillion: Double, outputPerMillion: Double) {
        self.inputPerMillion = inputPerMillion
        self.cachedInputPerMillion = cachedInputPerMillion
        self.outputPerMillion = outputPerMillion
    }

    public func estimate(_ usage: CodexTokenUsage) -> Double {
        let uncachedInput = max(0, usage.inputTokens - usage.cachedInputTokens)
        return (Double(uncachedInput) / 1_000_000 * inputPerMillion)
            + (Double(usage.cachedInputTokens) / 1_000_000 * cachedInputPerMillion)
            + (Double(usage.outputTokens) / 1_000_000 * outputPerMillion)
    }
}

public struct CodexDailyUsage: Equatable, Identifiable, Sendable {
    public let id: Date
    public let date: Date
    public let tokens: Double
    public let cost: Double
    public let requests: Double

    public init(date: Date, tokens: Double, cost: Double, requests: Double) {
        self.id = date
        self.date = date
        self.tokens = tokens
        self.cost = cost
        self.requests = requests
    }
}

public struct CodexUsageSummary: Equatable, Sendable {
    public let events: [CodexUsageEvent]
    public let totalTokens: Int
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
    public let reasoningOutputTokens: Int
    public let requestCount: Int
    public let activeDayCount: Int
    public let estimatedCost: Double
    public let favoriteModel: String
    public let trendPoints: [CodexDailyUsage]
    public let trendRecords: [UsageTrendRecord]
    public let heatmapRecords: [UsageHeatmapRecord]

    public static let empty = CodexUsageSummary(
        events: [],
        totalTokens: 0,
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        reasoningOutputTokens: 0,
        requestCount: 0,
        activeDayCount: 0,
        estimatedCost: 0,
        favoriteModel: "Codex",
        trendPoints: [],
        trendRecords: [],
        heatmapRecords: []
    )

    public static func build(
        events: [CodexUsageEvent],
        calendar inputCalendar: Calendar,
        costEstimator: CodexUsageCostEstimator = .localEstimate
    ) -> CodexUsageSummary {
        var calendar = inputCalendar
        calendar.timeZone = inputCalendar.timeZone
        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }

        var totals = CodexTokenUsage(
            inputTokens: 0,
            cachedInputTokens: 0,
            outputTokens: 0,
            reasoningOutputTokens: 0,
            totalTokens: 0
        )
        var cost = 0.0
        var daily = [Date: CodexDailyAccumulator]()
        var trendRecords: [UsageTrendRecord] = []
        var modelCounts = [String: Int]()

        for event in sortedEvents {
            totals = totals.adding(event.usage)
            let estimatedCost = costEstimator.estimate(event.usage)
            cost += estimatedCost
            trendRecords.append(
                UsageTrendRecord(
                    timestamp: event.timestamp,
                    tokens: Double(event.usage.totalTokens),
                    cost: estimatedCost,
                    requests: 1
                )
            )

            let day = calendar.startOfDay(for: event.timestamp)
            daily[day, default: CodexDailyAccumulator()].add(event.usage, cost: estimatedCost)

            if let model = event.model, !model.isEmpty, model != "custom" {
                modelCounts[model, default: 0] += 1
            }
        }

        let trendPoints = daily.keys.sorted().map { date in
            let usage = daily[date] ?? CodexDailyAccumulator()
            return CodexDailyUsage(
                date: date,
                tokens: Double(usage.tokens),
                cost: usage.cost,
                requests: Double(usage.requests)
            )
        }

        let favoriteModel = modelCounts.max { lhs, rhs in
            lhs.value < rhs.value
        }?.key ?? "Codex"

        return CodexUsageSummary(
            events: sortedEvents,
            totalTokens: totals.totalTokens,
            inputTokens: totals.inputTokens,
            cachedInputTokens: totals.cachedInputTokens,
            outputTokens: totals.outputTokens,
            reasoningOutputTokens: totals.reasoningOutputTokens,
            requestCount: events.count,
            activeDayCount: daily.count,
            estimatedCost: cost,
            favoriteModel: favoriteModel,
            trendPoints: trendPoints,
            trendRecords: trendRecords.sorted { $0.timestamp < $1.timestamp },
            heatmapRecords: trendPoints.map { point in
                UsageHeatmapRecord(
                    date: point.date,
                    tokens: point.tokens,
                    cost: point.cost,
                    requests: point.requests
                )
            }
        )
    }

    public func filtered(
        range: StatsTimeRange,
        today: Date,
        calendar inputCalendar: Calendar,
        costEstimator: CodexUsageCostEstimator = .localEstimate
    ) -> CodexUsageSummary {
        var calendar = inputCalendar
        calendar.timeZone = inputCalendar.timeZone
        let start = range.startDate(today: today, calendar: calendar)
        let end = today
        let filteredEvents = events.filter { event in
            event.timestamp >= start && event.timestamp <= end
        }

        return CodexUsageSummary.build(
            events: filteredEvents,
            calendar: calendar,
            costEstimator: costEstimator
        )
    }
}

private struct CodexDailyAccumulator {
    var tokens: Int = 0
    var cost: Double = 0
    var requests: Int = 0

    mutating func add(_ usage: CodexTokenUsage, cost estimatedCost: Double) {
        tokens += usage.totalTokens
        cost += estimatedCost
        requests += 1
    }
}

private extension CodexTokenUsage {
    func adding(_ other: CodexTokenUsage) -> CodexTokenUsage {
        CodexTokenUsage(
            inputTokens: inputTokens + other.inputTokens,
            cachedInputTokens: cachedInputTokens + other.cachedInputTokens,
            outputTokens: outputTokens + other.outputTokens,
            reasoningOutputTokens: reasoningOutputTokens + other.reasoningOutputTokens,
            totalTokens: totalTokens + other.totalTokens
        )
    }
}
