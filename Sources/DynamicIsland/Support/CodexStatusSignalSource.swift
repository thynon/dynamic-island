import Foundation
import DynamicIslandCore

final class CodexStatusSignalSource: @unchecked Sendable {
    private enum RolloutLifecycle {
        case unknown
        case running
        case terminal
    }

    private struct ThreadRecord {
        let id: String
        let threadTitle: String?
        let tokensUsed: Int
        let rolloutPath: String?
        let parentThreadID: String?
        let rootThreadID: String?
        let agentNickname: String?
        let agentDepth: Int

        var isSubagent: Bool {
            parentThreadID != nil
        }
    }

    private struct RolloutState {
        var totalTokens: Int?
        var startedAt: TimeInterval?
        var completedAt: TimeInterval?
        var durationMilliseconds: Int?
        var activityState: CodexStatusBarSnapshot.ActivityState?
        var approvalState: CodexTaskStatus.ApprovalState = .none
        var hasRecentActivity = false
        var lifecycle: RolloutLifecycle = .unknown
        var lastEventAt: TimeInterval?
        var turnID: String?
        var progressEvents: [CodexSessionProgressEvent] = []
        var progressEventSequence = 0

        var isRunning: Bool {
            switch lifecycle {
            case .unknown:
                startedAt.map { $0 > (completedAt ?? 0) } ?? false
            case .running:
                true
            case .terminal:
                false
            }
        }

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
    private let iso8601DateFormatter = ISO8601DateFormatter()
    private let codexStateDatabaseRelativePath = ".codex/state_5.sqlite"
    private let codexGlobalStateRelativePath = ".codex/.codex-global-state.json"
    private let rolloutFastTailMaximumBytes = 128 * 1024
    private let rolloutExpandedTailMaximumBytes = 8 * 1024 * 1024
    private let threadRefreshInterval: TimeInterval = 5
    private let globalStateRefreshInterval: TimeInterval = 1
    private let completedTaskRetentionDuration: TimeInterval = 10
    private let staleTaskTimeoutDuration: TimeInterval = 60
    private let progressEventLimit = 12
    private var cachedThreadRecords: [ThreadRecord] = []
    private var cachedThreadRefreshDate: Date?
    private var cachedGlobalApprovalStates: [String: CodexTaskStatus.ApprovalState] = [:]
    private var cachedGlobalStateRefreshDate: Date?
    private var cachedGlobalStateSignature: RolloutFileSignature?
    private var cachedGlobalStateThreadIDs: Set<String> = []
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
        guard !threads.isEmpty else {
            return .unavailable
        }

        let globalApprovalStates = readGlobalApprovalStatesIfNeeded(
            threadIDs: Set(threads.map(\.id)),
            now: now
        )
        let tasks = threads.compactMap {
            taskStatus(for: $0, now: now, globalApprovalState: globalApprovalStates[$0.id])
        }
        let primaryTask = tasks.first(where: { !$0.isSubagent }) ?? tasks.first
        let primaryThreadID = primaryTask?.rootThreadID ?? primaryTask?.id
        let primaryThread = primaryThreadID.flatMap { id in
            threads.first(where: { $0.id == id })
        } ?? threads.first(where: { !$0.isSubagent }) ?? threads[0]

