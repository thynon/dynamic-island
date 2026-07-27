import Foundation
import DynamicIslandCore

private enum FakeSQLiteRunnerError: Error, Sendable {
    case noResponse
}

private actor FakeSQLiteJSONQueryRunner: SQLiteJSONQueryRunning {
    var responses: [Data]
    private let failure: SQLiteJSONQueryError?
    private let cancellation: Bool
    private(set) var invocations: [(URL, String)] = []

    init(
        responses: [Data] = [],
        failure: SQLiteJSONQueryError? = nil,
        cancellation: Bool = false
    ) {
        self.responses = responses
        self.failure = failure
        self.cancellation = cancellation
    }

    func query(databaseURL: URL, sql: String) async throws -> Data {
        invocations.append((databaseURL, sql))
        if cancellation {
            throw CancellationError()
        }
        if let failure {
            throw failure
        }
        guard !responses.isEmpty else {
            throw FakeSQLiteRunnerError.noResponse
        }
        return responses.removeFirst()
    }
}

private actor ControlledUsageSource: UsageEntrySource {
    enum Result: Sendable {
        case success(UsageSourceBatch)
        case failure(UsageWarningCategory)
        case cancelled
    }

    private var continuation: CheckedContinuation<UsageSourceBatch, Error>?
    private var started = false

    func load(in window: UsageQueryWindow) async throws -> UsageSourceBatch {
        try await withCheckedThrowingContinuation { continuation in
            precondition(self.continuation == nil)
            self.continuation = continuation
            started = true
        }
    }

    func hasStarted() -> Bool {
        started
    }

    func resume(with result: Result) {
        guard let continuation else {
            preconditionFailure("controlled source resumed before load")
        }
        self.continuation = nil
        switch result {
        case .success(let batch):
            continuation.resume(returning: batch)
        case .failure(let warning):
            continuation.resume(throwing: UsageSourceFailure(warning: warning))
        case .cancelled:
            continuation.resume(throwing: CancellationError())
        }
    }
}

private actor UsagePublicationRecorder {
    private var generation = 0
    private var range: UsageTimeRange = .today
    private var snapshot: UsageSnapshot?

    func select(generation: Int, range: UsageTimeRange) {
        self.generation = generation
        self.range = range
    }

    func publish(
        _ outcome: UsageAggregationOutcome,
        identity: UsageRefreshRequestIdentity,
        isCancelled: Bool
    ) {
        guard identity.permitsPublication(
            currentGeneration: generation,
            currentRange: range,
            isCancelled: isCancelled
        ), case .snapshot(let snapshot) = outcome else { return }
        self.snapshot = snapshot
    }

    func publishedSnapshot() -> UsageSnapshot? {
        snapshot
    }
}

private final class CodexReadHookRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var attempts: [(URL, Int)] = []
    var onAttempt: ((URL, Int) -> Void)?

    func hook() -> CodexUsageSourceHooks {
        CodexUsageSourceHooks(didFinishReadAttempt: { [weak self] url, attempt in
            guard let self else { return }
            self.lock.lock()
            self.attempts.append((url, attempt))
            let callback = self.onAttempt
            self.lock.unlock()
            callback?(url, attempt)
        })
    }

}

private final class CodexOneShotAppendHook: @unchecked Sendable {
    private let lock = NSLock()
    private let targetURL: URL
    private let appendedLine: String
    private let triggerAttempt: Int
    private var attempt = 0

    init(targetURL: URL, appendedLine: String, triggerAttempt: Int = 1) {
        self.targetURL = targetURL.resolvingSymlinksInPath()
        self.appendedLine = appendedLine
        self.triggerAttempt = triggerAttempt
    }

    func hook() -> CodexUsageSourceHooks {
        CodexUsageSourceHooks(shouldFailRead: { [weak self] url in
            self?.interceptRead(of: url) ?? false
        })
    }

    private func interceptRead(of url: URL) -> Bool {
        guard url.resolvingSymlinksInPath() == targetURL else { return false }
        lock.lock()
        attempt += 1
        let shouldAppend = attempt == triggerAttempt
        lock.unlock()
        if shouldAppend, let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((appendedLine + "\n").utf8))
            try? handle.close()
        }
        return false
    }
}

private func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard actual == expected else {
        fputs("FAIL: \(message). Expected \(expected), got \(actual) at \(file):\(line)\n", stderr)
        Foundation.exit(1)
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        Foundation.exit(1)
    }
}

private func fixtureData(_ rows: [[String: Any]]) throws -> Data {
    try JSONSerialization.data(withJSONObject: rows)
}

private func coverageRow(start: Double?, end: Double?) -> [String: Any] {
    [
        "row_kind": "coverage",
        "request_id": NSNull(),
        "app_type": NSNull(),
        "input_tokens": NSNull(),
        "output_tokens": NSNull(),
        "cache_read_tokens": NSNull(),
        "cache_creation_tokens": NSNull(),
        "total_cost_usd": NSNull(),
        "created_at": NSNull(),
        "input_token_semantics": NSNull(),
        "coverage_start": start ?? NSNull(),
        "coverage_end": end ?? NSNull()
    ]
}

private func usageRow(
    id: String,
    app: String,
    input: Int64,
    output: Int64,
    cacheRead: Int64,
    cacheCreation: Int64,
    cost: Any,
    createdAt: Double,
    semantics: Int64
) -> [String: Any] {
    [
        "row_kind": "usage",
        "request_id": id,
        "app_type": app,
        "input_tokens": input,
        "output_tokens": output,
        "cache_read_tokens": cacheRead,
        "cache_creation_tokens": cacheCreation,
        "total_cost_usd": cost,
        "created_at": createdAt,
        "input_token_semantics": semantics,
        "coverage_start": NSNull(),
        "coverage_end": NSNull()
    ]
}

private func window(start: Double = 1_000.125, end: Double = 1_001.875) -> UsageQueryWindow {
    UsageQueryWindow(
        range: .today,
        startUTC: Date(timeIntervalSince1970: start),
        endUTC: Date(timeIntervalSince1970: end),
        timeZoneIdentifier: "GMT"
    )
}

