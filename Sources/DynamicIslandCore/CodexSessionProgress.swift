import Foundation

public struct CodexSessionProgressEvent: Equatable, Identifiable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case started
        case thinking
        case tool
        case responding
        case compacting
        case waitingApproval
        case retrying
        case completed

        fileprivate var defaultDisplayText: String {
            switch self {
            case .started:
                "开始处理会话"
            case .thinking:
                "分析会话内容"
            case .tool:
                "运行工具"
            case .responding:
                "整理回复"
            case .compacting:
                "压缩会话上下文"
            case .waitingApproval:
                "等待用户批准"
            case .retrying:
                "重试连接"
            case .completed:
                "完成本轮会话"
            }
        }
    }

    public let id: String
    public let kind: Kind
    public let occurredAt: TimeInterval?
    public let displayText: String

    public init(
        id: String,
        kind: Kind,
        occurredAt: TimeInterval? = nil,
        displayText: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        let resolvedDisplayText = displayText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayText = resolvedDisplayText?.isEmpty == false
            ? resolvedDisplayText!
            : kind.defaultDisplayText
    }
}

public enum CodexCompanionState: String, Equatable, Sendable {
    case idle
    case thinking
    case tool
    case done
}

public extension CodexTaskStatus {
    var companionState: CodexCompanionState {
        switch activityState {
        case .unavailable:
            .idle
        case .idle:
            .done
        case .runningTool:
            .tool
        case .thinking, .writing, .compacting, .retrying, .waitingApproval:
            .thinking
        }
    }
}