        return CodexStatusBarSnapshot(
            threadID: primaryThread.id,
            threadTitle: primaryThread.threadTitle,
            elapsedSeconds: primaryTask?.elapsedSeconds ?? 0,
            totalTokens: primaryTask?.totalTokens ?? primaryThread.tokensUsed,
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
        WITH RECURSIVE
        root_threads AS (
            SELECT
                id,
                title,
                tokens_used,
                rollout_path,
                updated_at_ms,
                NULL AS parent_thread_id,
                id AS root_thread_id,
                NULL AS agent_nickname,
                0 AS agent_depth,
                0 AS is_subagent
            FROM threads
            WHERE archived = 0
              AND COALESCE(thread_source, 'user') <> 'subagent'
            ORDER BY updated_at_ms DESC
            LIMIT 8
        ),
        agent_tree AS (
            SELECT
                thread.id,
                thread.title,
                thread.tokens_used,
                thread.rollout_path,
                thread.updated_at_ms,
                json_extract(thread.source, '$.subagent.thread_spawn.parent_thread_id') AS parent_thread_id,
                root.id AS root_thread_id,
                thread.agent_nickname,
                COALESCE(json_extract(thread.source, '$.subagent.thread_spawn.depth'), 1) AS agent_depth,
                1 AS is_subagent
            FROM threads AS thread
            JOIN root_threads AS root
              ON json_extract(thread.source, '$.subagent.thread_spawn.parent_thread_id') = root.id
            WHERE thread.archived = 0
              AND thread.thread_source = 'subagent'

            UNION ALL

            SELECT
                thread.id,
                thread.title,
                thread.tokens_used,
                thread.rollout_path,
                thread.updated_at_ms,
                json_extract(thread.source, '$.subagent.thread_spawn.parent_thread_id') AS parent_thread_id,
                parent.root_thread_id,
                thread.agent_nickname,
                COALESCE(json_extract(thread.source, '$.subagent.thread_spawn.depth'), parent.agent_depth + 1) AS agent_depth,
                1 AS is_subagent
            FROM threads AS thread
            JOIN agent_tree AS parent
              ON json_extract(thread.source, '$.subagent.thread_spawn.parent_thread_id') = parent.id
            WHERE thread.archived = 0
              AND thread.thread_source = 'subagent'
        ),
        selected_agents AS (
            SELECT *
            FROM agent_tree
            ORDER BY updated_at_ms DESC
            LIMIT 24
        )
        SELECT * FROM root_threads
        UNION ALL
        SELECT * FROM selected_agents
        ORDER BY is_subagent ASC, updated_at_ms DESC;
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
                rolloutPath: row["rollout_path"] as? String,
                parentThreadID: row["parent_thread_id"] as? String,
                rootThreadID: row["root_thread_id"] as? String,
                agentNickname: row["agent_nickname"] as? String,
                agentDepth: intValue(row["agent_depth"]) ?? 0
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
        let isTerminal = rolloutState?.lifecycle == .terminal
        let approvalState = isTerminal
            ? .none
            : resolvedApprovalState(
                rolloutState: rolloutState?.approvalState ?? .none,
                globalApprovalState: globalApprovalState ?? .none
            )
        let isRunning = rolloutState?.isRunning ?? false
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
            approvalState: approvalState,
            parentThreadID: thread.parentThreadID,
            rootThreadID: thread.rootThreadID,
            agentNickname: thread.agentNickname,
            agentDepth: thread.agentDepth,
            turnID: rolloutState?.turnID,
            completedAt: rolloutState?.completedAt,
            progressEvents: rolloutState?.progressEvents ?? []
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
            if let lastEventAt = rolloutState?.lastEventAt,
               now.timeIntervalSince1970 - lastEventAt > staleTaskTimeoutDuration
            {
                return false
            }
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
        state.lastEventAt = signature?.modificationDate?.timeIntervalSince1970
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
            state.turnID = stringValue(payload["turn_id"])
                ?? stringValue(payload["turnId"])
                ?? stringValue(event["turn_id"])
                ?? stringValue(event["turnId"])
                ?? state.turnID
            applyAppServerNotification(event, payload: payload, to: &state)
            if event["type"] as? String == "event_msg" {
                applyEventMessagePayload(payload, event: event, to: &state)
            } else if event["type"] as? String == "response_item" {
                applyResponseItemPayload(payload, event: event, to: &state)
            }
        }
        return state
    }

