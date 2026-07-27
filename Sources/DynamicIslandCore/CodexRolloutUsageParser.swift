import Foundation

public struct CodexCumulativeUsageSample: Equatable, Sendable {
    public let occurredAt: Date
    public let counters: UsageCumulativeCounters
    public let endingByteOffset: Int64
    public let startsNewBaseline: Bool
}

public struct CodexRolloutWindowResult: Equatable, Sendable {
    public let entries: [UsageEntry]
    public let warnings: Set<UsageWarningCategory>
}

public struct CodexRolloutParseResult: Equatable, Sendable {
    public let threadID: String
    public let samples: [CodexCumulativeUsageSample]
    public let firstTokenEventAt: Date?
    public let lastTokenEventAt: Date?
    public let lastCumulativeCounters: UsageCumulativeCounters?
    public let completeByteCount: Int64
    public let tokenEventFingerprint: UInt64
    public let warnings: Set<UsageWarningCategory>

    public func entries(in window: UsageQueryWindow) -> CodexRolloutWindowResult {
        var previous: UsageCumulativeCounters?
        var entries = [UsageEntry]()
        var windowWarnings = warnings

        for sample in samples {
            if sample.startsNewBaseline {
                previous = sample.counters
                continue
            }

            let delta = sample.counters.delta(from: previous)
            previous = sample.counters

            guard window.contains(sample.occurredAt) else { continue }
            guard let tokens = delta.normalizedCodexDelta() else {
                windowWarnings.insert(.codexRolloutUnreadable)
                continue
            }
            guard tokens.realTotal > 0 else { continue }

            entries.append(UsageEntry(
                id: "\(threadID):\(sample.endingByteOffset)",
                occurredAt: sample.occurredAt,
                tokens: tokens,
                requestCount: 1,
                estimatedCostUSD: nil
            ))
        }

        return CodexRolloutWindowResult(entries: entries, warnings: windowWarnings)
    }
}

public struct CodexRolloutUsageParser: Sendable {
    private let threadID: String
    private var samples = [CodexCumulativeUsageSample]()
    private var firstTokenEventAt: Date?
    private var lastTokenEventAt: Date?
    private var lastCumulativeCounters: UsageCumulativeCounters?
    private var tokenEventFingerprint: UInt64 = 14_695_981_039_346_656_037
    private var warnings = Set<UsageWarningCategory>()
    private var nextSampleStartsNewBaseline = false
    private var hasPendingInitialEmptyTokenEvent = false

    public init(threadID: String) {
        self.threadID = threadID
    }

    public mutating func consumeCompleteLine(
        _ line: Data,
        endingByteOffset: Int64
    ) {
        guard containsStructuredTokenCountType(in: line) else { return }

        guard let event = try? JSONDecoder().decode(CodexRolloutEvent.self, from: line) else {
            updateFingerprint(with: line)
            markUnreadableTokenEvent()
            return
        }
        guard event.type == "event_msg",
              let payload = event.payload,
              payload.type == "token_count" else { return }
        updateFingerprint(with: line)
        guard let timestamp = event.timestamp,
              let occurredAt = parseISO8601Timestamp(timestamp) else {
            markUnreadableTokenEvent()
            return
        }
        guard let usage = payload.info?.totalTokenUsage else {
            if payload.isInfoExplicitlyNull,
               samples.isEmpty,
               !hasPendingInitialEmptyTokenEvent,
               !nextSampleStartsNewBaseline,
               !warnings.contains(.codexRolloutUnreadable) {
                hasPendingInitialEmptyTokenEvent = true
            } else {
                markUnreadableTokenEvent()
            }
            return
        }
        guard let input = usage.inputTokens,
              let output = usage.outputTokens else {
            markUnreadableTokenEvent()
            return
        }

        let cachedInput = usage.cachedInputTokens ?? 0
        let reasoningOutput = usage.reasoningOutputTokens ?? 0
        let cacheCreation = usage.cacheCreationInputTokens ?? 0
        guard input >= 0, cachedInput >= 0, output >= 0, reasoningOutput >= 0, cacheCreation >= 0 else {
            markUnreadableTokenEvent()
            return
        }

        if hasPendingInitialEmptyTokenEvent {
            hasPendingInitialEmptyTokenEvent = false
            guard usage.cachedInputTokens != nil,
                  usage.reasoningOutputTokens != nil else {
                markUnreadableTokenEvent()
                return
            }
            if input != 0 || cachedInput != 0 || output != 0 || reasoningOutput != 0 || cacheCreation != 0 {
                markUnreadableTokenEvent()
            }
        }

        let counters = UsageCumulativeCounters(
            input: input,
            cachedInput: cachedInput,
            output: output,
            cacheCreation: cacheCreation
        )
        samples.append(CodexCumulativeUsageSample(
            occurredAt: occurredAt,
            counters: counters,
            endingByteOffset: endingByteOffset,
            startsNewBaseline: nextSampleStartsNewBaseline
        ))
        nextSampleStartsNewBaseline = false
        firstTokenEventAt = firstTokenEventAt ?? occurredAt
        lastTokenEventAt = occurredAt
        lastCumulativeCounters = counters

        if cacheCreation > 0 {
            warnings.insert(.codexRolloutUnreadable)
        }
    }

