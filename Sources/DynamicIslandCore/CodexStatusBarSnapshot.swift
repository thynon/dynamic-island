import Foundation

public struct CodexTaskStatus: Equatable, Identifiable, Sendable {
    public enum ApprovalState: String, Equatable, Sendable {
        case none
        case pending
        case pendingCommand
        case pendingFileChange
        case pendingPermissions
        case autoReviewing

        public var displayText: String {
            switch self {
            case .none:
                ""
            case .autoReviewing:
                "审查中"
            case .pending, .pendingCommand, .pendingFileChange, .pendingPermissions:
                "待审"
            }
        }

        public var requiresManualApproval: Bool {
            switch self {
            case .pending, .pendingCommand, .pendingFileChange, .pendingPermissions:
                true
            case .none, .autoReviewing:
                false
            }
        }

        public var accessibilityText: String {
            switch self {
            case .none:
                "No approval pending"
            case .pending:
                "Approval pending"
            case .pendingCommand:
                "Command approval pending"
            case .pendingFileChange:
                "File change approval pending"
            case .pendingPermissions:
                "Permission approval pending"
            case .autoReviewing:
                "Automatic approval review in progress"
            }
        }

        public var isVisible: Bool {
            self != .none
        }
    }

    public let id: String
    public let title: String
    public let elapsedSeconds: Int
    public let totalTokens: Int
    public let activityState: CodexStatusBarSnapshot.ActivityState
    public let approvalState: ApprovalState
    public let parentThreadID: String?
    public let rootThreadID: String?
    public let agentNickname: String?
    public let agentDepth: Int
    public let turnID: String?
    public let completedAt: TimeInterval?
    public let progressEvents: [CodexSessionProgressEvent]

    public init(
        id: String,
        title: String,
        elapsedSeconds: Int = 0,
        totalTokens: Int = 0,
        activityState: CodexStatusBarSnapshot.ActivityState = .unavailable,
        approvalState: ApprovalState = .none,
        parentThreadID: String? = nil,
        rootThreadID: String? = nil,
        agentNickname: String? = nil,
        agentDepth: Int = 0,
        turnID: String? = nil,
        completedAt: TimeInterval? = nil,
        progressEvents: [CodexSessionProgressEvent] = []
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Codex"
            : title
        self.elapsedSeconds = max(0, elapsedSeconds)
        self.totalTokens = max(0, totalTokens)
        self.activityState = activityState
        self.approvalState = approvalState
        self.parentThreadID = parentThreadID
        self.rootThreadID = rootThreadID
        let resolvedAgentNickname = agentNickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.agentNickname = resolvedAgentNickname?.isEmpty == false ? resolvedAgentNickname : nil
        self.agentDepth = max(0, agentDepth)
        self.turnID = turnID
        self.completedAt = completedAt
        self.progressEvents = progressEvents
    }

    public var formattedElapsedTime: String {
        CodexStatusBarSnapshot.formatElapsedTime(elapsedSeconds)
    }

    public var formattedTokenCount: String {
        CodexStatusBarSnapshot.formatTokenCount(totalTokens)
    }

    public var isSubagent: Bool {
        parentThreadID != nil
    }

    public var agentDisplayName: String {
        guard isSubagent else { return title }
        return agentNickname ?? "子代理"
    }

    public var dismissalKey: String {
        if let turnID, !turnID.isEmpty {
            return "\(id):turn:\(turnID)"
        }
        if let completedAt {
            return "\(id):completed:\(Int(completedAt.rounded()))"
        }
        return id
    }
}

public struct CodexStatusBarSnapshot: Equatable, Sendable {
    public enum ActivityState: String, Equatable, Sendable {
        case unavailable
        case idle
        case thinking
        case writing
        case runningTool
        case compacting
        case retrying
        case waitingApproval

        public var displayText: String {
            switch self {
            case .unavailable:
                "Codex unavailable"
            case .idle:
                "Idle"
            case .thinking:
                "Thinking"
            case .writing:
                "Responding"
            case .runningTool:
                "Running tool"
            case .compacting:
                "Compacting conversation"
            case .retrying:
                "Retrying"
            case .waitingApproval:
                "Waiting approval"
            }
        }

        public var isWorking: Bool {
            switch self {
            case .thinking, .writing, .runningTool, .compacting, .retrying, .waitingApproval:
                true
            case .unavailable, .idle:
                false
            }
        }
    }

    public let threadID: String?
    public let threadTitle: String?
    public let elapsedSeconds: Int
    public let totalTokens: Int
    public let runningTasksCount: Int
    public let activityState: ActivityState
    public let tasks: [CodexTaskStatus]

    public init(
        threadID: String? = nil,
        threadTitle: String? = nil,
        elapsedSeconds: Int = 0,
        totalTokens: Int = 0,
        runningTasksCount: Int = 0,
        activityState: ActivityState = .unavailable,
        tasks: [CodexTaskStatus] = []
    ) {
        self.threadID = threadID
        self.threadTitle = threadTitle
        self.elapsedSeconds = max(0, elapsedSeconds)
        self.totalTokens = max(0, totalTokens)
        self.runningTasksCount = max(0, runningTasksCount)
        self.activityState = activityState
        self.tasks = tasks
    }

    public static let unavailable = CodexStatusBarSnapshot()

    public var isWorking: Bool {
        activityState.isWorking || runningTasksCount > 0
    }

    public var formattedElapsedTime: String {
        Self.formatElapsedTime(elapsedSeconds)
    }

    public var formattedTokenCount: String {
        Self.formatTokenCount(totalTokens)
    }

    public var runningTasksText: String? {
        guard runningTasksCount > 0 else { return nil }
        return runningTasksCount == 1 ? "1 running task" : "\(runningTasksCount) running tasks"
    }

    public static func formatElapsedTime(_ seconds: Int) -> String {
        let resolvedSeconds = max(0, seconds)
        guard resolvedSeconds >= 60 else {
            return "\(resolvedSeconds)s"
        }

        let minutes = resolvedSeconds / 60
        let remainingSeconds = resolvedSeconds % 60
        return "\(minutes)m \(remainingSeconds)s"
    }

    public static func formatTokenCount(_ tokens: Int) -> String {
        let resolvedTokens = max(0, tokens)
        guard resolvedTokens >= 1000 else {
            return "\(resolvedTokens)"
        }

        if resolvedTokens < 1_000_000 {
            let thousands = Double(resolvedTokens) / 1000
            return thousands.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(thousands))k"
                : String(format: "%.1fk", thousands)
        }

        let millions = Double(resolvedTokens) / 1_000_000
        return millions.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(millions))m"
            : String(format: "%.1fm", millions)
    }
}