private func source(
    rows: [[String: Any]],
    failure: SQLiteJSONQueryError? = nil
) throws -> (CCSwitchUsageSource, FakeSQLiteJSONQueryRunner) {
    let runner = FakeSQLiteJSONQueryRunner(
        responses: failure == nil ? [try fixtureData(rows)] : [],
        failure: failure
    )
    return (
        CCSwitchUsageSource(
            databaseURL: URL(fileURLWithPath: #filePath),
            queryRunner: runner
        ),
        runner
    )
}

private func usageBatch(
    entries: [UsageEntry] = [],
    coverageStart: Date?,
    coverageEnd: Date?,
    warnings: Set<UsageWarningCategory> = [],
    scannedFileCount: Int = 0
) -> UsageSourceBatch {
    UsageSourceBatch(
        entries: entries,
        coverageStart: coverageStart,
        coverageEnd: coverageEnd,
        warnings: warnings,
        scannedFileCount: scannedFileCount
    )
}

private func waitUntilStarted(_ source: ControlledUsageSource) async -> Bool {
    for _ in 0..<1_000 {
        if await source.hasStarted() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return false
}

private func snapshot(from outcome: UsageAggregationOutcome, _ message: String) -> UsageSnapshot {
    guard case .snapshot(let snapshot) = outcome else {
        fputs("FAIL: \(message)\n", stderr)
        Foundation.exit(1)
    }
    return snapshot
}

private enum UsageCheckMode: Equatable {
    case fixtures
    case live
    case invalid
}

private func usageCheckMode(arguments: ArraySlice<String>) -> UsageCheckMode {
    if arguments.isEmpty { return .fixtures }
    if arguments.elementsEqual(["--live"]) { return .live }
    return .invalid
}

private func liveOutcomesHaveAnomaly(_ outcomes: [UsageAggregationOutcome]) -> Bool {
    var snapshots = [UsageSnapshot]()
    for outcome in outcomes {
        switch outcome {
        case .snapshot(let snapshot):
            if snapshot.completeness == .partial { return true }
            snapshots.append(snapshot)
        case .failed, .cancelled:
            return true
        }
    }

    guard snapshots.count == UsageTimeRange.allCases.count else { return true }
    return liveCompleteSnapshotsAreNonMonotonic(snapshots)
}

private func liveCompleteSnapshotsAreNonMonotonic(_ snapshots: [UsageSnapshot]) -> Bool {
    zip(snapshots, snapshots.dropFirst()).contains {
        $0.tokens.realTotal > $1.tokens.realTotal || $0.requestCount > $1.requestCount
    }
}

private func liveFixtureSnapshot(
    range: UsageTimeRange,
    totalTokens: Int64,
    requests: Int64,
    completeness: UsageSnapshotCompleteness = .complete
) -> UsageSnapshot {
    let queryWindow = UsageQueryWindow(
        range: range,
        startUTC: Date(timeIntervalSince1970: 1_000 - Double(range.dayCount)),
        endUTC: Date(timeIntervalSince1970: 1_000),
        timeZoneIdentifier: "GMT"
    )
    return UsageSnapshot(
        tokens: UsageTokenCounts(freshInput: totalTokens, output: 0, cacheCreation: 0, cacheRead: 0),
        requestCount: requests,
        estimatedCostUSD: .zero,
        coverageStart: queryWindow.startUTC,
        coverageEnd: queryWindow.endUTC,
        scannedFileCount: 0,
        refreshedAt: queryWindow.endUTC,
        queryWindow: queryWindow,
        completeness: completeness,
        warnings: completeness == .partial ? [.insufficientCoverage] : []
    )
}

@main
private enum DynamicIslandUsageChecks {
    static func main() async throws {
        switch usageCheckMode(arguments: CommandLine.arguments.dropFirst()) {
        case .live:
            await runLiveChecks()
            return
        case .invalid:
            fputs("unsupported usage-check argument\n", stderr)
            Foundation.exit(2)
        case .fixtures:
            break
        }

        try await testCancellationOutcomeIsExplicit()
        testUnknownArgumentsAreRejected()
        testLiveAnomalyDetection()
        try await testAggregationStartsBothSourcesAndMergesSuccesses()
        try await testAggregationFailureMatrixPreservesAvailableData()
        try await testAggregationCompletenessAndCapturedRefreshTime()
        try await testRefreshIdentityRejectsStalePublication()
        try await testGeminiCacheSubsetValidationMatchesInputSemantics()
        try await testInvalidRequestIDsDoNotSuppressLaterValidRows()
        try await testCancellationIsPropagatedBySource()
        try await testHalfOpenQueryDeduplicatesByRequestIDAndExcludesCodex()
        try await testSemanticsMappingIsExplicitForEverySupportedApplication()
        try await testInvalidNumericRowsAreExcludedAndHistoricalCostUsesDecimal()
        try await testEmptyWindowRetainsFullNonCodexCoverage()
        try await testMissingDatabaseAndQueryFailuresMapAtTheSourceBoundary()
        try await testSystemRunnerExposesOnlyGenericSQLiteErrors()
        try await testRealSQLiteFixtureHonorsProjectionBoundsAndCoverage()
        try await testSystemRunnerCancellationTerminatesTheSQLiteProcess()
        try await testCodexCanonicalStateIncludesChildAgents()
        try await testCodexFallbackDeduplicatesMovedCopiesAndRanksConflicts()
        try await testCodexFallbackMixedMtimeStillComparesAllCandidates()
        try await testCodexStreamingRetryAndActorCache()
        try await testCodexSecondReadChangeWarnsAndAvoidsStaleCache()
        try await testCodexCanonicalStateDuplicateUUIDsFoldSafely()
        try await testCodexFallbackOldMtimeSkipRechecksSignaturesBeforeReturning()
        try await testCodexOldMtimeSkipRechecksSignatureBeforeReturning()
        try await testCodexRejectsMismatchedCanonicalIdentityAndUsesFallback()
        try await testCodexStateKnownThreadWithoutRolloutWarnsAndKeepsValidThreads()
        try await testCodexStateAndRolloutFailureBoundaries()
        try await testCodexBadRolloutReadDoesNotDiscardValidThreads()
        try await testCodexIgnoresUnidentifiedJSONLFiles()
        try await testCodexCanonicalizesUppercaseStateUUID()
        try await testCodexEnumeratorErrorsKeepRecoverableFiles()
        try await testCodexMtimeCoverageAndPartialFiles()
        print("DynamicIslandUsageChecks passed")
    }

    private static func testCancellationOutcomeIsExplicit() async throws {
        let queryWindow = window(start: 1_000, end: 1_100)
        let codex = ControlledUsageSource()
        let ccSwitch = ControlledUsageSource()
        let service = UsageAggregationService(codexSource: codex, ccSwitchSource: ccSwitch)
        let load = Task { await service.loadSnapshot(in: queryWindow, refreshedAt: queryWindow.endUTC) }
        expectEqual(await waitUntilStarted(codex), true, "cancellation Codex source starts")
        expectEqual(await waitUntilStarted(ccSwitch), true, "cancellation CC Switch source starts")
        await codex.resume(with: .cancelled)
        await ccSwitch.resume(with: .success(usageBatch(
            coverageStart: queryWindow.startUTC,
            coverageEnd: queryWindow.endUTC
        )))
        expectEqual(await load.value, .cancelled, "source cancellation returns an explicit cancelled outcome")
    }

    private static func testUnknownArgumentsAreRejected() {
        expectEqual(usageCheckMode(arguments: []), .fixtures, "no arguments run fixture checks")
        expectEqual(usageCheckMode(arguments: ["--live"]), .live, "only --live enables live checks")
        expectEqual(usageCheckMode(arguments: ["--unexpected"]), .invalid, "unknown arguments are rejected")
        expectEqual(usageCheckMode(arguments: ["--live", "--unexpected"]), .invalid, "mixed arguments are rejected")
    }

    private static func testLiveAnomalyDetection() {
        let monotonic = zip(UsageTimeRange.allCases, [(1, 1), (2, 2), (3, 3), (4, 4)]).map {
            UsageAggregationOutcome.snapshot(liveFixtureSnapshot(
                range: $0.0,
                totalTokens: Int64($0.1.0),
                requests: Int64($0.1.1)
            ))
        }
        expectEqual(liveOutcomesHaveAnomaly(monotonic), false, "complete monotonic live snapshots pass")

        let nonMonotonic = zip(UsageTimeRange.allCases, [(1, 1), (3, 3), (2, 2), (4, 4)]).map {
            UsageAggregationOutcome.snapshot(liveFixtureSnapshot(
                range: $0.0,
                totalTokens: Int64($0.1.0),
                requests: Int64($0.1.1)
            ))
        }
        expectEqual(liveOutcomesHaveAnomaly(nonMonotonic), true, "complete non-monotonic live snapshots fail")

        var partial = monotonic
        partial[1] = .snapshot(liveFixtureSnapshot(
            range: .threeDays,
            totalTokens: 2,
            requests: 2,
            completeness: .partial
        ))
        expectEqual(liveOutcomesHaveAnomaly(partial), true, "partial live snapshots are anomalous")

        var failed = monotonic
        failed[2] = .failed([.codexRolloutUnreadable])
        expectEqual(liveOutcomesHaveAnomaly(failed), true, "failed live snapshots are anomalous")
    }

    private static func testAggregationStartsBothSourcesAndMergesSuccesses() async throws {
        let queryWindow = window(start: 1_000, end: 1_100)
        let refreshedAt = Date(timeIntervalSince1970: 1_101)
        let codex = ControlledUsageSource()
        let ccSwitch = ControlledUsageSource()
        let service = UsageAggregationService(codexSource: codex, ccSwitchSource: ccSwitch)
        let load = Task {
            await service.loadSnapshot(in: queryWindow, refreshedAt: refreshedAt)
        }

        let codexStarted = await waitUntilStarted(codex)
        let ccSwitchStarted = await waitUntilStarted(ccSwitch)
        expectEqual(codexStarted, true, "aggregation starts the Codex source")
        expectEqual(ccSwitchStarted, true, "aggregation starts CC Switch before either source completes")

        let codexEntry = UsageEntry(
            id: "codex-entry",
            occurredAt: Date(timeIntervalSince1970: 1_010),
            tokens: UsageTokenCounts(freshInput: 10, output: 2, cacheCreation: 0, cacheRead: 3),
            requestCount: 1,
            estimatedCostUSD: Decimal(string: "0.10")
        )
        let ccSwitchEntry = UsageEntry(
            id: "cc-entry",
            occurredAt: Date(timeIntervalSince1970: 1_020),
            tokens: UsageTokenCounts(freshInput: 20, output: 4, cacheCreation: 1, cacheRead: 5),
            requestCount: 2,
            estimatedCostUSD: Decimal(string: "0.20")
        )
        await ccSwitch.resume(with: .success(usageBatch(
            entries: [ccSwitchEntry],
            coverageStart: queryWindow.startUTC,
            coverageEnd: queryWindow.endUTC
        )))
        await codex.resume(with: .success(usageBatch(
            entries: [codexEntry],
            coverageStart: queryWindow.startUTC,
            coverageEnd: queryWindow.endUTC,
            scannedFileCount: 2
        )))

        let merged = snapshot(from: await load.value, "two successful sources return a snapshot")
        expectEqual(merged.tokens.realTotal, 45, "aggregation merges token totals from both successful sources")
        expectEqual(merged.requestCount, 3, "aggregation merges request counts from both successful sources")
        expectEqual(merged.scannedFileCount, 2, "aggregation preserves Codex scanned-file metadata")
        expectEqual(merged.completeness, .complete, "two complete sources produce a complete snapshot")
        expectEqual(merged.refreshedAt, refreshedAt, "aggregation preserves the captured refresh time exactly")

        let emptyCodex = ControlledUsageSource()
        let emptyCCSwitch = ControlledUsageSource()
        let emptyService = UsageAggregationService(codexSource: emptyCodex, ccSwitchSource: emptyCCSwitch)
        let emptyLoad = Task { await emptyService.loadSnapshot(in: queryWindow, refreshedAt: refreshedAt) }
        expectEqual(await waitUntilStarted(emptyCodex), true, "empty Codex source starts")
        expectEqual(await waitUntilStarted(emptyCCSwitch), true, "empty CC Switch source starts")
        await emptyCodex.resume(with: .success(usageBatch(
            coverageStart: queryWindow.startUTC,
            coverageEnd: queryWindow.endUTC
        )))
        await emptyCCSwitch.resume(with: .success(usageBatch(
            coverageStart: queryWindow.startUTC,
            coverageEnd: queryWindow.endUTC
        )))
        let empty = snapshot(from: await emptyLoad.value, "two trusted empty sources return a snapshot")
        expectEqual(empty.tokens.realTotal, 0, "trusted empty sources produce a real zero total")
        expectEqual(empty.requestCount, 0, "trusted empty sources produce zero requests")
        expectEqual(empty.estimatedCostUSD, .zero, "trusted empty sources produce zero cost")
        expectEqual(empty.completeness, .complete, "trusted empty sources remain complete")
    }

    private static func testAggregationFailureMatrixPreservesAvailableData() async throws {
        let queryWindow = window(start: 1_000, end: 1_100)
        let refreshedAt = Date(timeIntervalSince1970: 1_101)
        let codexEntry = UsageEntry(
            id: "codex-only",
            occurredAt: Date(timeIntervalSince1970: 1_010),
            tokens: UsageTokenCounts(freshInput: 11, output: 1, cacheCreation: 0, cacheRead: 0),
            requestCount: 1,
            estimatedCostUSD: nil
        )
        let ccEntry = UsageEntry(
            id: "non-codex-only",
            occurredAt: Date(timeIntervalSince1970: 1_020),
            tokens: UsageTokenCounts(freshInput: 21, output: 2, cacheCreation: 0, cacheRead: 0),
            requestCount: 1,
            estimatedCostUSD: Decimal(string: "0.20")
        )

        let codexSuccess = ControlledUsageSource()
        let ccFailure = ControlledUsageSource()
        let codexOnlyService = UsageAggregationService(codexSource: codexSuccess, ccSwitchSource: ccFailure)
        let codexOnlyLoad = Task { await codexOnlyService.loadSnapshot(in: queryWindow, refreshedAt: refreshedAt) }
        expectEqual(await waitUntilStarted(codexSuccess), true, "Codex success branch starts")
        expectEqual(await waitUntilStarted(ccFailure), true, "CC Switch failure branch starts")
        await codexSuccess.resume(with: .success(usageBatch(
            entries: [codexEntry],
            coverageStart: queryWindow.startUTC,
            coverageEnd: queryWindow.endUTC,
            warnings: [.unpricedUsage]
        )))
        await ccFailure.resume(with: .failure(.ccSwitchQueryFailed))
        let codexOnly = snapshot(from: await codexOnlyLoad.value, "one successful source still returns a snapshot")
        expectEqual(codexOnly.tokens.realTotal, 12, "CC Switch failure preserves Codex totals")
        expectEqual(codexOnly.completeness, .partial, "CC Switch failure marks the snapshot partial")
        expectEqual(codexOnly.warnings.contains(.ccSwitchQueryFailed), true, "CC Switch failure warning is retained")

        let codexFailure = ControlledUsageSource()
        let ccSuccess = ControlledUsageSource()
        let ccOnlyService = UsageAggregationService(codexSource: codexFailure, ccSwitchSource: ccSuccess)
        let ccOnlyLoad = Task { await ccOnlyService.loadSnapshot(in: queryWindow, refreshedAt: refreshedAt) }
        expectEqual(await waitUntilStarted(codexFailure), true, "Codex failure branch starts")
        expectEqual(await waitUntilStarted(ccSuccess), true, "CC Switch success branch starts")
        await codexFailure.resume(with: .failure(.codexRolloutUnreadable))
        await ccSuccess.resume(with: .success(usageBatch(
            entries: [ccEntry],
            coverageStart: queryWindow.startUTC,
            coverageEnd: queryWindow.endUTC
        )))
        let ccOnly = snapshot(from: await ccOnlyLoad.value, "CC Switch data survives a Codex failure")
        expectEqual(ccOnly.tokens.realTotal, 23, "Codex failure keeps only the non-Codex source totals")
        expectEqual(ccOnly.requestCount, 1, "Codex failure does not synthesize Codex requests from CC Switch")
        expectEqual(ccOnly.completeness, .partial, "Codex failure marks the snapshot partial")
        expectEqual(ccOnly.warnings.contains(.codexRolloutUnreadable), true, "Codex failure warning is retained")

        let failedCodex = ControlledUsageSource()
        let failedCCSwitch = ControlledUsageSource()
        let failedService = UsageAggregationService(codexSource: failedCodex, ccSwitchSource: failedCCSwitch)
        let failedLoad = Task { await failedService.loadSnapshot(in: queryWindow, refreshedAt: refreshedAt) }
        expectEqual(await waitUntilStarted(failedCodex), true, "failed Codex branch starts")
        expectEqual(await waitUntilStarted(failedCCSwitch), true, "failed CC Switch branch starts")
        await failedCodex.resume(with: .failure(.codexRolloutUnreadable))
        await failedCCSwitch.resume(with: .failure(.ccSwitchUnavailable))
        let failed = await failedLoad.value
        expectEqual(
            failed,
            .failed([.codexRolloutUnreadable, .ccSwitchUnavailable]),
            "two source failures return failed rather than a fabricated zero snapshot"
        )
    }

    private static func testAggregationCompletenessAndCapturedRefreshTime() async throws {
        let queryWindow = window(start: 1_000, end: 1_100)
        let refreshedAt = Date(timeIntervalSince1970: 9_999.25)
        let lateCodex = ControlledUsageSource()
        let unpricedCCSwitch = ControlledUsageSource()
        let service = UsageAggregationService(codexSource: lateCodex, ccSwitchSource: unpricedCCSwitch)
        let load = Task { await service.loadSnapshot(in: queryWindow, refreshedAt: refreshedAt) }
        expectEqual(await waitUntilStarted(lateCodex), true, "late-coverage source starts")
        expectEqual(await waitUntilStarted(unpricedCCSwitch), true, "unpriced source starts")

        let unpricedEntry = UsageEntry(
            id: "unpriced",
            occurredAt: Date(timeIntervalSince1970: 1_050),
            tokens: UsageTokenCounts(freshInput: 5, output: 1, cacheCreation: 0, cacheRead: 0),
            requestCount: 1,
            estimatedCostUSD: nil
        )
        await lateCodex.resume(with: .success(usageBatch(
            coverageStart: queryWindow.startUTC.addingTimeInterval(1),
            coverageEnd: queryWindow.endUTC
        )))
        await unpricedCCSwitch.resume(with: .success(usageBatch(
            entries: [unpricedEntry],
            coverageStart: queryWindow.startUTC,
            coverageEnd: queryWindow.endUTC,
            warnings: [.unpricedUsage]
        )))
        let result = snapshot(from: await load.value, "coverage and pricing warnings still return a snapshot")
        expectEqual(result.completeness, .partial, "late source coverage makes the merged snapshot partial")
        expectEqual(result.warnings.contains(.insufficientCoverage), true, "late source coverage adds the coverage warning")
        expectEqual(result.estimatedCostUSD, nil, "unpriced positive usage keeps cost unavailable")
        expectEqual(result.refreshedAt, refreshedAt, "the injected refresh time is not recaptured")

        let completeCodex = ControlledUsageSource()
        let unpricedOnlyCCSwitch = ControlledUsageSource()
        let completeService = UsageAggregationService(codexSource: completeCodex, ccSwitchSource: unpricedOnlyCCSwitch)
        let completeLoad = Task { await completeService.loadSnapshot(in: queryWindow, refreshedAt: refreshedAt) }
        expectEqual(await waitUntilStarted(completeCodex), true, "complete Codex source starts")
        expectEqual(await waitUntilStarted(unpricedOnlyCCSwitch), true, "unpriced-only source starts")
        await completeCodex.resume(with: .success(usageBatch(
            coverageStart: queryWindow.startUTC,
            coverageEnd: queryWindow.endUTC
        )))
        await unpricedOnlyCCSwitch.resume(with: .success(usageBatch(
            entries: [unpricedEntry],
            coverageStart: queryWindow.startUTC,
            coverageEnd: queryWindow.endUTC,
            warnings: [.unpricedUsage]
        )))
        let unpricedOnly = snapshot(from: await completeLoad.value, "unpriced-only usage returns a snapshot")
        expectEqual(unpricedOnly.completeness, .complete, "unpriced usage alone keeps token completeness complete")
        expectEqual(unpricedOnly.estimatedCostUSD, nil, "unpriced usage alone keeps cost unavailable")
    }

    private static func testRefreshIdentityRejectsStalePublication() async throws {
        let todayWindow = UsageQueryWindow(
            range: .today,
            startUTC: Date(timeIntervalSince1970: 1_000),
            endUTC: Date(timeIntervalSince1970: 2_000),
            timeZoneIdentifier: "GMT"
        )
        let thirtyDayWindow = UsageQueryWindow(
            range: .thirtyDays,
            startUTC: Date(timeIntervalSince1970: 100),
            endUTC: Date(timeIntervalSince1970: 2_000),
            timeZoneIdentifier: "GMT"
        )
        let oldIdentity = UsageRefreshRequestIdentity(generation: 1, range: .today)
        let newIdentity = UsageRefreshRequestIdentity(generation: 2, range: .thirtyDays)
        expectEqual(newIdentity.permitsPublication(currentGeneration: 2, currentRange: .thirtyDays, isCancelled: false), true, "current request identity permits publication")
        expectEqual(newIdentity.permitsPublication(currentGeneration: 3, currentRange: .thirtyDays, isCancelled: false), false, "generation mismatch rejects publication")
        expectEqual(newIdentity.permitsPublication(currentGeneration: 2, currentRange: .today, isCancelled: false), false, "range mismatch rejects publication")
        expectEqual(newIdentity.permitsPublication(currentGeneration: 2, currentRange: .thirtyDays, isCancelled: true), false, "cancelled request rejects publication")

        let oldCodex = ControlledUsageSource()
        let oldCCSwitch = ControlledUsageSource()
        let oldService = UsageAggregationService(codexSource: oldCodex, ccSwitchSource: oldCCSwitch)
        let newCodex = ControlledUsageSource()
        let newCCSwitch = ControlledUsageSource()
        let newService = UsageAggregationService(codexSource: newCodex, ccSwitchSource: newCCSwitch)
        let recorder = UsagePublicationRecorder()
        await recorder.select(generation: 1, range: .today)
        let oldLoad = Task {
            let outcome = await oldService.loadSnapshot(in: todayWindow, refreshedAt: todayWindow.endUTC)
            await recorder.publish(outcome, identity: oldIdentity, isCancelled: false)
        }
        expectEqual(await waitUntilStarted(oldCodex), true, "generation one Codex load starts")
        expectEqual(await waitUntilStarted(oldCCSwitch), true, "generation one CC Switch load starts")

        await recorder.select(generation: 2, range: .thirtyDays)
        let newLoad = Task {
            let outcome = await newService.loadSnapshot(in: thirtyDayWindow, refreshedAt: thirtyDayWindow.endUTC)
            await recorder.publish(outcome, identity: newIdentity, isCancelled: false)
        }
        expectEqual(await waitUntilStarted(newCodex), true, "generation two Codex load starts")
        expectEqual(await waitUntilStarted(newCCSwitch), true, "generation two CC Switch load starts")
        await newCodex.resume(with: .success(usageBatch(
            coverageStart: thirtyDayWindow.startUTC,
            coverageEnd: thirtyDayWindow.endUTC
        )))
        await newCCSwitch.resume(with: .success(usageBatch(
            coverageStart: thirtyDayWindow.startUTC,
            coverageEnd: thirtyDayWindow.endUTC
        )))
        await newLoad.value

        await oldCodex.resume(with: .success(usageBatch(
            coverageStart: todayWindow.startUTC,
            coverageEnd: todayWindow.endUTC
        )))
        await oldCCSwitch.resume(with: .success(usageBatch(
            coverageStart: todayWindow.startUTC,
            coverageEnd: todayWindow.endUTC
        )))
        await oldLoad.value
        let published = await recorder.publishedSnapshot()
        expectEqual(published?.queryWindow.range, .thirtyDays, "late generation one completion cannot replace the published 30-day snapshot")

        let cancelledRecorder = UsagePublicationRecorder()
        await cancelledRecorder.select(generation: 2, range: .thirtyDays)
        let cancelledSnapshot = UsageAggregator.snapshot(
            batches: [usageBatch(
                coverageStart: thirtyDayWindow.startUTC,
                coverageEnd: thirtyDayWindow.endUTC
            )],
            window: thirtyDayWindow,
            refreshedAt: thirtyDayWindow.endUTC
        )
        await cancelledRecorder.publish(
            .snapshot(cancelledSnapshot),
            identity: newIdentity,
            isCancelled: true
        )
        expectEqual(await cancelledRecorder.publishedSnapshot(), nil, "publication recorder rejects a cancelled current request")
    }

    private static func runLiveChecks() async {
        let service = UsageAggregationService.live()
        let now = Date()
        let timeZone = TimeZone.current
        var outcomes = [UsageAggregationOutcome]()
        print("range,totalTokens,requests,cacheHitRate,completeness,coverage,durationMs")

        for range in UsageTimeRange.allCases {
            let startedAt = ContinuousClock.now
            let outcome = await service.loadSnapshot(
                in: range.queryWindow(now: now, timeZone: timeZone),
                refreshedAt: now
            )
            outcomes.append(outcome)
            let duration = startedAt.duration(to: .now)
            let durationMilliseconds = duration.components.seconds * 1_000
                + duration.components.attoseconds / 1_000_000_000_000_000

            switch outcome {
            case .snapshot(let snapshot):
                let cacheHitRate = snapshot.cacheHitRate.map {
                    String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), $0)
                } ?? "N/A"
                let completeness = snapshot.completeness == .complete ? "complete" : "partial"
                let coverage = snapshot.coverageStart == nil && snapshot.coverageEnd == nil ? "unknown" : "known"
                print("\(range.rawValue),\(snapshot.tokens.realTotal),\(snapshot.requestCount),\(cacheHitRate),\(completeness),\(coverage),\(durationMilliseconds)")
                if snapshot.completeness == .partial {
                    for warning in snapshot.warnings.sorted(by: { $0.rawValue < $1.rawValue }) {
                        print("warning,\(range.rawValue),\(warning.rawValue)")
                    }
                }
            case .failed(let warnings):
                print("\(range.rawValue),N/A,N/A,N/A,failed,unknown,\(durationMilliseconds)")
                for warning in warnings.sorted(by: { $0.rawValue < $1.rawValue }) {
                    print("warning,\(range.rawValue),\(warning.rawValue)")
                }
            case .cancelled:
                print("\(range.rawValue),N/A,N/A,N/A,cancelled,unknown,\(durationMilliseconds)")
            }
        }

        if outcomes.allSatisfy({
            if case .snapshot(let snapshot) = $0 { return snapshot.completeness == .complete }
            return false
        }), liveCompleteSnapshotsAreNonMonotonic(outcomes.compactMap {
            if case .snapshot(let snapshot) = $0 { return snapshot }
            return nil
        }) {
            print("warning,allRanges,nonMonotonicCompleteSnapshots")
        }

        if liveOutcomesHaveAnomaly(outcomes) {
            Foundation.exit(1)
        }
    }

    private static func testInvalidRequestIDsDoNotSuppressLaterValidRows() async throws {
        let whitespaceID = usageRow(
            id: "   ", app: "claude", input: 10, output: 1, cacheRead: 0, cacheCreation: 0,
            cost: "1", createdAt: 1_001, semantics: 2
        )
        let negative = usageRow(
            id: "retry-negative", app: "claude", input: -1, output: 1, cacheRead: 0, cacheCreation: 0,
            cost: "1", createdAt: 1_002, semantics: 2
        )
        let negativeRetry = usageRow(
            id: "retry-negative", app: "claude", input: 10, output: 1, cacheRead: 0, cacheCreation: 0,
            cost: "1", createdAt: 1_003, semantics: 2
        )
        let unknown = usageRow(
            id: "retry-unknown", app: "future-client", input: 10, output: 1, cacheRead: 0, cacheCreation: 0,
            cost: "1", createdAt: 1_004, semantics: 0
        )
        let unknownRetry = usageRow(
            id: "retry-unknown", app: "future-client", input: 10, output: 1, cacheRead: 0, cacheCreation: 0,
            cost: "1", createdAt: 1_005, semantics: 2
        )
        let cacheOverflow = usageRow(
            id: "retry-cache", app: "gemini", input: 10, output: 1, cacheRead: 8, cacheCreation: 3,
            cost: "1", createdAt: 1_006, semantics: 1
        )
        let cacheRetry = usageRow(
            id: "retry-cache", app: "gemini", input: 10, output: 1, cacheRead: 8, cacheCreation: 0,
            cost: "1", createdAt: 1_007, semantics: 1
        )
        var missingField = usageRow(
            id: "retry-missing", app: "claude", input: 10, output: 1, cacheRead: 0, cacheCreation: 0,
            cost: "1", createdAt: 1_008, semantics: 2
        )
        missingField.removeValue(forKey: "output_tokens")
        let missingRetry = usageRow(
            id: "retry-missing", app: "claude", input: 10, output: 1, cacheRead: 0, cacheCreation: 0,
            cost: "1", createdAt: 1_009, semantics: 2
        )
        let trimmed = usageRow(
            id: "  trimmed-id  ", app: "claude", input: 10, output: 1, cacheRead: 0, cacheCreation: 0,
            cost: "1", createdAt: 1_010, semantics: 2
        )

        let (usageSource, _) = try source(rows: [
            coverageRow(start: 900, end: 1_100),
            whitespaceID,
            negative,
            negativeRetry,
            unknown,
            unknownRetry,
            cacheOverflow,
            cacheRetry,
            missingField,
            missingRetry,
            trimmed
        ])
        let batch = try await usageSource.load(in: window(start: 1_000, end: 1_100))

        expectEqual(
            batch.entries.map(\.id),
            ["retry-negative", "retry-unknown", "retry-cache", "retry-missing", "trimmed-id"],
            "invalid rows do not reserve their request id and non-empty ids are trimmed before entry creation"
        )
        expectEqual(batch.warnings.contains(.ccSwitchQueryFailed), true, "empty or structurally incomplete request rows are visible as source warnings")
        expectEqual(batch.warnings.contains(.numericOverflow), true, "negative and cache-overflow rows retain their numeric warning")
        expectEqual(batch.warnings.contains(.unknownInputSemantics), true, "unknown semantic rows retain their semantic warning")
    }

    private static func testGeminiCacheSubsetValidationMatchesInputSemantics() async throws {
        let rows = [
            coverageRow(start: 900, end: 1_100),
            usageRow(
                id: "gemini-read-only", app: "gemini", input: 10, output: 1,
                cacheRead: 8, cacheCreation: 3, cost: "1.25", createdAt: 1_001, semantics: 0
            ),
            usageRow(
                id: "gemini-read-only", app: "gemini", input: 100, output: 7,
                cacheRead: 20, cacheCreation: 4, cost: "9", createdAt: 1_002, semantics: 0
            ),
            usageRow(
                id: "gemini-read-and-creation", app: "gemini", input: 10, output: 1,
                cacheRead: 8, cacheCreation: 3, cost: "2", createdAt: 1_003, semantics: 1
            )
        ]
        let (usageSource, _) = try source(rows: rows)
        let batch = try await usageSource.load(in: window(start: 1_000, end: 1_100))

        expectEqual(batch.entries.map(\.id), ["gemini-read-only"], "Gemini semantics 0 retains the first request and deduplicates its later retry while semantics 1 rejects an oversized cache subset")
        expectEqual(batch.entries[0].tokens, UsageTokenCounts(freshInput: 2, output: 1, cacheCreation: 3, cacheRead: 8), "Gemini semantics 0 subtracts only cache reads from input and keeps cache creation independently")
        expectEqual(batch.entries[0].requestCount, 1, "the retained Gemini request counts exactly once")
        expectEqual(batch.entries[0].estimatedCostUSD, Decimal(string: "1.25", locale: Locale(identifier: "en_US_POSIX")), "deduplication keeps the first Gemini request cost instead of its retry")
        expectEqual(batch.warnings, Set([UsageWarningCategory.numericOverflow]), "Gemini semantics 1 reports an oversized cache read-and-creation subset")
    }

    private static func testCancellationIsPropagatedBySource() async throws {
        let runner = FakeSQLiteJSONQueryRunner(cancellation: true)
        let usageSource = CCSwitchUsageSource(
            databaseURL: URL(fileURLWithPath: #filePath),
            queryRunner: runner
        )

        do {
            _ = try await usageSource.load(in: window())
            expect(false, "source must propagate cancellation instead of converting it into a query warning")
        } catch is CancellationError {
        } catch {
            expect(false, "source cancellation must not be mapped to UsageSourceFailure")
        }
    }

    private static func testHalfOpenQueryDeduplicatesByRequestIDAndExcludesCodex() async throws {
        let rows = [
            coverageRow(start: 10, end: 2_000),
            usageRow(id: "codex", app: "CoDeX", input: 90, output: 10, cacheRead: 20, cacheCreation: 0, cost: "1", createdAt: 1_000.5, semantics: 2),
            usageRow(id: "same", app: "gemini", input: 100, output: 10, cacheRead: 40, cacheCreation: 0, cost: "0.25", createdAt: 1_000.5, semantics: 0),
            usageRow(id: "same", app: "gemini", input: 999, output: 999, cacheRead: 0, cacheCreation: 0, cost: "9", createdAt: 1_000.6, semantics: 0),
            usageRow(id: "parallel", app: "gemini", input: 100, output: 10, cacheRead: 40, cacheCreation: 0, cost: "0.25", createdAt: 1_000.5, semantics: 0),
            usageRow(id: "before", app: "claude", input: 1, output: 0, cacheRead: 0, cacheCreation: 0, cost: "0.01", createdAt: 1_000.124, semantics: 2),
            usageRow(id: "at-end", app: "claude", input: 1, output: 0, cacheRead: 0, cacheCreation: 0, cost: "0.01", createdAt: 1_001.875, semantics: 2),
            usageRow(id: "zero", app: "claude", input: 0, output: 0, cacheRead: 0, cacheCreation: 0, cost: "1", createdAt: 1_001, semantics: 2)
        ]
        let (usageSource, runner) = try source(rows: rows)
        let batch = try await usageSource.load(in: window())
        let invocations = await runner.invocations

        expectEqual(batch.entries.map(\.id), ["same", "parallel"], "only unique positive non-Codex requests inside the half-open window are retained")
        expectEqual(batch.entries.map(\.tokens), [
            UsageTokenCounts(freshInput: 60, output: 10, cacheCreation: 0, cacheRead: 40),
            UsageTokenCounts(freshInput: 60, output: 10, cacheCreation: 0, cacheRead: 40)
        ], "token-identical concurrent requests remain distinct when request ids differ")
        expectEqual(batch.entries.map(\.requestCount), [1, 1], "each retained unique positive request counts once")
        expectEqual(batch.coverageStart, Date(timeIntervalSince1970: 10), "coverage starts at the full-table non-Codex minimum")
        expectEqual(batch.coverageEnd, Date(timeIntervalSince1970: 2_000), "coverage ends at the full-table non-Codex maximum")
        expectEqual(invocations.count, 1, "one read transaction produces rows and coverage metadata")
        expectEqual(invocations[0].0, URL(fileURLWithPath: #filePath), "the injected database URL is used")

        let sql = invocations[0].1
        expect(sql.hasPrefix("PRAGMA query_only=ON;\nBEGIN;"), "query starts by enforcing query-only mode and opening a transaction")
        expect(sql.hasSuffix("COMMIT;"), "query closes the read transaction")
        expectEqual(sql.components(separatedBy: "lower(app_type) <> 'codex'").count - 1, 2, "coverage and window rows use the same non-Codex predicate")
        expect(sql.contains("created_at >= 1000.125"), "fractional start epoch is preserved in the SQL lower bound")
        expect(sql.contains("created_at < 1001.875"), "fractional end epoch is preserved in the exclusive SQL upper bound")
        expect(!sql.contains("usage_daily_rollups"), "source reads original request rows rather than rollups")
    }

    private static func testSemanticsMappingIsExplicitForEverySupportedApplication() async throws {
        let rows = [
            coverageRow(start: 900, end: 1_100),
            usageRow(id: "gemini-legacy", app: "GEMINI", input: 100, output: 20, cacheRead: 40, cacheCreation: 10, cost: "1", createdAt: 1_001, semantics: 0),
            usageRow(id: "gemini-total", app: "gemini", input: 100, output: 20, cacheRead: 40, cacheCreation: 10, cost: "1", createdAt: 1_002, semantics: 1),
            usageRow(id: "future-fresh", app: "future-client", input: 100, output: 20, cacheRead: 40, cacheCreation: 10, cost: "1", createdAt: 1_003, semantics: 2),
            usageRow(id: "claude-0", app: "claude", input: 100, output: 1, cacheRead: 20, cacheCreation: 5, cost: "1", createdAt: 1_004, semantics: 0),
            usageRow(id: "claude-1", app: "claude", input: 100, output: 1, cacheRead: 20, cacheCreation: 5, cost: "1", createdAt: 1_005, semantics: 1),
            usageRow(id: "desktop-0", app: "claude-desktop", input: 100, output: 1, cacheRead: 20, cacheCreation: 5, cost: "1", createdAt: 1_006, semantics: 0),
            usageRow(id: "desktop-1", app: "claude-desktop", input: 100, output: 1, cacheRead: 20, cacheCreation: 5, cost: "1", createdAt: 1_007, semantics: 1),
            usageRow(id: "opencode-0", app: "opencode", input: 100, output: 1, cacheRead: 20, cacheCreation: 5, cost: "1", createdAt: 1_008, semantics: 0),
            usageRow(id: "opencode-1", app: "opencode", input: 100, output: 1, cacheRead: 20, cacheCreation: 5, cost: "1", createdAt: 1_009, semantics: 1),
            usageRow(id: "unknown-legacy", app: "future-client", input: 10, output: 0, cacheRead: 0, cacheCreation: 0, cost: "1", createdAt: 1_010, semantics: 0),
            usageRow(id: "unknown-code", app: "gemini", input: 10, output: 0, cacheRead: 0, cacheCreation: 0, cost: "1", createdAt: 1_011, semantics: 99)
        ]
        let (usageSource, _) = try source(rows: rows)
        let batch = try await usageSource.load(in: window(start: 1_000, end: 1_100))
        let byID = Dictionary(uniqueKeysWithValues: batch.entries.map { ($0.id, $0.tokens) })

        expectEqual(byID["gemini-legacy"], UsageTokenCounts(freshInput: 60, output: 20, cacheCreation: 10, cacheRead: 40), "Gemini semantics 0 includes cache reads but not cache creation")
        expectEqual(byID["gemini-total"], UsageTokenCounts(freshInput: 50, output: 20, cacheCreation: 10, cacheRead: 40), "Gemini semantics 1 includes cache reads and creation")
        expectEqual(byID["future-fresh"], UsageTokenCounts(freshInput: 100, output: 20, cacheCreation: 10, cacheRead: 40), "semantics 2 is fresh for any application")
        for id in ["claude-0", "claude-1", "desktop-0", "desktop-1", "opencode-0", "opencode-1"] {
            expectEqual(byID[id], UsageTokenCounts(freshInput: 100, output: 1, cacheCreation: 5, cacheRead: 20), "\(id) keeps fresh input for semantics 0 or 1")
        }
        expectEqual(byID["unknown-legacy"], nil, "unknown application semantics are not guessed")
        expectEqual(byID["unknown-code"], nil, "unknown semantics codes are excluded")
        expectEqual(batch.warnings.contains(.unknownInputSemantics), true, "excluded semantic combinations make token completeness explicit")
    }

    private static func testInvalidNumericRowsAreExcludedAndHistoricalCostUsesDecimal() async throws {
        let rows = [
            coverageRow(start: 900, end: 1_100),
            usageRow(id: "negative-input", app: "claude", input: -1, output: 0, cacheRead: 0, cacheCreation: 0, cost: "1", createdAt: 1_001, semantics: 2),
            usageRow(id: "negative-output", app: "claude", input: 1, output: -1, cacheRead: 0, cacheCreation: 0, cost: "1", createdAt: 1_002, semantics: 2),
            usageRow(id: "negative-read", app: "claude", input: 1, output: 0, cacheRead: -1, cacheCreation: 0, cost: "1", createdAt: 1_003, semantics: 2),
            usageRow(id: "negative-create", app: "claude", input: 1, output: 0, cacheRead: 0, cacheCreation: -1, cost: "1", createdAt: 1_004, semantics: 2),
            usageRow(id: "total-cache-over", app: "gemini", input: 10, output: 0, cacheRead: 8, cacheCreation: 3, cost: "1", createdAt: 1_006, semantics: 1),
            usageRow(id: "real-total-overflow", app: "claude", input: .max, output: 1, cacheRead: 0, cacheCreation: 0, cost: "1", createdAt: 1_007, semantics: 2),
            usageRow(id: "precise", app: "claude", input: 1, output: 0, cacheRead: 0, cacheCreation: 0, cost: "0.123456789012345678", createdAt: 1_008, semantics: 2),
            usageRow(id: "zero-cost", app: "claude", input: 1, output: 0, cacheRead: 0, cacheCreation: 0, cost: "0", createdAt: 1_009, semantics: 2),
            usageRow(id: "negative-cost", app: "claude", input: 1, output: 0, cacheRead: 0, cacheCreation: 0, cost: "-1", createdAt: 1_010, semantics: 2),
            usageRow(id: "empty-cost", app: "claude", input: 1, output: 0, cacheRead: 0, cacheCreation: 0, cost: "", createdAt: 1_011, semantics: 2),
            usageRow(id: "null-cost", app: "claude", input: 1, output: 0, cacheRead: 0, cacheCreation: 0, cost: NSNull(), createdAt: 1_012, semantics: 2),
            usageRow(id: "invalid-cost", app: "claude", input: 1, output: 0, cacheRead: 0, cacheCreation: 0, cost: "not-a-decimal", createdAt: 1_013, semantics: 2)
        ]
        let (usageSource, _) = try source(rows: rows)
        let batch = try await usageSource.load(in: window(start: 1_000, end: 1_100))

        expectEqual(batch.entries.map(\.id), ["precise", "zero-cost", "negative-cost", "empty-cost", "null-cost", "invalid-cost"], "invalid token rows are excluded while unpriced positive usage remains countable")
        expectEqual(batch.entries[0].estimatedCostUSD, Decimal(string: "0.123456789012345678", locale: Locale(identifier: "en_US_POSIX")), "historical cost is decoded directly as Decimal without a Double round trip")
        expectEqual(batch.entries.dropFirst().allSatisfy { $0.estimatedCostUSD == nil }, true, "zero, negative, empty, null, and invalid historical costs are unpriced")
        expectEqual(batch.warnings.contains(.numericOverflow), true, "negative, inconsistent cache, and overflowing totals warn instead of being clamped")
        expectEqual(batch.warnings.contains(.unpricedUsage), true, "positive usage with no reliable historical cost is marked unpriced")
    }

    private static func testEmptyWindowRetainsFullNonCodexCoverage() async throws {
        let (usageSource, _) = try source(rows: [coverageRow(start: 100, end: 900)])
        let batch = try await usageSource.load(in: window())

        expectEqual(batch.entries, [], "an empty window stays empty")
        expectEqual(batch.coverageStart, Date(timeIntervalSince1970: 100), "empty windows retain full-table coverage start")
        expectEqual(batch.coverageEnd, Date(timeIntervalSince1970: 900), "empty windows retain full-table coverage end")
    }

    private static func testMissingDatabaseAndQueryFailuresMapAtTheSourceBoundary() async throws {
        let missingRunner = FakeSQLiteJSONQueryRunner(responses: [])
        let missing = CCSwitchUsageSource(
            databaseURL: URL(fileURLWithPath: "/definitely/missing/cc-switch.db"),
            queryRunner: missingRunner
        )
        do {
            _ = try await missing.load(in: window())
            expect(false, "a missing CC Switch database must fail")
        } catch let failure as UsageSourceFailure {
            expectEqual(failure.warning, .ccSwitchUnavailable, "missing CC Switch database maps to unavailable")
        }
        expectEqual(await missingRunner.invocations.count, 0, "missing databases are rejected before invoking sqlite")

        let (failing, _) = try source(rows: [], failure: .nonzeroExit(1))
        do {
            _ = try await failing.load(in: window())
            expect(false, "a sqlite query failure must fail the source")
        } catch let failure as UsageSourceFailure {
            expectEqual(failure.warning, .ccSwitchQueryFailed, "generic sqlite failures map to the CC Switch boundary warning")
        }

        let malformedRunner = FakeSQLiteJSONQueryRunner(responses: [Data("not-json".utf8)])
        let malformed = CCSwitchUsageSource(databaseURL: URL(fileURLWithPath: #filePath), queryRunner: malformedRunner)
        do {
            _ = try await malformed.load(in: window())
            expect(false, "malformed sqlite JSON must fail the source")
        } catch let failure as UsageSourceFailure {
            expectEqual(failure.warning, .ccSwitchQueryFailed, "malformed sqlite JSON maps to query failure")
        }
    }

    private static func testSystemRunnerExposesOnlyGenericSQLiteErrors() async throws {
        do {
            _ = try await SystemSQLiteJSONQueryRunner().query(
                databaseURL: URL(fileURLWithPath: #filePath),
                sql: "SELECT * FROM definitely_missing_table;"
            )
            expect(false, "invalid sqlite input must fail")
        } catch is SQLiteJSONQueryError {
        } catch {
            expect(false, "runner errors must stay generic and source-agnostic")
        }
    }

    private static func testRealSQLiteFixtureHonorsProjectionBoundsAndCoverage() async throws {
        let schemaAndRows = """
        CREATE TABLE proxy_request_logs (
            request_id TEXT PRIMARY KEY,
            app_type TEXT NOT NULL,
            input_tokens INTEGER NOT NULL,
            output_tokens INTEGER NOT NULL,
            cache_read_tokens INTEGER NOT NULL,
            cache_creation_tokens INTEGER NOT NULL,
            input_token_semantics INTEGER NOT NULL,
            total_cost_usd TEXT,
            created_at REAL NOT NULL
        );
        INSERT INTO proxy_request_logs VALUES ('codex-low', 'codex', 99, 1, 0, 0, 2, '9', -100);
        INSERT INTO proxy_request_logs VALUES ('before', 'claude', 3, 1, 0, 0, 2, '0.01', 999.5);
        INSERT INTO proxy_request_logs VALUES ('inside', 'gemini', 100, 10, 40, 0, 0, '0.50', 1000.5);
        INSERT INTO proxy_request_logs VALUES ('at-end', 'claude', 3, 1, 0, 0, 2, '0.01', 1001.875);
        INSERT INTO proxy_request_logs VALUES ('after', 'opencode', 3, 1, 0, 0, 2, '0.01', 2000);
        INSERT INTO proxy_request_logs VALUES ('codex-high', 'CoDeX', 99, 1, 0, 0, 2, '9', 3000);
        """
        let databaseURL = try makeSQLiteFixture(schemaAndRows)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let usageSource = CCSwitchUsageSource(databaseURL: databaseURL)
        let batch = try await usageSource.load(in: window(start: 1_000.125, end: 1_001.875))

        expectEqual(batch.entries.map(\.id), ["inside"], "real sqlite output applies Codex exclusion and the half-open bounds")
        expectEqual(batch.entries[0].tokens, UsageTokenCounts(freshInput: 60, output: 10, cacheCreation: 0, cacheRead: 40), "real sqlite output preserves Gemini cache-read semantics")
        expectEqual(batch.coverageStart, Date(timeIntervalSince1970: 999.5), "real sqlite coverage ignores the Codex minimum")
        expectEqual(batch.coverageEnd, Date(timeIntervalSince1970: 2_000), "real sqlite coverage scans non-Codex rows outside the query window")
    }

    private static func testSystemRunnerCancellationTerminatesTheSQLiteProcess() async throws {
        let databaseURL = try makeSQLiteFixture("CREATE TABLE cancellation_probe (value INTEGER);")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let query = """
        WITH RECURSIVE counter(x) AS (
            VALUES(0)
            UNION ALL
            SELECT x + 1 FROM counter WHERE x < 5000000
        )
        SELECT sum(x) FROM counter;
        """
        let task = Task {
            try await SystemSQLiteJSONQueryRunner().query(databaseURL: databaseURL, sql: query)
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()

        do {
            _ = try await task.value
            expect(false, "cancelling the query task must stop sqlite and throw CancellationError")
        } catch is CancellationError {
        } catch {
            expect(false, "cancelled sqlite queries must not surface as generic runner errors")
        }
    }

    private static func testCodexCanonicalStateIncludesChildAgents() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }

        let primaryID = "11111111-1111-4111-8111-111111111111"
        let childID = "22222222-2222-4222-8222-222222222222"
        let primaryPath = fixture.active.appendingPathComponent("rollout-\(primaryID).jsonl")
        let archivePath = fixture.archived.appendingPathComponent("rollout-\(primaryID).jsonl")
        let childPath = fixture.archived.appendingPathComponent("rollout-\(childID).jsonl")
        try writeRollout([tokenLine(at: 1001, input: 10, output: 1), tokenLine(at: 1002, input: 20, output: 2)], to: primaryPath)
        try writeRollout([tokenLine(at: 1001, input: 900, output: 9), tokenLine(at: 1002, input: 999, output: 9)], to: archivePath)
        try writeRollout([tokenLine(at: 1001, input: 5, output: 1), tokenLine(at: 1002, input: 8, output: 2)], to: childPath)
        let state = try stateData([
            stateRow(id: primaryID, path: primaryPath.path, createdAt: 900),
            stateRow(id: childID, path: childPath.path, createdAt: 901)
        ])
        let runner = FakeSQLiteJSONQueryRunner(responses: [state])
        let source = CodexUsageSource(
            stateDatabaseURL: fixture.state,
            rolloutRoots: [fixture.active, fixture.archived],
            queryRunner: runner
        )

        let batch = try await source.load(in: UsageQueryWindow(
            range: .today,
            startUTC: Date(timeIntervalSince1970: 1000),
            endUTC: Date(timeIntervalSince1970: 1010),
            timeZoneIdentifier: "GMT"
        ))
        expectEqual(batch.entries.map { $0.id.split(separator: ":").first.map(String.init) ?? "" }, [primaryID, primaryID, childID, childID], "state canonical and child-agent rollout entries are both retained")
        expectEqual(batch.entries.map(\.tokens), [
            UsageTokenCounts(freshInput: 10, output: 1, cacheCreation: 0, cacheRead: 0),
            UsageTokenCounts(freshInput: 10, output: 1, cacheCreation: 0, cacheRead: 0),
            UsageTokenCounts(freshInput: 5, output: 1, cacheCreation: 0, cacheRead: 0),
            UsageTokenCounts(freshInput: 3, output: 1, cacheCreation: 0, cacheRead: 0)
        ], "state canonical path wins over an archived duplicate without filtering child agents")
        expectEqual(batch.warnings, Set<UsageWarningCategory>(), "state-backed canonical reads do not report a conflict for ignored archived copies")
    }

    private static func testCodexFallbackDeduplicatesMovedCopiesAndRanksConflicts() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let movedID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let active = fixture.active.appendingPathComponent("rollout-\(movedID).jsonl")
        let archived = fixture.archived.appendingPathComponent("rollout-\(movedID).jsonl")
        let same = [tokenLine(at: 1001, input: 10, output: 1), tokenLine(at: 1002, input: 20, output: 2)]
        try writeRollout(same, to: active)
        try writeRollout(same, to: archived)
        let state = try stateData([])
        let runner = FakeSQLiteJSONQueryRunner(responses: [state])
        let source = CodexUsageSource(stateDatabaseURL: fixture.state, rolloutRoots: [fixture.active, fixture.archived], queryRunner: runner)
        var batch = try await source.load(in: window(start: 1000, end: 1010))
        expectEqual(batch.entries.count, 2, "identical active/archive contents are treated as a moved copy")
        expectEqual(batch.warnings.contains(.codexRolloutConflict), false, "identical moved copies do not report a conflict")

        let conflictID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let newer = fixture.active.appendingPathComponent("rollout-\(conflictID).jsonl")
        let older = fixture.archived.appendingPathComponent("rollout-\(conflictID).jsonl")
        try writeRollout([tokenLine(at: 1001, input: 5, output: 1), tokenLine(at: 1003, input: 8, output: 2)], to: newer)
        try writeRollout([tokenLine(at: 1001, input: 5, output: 1), tokenLine(at: 1002, input: 9, output: 2)], to: older)
        let conflictState = try stateData([])
        let conflictRunner = FakeSQLiteJSONQueryRunner(responses: [conflictState])
        let conflictSource = CodexUsageSource(stateDatabaseURL: fixture.state, rolloutRoots: [fixture.active, fixture.archived], queryRunner: conflictRunner)
        batch = try await conflictSource.load(in: window(start: 1000, end: 1010))
        expectEqual(batch.entries.filter { $0.id.hasPrefix(conflictID + ":") }.map(\.tokens).last, UsageTokenCounts(freshInput: 3, output: 1, cacheCreation: 0, cacheRead: 0), "fallback conflict selects the candidate with the latest complete token event")
        expectEqual(batch.warnings.contains(.codexRolloutConflict), true, "conflicting fallback candidates mark partial data")
    }

    private static func testCodexFallbackMixedMtimeStillComparesAllCandidates() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let id = "11111111-1111-4111-8111-111111111111"
        let oldPath = fixture.active.appendingPathComponent("rollout-\(id).jsonl")
        let recentPath = fixture.archived.appendingPathComponent("rollout-\(id).jsonl")
        try writeRollout([tokenLine(at: 1001, input: 10, output: 1), tokenLine(at: 1002, input: 12, output: 2)], to: oldPath)
        try writeRollout([tokenLine(at: 1001, input: 20, output: 1), tokenLine(at: 1003, input: 25, output: 2)], to: recentPath)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: oldPath.path)
        let runner = FakeSQLiteJSONQueryRunner(responses: [try stateData([])])
        let source = CodexUsageSource(stateDatabaseURL: fixture.state, rolloutRoots: [fixture.active, fixture.archived], queryRunner: runner)
        let batch = try await source.load(in: window(start: 1000, end: 1010))
        expectEqual(batch.entries.filter { $0.id.hasPrefix(id + ":") }.map(\.tokens).last, UsageTokenCounts(freshInput: 5, output: 1, cacheCreation: 0, cacheRead: 0), "a newer fallback wins after all candidates are parsed")
        expectEqual(batch.warnings.contains(.codexRolloutConflict), true, "a mixed-mtime fallback still compares the old candidate for conflict")
    }

    private static func testCodexStreamingRetryAndActorCache() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let id = "thread-stream"
        let path = fixture.active.appendingPathComponent("rollout-\(id).jsonl")
        let firstLine = largeTokenLine(at: 1001, input: 10, output: 1)
        try writeRollout([firstLine], to: path)
        let state = try stateData([stateRow(id: id, path: path.path, createdAt: 900)])
        let runner = FakeSQLiteJSONQueryRunner(responses: [state, state])
        let hooks = CodexReadHookRecorder()
        hooks.onAttempt = { url, attempt in
            guard url == path, attempt == 1 else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(("\n" + tokenLine(at: 1002, input: 20, output: 2) + "\n").utf8))
                try? handle.close()
            }
        }
        let source = CodexUsageSource(
            stateDatabaseURL: fixture.state,
            rolloutRoots: [fixture.active, fixture.archived],
            queryRunner: runner,
            hooks: hooks.hook()
        )
        let queryWindow = window(start: 1000, end: 1010)
        let first = try await source.load(in: queryWindow)
        expectEqual(first.entries.map(\.tokens), [UsageTokenCounts(freshInput: 10, output: 1, cacheCreation: 0, cacheRead: 0), UsageTokenCounts(freshInput: 10, output: 1, cacheCreation: 0, cacheRead: 0)], "64KiB boundary and post-read append retry parse only complete lines")
        expectEqual(hooks.attempts.map(\.1), [1, 2], "a changed signature retries exactly once")

        let second = try await source.load(in: queryWindow)
        expectEqual(second.entries, first.entries, "same size and mtime hits actor cache while entries are recomputed from samples")
        expectEqual(hooks.attempts.map(\.1), [1, 2], "cache hit does not reread the rollout")
    }

    private static func testCodexSecondReadChangeWarnsAndAvoidsStaleCache() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let id = "thread-moving"
        let path = fixture.active.appendingPathComponent("rollout-\(id).jsonl")
        try writeRollout([tokenLine(at: 1001, input: 10, output: 1)], to: path)
        let state = try stateData([stateRow(id: id, path: path.path, createdAt: 900)])
        let runner = FakeSQLiteJSONQueryRunner(responses: [state, state])
        let hooks = CodexReadHookRecorder()
        hooks.onAttempt = { url, attempt in
            guard url == path else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data((tokenLine(at: 1001 + Double(attempt), input: Int64(10 * (attempt + 1)), output: Int64(attempt + 1)) + "\n").utf8))
                try? handle.close()
            }
        }
        let source = CodexUsageSource(
            stateDatabaseURL: fixture.state,
            rolloutRoots: [fixture.active, fixture.archived],
            queryRunner: runner,
            hooks: hooks.hook()
        )

        let first = try await source.load(in: window(start: 1000, end: 1010))
        expectEqual(first.entries.count, 2, "a twice-changing rollout returns only the second attempt's confirmed complete lines")
        expectEqual(first.warnings.contains(.codexRolloutChangedDuringRead), true, "a second signature change is visible")
        expectEqual(hooks.attempts.map(\.1), [1, 2], "a changing rollout never retries more than once")

        hooks.onAttempt = nil
        let refreshed = try await source.load(in: window(start: 1000, end: 1010))
        expectEqual(refreshed.entries.count, 3, "the result from a second changed attempt is not cached under the later signature")
        expectEqual(hooks.attempts.map(\.1), [1, 2, 1], "the next stable query rereads after a twice-changing attempt")
    }

    private static func testCodexFallbackOldMtimeSkipRechecksSignaturesBeforeReturning() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let id = "99999999-9999-4999-8999-999999999999"
        let path = fixture.active.appendingPathComponent("rollout-\(id).jsonl")
        try writeRollout([tokenLine(at: 10, input: 10, output: 1)], to: path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: path.path)
        let runner = FakeSQLiteJSONQueryRunner(responses: [try stateData([])])
        let hooks = CodexOneShotAppendHook(
            targetURL: path,
            appendedLine: tokenLine(at: 1001, input: 14, output: 2),
            triggerAttempt: 2
        )
        let source = CodexUsageSource(
            stateDatabaseURL: fixture.state,
            rolloutRoots: [fixture.active, fixture.archived],
            queryRunner: runner,
            hooks: hooks.hook()
        )

        let batch = try await source.load(in: window(start: 1000, end: 1010))
        expectEqual(batch.entries.map(\.tokens), [
            UsageTokenCounts(freshInput: 4, output: 1, cacheCreation: 0, cacheRead: 0)
        ], "a fallback-only old candidate that changes during the skip check is parsed")
        expectEqual(batch.warnings.contains(.codexRolloutChangedDuringRead), false, "a stable fallback reread after the skip signature changes does not report an in-read mutation")
    }

    private static func testCodexCanonicalStateDuplicateUUIDsFoldSafely() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let id = "abcdefab-cdef-4abc-8def-abcdefabcdef"
        let unreadableDirectory = fixture.base.appendingPathComponent("a")
        let readableDirectory = fixture.base.appendingPathComponent("z")
        try FileManager.default.createDirectory(at: unreadableDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: readableDirectory, withIntermediateDirectories: true)
        let unreadablePath = unreadableDirectory.appendingPathComponent("rollout-\(id).jsonl")
        let readablePath = readableDirectory.appendingPathComponent("rollout-\(id).jsonl")
        try writeRollout([tokenLine(at: 1001, input: 60, output: 10)], to: unreadablePath)
        try writeRollout([tokenLine(at: 1001, input: 6, output: 1)], to: readablePath)
        let state = try stateData([
            stateRow(id: id, path: unreadablePath.path, createdAt: 900),
            stateRow(id: id.uppercased(), path: readablePath.path, createdAt: 901)
        ])
        let runner = FakeSQLiteJSONQueryRunner(responses: [state])
        let hooks = CodexUsageSourceHooks(shouldFailRead: { $0 == unreadablePath })
        let source = CodexUsageSource(
            stateDatabaseURL: fixture.state,
            rolloutRoots: [fixture.active, fixture.archived],
            queryRunner: runner,
            hooks: hooks
        )

        let batch = try await source.load(in: window(start: 1000, end: 1010))
        expectEqual(batch.entries.map(\.tokens), [
            UsageTokenCounts(freshInput: 6, output: 1, cacheCreation: 0, cacheRead: 0)
        ], "case variants of one canonical state UUID fold to one readable rollout")
        expectEqual(batch.warnings.contains(.codexRolloutConflict), true, "conflicting duplicate canonical state rows are visible as partial")
        expectEqual(batch.coverageStart, Date(timeIntervalSince1970: 900), "duplicate canonical state rows retain the earliest coverage start")
    }

    private static func testCodexOldMtimeSkipRechecksSignatureBeforeReturning() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let id = "thread-old-mtime-race"
        let path = fixture.base.appendingPathComponent("canonical.jsonl")
        try writeRollout([tokenLine(at: 10, input: 10, output: 1)], to: path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: path.path)
        let state = try stateData([stateRow(id: id, path: path.path, createdAt: 0)])
        let runner = FakeSQLiteJSONQueryRunner(responses: [state])
        let hooks = CodexOneShotAppendHook(
            targetURL: path,
            appendedLine: tokenLine(at: 1001, input: 14, output: 2)
        )
        let source = CodexUsageSource(
            stateDatabaseURL: fixture.state,
            rolloutRoots: [fixture.active, fixture.archived],
            queryRunner: runner,
            hooks: hooks.hook()
        )

        let batch = try await source.load(in: window(start: 1000, end: 1010))
        expectEqual(batch.entries.map(\.tokens), [
            UsageTokenCounts(freshInput: 4, output: 1, cacheCreation: 0, cacheRead: 0)
        ], "an old-mtime canonical that changes during the skip check is parsed instead of silently skipped")
        expectEqual(batch.warnings.contains(.codexRolloutChangedDuringRead), false, "a stable reread after the skip signature changes does not report an in-read mutation")
    }

    private static func testCodexRejectsMismatchedCanonicalIdentityAndUsesFallback() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let firstID = "11111111-1111-4111-8111-111111111111"
        let secondID = "22222222-2222-4222-8222-222222222222"
        let mismatchedPath = fixture.active.appendingPathComponent("rollout-\(firstID).jsonl")
        let fallbackPath = fixture.archived.appendingPathComponent("rollout-\(firstID).jsonl")
        try writeRollout([
            sessionMetadataLine(id: secondID),
            tokenLine(at: 1001, input: 20, output: 2)
        ], to: mismatchedPath)
        try writeRollout([
            sessionMetadataLine(id: firstID),
            tokenLine(at: 1001, input: 5, output: 1)
        ], to: fallbackPath)
        let state = try stateData([
            stateRow(id: firstID, path: mismatchedPath.path, createdAt: 900),
            stateRow(id: secondID, path: mismatchedPath.path, createdAt: 901)
        ])
        let runner = FakeSQLiteJSONQueryRunner(responses: [state])
        let source = CodexUsageSource(
            stateDatabaseURL: fixture.state,
            rolloutRoots: [fixture.active, fixture.archived],
            queryRunner: runner
        )

        let batch = try await source.load(in: window(start: 1000, end: 1010))
        expectEqual(batch.entries.map(\.tokens), [
            UsageTokenCounts(freshInput: 5, output: 1, cacheCreation: 0, cacheRead: 0),
            UsageTokenCounts(freshInput: 20, output: 2, cacheCreation: 0, cacheRead: 0)
        ], "a mismatched canonical identity is rejected, its matching fallback is used, and the real owner is counted once")
        expectEqual(batch.warnings.contains(.codexRolloutUnreadable), true, "a mismatched state canonical identity is visible as partial")
    }

    private static func testCodexStateKnownThreadWithoutRolloutWarnsAndKeepsValidThreads() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let validID = "11111111-1111-4111-8111-111111111111"
        let missingID = "22222222-2222-4222-8222-222222222222"
        let validPath = fixture.active.appendingPathComponent("rollout-\(validID).jsonl")
        try writeRollout([tokenLine(at: 1001, input: 3, output: 1)], to: validPath)
        let state = try stateData([
            stateRow(id: validID, path: validPath.path, createdAt: 900),
            ["id": missingID, "rollout_path": NSNull(), "created_at": Int64(901)]
        ])
        let runner = FakeSQLiteJSONQueryRunner(responses: [state])
        let source = CodexUsageSource(
            stateDatabaseURL: fixture.state,
            rolloutRoots: [fixture.active, fixture.archived],
            queryRunner: runner
        )

        let batch = try await source.load(in: window(start: 1000, end: 1010))
        expectEqual(batch.entries.count, 1, "a state-known thread without any rollout does not discard a valid thread")
        expectEqual(batch.warnings.contains(.codexRolloutUnreadable), true, "a state-known thread without a canonical or fallback rollout is partial")

        try FileManager.default.removeItem(at: validPath)
        let fallbackPath = fixture.archived.appendingPathComponent("rollout-\(missingID).jsonl")
        try writeRollout([tokenLine(at: 1001, input: 4, output: 1)], to: fallbackPath)
        let fallbackState = try stateData([
            ["id": missingID, "rollout_path": NSNull(), "created_at": Int64(901)]
        ])
        let fallbackRunner = FakeSQLiteJSONQueryRunner(responses: [fallbackState])
        let fallbackSource = CodexUsageSource(
            stateDatabaseURL: fixture.state,
            rolloutRoots: [fixture.active, fixture.archived],
            queryRunner: fallbackRunner
        )

        let recovered = try await fallbackSource.load(in: window(start: 1000, end: 1010))
        expectEqual(recovered.entries.map(\.tokens), [
            UsageTokenCounts(freshInput: 4, output: 1, cacheCreation: 0, cacheRead: 0)
        ], "a state-known nil path uses its valid fallback")
        expectEqual(recovered.warnings, Set<UsageWarningCategory>(), "a state-known nil path does not warn when its fallback is valid")
    }

    private static func testCodexStateAndRolloutFailureBoundaries() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let cancellationRunner = FakeSQLiteJSONQueryRunner(cancellation: true)
        let cancellationSource = CodexUsageSource(
            stateDatabaseURL: fixture.state,
            rolloutRoots: [fixture.active, fixture.archived],
            queryRunner: cancellationRunner
        )
        do {
            _ = try await cancellationSource.load(in: window())
            expect(false, "Codex state runner cancellation must propagate")
        } catch is CancellationError {
        } catch {
            expect(false, "Codex cancellation must not become a source warning")
        }

        let id = "thread-partial"
        let validPath = fixture.active.appendingPathComponent("rollout-\(id).jsonl")
        try writeRollout([tokenLine(at: 1001, input: 3, output: 1)], to: validPath)
        let state = try stateData([
            stateRow(id: id, path: validPath.path, createdAt: 900),
            stateRow(id: "thread-missing", path: fixture.active.appendingPathComponent("missing.jsonl").path, createdAt: 901)
        ])
        let runner = FakeSQLiteJSONQueryRunner(responses: [state])
        let source = CodexUsageSource(stateDatabaseURL: fixture.state, rolloutRoots: [fixture.active, fixture.archived], queryRunner: runner)
        let batch = try await source.load(in: window(start: 1000, end: 1010))
        expectEqual(batch.entries.count, 1, "one missing canonical rollout does not discard a valid thread")
        expectEqual(batch.warnings.contains(.codexRolloutUnreadable), true, "missing canonical rollout is visible as a partial warning")

        try FileManager.default.removeItem(at: validPath)
        let emptyStateRunner = FakeSQLiteJSONQueryRunner(responses: [try stateData([])])
        let emptySource = CodexUsageSource(stateDatabaseURL: fixture.state, rolloutRoots: [fixture.active, fixture.archived], queryRunner: emptyStateRunner)
        let empty = try await emptySource.load(in: window())
        expectEqual(empty.entries, [UsageEntry](), "legal empty state plus enumerable roots is a trusted empty result")
        expectEqual(empty.warnings, Set<UsageWarningCategory>(), "trusted empty state does not warn")

        let stateFailureRunner = FakeSQLiteJSONQueryRunner(responses: [], failure: .nonzeroExit(1))
        let recovering = CodexUsageSource(stateDatabaseURL: fixture.state, rolloutRoots: [fixture.active, fixture.archived], queryRunner: stateFailureRunner)
        let recovered = try await recovering.load(in: window(start: 1000, end: 1010))
        expectEqual(recovered.warnings.contains(.codexStateUnavailable), true, "state failure falls back to enumerable rollout roots")

        let missingRoots = fixture.base.appendingPathComponent("missing-roots")
        let failedRootsRunner = FakeSQLiteJSONQueryRunner(responses: [], failure: .nonzeroExit(1))
        let failedRoots = CodexUsageSource(stateDatabaseURL: fixture.state, rolloutRoots: [missingRoots], queryRunner: failedRootsRunner)
        do {
            _ = try await failedRoots.load(in: window())
            expect(false, "state failure and wholly unenumerable roots must throw")
        } catch let failure as UsageSourceFailure {
            expectEqual(failure.warning, .codexRolloutUnreadable, "unrecoverable state/root failure maps to rollout unreadable")
        }
    }

    private static func testCodexBadRolloutReadDoesNotDiscardValidThreads() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let validID = "22222222-2222-4222-8222-222222222222"
        let validPath = fixture.active.appendingPathComponent("rollout-\(validID).jsonl")
        try writeRollout([tokenLine(at: 1001, input: 4, output: 1)], to: validPath)
        let brokenID = "77777777-7777-4777-8777-777777777777"
        let brokenPath = fixture.active.appendingPathComponent("rollout-\(brokenID).jsonl")
        let fallbackPath = fixture.archived.appendingPathComponent("rollout-\(brokenID).jsonl")
        try writeRollout([tokenLine(at: 10, input: 100, output: 10)], to: brokenPath)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: brokenPath.path)
        try writeRollout([tokenLine(at: 1001, input: 3, output: 1)], to: fallbackPath)
        let state = try stateData([
            stateRow(id: brokenID, path: brokenPath.path, createdAt: 900),
            stateRow(id: validID, path: validPath.path, createdAt: 901)
        ])
        let runner = FakeSQLiteJSONQueryRunner(responses: [state])
        let hooks = CodexUsageSourceHooks(shouldFailRead: { $0 == brokenPath })
        let source = CodexUsageSource(
            stateDatabaseURL: fixture.state,
            rolloutRoots: [fixture.active, fixture.archived],
            queryRunner: runner,
            hooks: hooks
        )
        let batch = try await source.load(in: window(start: 1000, end: 1010))
        expectEqual(batch.entries.count, 2, "an injected regular-file read failure keeps fallback and other thread entries")
        expectEqual(batch.warnings.contains(.codexRolloutUnreadable), true, "a bad old canonical regular file becomes a rollout warning")
    }

    private static func testCodexIgnoresUnidentifiedJSONLFiles() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let notesPath = fixture.active.appendingPathComponent("notes.jsonl")
        try writeRollout([tokenLine(at: 1001, input: 100, output: 10)], to: notesPath)
        let runner = FakeSQLiteJSONQueryRunner(responses: [try stateData([])])
        let source = CodexUsageSource(stateDatabaseURL: fixture.state, rolloutRoots: [fixture.active, fixture.archived], queryRunner: runner)
        let batch = try await source.load(in: window(start: 1000, end: 1010))
        expectEqual(batch.entries, [UsageEntry](), "a non-UUID notes JSONL is not treated as a rollout")
        expectEqual(batch.warnings.contains(.codexRolloutUnreadable), true, "an unidentified JSONL is visible as an unreadable candidate warning")
    }

    private static func testCodexCanonicalizesUppercaseStateUUID() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let canonicalID = "abcdefab-cdef-4abc-8def-abcdefabcdef"
        let path = fixture.active.appendingPathComponent("rollout-\(canonicalID).jsonl")
        try writeRollout([tokenLine(at: 1001, input: 7, output: 1)], to: path)
        let state = try stateData([stateRow(id: canonicalID.uppercased(), path: path.path, createdAt: 900)])
        let runner = FakeSQLiteJSONQueryRunner(responses: [state])
        let source = CodexUsageSource(stateDatabaseURL: fixture.state, rolloutRoots: [fixture.active, fixture.archived], queryRunner: runner)
        let batch = try await source.load(in: window(start: 1000, end: 1010))
        expectEqual(batch.entries.count, 1, "uppercase state UUID and lowercase rollout identity form one canonical thread")
        expectEqual(batch.entries.first?.id.hasPrefix(canonicalID + ":"), true, "canonical UUID entry ids use lowercase identity")
    }

    private static func testCodexEnumeratorErrorsKeepRecoverableFiles() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let validID = "33333333-3333-4333-8333-333333333333"
        let validPath = fixture.active.appendingPathComponent("rollout-\(validID).jsonl")
        try writeRollout([tokenLine(at: 1001, input: 2, output: 1)], to: validPath)
        let inaccessible = fixture.archived.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: inaccessible, withIntermediateDirectories: true)
        try writeRollout([tokenLine(at: 1001, input: 3, output: 1)], to: inaccessible.appendingPathComponent("rollout-44444444-4444-4444-8444-444444444444.jsonl"))
        let siblingID = "55555555-5555-4555-8555-555555555555"
        try writeRollout([tokenLine(at: 1001, input: 4, output: 1)], to: fixture.archived.appendingPathComponent("rollout-\(siblingID).jsonl"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: inaccessible.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: inaccessible.path) }
        let runner = FakeSQLiteJSONQueryRunner(responses: [], failure: .nonzeroExit(1))
        let source = CodexUsageSource(stateDatabaseURL: fixture.state, rolloutRoots: [fixture.active, fixture.archived], queryRunner: runner)
        let batch = try await source.load(in: window(start: 1000, end: 1010))
        expectEqual(batch.entries.count, 2, "recoverable sibling files remain available after a recursive root error")
        expectEqual(batch.warnings.contains(.codexStateUnavailable), true, "state failure remains visible during root recovery")
        expectEqual(batch.warnings.contains(.codexRolloutUnreadable), true, "a root enumeration error is visible without discarding recoverable files")

        let failedRunner = FakeSQLiteJSONQueryRunner(responses: [], failure: .nonzeroExit(1))
        let failedSource = CodexUsageSource(stateDatabaseURL: fixture.state, rolloutRoots: [inaccessible], queryRunner: failedRunner)
        do {
            _ = try await failedSource.load(in: window(start: 1000, end: 1010))
            expect(false, "state failure plus an enumeration error with no recoverable URL must throw")
        } catch let failure as UsageSourceFailure {
            expectEqual(failure.warning, .codexRolloutUnreadable, "unrecoverable enumeration errors stay at the rollout boundary")
        }
    }

    private static func testCodexMtimeCoverageAndPartialFiles() async throws {
        let fixture = try makeCodexFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let id = "thread-old"
        let path = fixture.active.appendingPathComponent("rollout-\(id).jsonl")
        try writeRollout([tokenLine(at: 10, input: 10, output: 1)], to: path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: path.path)
        let state = try stateData([stateRow(id: id, path: path.path, createdAt: 50)])
        let runner = FakeSQLiteJSONQueryRunner(responses: [state])
        let hooks = CodexReadHookRecorder()
        let source = CodexUsageSource(stateDatabaseURL: fixture.state, rolloutRoots: [fixture.active, fixture.archived], queryRunner: runner, hooks: hooks.hook())
        let batch = try await source.load(in: window(start: 1000, end: 1010))
        expectEqual(batch.entries, [UsageEntry](), "rollouts older than the query window may skip body parsing")
        expectEqual(batch.coverageStart, Date(timeIntervalSince1970: 50), "state created_at preserves coverage when old rollout body is skipped")
        expectEqual(hooks.attempts.count, 0, "mtime skip avoids opening old canonical rollout")

        let partialID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        let partialPath = fixture.archived.appendingPathComponent("rollout-\(partialID).jsonl")
        try writeRollout([tokenLine(at: 1001, input: 4, output: 1) + "\n{"], to: partialPath, finalNewline: false)
        let partialRunner = FakeSQLiteJSONQueryRunner(responses: [try stateData([])])
        let partialSource = CodexUsageSource(stateDatabaseURL: fixture.state, rolloutRoots: [fixture.active, fixture.archived], queryRunner: partialRunner)
        let partial = try await partialSource.load(in: window(start: 1000, end: 1010))
        expectEqual(partial.entries.count, 1, "a damaged trailing remainder does not discard complete token lines")
    }

    private struct CodexFixture {
        let base: URL
        let active: URL
        let archived: URL
        let state: URL
    }

    private static func makeCodexFixture() throws -> CodexFixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("dynamic-island-codex-\(UUID().uuidString)")
        let active = base.appendingPathComponent("sessions")
        let archived = base.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        let state = base.appendingPathComponent("state_5.sqlite")
        FileManager.default.createFile(atPath: state.path, contents: Data())
        return CodexFixture(base: base, active: active, archived: archived, state: state)
    }

    private static func stateRow(id: String, path: String, createdAt: Int64) -> [String: Any] {
        ["id": id, "rollout_path": path, "created_at": createdAt]
    }

    private static func stateData(_ rows: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: rows)
    }

    private static func tokenLine(at seconds: Double, input: Int64, output: Int64, cached: Int64 = 0, cacheCreation: Int64 = 0) -> String {
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: date)
        return "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cached),\"output_tokens\":\(output),\"reasoning_output_tokens\":0,\"cache_creation_input_tokens\":\(cacheCreation)}}}}"
    }

    private static func sessionMetadataLine(id: String) -> String {
        "{\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\"}}"
    }

    private static func largeTokenLine(at seconds: Double, input: Int64, output: Int64) -> String {
        tokenLine(at: seconds, input: input, output: output).replacingOccurrences(
            of: "\"reasoning_output_tokens\":0",
            with: "\"reasoning_output_tokens\":0,\"padding\":\"\(String(repeating: "x", count: 65_400))\""
        )
    }

    private static func writeRollout(_ lines: [String], to url: URL, finalNewline: Bool = true) throws {
        var text = lines.joined(separator: "\n")
        if finalNewline { text.append("\n") }
        try Data(text.utf8).write(to: url)
    }

    private static func makeSQLiteFixture(_ sql: String) throws -> URL {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dynamic-island-usage-\(UUID().uuidString).db")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path, sql]
        let standardOutput = Pipe()
        process.standardOutput = standardOutput
        process.standardError = FileHandle.nullDevice
        try process.run()
        _ = standardOutput.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FakeSQLiteRunnerError.noResponse
        }
        return databaseURL
    }
}
