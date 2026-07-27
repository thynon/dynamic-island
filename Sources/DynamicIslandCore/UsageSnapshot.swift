import Foundation

public enum UsageInputTokenSemantics: Sendable {
    case fresh
    case includesCacheRead
    case includesCacheReadAndCreation
}

public struct UsageTokenCounts: Equatable, Sendable {
    public var freshInput: Int64
    public var output: Int64
    public var cacheCreation: Int64
    public var cacheRead: Int64

    public init(freshInput: Int64, output: Int64, cacheCreation: Int64, cacheRead: Int64) {
        self.freshInput = max(0, freshInput)
        self.output = max(0, output)
        self.cacheCreation = max(0, cacheCreation)
        self.cacheRead = max(0, cacheRead)
    }

    public var realTotal: Int64 {
        realTotalResult.value
    }

    fileprivate var realTotalResult: (value: Int64, overflow: Bool) {
        var total: Int64 = 0
        var overflow = false
        for value in [freshInput, output, cacheCreation, cacheRead] {
            let result = saturatedAdd(total, value)
            total = result.value
            overflow = overflow || result.overflow
        }
        return (total, overflow)
    }

    public static func normalized(
        input: Int64,
        output: Int64,
        cacheCreation: Int64,
        cacheRead: Int64,
        semantics: UsageInputTokenSemantics
    ) -> UsageTokenCounts {
        let boundedInput = max(0, input)
        let boundedOutput = max(0, output)
        let boundedRead = min(max(0, cacheRead), boundedInput)
        let remainingInput = boundedInput - boundedRead

        switch semantics {
        case .fresh:
            return UsageTokenCounts(
                freshInput: boundedInput,
                output: boundedOutput,
                cacheCreation: max(0, cacheCreation),
                cacheRead: max(0, cacheRead)
            )
        case .includesCacheRead:
            return UsageTokenCounts(
                freshInput: remainingInput,
                output: boundedOutput,
                cacheCreation: max(0, cacheCreation),
                cacheRead: boundedRead
            )
        case .includesCacheReadAndCreation:
            let boundedCreation = min(max(0, cacheCreation), remainingInput)
            return UsageTokenCounts(
                freshInput: remainingInput - boundedCreation,
                output: boundedOutput,
                cacheCreation: boundedCreation,
                cacheRead: boundedRead
            )
        }
    }
}

public struct UsageCumulativeCounters: Equatable, Sendable {
    public var input: Int64
    public var cachedInput: Int64
    public var output: Int64
    public var cacheCreation: Int64

    public init(input: Int64, cachedInput: Int64, output: Int64, cacheCreation: Int64) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
        self.cacheCreation = cacheCreation
    }

    public func delta(from previous: UsageCumulativeCounters?) -> UsageCumulativeCounters {
        guard let previous else {
            return UsageCumulativeCounters(
                input: max(0, input),
                cachedInput: max(0, cachedInput),
                output: max(0, output),
                cacheCreation: max(0, cacheCreation)
            )
        }

        return UsageCumulativeCounters(
            input: cumulativeDelta(current: input, previous: previous.input),
            cachedInput: cumulativeDelta(current: cachedInput, previous: previous.cachedInput),
            output: cumulativeDelta(current: output, previous: previous.output),
            cacheCreation: cumulativeDelta(current: cacheCreation, previous: previous.cacheCreation)
        )
    }

    public func normalizedCodexDelta() -> UsageTokenCounts? {
        let boundedInput = max(0, input)
        let boundedCachedInput = max(0, cachedInput)
        guard cacheCreation <= 0, boundedCachedInput <= boundedInput else { return nil }

        return UsageTokenCounts.normalized(
            input: boundedInput,
            output: max(0, output),
            cacheCreation: 0,
            cacheRead: boundedCachedInput,
            semantics: .includesCacheRead
        )
    }
}

public struct UsageEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let occurredAt: Date
    public let tokens: UsageTokenCounts
    public let requestCount: Int64
    public let estimatedCostUSD: Decimal?

    public init(id: String, occurredAt: Date, tokens: UsageTokenCounts, requestCount: Int64, estimatedCostUSD: Decimal?) {
        self.id = id
        self.occurredAt = occurredAt
        self.tokens = tokens
        self.requestCount = requestCount
        self.estimatedCostUSD = estimatedCostUSD
    }
}