    private func applyEventMessagePayload(
        _ payload: [String: Any],
        event: [String: Any],
        to state: inout RolloutState
    ) {
        switch payload["type"] as? String {
        case "task_started":
            state.progressEvents.removeAll(keepingCapacity: true)
            state.progressEventSequence = 0
            state.startedAt = doubleValue(payload["started_at"])
            state.lifecycle = .running
            state.activityState = .thinking
            appendProgressEvent(kind: .started, occurredAt: eventTimestamp(event), to: &state)
        case "task_complete":
            completeTurn(payload: payload, event: event, state: &state)
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
            if state.lifecycle != .terminal {
                state.lifecycle = .running
            }
            state.activityState = .writing
            appendProgressEvent(kind: .responding, occurredAt: eventTimestamp(event), to: &state)
        case "agent_reasoning":
            state.hasRecentActivity = true
            if state.lifecycle != .terminal {
                state.lifecycle = .running
            }
            state.activityState = .thinking
            appendProgressEvent(kind: .thinking, occurredAt: eventTimestamp(event), to: &state)
        case "error":
            state.hasRecentActivity = true
            if state.lifecycle != .terminal {
                state.lifecycle = .running
            }
            state.activityState = .retrying
            appendProgressEvent(kind: .retrying, occurredAt: eventTimestamp(event), to: &state)
        case "turn_aborted":
            completeTurn(payload: payload, event: event, state: &state)
        case "turn_failed", "turn_cancelled":
            completeTurn(payload: payload, event: event, state: &state)
        case "exec_approval_request", "command_execution_request_approval":
            state.approvalState = .pendingCommand
            state.activityState = .waitingApproval
            appendProgressEvent(kind: .waitingApproval, occurredAt: eventTimestamp(event), to: &state)
        case "apply_patch_approval_request", "patch_approval_request", "file_change_request_approval":
            state.approvalState = .pendingFileChange
            state.activityState = .waitingApproval
            appendProgressEvent(kind: .waitingApproval, occurredAt: eventTimestamp(event), to: &state)
        case "request_permissions", "permissions_request_approval":
            state.approvalState = .pendingPermissions
            state.activityState = .waitingApproval
            appendProgressEvent(kind: .waitingApproval, occurredAt: eventTimestamp(event), to: &state)
        default:
            if let message = payload["message"] as? String,
               message.localizedCaseInsensitiveContains("compacting")
            {
                state.activityState = .compacting
                appendProgressEvent(kind: .compacting, occurredAt: eventTimestamp(event), to: &state)
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
            appendProgressEvent(kind: .waitingApproval, occurredAt: eventTimestamp(event), to: &state)
        case "item/fileChange/requestApproval":
            state.approvalState = .pendingFileChange
            state.activityState = .waitingApproval
            appendProgressEvent(kind: .waitingApproval, occurredAt: eventTimestamp(event), to: &state)
        case "item/permissions/requestApproval":
            state.approvalState = .pendingPermissions
            state.activityState = .waitingApproval
            appendProgressEvent(kind: .waitingApproval, occurredAt: eventTimestamp(event), to: &state)
        case "item/autoApprovalReview/started":
            if state.approvalState == .none {
                state.approvalState = .autoReviewing
            }
        case "item/autoApprovalReview/completed":
            if state.approvalState == .autoReviewing {
                state.approvalState = .none
            }
        case "serverRequest/resolved":
            state.approvalState = .none
        case "turn/completed", "turn/aborted", "turn/cancelled", "turn/failed":
            completeTurn(payload: payload, event: event, state: &state)
        default:
            break
        }
    }

    private func applyResponseItemPayload(
        _ payload: [String: Any],
        event: [String: Any],
        to state: inout RolloutState
    ) {
        state.hasRecentActivity = true
        if state.lifecycle != .terminal {
            state.lifecycle = .running
        }

        switch stringValue(payload["type"]) {
        case "reasoning":
            state.activityState = .thinking
            appendProgressEvent(kind: .thinking, occurredAt: eventTimestamp(event), to: &state)
        case "custom_tool_call", "function_call":
            state.activityState = .runningTool
            appendProgressEvent(
                kind: .tool,
                occurredAt: eventTimestamp(event),
                displayText: sanitizedToolProgressText(stringValue(payload["name"])),
                to: &state
            )
        case "message":
            state.activityState = .writing
            appendProgressEvent(kind: .responding, occurredAt: eventTimestamp(event), to: &state)
        default:
            if payload["name"] != nil || payload["arguments"] != nil {
                state.activityState = .runningTool
                appendProgressEvent(
                    kind: .tool,
                    occurredAt: eventTimestamp(event),
                    displayText: sanitizedToolProgressText(stringValue(payload["name"])),
                    to: &state
                )
            } else if payload["phase"] != nil || payload["role"] as? String == "assistant" {
                state.activityState = .writing
                appendProgressEvent(kind: .responding, occurredAt: eventTimestamp(event), to: &state)
            }
        }
    }

    private func completeTurn(
        payload: [String: Any],
        event: [String: Any],
        state: inout RolloutState
    ) {
        let completedAt = doubleValue(payload["completed_at"])
            ?? eventTimestamp(event)
            ?? Date().timeIntervalSince1970
        state.completedAt = completedAt
        if let durationMilliseconds = intValue(payload["duration_ms"]) {
            state.durationMilliseconds = durationMilliseconds
        } else if let startedAt = state.startedAt {
            state.durationMilliseconds = max(0, Int(((completedAt - startedAt) * 1000).rounded()))
        }
        state.lifecycle = .terminal
        state.activityState = .idle
        state.approvalState = .none
        appendProgressEvent(
            kind: .completed,
            occurredAt: completedAt,
            displayText: completionProgressText(payload: payload, event: event),
            to: &state
        )
    }

    private func appendProgressEvent(
        kind: CodexSessionProgressEvent.Kind,
        occurredAt: TimeInterval?,
        displayText: String? = nil,
        to state: inout RolloutState
    ) {
        let event = CodexSessionProgressEvent(
            id: "\(kind.rawValue)-\(Int((occurredAt ?? 0) * 1000))-\(state.progressEventSequence)",
            kind: kind,
            occurredAt: occurredAt,
            displayText: displayText
        )
        guard state.progressEvents.last?.kind != event.kind
            || state.progressEvents.last?.displayText != event.displayText
        else {
            return
        }

        state.progressEventSequence += 1
        state.progressEvents.append(event)
        if state.progressEvents.count > progressEventLimit {
            state.progressEvents.removeFirst(state.progressEvents.count - progressEventLimit)
        }
    }

    private func sanitizedToolProgressText(_ name: String?) -> String {
        let normalizedName = name?.lowercased() ?? ""
        if normalizedName.contains("apply_patch") {
            return "修改文件"
        }
        if normalizedName.contains("view_image") {
            return "查看图像"
        }
        if normalizedName.contains("imagegen") || normalizedName.contains("image_gen") {
            return "生成图像"
        }
        if normalizedName == "wait" || normalizedName.hasSuffix("__wait") {
            return "等待工具"
        }
        if normalizedName.contains("exec") {
            return "运行命令"
        }
        return "运行工具"
    }

    private func completionProgressText(
        payload: [String: Any],
        event: [String: Any]
    ) -> String {
        let terminalType = stringValue(payload["type"])
            ?? stringValue(event["method"])
            ?? ""
        if terminalType.localizedCaseInsensitiveContains("aborted")
            || terminalType.localizedCaseInsensitiveContains("cancelled")
        {
            return "会话已中止"
        }
        if terminalType.localizedCaseInsensitiveContains("failed") {
            return "会话失败"
        }
        return "完成本轮会话"
    }

    private func eventTimestamp(_ event: [String: Any]) -> TimeInterval? {
        guard let rawTimestamp = event["timestamp"] as? String else { return nil }
        return iso8601DateFormatter.date(from: rawTimestamp)?.timeIntervalSince1970
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
           now.timeIntervalSince(cachedGlobalStateRefreshDate) < globalStateRefreshInterval,
           cachedGlobalStateThreadIDs == threadIDs
        {
            return cachedGlobalApprovalStates
        }

        let signature = rolloutFileSignature(at: codexGlobalStateURL)
        if cachedGlobalStateRefreshDate != nil,
           cachedGlobalStateSignature == signature,
           cachedGlobalStateThreadIDs == threadIDs
        {
            cachedGlobalStateRefreshDate = now
            return cachedGlobalApprovalStates
        }

        let states = readGlobalApprovalStates(threadIDs: threadIDs)
        cachedGlobalApprovalStates = states
        cachedGlobalStateRefreshDate = now
        cachedGlobalStateSignature = signature
        cachedGlobalStateThreadIDs = threadIDs
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
