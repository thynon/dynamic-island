public enum CodexJSONRPCRequestID: Equatable, Hashable, Sendable {
    case string(String)
    case integer(Int64)
}

public enum CodexApprovalDecision: String, Equatable, Hashable, Sendable {
    case decline
    case accept
    case acceptForSession
}

public enum CodexApprovalKind: String, Equatable, Sendable {
    case command
    case fileChange
    case permissions
}

public enum CodexApprovalSource: Equatable, Sendable {
    case passiveObservation
    case managedAppServer
}

public enum CodexApprovalAutoPresentationAction: Equatable, Sendable {
    case ignore
    case selectTaskOnly
    case selectTasks
    case selectTasksAndExpand
}

public enum CodexApprovalAutoPresentationPolicy {
    public static func action(
        isShellHidden: Bool,
        isFilesPinned: Bool,
        isExpanded: Bool
    ) -> CodexApprovalAutoPresentationAction {
        if isShellHidden {
            return .ignore
        }
        if isFilesPinned {
            return .selectTaskOnly
        }
        return isExpanded ? .selectTasks : .selectTasksAndExpand
    }
}

public enum CodexApprovalSubmissionState: Equatable, Sendable {
    case ready
    case submitting(CodexApprovalDecision)
    case failed(String)
}

public struct CodexApprovalRequest: Equatable, Identifiable, Sendable {
    public struct ID: Equatable, Hashable, Sendable {
        fileprivate enum Storage: Equatable, Hashable, Sendable {
            case managed(requestID: CodexJSONRPCRequestID, threadID: String)
            case managedWithoutRequestID(
                threadID: String,
                turnID: String,
                itemID: String?,
                approvalID: String?,
                kindRawValue: String
            )
            case passive(threadID: String, turnID: String, kindRawValue: String)
        }

        fileprivate let storage: Storage
    }

    public let requestID: CodexJSONRPCRequestID?
    public let threadID: String
    public let turnID: String
    public let itemID: String?
    public let approvalID: String?
    public let kind: CodexApprovalKind
    public let startedAtMilliseconds: Int64
    public let source: CodexApprovalSource
    public let availableDecisions: [CodexApprovalDecision]
    public let reviewSummary: String?

    public var id: ID {
        switch (source, requestID) {
        case let (.managedAppServer, requestID?):
            return ID(storage: .managed(requestID: requestID, threadID: threadID))
        case (.managedAppServer, nil):
            return ID(
                storage: .managedWithoutRequestID(
                    threadID: threadID,
                    turnID: turnID,
                    itemID: itemID,
                    approvalID: approvalID,
                    kindRawValue: kind.rawValue
                )
            )
        case (.passiveObservation, _):
            return ID(
                storage: .passive(
                    threadID: threadID,
                    turnID: turnID,
                    kindRawValue: kind.rawValue
                )
            )
        }
    }

    public var canRespondInline: Bool {
        guard source == .managedAppServer,
              requestID != nil,
              availableDecisions.contains(.accept),
              availableDecisions.contains(.decline)
        else { return false }

        switch kind {
        case .command, .fileChange:
            return true
        case .permissions:
            return false
        }
    }

    public init(
        requestID: CodexJSONRPCRequestID?,
        threadID: String,
        turnID: String,
        itemID: String?,
        approvalID: String?,
        kind: CodexApprovalKind,
        startedAtMilliseconds: Int64,
        source: CodexApprovalSource,
        availableDecisions: [CodexApprovalDecision],
        reviewSummary: String?
    ) {
        self.requestID = requestID
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.approvalID = approvalID
        self.kind = kind
        self.startedAtMilliseconds = startedAtMilliseconds
        self.source = source
        self.availableDecisions = availableDecisions
        self.reviewSummary = reviewSummary
    }

    public static func passive(
        threadID: String,
        turnID: String,
        kind: CodexApprovalKind,
        startedAtMilliseconds: Int64
    ) -> CodexApprovalRequest {
        CodexApprovalRequest(
            requestID: nil,
            threadID: threadID,
            turnID: turnID,
            itemID: nil,
            approvalID: nil,
            kind: kind,
            startedAtMilliseconds: startedAtMilliseconds,
            source: .passiveObservation,
            availableDecisions: [],
            reviewSummary: nil
        )
    }
}

public struct CodexApprovalPresentation: Equatable, Sendable {
    public static let hidden = CodexApprovalPresentation(
        request: nil,
        pendingCount: 0,
        submissionState: .ready
    )

    public let request: CodexApprovalRequest?
    public let pendingCount: Int
    public let submissionState: CodexApprovalSubmissionState
    public let pendingThreadIDs: Set<String>

