public enum CodexApprovalApplicationOpenCompletion: Equatable, Sendable {
    case ignored
    case succeeded
    case failed
}

public struct CodexApprovalApplicationOpenAttempt: Equatable, Sendable {
    fileprivate let requestID: CodexApprovalRequest.ID
    fileprivate let generation: UInt64
}

public struct CodexApprovalApplicationOpenState: Sendable {
    private var generation: UInt64 = 0
    private var activeAttempt: CodexApprovalApplicationOpenAttempt?
    private var failedRequestID: CodexApprovalRequest.ID?

    public init() {}

    public mutating func begin(
        requestID: CodexApprovalRequest.ID
    ) -> CodexApprovalApplicationOpenAttempt {
        generation &+= 1
        let attempt = CodexApprovalApplicationOpenAttempt(
            requestID: requestID,
            generation: generation
        )
        activeAttempt = attempt
        return attempt
    }

    public mutating func complete(
        _ attempt: CodexApprovalApplicationOpenAttempt,
        currentRequestID: CodexApprovalRequest.ID?,
        succeeded: Bool
    ) -> CodexApprovalApplicationOpenCompletion {
        guard activeAttempt == attempt else { return .ignored }
        activeAttempt = nil
        guard currentRequestID == attempt.requestID else { return .ignored }

        if succeeded {
            if failedRequestID == attempt.requestID {
                failedRequestID = nil
            }
            return .succeeded
        }

        failedRequestID = attempt.requestID
        return .failed
    }

    public mutating func requestDidChange(to requestID: CodexApprovalRequest.ID?) {
        guard failedRequestID != requestID else { return }
        failedRequestID = nil
    }

    public func hasFailure(for requestID: CodexApprovalRequest.ID) -> Bool {
        failedRequestID == requestID
    }
}