public enum UsageWarningCategory: String, Hashable, Sendable {
    case codexStateUnavailable
    case codexRolloutUnreadable
    case codexRolloutConflict
    case codexRolloutChangedDuringRead
    case ccSwitchUnavailable
    case ccSwitchQueryFailed
    case unknownInputSemantics
    case insufficientCoverage
    case unpricedUsage
    case numericOverflow

    public var affectsTokenCompleteness: Bool { self != .unpricedUsage }
}

public struct UsageSourceBatch: Equatable, Sendable {
    public let entries: [UsageEntry]
    public let coverageStart: Date?
    public let coverageEnd: Date?
    public let warnings: Set<UsageWarningCategory>
    public let scannedFileCount: Int

    public init(
        entries: [UsageEntry],
        coverageStart: Date?,
        coverageEnd: Date?,
        warnings: Set<UsageWarningCategory>,
        scannedFileCount: Int
    ) {
        self.entries = entries
        self.coverageStart = coverageStart
        self.coverageEnd = coverageEnd
        self.warnings = warnings
        self.scannedFileCount = scannedFileCount
    }
}

public enum UsageSnapshotCompleteness: Equatable, Sendable {
    case complete
    case partial
}

public struct UsageSnapshot: Equatable, Sendable {
    public let tokens: UsageTokenCounts
    public let requestCount: Int64
    public let estimatedCostUSD: Decimal?
    public let coverageStart: Date?
    public let coverageEnd: Date?
    public let scannedFileCount: Int
    public let refreshedAt: Date
    public let queryWindow: UsageQueryWindow
    public let completeness: UsageSnapshotCompleteness
    public let warnings: Set<UsageWarningCategory>

    public init(
        tokens: UsageTokenCounts,
        requestCount: Int64,
        estimatedCostUSD: Decimal?,
        coverageStart: Date?,
        coverageEnd: Date?,
        scannedFileCount: Int,
        refreshedAt: Date,
        queryWindow: UsageQueryWindow,
        completeness: UsageSnapshotCompleteness,
        warnings: Set<UsageWarningCategory>
    ) {
        self.tokens = tokens
        self.requestCount = requestCount
        self.estimatedCostUSD = estimatedCostUSD
        self.coverageStart = coverageStart
        self.coverageEnd = coverageEnd
        self.scannedFileCount = scannedFileCount
        self.refreshedAt = refreshedAt
        self.queryWindow = queryWindow
        self.completeness = completeness
        self.warnings = warnings
    }

    public var cacheHitRate: Double? {
        let input = Double(tokens.freshInput) + Double(tokens.cacheCreation) + Double(tokens.cacheRead)
        guard input > 0 else { return nil }
        return Double(tokens.cacheRead) / input
    }
}

public enum UsagePresentationState: Equatable, Sendable {
    case idle
    case loading(previous: UsageSnapshot?)
    case available(UsageSnapshot)
    case empty(UsageSnapshot)
    case partial(UsageSnapshot)
    case failed(Set<UsageWarningCategory>)

    public var snapshot: UsageSnapshot? {
        switch self {
        case .loading(let previous): previous
        case .available(let snapshot), .empty(let snapshot), .partial(let snapshot): snapshot
        case .idle, .failed: nil
        }
    }
}

