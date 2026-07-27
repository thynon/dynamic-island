import Foundation
import DynamicIslandCore

actor CCSwitchUsageSource: UsageEntrySource {
    private let databaseURL: URL
    private let queryRunner: any SQLiteJSONQueryRunning

    init(
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cc-switch/cc-switch.db"),
        queryRunner: any SQLiteJSONQueryRunning = SystemSQLiteJSONQueryRunner()
    ) {
        self.databaseURL = databaseURL
        self.queryRunner = queryRunner
    }

    func load(in window: UsageQueryWindow) async throws -> UsageSourceBatch {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw UsageSourceFailure(warning: .ccSwitchUnavailable)
        }

        let data: Data
        do {
            data = try await queryRunner.query(databaseURL: databaseURL, sql: Self.query(in: window))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UsageSourceFailure(warning: .ccSwitchQueryFailed)
        }

        try Task.checkCancellation()
        do {
            return try Self.batch(from: data, in: window)
        } catch {
            throw UsageSourceFailure(warning: .ccSwitchQueryFailed)
        }
    }

    private static func query(in window: UsageQueryWindow) -> String {
        let start = epochLiteral(window.startUTC)
        let end = epochLiteral(window.endUTC)
        return """
        PRAGMA query_only=ON;
        BEGIN;
        SELECT
            'coverage' AS row_kind,
            NULL AS request_id,
            NULL AS app_type,
            NULL AS input_tokens,
            NULL AS output_tokens,
            NULL AS cache_read_tokens,
            NULL AS cache_creation_tokens,
            NULL AS total_cost_usd,
            NULL AS created_at,
            NULL AS input_token_semantics,
            MIN(created_at) AS coverage_start,
            MAX(created_at) AS coverage_end
        FROM proxy_request_logs
        WHERE lower(app_type) <> 'codex'
        UNION ALL
        SELECT
            'usage' AS row_kind,
            request_id,
            app_type,
            input_tokens,
            output_tokens,
            cache_read_tokens,
            cache_creation_tokens,
            CAST(total_cost_usd AS TEXT) AS total_cost_usd,
            created_at,
            input_token_semantics,
            NULL AS coverage_start,
            NULL AS coverage_end
        FROM proxy_request_logs
        WHERE lower(app_type) <> 'codex'
          AND created_at >= \(start)
          AND created_at < \(end)
        ORDER BY row_kind, created_at, request_id;
        COMMIT;
        """
    }

    private static func epochLiteral(_ date: Date) -> String {
        var value = String(
            format: "%.9f",
            locale: Locale(identifier: "en_US_POSIX"),
            date.timeIntervalSince1970
        )
        while value.last == "0" {
            value.removeLast()
        }
        if value.last == "." {
            value.removeLast()
        }
        return value
    }

    private static func batch(from data: Data, in window: UsageQueryWindow) throws -> UsageSourceBatch {
        let rows = try JSONDecoder().decode([QueryRow].self, from: data)
        let locale = Locale(identifier: "en_US_POSIX")
        var entries: [UsageEntry] = []
        var seenRequestIDs = Set<String>()
        var warnings = Set<UsageWarningCategory>()
        var coverageStart: Date?
        var coverageEnd: Date?

        for row in rows {
            if row.rowKind == "coverage" {
                coverageStart = row.coverageStart.map(Date.init(timeIntervalSince1970:))
                coverageEnd = row.coverageEnd.map(Date.init(timeIntervalSince1970:))
                continue
            }

            guard row.rowKind == "usage" else {
                warnings.insert(.ccSwitchQueryFailed)
                continue
            }
            guard row.has(.requestID),
                  row.has(.appType),
                  row.has(.inputTokens),
                  row.has(.outputTokens),
                  row.has(.cacheReadTokens),
                  row.has(.cacheCreationTokens),
                  row.has(.totalCostUSD),
                  row.has(.createdAt),
                  row.has(.inputTokenSemantics),
                  let rawRequestID = row.requestID,
                  let rawAppType = row.appType,
                  let input = row.inputTokens,
                  let output = row.outputTokens,
                  let cacheRead = row.cacheReadTokens,
                  let cacheCreation = row.cacheCreationTokens,
                  let createdAt = row.createdAt,
                  let inputSemantics = row.inputTokenSemantics else {
                warnings.insert(.ccSwitchQueryFailed)
                continue
            }

            let requestID = rawRequestID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !requestID.isEmpty else {
                warnings.insert(.ccSwitchQueryFailed)
                continue
            }
            let appType = rawAppType.lowercased()
            let occurredAt = Date(timeIntervalSince1970: createdAt)
            guard appType != "codex", window.contains(occurredAt) else { continue }

            guard input >= 0, output >= 0, cacheRead >= 0, cacheCreation >= 0 else {
                warnings.insert(.numericOverflow)
                continue
            }
            guard let semantics = semantics(for: appType, value: inputSemantics) else {
                warnings.insert(.unknownInputSemantics)
                continue
            }

            switch semantics {
            case .includesCacheRead:
                guard cacheRead <= input else {
                    warnings.insert(.numericOverflow)
                    continue
                }
            case .includesCacheReadAndCreation:
                let cacheTotal = cacheRead.addingReportingOverflow(cacheCreation)
                guard !cacheTotal.overflow, cacheTotal.partialValue <= input else {
                    warnings.insert(.numericOverflow)
                    continue
                }
            case .fresh:
                break
            }

            let tokens = UsageTokenCounts.normalized(
                input: input,
                output: output,
                cacheCreation: cacheCreation,
                cacheRead: cacheRead,
                semantics: semantics
            )
            guard exactTotal(of: tokens) != nil else {
                warnings.insert(.numericOverflow)
                continue
            }
            guard tokens.realTotal > 0 else { continue }
            guard seenRequestIDs.insert(requestID).inserted else { continue }

            let cost: Decimal?
            if let costText = row.totalCostUSD,
               let parsed = Decimal(string: costText, locale: locale),
               parsed > .zero {
                cost = parsed
            } else {
                cost = nil
                warnings.insert(.unpricedUsage)
            }

            entries.append(UsageEntry(
                id: requestID,
                occurredAt: occurredAt,
                tokens: tokens,
                requestCount: 1,
                estimatedCostUSD: cost
            ))
        }

        return UsageSourceBatch(
            entries: entries,
            coverageStart: coverageStart,
            coverageEnd: coverageEnd,
            warnings: warnings,
            scannedFileCount: 0
        )
    }

    private static func semantics(for appType: String, value: Int64) -> UsageInputTokenSemantics? {
        if value == 2 {
            return .fresh
        }
        if appType == "gemini" {
            switch value {
            case 0: return .includesCacheRead
            case 1: return .includesCacheReadAndCreation
            default: return nil
            }
        }
        if ["claude", "claude-desktop", "opencode"].contains(appType), value == 0 || value == 1 {
            return .fresh
        }
        return nil
    }

    private static func exactTotal(of tokens: UsageTokenCounts) -> Int64? {
        var total: Int64 = 0
        for value in [tokens.freshInput, tokens.output, tokens.cacheCreation, tokens.cacheRead] {
            let result = total.addingReportingOverflow(value)
            guard !result.overflow else { return nil }
            total = result.partialValue
        }
        return total
    }

    private struct QueryRow: Decodable {
        private let presentKeys: Set<String>
        let rowKind: String
        let requestID: String?
        let appType: String?
        let inputTokens: Int64?
        let outputTokens: Int64?
        let cacheReadTokens: Int64?
        let cacheCreationTokens: Int64?
        let totalCostUSD: String?
        let createdAt: Double?
        let inputTokenSemantics: Int64?
        let coverageStart: Double?
        let coverageEnd: Double?

        enum CodingKeys: String, CodingKey {
            case rowKind = "row_kind"
            case requestID = "request_id"
            case appType = "app_type"
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadTokens = "cache_read_tokens"
            case cacheCreationTokens = "cache_creation_tokens"
            case totalCostUSD = "total_cost_usd"
            case createdAt = "created_at"
            case inputTokenSemantics = "input_token_semantics"
            case coverageStart = "coverage_start"
            case coverageEnd = "coverage_end"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            presentKeys = Set(container.allKeys.map(\.stringValue))
            rowKind = try container.decode(String.self, forKey: .rowKind)
            requestID = try container.decodeIfPresent(String.self, forKey: .requestID)
            appType = try container.decodeIfPresent(String.self, forKey: .appType)
            inputTokens = try container.decodeIfPresent(Int64.self, forKey: .inputTokens)
            outputTokens = try container.decodeIfPresent(Int64.self, forKey: .outputTokens)
            cacheReadTokens = try container.decodeIfPresent(Int64.self, forKey: .cacheReadTokens)
            cacheCreationTokens = try container.decodeIfPresent(Int64.self, forKey: .cacheCreationTokens)
            totalCostUSD = try container.decodeIfPresent(String.self, forKey: .totalCostUSD)
            createdAt = try container.decodeIfPresent(Double.self, forKey: .createdAt)
            inputTokenSemantics = try container.decodeIfPresent(Int64.self, forKey: .inputTokenSemantics)
            coverageStart = try container.decodeIfPresent(Double.self, forKey: .coverageStart)
            coverageEnd = try container.decodeIfPresent(Double.self, forKey: .coverageEnd)
        }

        func has(_ key: CodingKeys) -> Bool {
            presentKeys.contains(key.stringValue)
        }
    }
}
