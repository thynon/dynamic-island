import Foundation
import DynamicIslandCore

struct CodexUsageSourceHooks: Sendable {
    var didFinishReadAttempt: @Sendable (URL, Int) -> Void
    var shouldFailRead: @Sendable (URL) -> Bool

    init(
        shouldFailRead: @escaping @Sendable (URL) -> Bool = { _ in false },
        didFinishReadAttempt: @escaping @Sendable (URL, Int) -> Void = { _, _ in }
    ) {
        self.didFinishReadAttempt = didFinishReadAttempt
        self.shouldFailRead = shouldFailRead
    }
}

actor CodexUsageSource: UsageEntrySource {
    private let stateDatabaseURL: URL
    private let rolloutRoots: [URL]
    private let queryRunner: any SQLiteJSONQueryRunning
    private let hooks: CodexUsageSourceHooks
    private var cache: [URL: CachedRollout] = [:]

    init(
        stateDatabaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite"),
        rolloutRoots: [URL] = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/archived_sessions")
        ],
        queryRunner: any SQLiteJSONQueryRunning = SystemSQLiteJSONQueryRunner(),
        hooks: CodexUsageSourceHooks = CodexUsageSourceHooks()
    ) {
        self.stateDatabaseURL = stateDatabaseURL
        self.rolloutRoots = rolloutRoots
        self.queryRunner = queryRunner
        self.hooks = hooks
    }

    func load(in window: UsageQueryWindow) async throws -> UsageSourceBatch {
        try Task.checkCancellation()

        let stateResult = try await readState()
        var warnings = Set<UsageWarningCategory>()
        let stateThreads: [StateThread]
        switch stateResult {
        case .success(let threads):
            stateThreads = threads
        case .unavailable:
            warnings.insert(.codexStateUnavailable)
            stateThreads = []
        }

        let rootResult = try enumerateRolloutRoots()
        if case .unavailable = stateResult, !rootResult.anyEnumerable {
            throw UsageSourceFailure(warning: .codexRolloutUnreadable)
        }
        if rootResult.hasEnumerationError {
            warnings.insert(.codexRolloutUnreadable)
        }

        var candidatesByThread: [String: [URL]] = [:]
        for url in rootResult.urls {
            try Task.checkCancellation()
            let metadataID: String?
            do {
                metadataID = try sessionMetadataThreadID(for: url)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                warnings.insert(.codexRolloutUnreadable)
                metadataID = nil
            }
            guard let threadID = metadataID ?? candidateThreadID(for: url) else {
                warnings.insert(.codexRolloutUnreadable)
                continue
            }
            candidatesByThread[threadID, default: []].append(url)
        }
        if case .unavailable = stateResult,
           rootResult.hasEnumerationError,
           candidatesByThread.isEmpty {
            throw UsageSourceFailure(warning: .codexRolloutUnreadable)
        }

        var threadsByID = [String: StateThread]()
        for thread in stateThreads {
            if let existing = threadsByID[thread.id] {
                if existing.rolloutPath != thread.rolloutPath {
                    warnings.insert(.codexRolloutConflict)
                }
                threadsByID[thread.id] = preferredStateThread(existing, thread)
            } else {
                threadsByID[thread.id] = thread
            }
        }
        for threadID in candidatesByThread.keys where threadsByID[threadID] == nil {
            threadsByID[threadID] = StateThread(id: threadID, rolloutPath: nil, createdAt: nil, isKnownToState: false)
        }

        var allEntries = [UsageEntry]()
        var coverageStart: Date?
        var coverageEnd: Date?
        var scannedFileCount = 0

        for threadID in threadsByID.keys.sorted() {
            try Task.checkCancellation()
            let thread = threadsByID[threadID]!
            let selected = try await loadThread(
                thread,
                fallbackURLs: candidatesByThread[threadID] ?? [],
                window: window
            )
            warnings.formUnion(selected.warnings)
            allEntries.append(contentsOf: selected.entries)
            scannedFileCount = saturatedIntAdd(scannedFileCount, selected.scannedFileCount, warnings: &warnings)
            if let start = selected.coverageStart {
                coverageStart = min(coverageStart ?? start, start)
            }
            if let end = selected.coverageEnd {
                coverageEnd = max(coverageEnd ?? end, end)
            }
        }

        return UsageSourceBatch(
            entries: allEntries,
            coverageStart: coverageStart,
            coverageEnd: coverageEnd,
            warnings: warnings,
            scannedFileCount: scannedFileCount
        )
    }

    private enum StateResult {
        case success([StateThread])
        case unavailable
    }

    private struct StateThread: Sendable {
        let id: String
        let rolloutPath: String?
        let createdAt: Date?
        let isKnownToState: Bool
    }

    private struct RootResult {
        let urls: [URL]
        let anyEnumerable: Bool
        let hasEnumerationError: Bool
    }

    private struct FileSignature: Equatable, Sendable {
        let size: Int64
        let modificationDate: Date
    }

    private struct CachedRollout: Sendable {
        let signature: FileSignature
        let result: CodexRolloutParseResult
    }

    private struct ReadOutcome: Sendable {
        let result: CodexRolloutParseResult
        let changedDuringRead: Bool
        let scannedFileCount: Int
    }

    private struct SelectedThread {
        let entries: [UsageEntry]
        let warnings: Set<UsageWarningCategory>
        let coverageStart: Date?
        let coverageEnd: Date?
        let scannedFileCount: Int
    }

    private func readState() async throws -> StateResult {
        guard FileManager.default.fileExists(atPath: stateDatabaseURL.path) else {
            return .unavailable
        }

        let sql = """
        PRAGMA query_only=ON;
        BEGIN;
        SELECT id, rollout_path, created_at FROM threads ORDER BY created_at ASC, id ASC;
        COMMIT;
        """
        let data: Data
        do {
            data = try await queryRunner.query(databaseURL: stateDatabaseURL, sql: sql)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .unavailable
        }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let rows = object as? [[String: Any]] else {
            return .unavailable
        }

        var threads = [StateThread]()
        for row in rows {
            guard let rawID = row["id"] as? String, !rawID.isEmpty else {
                return .unavailable
            }
            let id = canonicalThreadID(rawID)
            let path = (row["rollout_path"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let createdAt = numberAsDouble(row["created_at"]).map(Date.init(timeIntervalSince1970:))
            threads.append(StateThread(id: id, rolloutPath: path, createdAt: createdAt, isKnownToState: true))
        }
        return .success(threads)
    }

    private func enumerateRolloutRoots() throws -> RootResult {
        var urls = [URL]()
        var anyEnumerable = false
        var hasEnumerationError = false
        for root in rolloutRoots {
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                hasEnumerationError = true
                continue
            }
            var recursiveError = false
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in
                    recursiveError = true
                    return true
                }
            ) else {
                hasEnumerationError = true
                continue
            }
            anyEnumerable = true
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                guard url.pathExtension.lowercased() == "jsonl" else { continue }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                urls.append(url)
            }
            if recursiveError {
                hasEnumerationError = true
            }
        }
        return RootResult(urls: urls, anyEnumerable: anyEnumerable, hasEnumerationError: hasEnumerationError)
    }

    private func identifiableThreadID(for url: URL) throws -> String? {
        do {
            if let metadataID = try sessionMetadataThreadID(for: url) {
                return metadataID
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
        }
        return candidateThreadID(for: url)
    }

    private func loadThread(
        _ thread: StateThread,
        fallbackURLs: [URL],
        window: UsageQueryWindow
    ) async throws -> SelectedThread {
        var warnings = Set<UsageWarningCategory>()
        var coverageStart = thread.createdAt
        var coverageEnd: Date?
        var scannedFileCount = 0

        if thread.isKnownToState, thread.rolloutPath == nil, fallbackURLs.isEmpty {
            warnings.insert(.codexRolloutUnreadable)
        }

        if let rawPath = thread.rolloutPath {
            let canonicalURL = URL(fileURLWithPath: rawPath)
            if let initialSignature = fileSignature(for: canonicalURL) {
                let identifiableID = try identifiableThreadID(for: canonicalURL)
                var signatureToRead: FileSignature?
                if let identifiableID, identifiableID != thread.id {
                    warnings.insert(.codexRolloutUnreadable)
                } else if initialSignature.modificationDate < window.startUTC {
                    if canOpenForReading(canonicalURL) {
                        if let refreshedSignature = fileSignature(for: canonicalURL) {
                            if refreshedSignature == initialSignature {
                                return SelectedThread(entries: [], warnings: warnings, coverageStart: coverageStart, coverageEnd: coverageEnd, scannedFileCount: 0)
                            }
                            signatureToRead = refreshedSignature
                        } else {
                            warnings.insert(.codexRolloutUnreadable)
                        }
                    } else {
                        warnings.insert(.codexRolloutUnreadable)
                    }
                } else {
                    signatureToRead = initialSignature
                }

                if let signatureToRead,
                   let outcome = try await readRollout(canonicalURL, threadID: thread.id, signature: signatureToRead) {
                    let result = outcome.result
                    let windowResult = result.entries(in: window)
                    warnings.formUnion(windowResult.warnings)
                    if outcome.changedDuringRead { warnings.insert(.codexRolloutChangedDuringRead) }
                    scannedFileCount += outcome.scannedFileCount
                    coverageStart = earlier(coverageStart, result.firstTokenEventAt)
                    coverageEnd = later(coverageEnd, result.lastTokenEventAt)
                    return SelectedThread(entries: windowResult.entries, warnings: warnings, coverageStart: coverageStart, coverageEnd: coverageEnd, scannedFileCount: scannedFileCount)
                } else if signatureToRead != nil {
                    warnings.insert(.codexRolloutUnreadable)
                }
            } else {
                warnings.insert(.codexRolloutUnreadable)
            }
        }

        let uniqueURLs = Array(Set(fallbackURLs)).sorted { $0.path < $1.path }
        var candidates = [(URL, FileSignature)]()
        for url in uniqueURLs {
            try Task.checkCancellation()
            guard let signature = fileSignature(for: url) else {
                warnings.insert(.codexRolloutUnreadable)
                continue
            }
            candidates.append((url, signature))
        }
        if !candidates.isEmpty,
           candidates.allSatisfy({ $0.1.modificationDate < window.startUTC }) {
            var refreshedCandidates = [(URL, FileSignature)]()
            var didChange = false
            for (url, signature) in candidates {
                try Task.checkCancellation()
                guard canOpenForReading(url), let refreshedSignature = fileSignature(for: url) else {
                    warnings.insert(.codexRolloutUnreadable)
                    continue
                }
                if refreshedSignature != signature {
                    didChange = true
                }
                refreshedCandidates.append((url, refreshedSignature))
            }
            if !didChange {
                return SelectedThread(entries: [], warnings: warnings, coverageStart: coverageStart, coverageEnd: coverageEnd, scannedFileCount: scannedFileCount)
            }
            candidates = refreshedCandidates
        }

        var parsed = [(URL, CodexRolloutParseResult, Bool)]()
        for (url, signature) in candidates {
            try Task.checkCancellation()
            guard let outcome = try await readRollout(url, threadID: thread.id, signature: signature) else {
                warnings.insert(.codexRolloutUnreadable)
                continue
            }
            scannedFileCount += outcome.scannedFileCount
            warnings.formUnion(outcome.result.warnings)
            if outcome.changedDuringRead { warnings.insert(.codexRolloutChangedDuringRead) }
            coverageStart = earlier(coverageStart, outcome.result.firstTokenEventAt)
            coverageEnd = later(coverageEnd, outcome.result.lastTokenEventAt)
            parsed.append((url, outcome.result, outcome.changedDuringRead))
        }

        guard let chosen = chooseFallback(parsed) else {
            return SelectedThread(entries: [], warnings: warnings, coverageStart: coverageStart, coverageEnd: coverageEnd, scannedFileCount: scannedFileCount)
        }
        if parsed.count > 1 {
            let allEqual = parsed.allSatisfy { $0.1.tokenEventFingerprint == chosen.1.tokenEventFingerprint && $0.1.samples == chosen.1.samples }
            if !allEqual { warnings.insert(.codexRolloutConflict) }
        }
        let windowResult = chosen.1.entries(in: window)
        warnings.formUnion(windowResult.warnings)
        return SelectedThread(entries: windowResult.entries, warnings: warnings, coverageStart: coverageStart, coverageEnd: coverageEnd, scannedFileCount: scannedFileCount)
    }

    private func chooseFallback(_ parsed: [(URL, CodexRolloutParseResult, Bool)]) -> (URL, CodexRolloutParseResult, Bool)? {
        guard let first = parsed.first else { return nil }
        return parsed.dropFirst().reduce(first) { best, candidate in
            let bestResult = best.1
            let candidateResult = candidate.1
            let bestDate = bestResult.lastTokenEventAt ?? .distantPast
            let candidateDate = candidateResult.lastTokenEventAt ?? .distantPast
            if candidateDate > bestDate { return candidate }
            if candidateDate == bestDate, candidateResult.completeByteCount > bestResult.completeByteCount { return candidate }
            return best
        }
    }

    private func readRollout(
        _ url: URL,
        threadID: String,
        signature initialSignature: FileSignature
    ) async throws -> ReadOutcome? {
        if let cached = cache[url], cached.signature == initialSignature, cached.result.threadID == threadID {
            return ReadOutcome(result: cached.result, changedDuringRead: false, scannedFileCount: 0)
        }
        cache.removeValue(forKey: url)

        var signature = initialSignature
        for attempt in 1...2 {
            try Task.checkCancellation()
            let result: CodexRolloutParseResult
            do {
                guard let parsed = try readRolloutBody(url: url, threadID: threadID) else { return nil }
                result = parsed
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                cache.removeValue(forKey: url)
                return nil
            }
            try Task.checkCancellation()
            hooks.didFinishReadAttempt(url, attempt)
            try Task.checkCancellation()
            let postSignature = fileSignature(for: url)
            if let postSignature, postSignature == signature {
                cache[url] = CachedRollout(signature: postSignature, result: result)
                return ReadOutcome(result: result, changedDuringRead: false, scannedFileCount: 1)
            }
            cache.removeValue(forKey: url)
            if attempt == 2 {
                return ReadOutcome(result: result, changedDuringRead: true, scannedFileCount: 1)
            }
            guard let nextSignature = fileSignature(for: url) else { return nil }
            signature = nextSignature
        }
        return nil
    }

    private func readRolloutBody(url: URL, threadID: String) throws -> CodexRolloutParseResult? {
        if hooks.shouldFailRead(url) { throw CodexUsageReadError.injected }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var parser = CodexRolloutUsageParser(threadID: threadID)
        var remainder = Data()
        var remainderStartOffset: Int64 = 0

        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty else { break }
            remainder.append(chunk)

            while let newline = remainder.firstIndex(of: 0x0a) {
                try Task.checkCancellation()
                var line = remainder.subdata(in: 0..<newline)
                if line.last == 0x0d { line.removeLast() }
                let endingOffset = remainderStartOffset + Int64(newline) + 1
                parser.consumeCompleteLine(line, endingByteOffset: endingOffset)
                remainder.removeSubrange(0...newline)
                remainderStartOffset = endingOffset
            }
        }

        return parser.finish(completeByteCount: remainderStartOffset)
    }

    private func fileSignature(for url: URL) -> FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }
        return FileSignature(size: size.int64Value, modificationDate: modificationDate)
    }

    private func canOpenForReading(_ url: URL) -> Bool {
        if hooks.shouldFailRead(url) { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        do {
            try handle.close()
            return true
        } catch {
            return false
        }
    }

    private func candidateThreadID(for url: URL) -> String? {
        let stem = url.deletingPathExtension().lastPathComponent
        if let uuid = UUID(uuidString: stem) {
            return uuid.uuidString.lowercased()
        }
        guard stem.hasPrefix("rollout-") else { return nil }
        let suffix = String(stem.suffix(36))
        if let uuid = UUID(uuidString: suffix) {
            return uuid.uuidString.lowercased()
        }
        return nil
    }

    private func canonicalThreadID(_ value: String) -> String {
        guard let uuid = UUID(uuidString: value) else { return value }
        return uuid.uuidString.lowercased()
    }

    private func sessionMetadataThreadID(for url: URL) throws -> String? {
        if hooks.shouldFailRead(url) { throw CodexUsageReadError.injected }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var remainder = Data()
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty else { return nil }
            remainder.append(chunk)
            guard let newline = remainder.firstIndex(of: 0x0a) else { continue }
            var line = remainder.subdata(in: 0..<newline)
            if line.last == 0x0d { line.removeLast() }
            guard let metadata = try? JSONDecoder().decode(SessionMetadataEnvelope.self, from: line),
                  metadata.type == "session_meta",
                  let id = metadata.payload?.id,
                  !id.isEmpty else {
                return nil
            }
            guard let uuid = UUID(uuidString: id) else { return nil }
            return uuid.uuidString.lowercased()
        }
    }

    private func earlier(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (nil, nil): nil
        case (let lhs?, nil): lhs
        case (nil, let rhs?): rhs
        case (let lhs?, let rhs?): min(lhs, rhs)
        }
    }

    private func later(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (nil, nil): nil
        case (let lhs?, nil): lhs
        case (nil, let rhs?): rhs
        case (let lhs?, let rhs?): max(lhs, rhs)
        }
    }

    private func preferredStateThread(_ lhs: StateThread, _ rhs: StateThread) -> StateThread {
        let lhsRank = stateThreadPathRank(lhs.rolloutPath)
        let rhsRank = stateThreadPathRank(rhs.rolloutPath)
        let preferred: StateThread
        if lhsRank != rhsRank {
            preferred = lhsRank > rhsRank ? lhs : rhs
        } else {
            preferred = (lhs.rolloutPath ?? "") <= (rhs.rolloutPath ?? "") ? lhs : rhs
        }
        return StateThread(
            id: preferred.id,
            rolloutPath: preferred.rolloutPath,
            createdAt: earlier(lhs.createdAt, rhs.createdAt),
            isKnownToState: true
        )
    }

    private func stateThreadPathRank(_ path: String?) -> Int {
        guard let path else { return 0 }
        let url = URL(fileURLWithPath: path)
        guard fileSignature(for: url) != nil else { return 1 }
        return canOpenForReading(url) ? 2 : 1
    }

    private func saturatedIntAdd(_ lhs: Int, _ rhs: Int, warnings: inout Set<UsageWarningCategory>) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        if result.overflow {
            warnings.insert(.numericOverflow)
            return Int.max
        }
        return result.partialValue
    }
}

private enum CodexUsageReadError: Error {
    case injected
}

private struct SessionMetadataEnvelope: Decodable {
    let type: String?
    let payload: Payload?

    struct Payload: Decodable {
        let id: String?
    }
}

private func numberAsDouble(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber else { return nil }
    return number.doubleValue
}