public enum UsageAggregator {
    public static func snapshot(
        batches: [UsageSourceBatch],
        window: UsageQueryWindow,
        refreshedAt: Date
    ) -> UsageSnapshot {
        var tokens = UsageTokenCounts(freshInput: 0, output: 0, cacheCreation: 0, cacheRead: 0)
        var requestCount: Int64 = 0
        var scannedFileCount = 0
        var coverageStart: Date?
        var coverageEnd: Date?
        var warnings = Set<UsageWarningCategory>()
        var acceptedEntries = [UsageEntry]()

        for batch in batches {
            warnings.formUnion(batch.warnings)
            if let batchStart = batch.coverageStart {
                coverageStart = min(coverageStart ?? batchStart, batchStart)
                if batchStart > window.startUTC {
                    warnings.insert(.insufficientCoverage)
                }
            }
            if let batchEnd = batch.coverageEnd {
                coverageEnd = max(coverageEnd ?? batchEnd, batchEnd)
            }

            let scannedResult = scannedFileCount.addingReportingOverflow(max(0, batch.scannedFileCount))
            scannedFileCount = scannedResult.overflow ? Int.max : scannedResult.partialValue
            if scannedResult.overflow {
                warnings.insert(.numericOverflow)
            }

            for entry in batch.entries where window.contains(entry.occurredAt) && entry.tokens.realTotal > 0 {
                acceptedEntries.append(entry)
                add(entry.tokens.freshInput, to: &tokens.freshInput, warnings: &warnings)
                add(entry.tokens.output, to: &tokens.output, warnings: &warnings)
                add(entry.tokens.cacheCreation, to: &tokens.cacheCreation, warnings: &warnings)
                add(entry.tokens.cacheRead, to: &tokens.cacheRead, warnings: &warnings)
                add(max(0, entry.requestCount), to: &requestCount, warnings: &warnings)
            }
        }

        if tokens.realTotalResult.overflow {
            warnings.insert(.numericOverflow)
        }

        let hasTokenCompletenessWarning = warnings.contains { $0.affectsTokenCompleteness }
        let hasUnpricedUsage = warnings.contains(.unpricedUsage)
        let estimatedCostUSD: Decimal?
        if acceptedEntries.isEmpty {
            estimatedCostUSD = hasTokenCompletenessWarning ? nil : .zero
        } else if hasTokenCompletenessWarning || hasUnpricedUsage || acceptedEntries.contains(where: { $0.estimatedCostUSD == nil }) {
            warnings.insert(.unpricedUsage)
            estimatedCostUSD = nil
        } else {
            estimatedCostUSD = acceptedEntries.reduce(Decimal.zero) { $0 + $1.estimatedCostUSD! }
        }

        return UsageSnapshot(
            tokens: tokens,
            requestCount: requestCount,
            estimatedCostUSD: estimatedCostUSD,
            coverageStart: coverageStart,
            coverageEnd: coverageEnd,
            scannedFileCount: scannedFileCount,
            refreshedAt: refreshedAt,
            queryWindow: window,
            completeness: hasTokenCompletenessWarning ? .partial : .complete,
            warnings: warnings
        )
    }
}

public enum UsageTokenFormatter {
    public static func exact(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    public static func compact(_ value: Int64) -> String {
        formatted(value, prefix: "", maximumFractionDigits: 1)
    }

    public static func approximate(_ value: Int64) -> String {
        formatted(value, prefix: "≈", maximumFractionDigits: 2)
    }

    private static func formatted(_ value: Int64, prefix: String, maximumFractionDigits: Int) -> String {
        let absolute = abs(Double(value))
        let unit: Double
        let suffix: String
        if absolute >= 100_000_000 {
            unit = 100_000_000
            suffix = "亿"
        } else if absolute >= 10_000 {
            unit = 10_000
            suffix = "万"
        } else {
            return prefix + exact(value)
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        let number = Double(value) / unit
        return prefix + (formatter.string(from: NSNumber(value: number)) ?? String(number)) + suffix
    }
}

private func cumulativeDelta(current: Int64, previous: Int64) -> Int64 {
    let boundedCurrent = max(0, current)
    let boundedPrevious = max(0, previous)
    return boundedCurrent >= boundedPrevious ? boundedCurrent - boundedPrevious : boundedCurrent
}

private func saturatedAdd(_ lhs: Int64, _ rhs: Int64) -> (value: Int64, overflow: Bool) {
    let result = lhs.addingReportingOverflow(rhs)
    return (result.overflow ? Int64.max : result.partialValue, result.overflow)
}

private func add(_ value: Int64, to total: inout Int64, warnings: inout Set<UsageWarningCategory>) {
    let result = saturatedAdd(total, value)
    total = result.value
    if result.overflow {
        warnings.insert(.numericOverflow)
    }
}
