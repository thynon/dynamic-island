import Foundation
import IslandCore
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum CCSwitchUsageDataSource {
    private static let sessionProxyDedupWindowSeconds = 10 * 60
    private static let cacheInclusiveAppTypes = ["codex", "gemini"]

    static let defaultDatabaseURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".cc-switch/cc-switch.db")

    static func loadSummary(
        databaseURL: URL = Self.defaultDatabaseURL,
        calendar: Calendar = .autoupdatingCurrent,
        appType: String? = nil
    ) async -> CodexUsageSummary? {
        await Task.detached(priority: .utility) {
            loadSummarySync(databaseURL: databaseURL, calendar: calendar, appType: appType)
        }.value
    }

    private static func loadSummarySync(
        databaseURL: URL,
        calendar: Calendar,
        appType: String?
    ) -> CodexUsageSummary? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return nil
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database
        else {
            return nil
        }
        defer {
            sqlite3_close(database)
        }

        let earliestDate = StatsTimeRange.all.startDate(today: Date(), calendar: calendar)
        let earliestTimestamp = Int64(earliestDate.timeIntervalSince1970)
        var events: [CodexUsageEvent] = []
        events.append(contentsOf: loadRequestLogEvents(database: database, appType: appType, earliestTimestamp: earliestTimestamp))

        guard !events.isEmpty else {
            return nil
        }

        return CodexUsageSummary.build(events: events, calendar: calendar)
    }

    private static func loadRequestLogEvents(
        database: OpaquePointer,
        appType: String?,
        earliestTimestamp: Int64
    ) -> [CodexUsageEvent] {
        let effectiveFilter = effectiveUsageLogFilter(logAlias: "l")
        let freshInput = freshInputSQL(alias: "l")
        let sql = """
        SELECT l.created_at, COALESCE(NULLIF(l.model, ''), NULLIF(l.request_model, ''), 'Codex') AS display_model,
               l.app_type, \(freshInput) AS fresh_input_tokens, l.cache_read_tokens, l.cache_creation_tokens,
               l.output_tokens, l.total_cost_usd
        FROM proxy_request_logs l
        WHERE (?1 IS NULL OR \(foldedAppTypeSQL(column: "l.app_type")) = ?1)
          AND l.created_at >= ?2
          AND \(effectiveFilter)
        ORDER BY created_at ASC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return []
        }
        defer {
            sqlite3_finalize(statement)
        }

        if let appType {
            sqlite3_bind_text(statement, 1, appType, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 1)
        }
        sqlite3_bind_int64(statement, 2, earliestTimestamp)

        var events: [CodexUsageEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let timestamp = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 0)))
            let model = textColumn(statement, 1) ?? "Codex"
            let appType = textColumn(statement, 2) ?? ""
            let freshInputTokens = intColumn(statement, 3)
            let cachedInputTokens = intColumn(statement, 4)
            let cacheCreationTokens = intColumn(statement, 5)
            let outputTokens = intColumn(statement, 6)
            let cost = doubleTextColumn(statement, 7)
            let realTotalTokens = realTotalTokens(
                appType: appType,
                freshInputTokens: freshInputTokens,
                cachedInputTokens: cachedInputTokens,
                cacheCreationTokens: cacheCreationTokens,
                outputTokens: outputTokens
            )

            events.append(
                CodexUsageEvent(
                    timestamp: timestamp,
                    usage: CodexTokenUsage(
                        inputTokens: freshInputTokens + cachedInputTokens,
                        cachedInputTokens: cachedInputTokens,
                        outputTokens: outputTokens,
                        reasoningOutputTokens: cacheCreationTokens,
                        totalTokens: realTotalTokens
                    ),
                    model: model,
                    costUSD: cost
                )
            )
        }

        return events
    }

    private static func textColumn(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    private static func intColumn(_ statement: OpaquePointer, _ index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    private static func doubleTextColumn(_ statement: OpaquePointer, _ index: Int32) -> Double {
        guard let text = textColumn(statement, index) else {
            return 0
        }
        return Double(text) ?? 0
    }

    private static func realTotalTokens(
        appType: String,
        freshInputTokens: Int,
        cachedInputTokens: Int,
        cacheCreationTokens: Int,
        outputTokens: Int
    ) -> Int {
        freshInputTokens + outputTokens + cacheCreationTokens + cachedInputTokens
    }

    private static func freshInputSQL(alias: String) -> String {
        let prefix = alias.isEmpty ? "" : "\(alias)."
        let appTypeList = cacheInclusiveAppTypes.map { "'\($0)'" }.joined(separator: ", ")
        return """
        CASE WHEN \(prefix)app_type IN (\(appTypeList)) AND \(prefix)input_tokens >= \(prefix)cache_read_tokens \
        THEN (\(prefix)input_tokens - \(prefix)cache_read_tokens) \
        ELSE \(prefix)input_tokens END
        """
    }

    private static func dataSourceExpr(logAlias: String) -> String {
        "COALESCE(\(logAlias).data_source, 'proxy')"
    }

    private static func foldedAppTypeSQL(column: String) -> String {
        "CASE WHEN \(column) = 'claude-desktop' THEN 'claude' ELSE \(column) END"
    }

    private static func effectiveUsageLogFilter(logAlias: String) -> String {
        let dataSource = dataSourceExpr(logAlias: logAlias)
        let proxyDataSource = dataSourceExpr(logAlias: "proxy_dedup")
        return """
        NOT (
            \(dataSource) IN ('session_log', 'codex_session', 'gemini_session', 'opencode_session')
            AND EXISTS (
                SELECT 1
                FROM proxy_request_logs proxy_dedup
                WHERE \(proxyDataSource) = 'proxy'
                  AND proxy_dedup.app_type = \(logAlias).app_type
                  AND proxy_dedup.status_code >= 200
                  AND proxy_dedup.status_code < 300
                  AND proxy_dedup.input_tokens = \(logAlias).input_tokens
                  AND proxy_dedup.output_tokens = \(logAlias).output_tokens
                  AND proxy_dedup.cache_read_tokens = \(logAlias).cache_read_tokens
                  AND (
                      proxy_dedup.cache_creation_tokens = \(logAlias).cache_creation_tokens
                      OR (
                          \(logAlias).cache_creation_tokens = 0
                          AND \(dataSource) IN ('codex_session', 'gemini_session', 'opencode_session')
                      )
                  )
                  AND proxy_dedup.created_at BETWEEN
                      \(logAlias).created_at - \(sessionProxyDedupWindowSeconds)
                      AND \(logAlias).created_at + \(sessionProxyDedupWindowSeconds)
                  AND (
                      LOWER(proxy_dedup.model) = LOWER(\(logAlias).model)
                      OR LOWER(proxy_dedup.model) = 'unknown'
                      OR LOWER(\(logAlias).model) = 'unknown'
                  )
            )
        )
        """
    }
}