    public func finish(completeByteCount: Int64) -> CodexRolloutParseResult {
        var finalWarnings = warnings
        if hasPendingInitialEmptyTokenEvent {
            finalWarnings.insert(.codexRolloutUnreadable)
        }
        return CodexRolloutParseResult(
            threadID: threadID,
            samples: samples,
            firstTokenEventAt: firstTokenEventAt,
            lastTokenEventAt: lastTokenEventAt,
            lastCumulativeCounters: lastCumulativeCounters,
            completeByteCount: completeByteCount,
            tokenEventFingerprint: tokenEventFingerprint,
            warnings: finalWarnings
        )
    }

    private mutating func markUnreadableTokenEvent() {
        hasPendingInitialEmptyTokenEvent = false
        warnings.insert(.codexRolloutUnreadable)
        nextSampleStartsNewBaseline = true
    }

    private mutating func updateFingerprint(with line: Data) {
        for byte in line {
            tokenEventFingerprint ^= UInt64(byte)
            tokenEventFingerprint = tokenEventFingerprint &* 1_099_511_628_211
        }
    }
}

private let jsonTypeKey: [UInt8] = [0x22, 0x74, 0x79, 0x70, 0x65, 0x22]
private let jsonTokenCountValue: [UInt8] = [0x22, 0x74, 0x6f, 0x6b, 0x65, 0x6e, 0x5f, 0x63, 0x6f, 0x75, 0x6e, 0x74, 0x22]

private func containsStructuredTokenCountType(in line: Data) -> Bool {
    line.withUnsafeBytes { rawBuffer in
        let bytes = rawBuffer.bindMemory(to: UInt8.self)
        guard bytes.count >= jsonTypeKey.count + 1 + jsonTokenCountValue.count else { return false }

        var keyStart = 0
        while keyStart + jsonTypeKey.count <= bytes.count {
            guard
                matches(jsonTypeKey, in: bytes, at: keyStart),
                isJSONObjectKeyStart(keyStart, in: bytes)
            else {
                keyStart += 1
                continue
            }

            var cursor = keyStart + jsonTypeKey.count
            skipJSONWhitespace(in: bytes, cursor: &cursor)
            guard cursor < bytes.count, bytes[cursor] == 0x3a else {
                keyStart += 1
                continue
            }
            cursor += 1
            skipJSONWhitespace(in: bytes, cursor: &cursor)
            if matches(jsonTokenCountValue, in: bytes, at: cursor) {
                return true
            }
            keyStart += 1
        }

        return false
    }
}

private func matches(
    _ pattern: [UInt8],
    in bytes: UnsafeBufferPointer<UInt8>,
    at start: Int
) -> Bool {
    guard start >= 0, start + pattern.count <= bytes.count else { return false }
    for index in pattern.indices where bytes[start + index] != pattern[index] {
        return false
    }
    return true
}

private func isJSONObjectKeyStart(
    _ keyStart: Int,
    in bytes: UnsafeBufferPointer<UInt8>
) -> Bool {
    var cursor = keyStart
    while cursor > 0 {
        cursor -= 1
        if isJSONWhitespace(bytes[cursor]) {
            continue
        }
        return bytes[cursor] == 0x7b || bytes[cursor] == 0x2c
    }
    return false
}

