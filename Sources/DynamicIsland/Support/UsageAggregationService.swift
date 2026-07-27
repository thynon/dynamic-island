import Foundation
import DynamicIslandCore

protocol UsageSnapshotLoading: Sendable {
    func loadSnapshot(
        in window: UsageQueryWindow,
        refreshedAt: Date
    ) async -> UsageAggregationOutcome
}

enum UsageAggregationOutcome: Equatable, Sendable {
    case snapshot(UsageSnapshot)
    case failed(Set<UsageWarningCategory>)
    case cancelled
}

struct UsageRefreshRequestIdentity: Equatable, Sendable {
    let generation: Int
    let range: UsageTimeRange

    func permitsPublication(
        currentGeneration: Int,
        currentRange: UsageTimeRange,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled && currentGeneration == generation && currentRange == range
    }
}

actor UsageAggregationService: UsageSnapshotLoading {
    private let codexSource: any UsageEntrySource
    private let ccSwitchSource: any UsageEntrySource

    init(
        codexSource: any UsageEntrySource,
        ccSwitchSource: any UsageEntrySource
    ) {
        self.codexSource = codexSource
        self.ccSwitchSource = ccSwitchSource
    }

    static func live() -> UsageAggregationService {
        UsageAggregationService(
            codexSource: CodexUsageSource(),
            ccSwitchSource: CCSwitchUsageSource()
        )
    }

    func loadSnapshot(
        in window: UsageQueryWindow,
        refreshedAt: Date
    ) async -> UsageAggregationOutcome {
        async let codexResult = load(
            from: codexSource,
            in: window,
            fallbackWarning: .codexRolloutUnreadable
        )
        async let ccSwitchResult = load(
            from: ccSwitchSource,
            in: window,
            fallbackWarning: .ccSwitchQueryFailed
        )

        switch await (codexResult, ccSwitchResult) {
        case (.cancelled, _), (_, .cancelled):
            return .cancelled
        case (.success(let codex), .success(let ccSwitch)):
            return .snapshot(UsageAggregator.snapshot(
                batches: [codex, ccSwitch],
                window: window,
                refreshedAt: refreshedAt
            ))
        case (.success(let batch), .failure(let warning)),
             (.failure(let warning), .success(let batch)):
            let partialBatch = UsageSourceBatch(
                entries: batch.entries,
                coverageStart: batch.coverageStart,
                coverageEnd: batch.coverageEnd,
                warnings: batch.warnings.union([warning]),
                scannedFileCount: batch.scannedFileCount
            )
            return .snapshot(UsageAggregator.snapshot(
                batches: [partialBatch],
                window: window,
                refreshedAt: refreshedAt
            ))
        case (.failure(let codexWarning), .failure(let ccSwitchWarning)):
            return .failed([codexWarning, ccSwitchWarning])
        }
    }

    private func load(
        from source: any UsageEntrySource,
        in window: UsageQueryWindow,
        fallbackWarning: UsageWarningCategory
    ) async -> SourceResult {
        do {
            return .success(try await source.load(in: window))
        } catch is CancellationError {
            return .cancelled
        } catch let failure as UsageSourceFailure {
            return .failure(failure.warning)
        } catch {
            return .failure(fallbackWarning)
        }
    }

    private enum SourceResult: Sendable {
        case success(UsageSourceBatch)
        case failure(UsageWarningCategory)
        case cancelled
    }
}
