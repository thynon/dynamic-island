import Foundation
import DynamicIslandCore

final class CodexStatusSignalSource: @unchecked Sendable {
    private struct ThreadRecord {
        let id: String
        let threadTitle: String?
        let tokensUsed: Int
        let rolloutPath: String?
    }

    private struct RolloutState {
        var totalTokens: Int?
        var startedAt: TimeInterval?
        var completedAt: TimeInterval?
        var durationMilliseconds: Int?
        var activityState: CodexStatusBarSnapshot.ActivityState?
        var approvalState: CodexTaskStatus.ApprovalState = .none
        var hasRecentActivity = false

        var needsExpandedTailRead: Bool {
            hasRecentActivity && startedAt == nil && completedAt == nil && !approvalState.isVisible
        }
    }

    private struct RolloutFileSignature: Equatable {
        let fileSize: UInt64
        let modificationDate: Date?
    }

    private struct CachedRolloutState {
        let signature: RolloutFileSignature
        let state: RolloutState?
    }

    private let homeDirectoryURL: URL
    private let fileManager: FileManager
    private let sqliteExecutableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    private let codexStateDatabaseRelativePath = ".codex/state_5.sqlite"
    private let codexGlobalStateRelativePath = ".codex/.codex-global-state.json"
    private let rolloutFastTailMaximumBytes = 128 * 1024
    private let rolloutExpandedTailMaximumBytes = 8 * 1024 * 1024
    private let threadRefreshInterval: TimeInterval = 5
    private let globalStateRefreshInterval: TimeInterval = 1
    private let completedTaskRetentionDuration: TimeInterval = 10
    private var cachedThreadRecords: [ThreadRecord] = []
    private var cachedThreadRefreshDate: Date?
    private var cachedGlobalApprovalStates: [String: CodexTaskStatus.ApprovalState] = [:]
    private var cachedGlobalStateRefreshDate: Date?
    private var cachedRolloutStates: [String: CachedRolloutState] = [:]

    init(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.homeDirectoryURL = homeDirectoryURL
        self.fileManager = fileManager
    }

    func currentSnapshot(now: Date = Date()) -> CodexStatusBarSnapshot {
        let threads = readLatestThreadRecordsIfNeeded(now: now)
        guard let thread = threads.first else {
            return .unavailable
        }

        let globalApprovalStates = readGlobalApprovalStatesIfNeeded(
            threadIDs: Set(threads.map(\.id)),
            now: now
        )
        let tasks = threads.compactMap {
            taskStatus(for: $0, now: now, globalApprovalState: globalApprovalStates[$0.id])
        }
        let primaryTask = tasks.first

        return CodexStatusBarSnapshot(
            threadID: thread.id,
            threadTitle: thread.threadTitle,
            elapsedSeconds: primaryTask?.elapsedSeconds ?? 0,
            totalTokens: primaryTask?.totalTokens ?? thread.tokensUsed,
            runningTasksCount: tasks.filter(\.activityState.isWorking).count,
            activityState: primaryTask?.activityState ?? .idle,
            tasks: tasks
        )
    }

    private var codexStateDatabaseURL: URL {
        homeDirectoryURL.appendingPathComponent(codexStateDatabaseRelativePath)
    }

    private var codexGlobalStateURL: URL {
        homeDirectoryURL.appendingPathComponent(codexGlobalStateRelativePath)
    }

    private func readLatestThreadRecordsIfNeeded(now: Date) -> [ThreadRecord] {
        if let cachedThreadRefreshDate,
           now.timeIntervalSince(cachedThreadRefreshDate) < threadRefreshInterval
        {
            return cachedThreadRecords
        }

        let records = readLatestThreadRecords()
        cachedThreadRecords = records
        cachedThreadRefreshDate = now
        return records
    }

    private func readLatestThreadRecords() -> [ThreadRecord] {
        guard fileManager.fileExists(atPath: codexStateDatabaseURL.path) else { return [] }
        let query = """
        SELECT id, title, tokens_used, rollout_path FROM threads WHERE archived=0 ORDER BY updated_at_ms DESC LIMIT 4;
        """
        guard let output = runSQLiteQuery(query),
              let data = output.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }

        return rows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return ThreadRecord(
                id: id,
                threadTitle: row["title"] as? String,
                tokensUsed: intValue(row["tokens_used"]) ?? 0,
                rolloutPath: row["rollout_path"] as? String
            )
        }
    }

    private func taskStatus(
        for thread: ThreadRecord,
        now: Date,
        globalApprovalState: CodexTaskStatus.ApprovalState?
    ) -> CodexTaskStatus? {
        let rolloutState = thread.rolloutPath
            .flatMap { readRolloutState(from: URL(fileURLWithPath: $0)) }
        let approvalState = resolvedApprovalState(
            rolloutState: rolloutState?.approvalState ?? .none,
            globalApprovalState: globalApprovalState ?? .none
        )
        let isRunning = rolloutState?.startedAt.map { startedAt in
            startedAt > (rolloutState?.completedAt ?? 0)
        } ?? false
        guard isTaskVisible(
            rolloutState: rolloutState,
            isRunning: isRunning,
            approvalState: approvalState,
            now: now
        ) else {
            return nil
        }

        let elapsedSeconds: Int
        if isRunning, let startedAt = rolloutState?.startedAt {
            elapsedSeconds = Int(max(0, now.timeIntervalSince1970 - startedAt).rounded(.down))
        } else if let durationMilliseconds = rolloutState?.durationMilliseconds {
            elapsedSeconds = max(0, durationMilliseconds / 1000)
        } else {
            elapsedSeconds = 0
        }

        return CodexTaskStatus(
            id: thread.id,
            title: thread.threadTitle ?? "Codex",
            elapsedSeconds: elapsedSeconds,
            totalTokens: rolloutState?.totalTokens ?? thread.tokensUsed,
            activityState: activityState(
                isRunning: isRunning,
                rolloutState: rolloutState,
                approvalState: approvalState
            ),
            approvalState: approvalState
        )
    }

    private func resolvedApprovalState(
        rolloutState: CodexTaskStatus.ApprovalState,
        globalApprovalState: CodexTaskStatus.ApprovalState
    ) -> CodexTaskStatus.ApprovalState {
        if rolloutState.isVisible, rolloutState != .autoReviewing {
            return rolloutState
        }
        if globalApprovalState.isVisible {
            return globalApprovalState
        }
        return rolloutState
    }

    private func activityState(
        isRunning: Bool,
        rolloutState: RolloutState?,
        approvalState: CodexTaskStatus.ApprovalState
    ) -> CodexStatusBarSnapshot.ActivityState {
        if approvalState.isVisible, approvalState != .autoReviewing {
            return .waitingApproval
        }
        if isRunning {
            return rolloutState?.activityState ?? .thinking
        }
        return .idle
    }

    private func isTaskVisible(
        rolloutState: RolloutState?,
        isRunning: Bool,
        approvalState: CodexTaskStatus.ApprovalState,
        now: Date
    ) -> Bool {
        if approvalState.isVisible {
            return true
        }
        if isRunning {
            return true
        }
        guard let completedAt = rolloutState?.completedAt else {
            return false
        }
        return now.timeIntervalSince1970 - completedAt <= completedTaskRetentionDuration
    }

    private func readRolloutState(from url: URL) -> RolloutState? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let signature = rolloutFileSignature(at: url)
        if let signature,
           let cached = cachedRolloutStates[url.path],
           cached.signature == signature
        {
            return cached.state
        }

        let fastLines = readRecentLines(from: url, maximumBytes: rolloutFastTailMaximumBytes)
        guard !fastLines.isEmpty else {
            cacheRolloutState(nil, signature: signature, path: url.path)
            return nil
        }

        var state = rolloutState(from: fastLines)
        if state.needsExpandedTailRead {
            let expandedLines = readRecentLines(from: url, maximumBytes: rolloutExpandedTailMaximumBytes)
            if !expandedLines.isEmpty {
                state = rolloutState(from: expandedLines)
            }
        }
        cacheRolloutState(state, signature: signature, path: url.path)
        return state
    }

    private func rolloutFileSignature(at url: URL) -> RolloutFileSignature? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date
        return RolloutFileSignature(fileSize: fileSize, modificationDate: modificationDate)
    }

    private func cacheRolloutState(_ state: RolloutState?, signature: RolloutFileSignature?, path: String) {
        guard let signature else { return }
        cachedRolloutStates[path] = CachedRolloutState(signature: signature, state: state)
    }

    private func rolloutState(from lines: [String]) -> RolloutState {
        var state = RolloutState()
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let event = object as? [String: Any]
            else {
                continue
            }

            let payload = event["payload"] as? [String: Any] ?? [:]
            applyAppServerNotification(event, payload: payload, to: &state)
            if event["type"] as? String == "event_msg" {
                applyEventMessagePayload(payload, to: &state)
            } else if event["type"] as? String == "response_item" {
                applyResponseItemPayload(payload, to: &state)
            }
        }
        return state
    }

    private func applyEventMessagePayload(_ payload: [String: Any], to state: inout RolloutState) {
        switch payload["type"] as? String {
        case "task_started":
            state.startedAt = doubleValue(payload["started_at"])
            state.activityState = .thinking
        case "task_complete":
            state.completedAt = doubleValue(payload["completed_at"])
            state.durationMilliseconds = intValue(payload["duration_ms"])
            state.activityState = .idle
            state.approvalState = .none
        case "token_count":
            state.hasRecentActivity = true
            if let info = payload["info"] as? [String: Any],
               let usage = info["total_token_usage"] as? [String: Any],
               let totalTokens = intValue(usage["total_tokens"])
            {
                state.totalTokens = totalTokens
            }
        case "agent_message":
            state.hasRecentActivity = true
            state.activityState = .writing
        case "error":
            state.hasRecentActivity = true
            state.activityState = .retrying
        case "turn_aborted":
            state.approvalState = .none
        case "exec_approval_request", "command_execution_request_approval":
            state.approvalState = .pendingCommand
            state.activityState = .waitingApproval
        case "apply_patch_approval_request", "patch_approval_request", "file_change_request_approval":
            state.approvalState = .pendingFileChange
            state.activityState = .waitingApproval
        case "request_permissions", "permissions_request_approval":
            state.approvalState = .pendingPermissions
            state.activityState = .waitingApproval
        default:
            if let message = payload["message"] as? String,
               message.localizedCaseInsensitiveContains("compacting")
            {
                state.activityState = .compacting
            }
        }
    }

    private func applyAppServerNotification(
        _ event: [String: Any],
        payload: [String: Any],
        to state: inout RolloutState
    ) {
        let method = stringValue(event["method"]) ?? stringValue(payload["method"])
        switch method {
        case "item/commandExecution/requestApproval":
            state.approvalState = .pendingCommand
            state.activityState = .waitingApproval
        case "item/fileChange/requestApproval":
            state.approvalState = .pendingFileChange
            state.activityState = .waitingApproval
        case "item/permissions/requestApproval":
            state.approvalState = .pendingPermissions
            state.activityState = .waitingApproval
        case "item/autoApprovalReview/started":
            if state.approvalState == .none {
                state.approvalState = .autoReviewing
            }
        case "item/autoApprovalReview/completed":
            if state.approvalState == .autoReviewing {
                state.approvalState = .none
            }
        case "serverRequest/resolved", "turn/completed":
            state.approvalState = .none
        default:
            break
        }
    }

    private func applyResponseItemPayload(_ payload: [String: Any], to state: inout RolloutState) {
        state.hasRecentActivity = true
        if payload["name"] != nil || payload["arguments"] != nil {
            state.activityState = .runningTool
        } else if payload["phase"] != nil || payload["role"] as? String == "assistant" {
            state.activityState = .writing
        }
    }

    private func readRecentLines(from url: URL, maximumBytes: Int) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readOffset = fileSize > UInt64(maximumBytes)
            ? fileSize - UInt64(maximumBytes)
            : 0
        try? handle.seek(toOffset: readOffset)
        let data = handle.readDataToEndOfFile()
        guard var text = String(data: data, encoding: .utf8) else { return [] }

        if readOffset > 0, let firstNewline = text.firstIndex(of: "\n") {
            text.removeSubrange(...firstNewline)
        }
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func readGlobalApprovalStatesIfNeeded(
        threadIDs: Set<String>,
        now: Date
    ) -> [String: CodexTaskStatus.ApprovalState] {
        if let cachedGlobalStateRefreshDate,
           now.timeIntervalSince(cachedGlobalStateRefreshDate) < globalStateRefreshInterval
        {
            return cachedGlobalApprovalStates
        }

        let states = readGlobalApprovalStates(threadIDs: threadIDs)
        cachedGlobalApprovalStates = states
        cachedGlobalStateRefreshDate = now
        return states
    }

    private func readGlobalApprovalStates(
        threadIDs: Set<String>
    ) -> [String: CodexTaskStatus.ApprovalState] {
        guard !threadIDs.isEmpty,
              fileManager.fileExists(atPath: codexGlobalStateURL.path),
              let data = try? Data(contentsOf: codexGlobalStateURL),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return [:]
        }

        var states: [String: CodexTaskStatus.ApprovalState] = [:]
        for threadID in threadIDs where globalStateIndicatesWaitingApproval(object, threadID: threadID) {
            states[threadID] = .pending
        }
        return states
    }

    private func globalStateIndicatesWaitingApproval(
        _ value: Any,
        threadID: String,
        isNearThread: Bool = false,
        depth: Int = 0
    ) -> Bool {
        guard depth <= 8 else { return false }

        if let dictionary = value as? [String: Any] {
            let nearThread = isNearThread || dictionaryContainsThreadID(dictionary, threadID: threadID)
            if nearThread, dictionaryContainsWaitingOnApproval(dictionary) {
                return true
            }
            return dictionary.values.contains {
                globalStateIndicatesWaitingApproval(
                    $0,
                    threadID: threadID,
                    isNearThread: nearThread,
                    depth: depth + 1
                )
            }
        }

        if let array = value as? [Any] {
            return array.contains {
                globalStateIndicatesWaitingApproval(
                    $0,
                    threadID: threadID,
                    isNearThread: isNearThread,
                    depth: depth + 1
                )
            }
        }

        return false
    }

    private func dictionaryContainsThreadID(
        _ dictionary: [String: Any],
        threadID: String
    ) -> Bool {
        if dictionary.keys.contains(threadID) {
            return true
        }

        for (key, value) in dictionary {
            if key == "threadId" || key == "thread_id" || key == "id" {
                if stringValue(value) == threadID {
                    return true
                }
            } else if stringValue(value) == threadID {
                return true
            }
        }
        return false
    }

    private func dictionaryContainsWaitingOnApproval(_ dictionary: [String: Any]) -> Bool {
        for (key, value) in dictionary {
            let normalizedKey = normalizeStateToken(key)
            if (key == "waitingOnApproval" || normalizedKey == "waitingonapproval"),
               boolValue(value) == true
            {
                return true
            }
            if normalizedKey == "activeflags", collectionContainsWaitingOnApproval(value) {
                return true
            }
        }
        return false
    }

    private func collectionContainsWaitingOnApproval(_ value: Any) -> Bool {
        if normalizeStateToken(stringValue(value)) == "waitingonapproval" {
            return true
        }

        if let array = value as? [Any] {
            return array.contains { collectionContainsWaitingOnApproval($0) }
        }

        if let dictionary = value as? [String: Any] {
            return dictionary.contains { key, value in
                (key == "waitingOnApproval" || normalizeStateToken(key) == "waitingonapproval")
                    && boolValue(value) != false
            }
        }

        return false
    }

    private func runSQLiteQuery(_ query: String) -> String? {
        guard fileManager.fileExists(atPath: sqliteExecutableURL.path) else { return nil }

        let process = Process()
        process.executableURL = sqliteExecutableURL
        process.arguments = [
            "-batch",
            "-json",
            codexStateDatabaseURL.path,
            query
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func doubleValue(_ value: Any?) -> TimeInterval? {
        if let double = value as? Double { return double }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return TimeInterval(string) }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            if string == "true" { return true }
            if string == "false" { return false }
        }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func normalizeStateToken(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }
}