private func skipJSONWhitespace(
    in bytes: UnsafeBufferPointer<UInt8>,
    cursor: inout Int
) {
    while cursor < bytes.count, isJSONWhitespace(bytes[cursor]) {
        cursor += 1
    }
}

private func isJSONWhitespace(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d
}

private struct CodexRolloutEvent: Decodable {
    let timestamp: String?
    let type: String?
    let payload: Payload?

    struct Payload: Decodable {
        let type: String?
        let info: Info?
        let isInfoExplicitlyNull: Bool

        enum CodingKeys: String, CodingKey {
            case type
            case info
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decodeIfPresent(String.self, forKey: .type)
            if container.contains(.info) {
                isInfoExplicitlyNull = try container.decodeNil(forKey: .info)
            } else {
                isInfoExplicitlyNull = false
            }
            info = try container.decodeIfPresent(Info.self, forKey: .info)
        }
    }

    struct Info: Decodable {
        let totalTokenUsage: TotalTokenUsage?

        enum CodingKeys: String, CodingKey {
            case totalTokenUsage = "total_token_usage"
        }
    }

    struct TotalTokenUsage: Decodable {
        let inputTokens: Int64?
        let cachedInputTokens: Int64?
        let outputTokens: Int64?
        let reasoningOutputTokens: Int64?
        let cacheCreationInputTokens: Int64?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case outputTokens = "output_tokens"
            case reasoningOutputTokens = "reasoning_output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
        }
    }
}

private func parseISO8601Timestamp(_ value: String) -> Date? {
    guard isStrictInternetDateTime(value) else { return nil }

    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractionalFormatter.date(from: value) {
        return date
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

private func isStrictInternetDateTime(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard bytes.count >= 20 else { return false }
    guard
        bytes[4] == 0x2d,
        bytes[7] == 0x2d,
        bytes[10] == 0x54,
        bytes[13] == 0x3a,
        bytes[16] == 0x3a,
        let year = decimalValue(in: bytes, range: 0..<4),
        let month = decimalValue(in: bytes, range: 5..<7),
        let day = decimalValue(in: bytes, range: 8..<10),
        let hour = decimalValue(in: bytes, range: 11..<13),
        let minute = decimalValue(in: bytes, range: 14..<16),
        let second = decimalValue(in: bytes, range: 17..<19),
        year >= 1,
        (1...12).contains(month),
        day >= 1,
        day <= daysInGregorianMonth(year: year, month: month),
        (0...23).contains(hour),
        (0...59).contains(minute),
        (0...59).contains(second)
    else {
        return false
    }

    var cursor = 19
    if cursor < bytes.count, bytes[cursor] == 0x2e {
        cursor += 1
        let fractionStart = cursor
        while cursor < bytes.count, isASCIIDigit(bytes[cursor]) {
            cursor += 1
        }
        guard cursor > fractionStart else { return false }
    }

    if cursor + 1 == bytes.count, bytes[cursor] == 0x5a {
        return true
    }

    guard
        cursor + 6 == bytes.count,
        bytes[cursor] == 0x2b || bytes[cursor] == 0x2d,
        bytes[cursor + 3] == 0x3a,
        let offsetHour = decimalValue(in: bytes, range: (cursor + 1)..<(cursor + 3)),
        let offsetMinute = decimalValue(in: bytes, range: (cursor + 4)..<(cursor + 6)),
        (0...23).contains(offsetHour),
        (0...59).contains(offsetMinute)
    else {
        return false
    }
    return true
}

private func decimalValue(in bytes: [UInt8], range: Range<Int>) -> Int? {
    guard range.lowerBound >= 0, range.upperBound <= bytes.count else { return nil }
    var value = 0
    for index in range {
        guard isASCIIDigit(bytes[index]) else { return nil }
        value = value * 10 + Int(bytes[index] - 0x30)
    }
    return value
}

private func isASCIIDigit(_ byte: UInt8) -> Bool {
    byte >= 0x30 && byte <= 0x39
}

private func daysInGregorianMonth(year: Int, month: Int) -> Int {
    switch month {
    case 2:
        let isLeapYear = year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
        return isLeapYear ? 29 : 28
    case 4, 6, 9, 11:
        return 30
    default:
        return 31
    }
}