    public init(
        request: CodexApprovalRequest?,
        pendingCount: Int,
        submissionState: CodexApprovalSubmissionState,
        pendingThreadIDs: Set<String>? = nil
    ) {
        self.request = request
        self.pendingCount = pendingCount
        self.submissionState = submissionState
        self.pendingThreadIDs = pendingThreadIDs ?? request.map { Set([$0.threadID]) } ?? []
    }
}

public enum CodexTaskSelectionPolicy {
    public static func resolvedSelection(
        selectedTaskID: String?,
        visibleTaskIDs: [String],
        pendingApprovalThreadIDs: Set<String>,
        fallbackTaskID: String?
    ) -> String? {
        guard let selectedTaskID else { return fallbackTaskID }
        if visibleTaskIDs.contains(selectedTaskID)
            || pendingApprovalThreadIDs.contains(selectedTaskID)
        {
            return selectedTaskID
        }
        return fallbackTaskID
    }
}

public struct CodexApprovalInbox: Sendable {
    private struct Entry: Sendable {
        var request: CodexApprovalRequest
        var submissionState: CodexApprovalSubmissionState
    }

    private var entries: [CodexApprovalRequest.ID: Entry] = [:]

    public init() {}

    public mutating func upsert(_ request: CodexApprovalRequest) {
        if var entry = entries[request.id] {
            entry.request = request
            entries[request.id] = entry
        } else {
            entries[request.id] = Entry(request: request, submissionState: .ready)
        }
    }

    public mutating func beginSubmitting(
        id: CodexApprovalRequest.ID,
        decision: CodexApprovalDecision
    ) -> Bool {
        guard var entry = entries[id],
              entry.submissionState == .ready,
              entry.request.canRespondInline,
              entry.request.availableDecisions.contains(decision)
        else {
            return false
        }

        entry.submissionState = .submitting(decision)
        entries[id] = entry
        return true
    }

    public mutating func resolve(requestID: CodexJSONRPCRequestID, threadID: String) {
        entries = entries.filter {
            $0.value.request.requestID != requestID || $0.value.request.threadID != threadID
        }
    }

    public mutating func remove(id: CodexApprovalRequest.ID) {
        entries.removeValue(forKey: id)
    }

    public mutating func removeAll() {
        entries.removeAll()
    }

    public mutating func markFailed(id: CodexApprovalRequest.ID, message: String) {
        guard var entry = entries[id] else { return }
        entry.submissionState = .failed(message)
        entries[id] = entry
    }

    public func presentation(for id: CodexApprovalRequest.ID) -> CodexApprovalPresentation {
        guard let entry = entries[id] else { return .hidden }
        return CodexApprovalPresentation(
            request: entry.request,
            pendingCount: entries.count,
            submissionState: entry.submissionState,
            pendingThreadIDs: Set(entries.values.map { $0.request.threadID })
        )
    }

    public var orderedRequests: [CodexApprovalRequest] {
        entries.values
            .map(\.request)
            .sorted(by: areInDisplayOrder)
    }

    private func areInDisplayOrder(
        _ lhs: CodexApprovalRequest,
        _ rhs: CodexApprovalRequest
    ) -> Bool {
        if lhs.startedAtMilliseconds != rhs.startedAtMilliseconds {
            return lhs.startedAtMilliseconds < rhs.startedAtMilliseconds
        }
        if let requestIDOrder = requestIDOrder(lhs.requestID, rhs.requestID) {
            return requestIDOrder
        }
        if lhs.threadID != rhs.threadID {
            return lhs.threadID < rhs.threadID
        }
        if lhs.turnID != rhs.turnID {
            return lhs.turnID < rhs.turnID
        }
        if lhs.itemID != rhs.itemID {
            return (lhs.itemID ?? "") < (rhs.itemID ?? "")
        }
        if lhs.approvalID != rhs.approvalID {
            return (lhs.approvalID ?? "") < (rhs.approvalID ?? "")
        }
        if lhs.kind != rhs.kind {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return sourceOrder(lhs.source) < sourceOrder(rhs.source)
    }

    private func requestIDOrder(
        _ lhs: CodexJSONRPCRequestID?,
        _ rhs: CodexJSONRPCRequestID?
    ) -> Bool? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case (nil, _):
            return false
        case (_, nil):
            return true
        case let (.integer(lhsValue)?, .integer(rhsValue)?):
            return lhsValue == rhsValue ? nil : lhsValue < rhsValue
        case (.integer?, .string?):
            return true
        case (.string?, .integer?):
            return false
        case let (.string(lhsValue)?, .string(rhsValue)?):
            return lhsValue == rhsValue ? nil : lhsValue < rhsValue
        }
    }

    private func sourceOrder(_ source: CodexApprovalSource) -> Int {
        switch source {
        case .passiveObservation:
            return 0
        case .managedAppServer:
            return 1
        }
    }
}
