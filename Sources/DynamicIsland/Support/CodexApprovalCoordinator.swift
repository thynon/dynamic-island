import Foundation
import DynamicIslandCore

enum CodexApprovalCoordinatorError: Error, Equatable {
    case capabilityUnavailable
    case decisionUnavailable
    case alreadySubmitting
    case responseFailed
}

enum CodexApprovalAuditErrorCategory: String, Equatable, Sendable {
    case responseFailed
    case confirmationTimeout
    case applicationUnavailable
}

enum CodexApprovalAuditEvent: Equatable, Sendable {
    case detected(
        kind: CodexApprovalKind,
        source: CodexApprovalSource,
        pendingCount: Int,
        threadIDLength: Int
    )
    case presented(kind: CodexApprovalKind, inlineCapable: Bool)
    case decisionSent(decision: CodexApprovalDecision, kind: CodexApprovalKind)
    case resolved(kind: CodexApprovalKind, latencyMilliseconds: Int64)
    case failed(kind: CodexApprovalKind, errorCategory: CodexApprovalAuditErrorCategory)
}

@MainActor
final class CodexApprovalCoordinator {
    private struct ManagedApprovalFingerprint: Equatable, Hashable, Sendable {
        let source: String
        let requestID: CodexJSONRPCRequestID
        let threadID: String
        let turnID: String
        let itemID: String?
        let approvalID: String?
    }

    private let connection: any CodexApprovalConnection
    private let confirmationTimeoutNanoseconds: UInt64
    private var inbox = CodexApprovalInbox()
    private var fingerprints: [CodexApprovalRequest.ID: ManagedApprovalFingerprint?] = [:]
    private var selectedRequestID: CodexApprovalRequest.ID?
    private var confirmationTasks: [CodexApprovalRequest.ID: Task<Void, Never>] = [:]
    private var observationTask: Task<Void, Never>?

    private(set) var presentation: CodexApprovalPresentation = .hidden
    var onPresentationChange: (@MainActor (CodexApprovalPresentation) -> Void)?
    var onNewRequest: (@MainActor (CodexApprovalRequest) -> Void)?
    var onAuditEvent: (@MainActor (CodexApprovalAuditEvent) -> Void)?

    var orderedRequests: [CodexApprovalRequest] {
        inbox.orderedRequests
    }

    init(
        connection: any CodexApprovalConnection,
        confirmationTimeoutNanoseconds: UInt64 = 15_000_000_000
    ) {
        self.connection = connection
        self.confirmationTimeoutNanoseconds = confirmationTimeoutNanoseconds
        observationTask = Task { [weak self] in
            for await event in connection.events {
                guard !Task.isCancelled else { return }
                self?.receive(event)
            }
        }
    }

    private func receive(_ event: CodexAppServerApprovalEvent) {
        switch event {
        case .request(let request):
            receive(request)
        case .resolved(let threadID, let requestID):
            removeRequests(auditingResolution: true) {
                $0.threadID == threadID && $0.requestID == requestID
            }
        case .turnEnded(let threadID, let turnID):
            removeRequests(auditingResolution: true) {
                $0.threadID == threadID && $0.turnID == turnID
            }
        case .disconnected:
            confirmationTasks.values.forEach { $0.cancel() }
            confirmationTasks.removeAll()
            inbox.removeAll()
            fingerprints.removeAll()
            selectedRequestID = nil
            publishPresentation()
        }
    }

    @discardableResult
    func selectRequest(threadID: String) -> Bool {
        selectedRequestID = inbox.orderedRequests.first {
            $0.threadID == threadID
        }?.id
        publishPresentation()
        return selectedRequestID != nil
    }

    func submit(
        _ decision: CodexApprovalDecision,
        for requestID: CodexApprovalRequest.ID
    ) async throws {
        guard let request = inbox.presentation(for: requestID).request,
              request.source == .managedAppServer,
              request.canRespondInline,
              let transportRequestID = request.requestID
        else {
            throw CodexApprovalCoordinatorError.capabilityUnavailable
        }
        guard request.availableDecisions.contains(decision) else {
            throw CodexApprovalCoordinatorError.decisionUnavailable
        }

        let currentState = inbox.presentation(for: requestID).submissionState
        guard currentState == .ready else {
            throw CodexApprovalCoordinatorError.alreadySubmitting
        }
        guard inbox.beginSubmitting(id: requestID, decision: decision) else {
            throw CodexApprovalCoordinatorError.alreadySubmitting
        }
        publishPresentation()

        do {
            try await connection.respond(to: transportRequestID, decision: decision)
        } catch {
            markFailed(
                id: requestID,
                message: "提交失败，请前往 Codex",
                errorCategory: .responseFailed
            )
            throw CodexApprovalCoordinatorError.responseFailed
        }

        onAuditEvent?(.decisionSent(decision: decision, kind: request.kind))

        guard inbox.presentation(for: requestID).request != nil else { return }
        let task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.confirmationTimeoutNanoseconds ?? 0)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.markFailed(
                id: requestID,
                message: "未确认，请在 Codex 中检查",
                errorCategory: .confirmationTimeout
            )
        }
        confirmationTasks[requestID]?.cancel()
        confirmationTasks[requestID] = task
    }

    private func receive(_ request: CodexApprovalRequest) {
        let fingerprint = Self.fingerprint(for: request)
        let previousRequest = inbox.presentation(for: request.id).request
        guard fingerprints[request.id] != fingerprint || previousRequest != request else { return }
        let isNewRequest = previousRequest == nil
        inbox.upsert(request)
        fingerprints[request.id] = fingerprint

        if selectedRequestID == nil
            || inbox.presentation(for: selectedRequestID!).request == nil {
            selectedRequestID = inbox.orderedRequests.first?.id
        }
        if isNewRequest {
            onAuditEvent?(.detected(
                kind: request.kind,
                source: request.source,
                pendingCount: inbox.orderedRequests.count,
                threadIDLength: request.threadID.count
            ))
        }
        publishPresentation()
        if isNewRequest {
            onNewRequest?(request)
        }
    }

    private static func fingerprint(
        for request: CodexApprovalRequest
    ) -> ManagedApprovalFingerprint? {
        guard request.source == .managedAppServer,
              let requestID = request.requestID
        else { return nil }
        return ManagedApprovalFingerprint(
            source: "managedAppServer",
            requestID: requestID,
            threadID: request.threadID,
            turnID: request.turnID,
            itemID: request.itemID,
            approvalID: request.approvalID
        )
    }

    private func removeRequests(
        auditingResolution: Bool,
        where shouldRemove: (CodexApprovalRequest) -> Bool
    ) {
        let removedRequests = inbox.orderedRequests.filter(shouldRemove)
        for request in removedRequests {
            let id = request.id
            confirmationTasks[id]?.cancel()
            confirmationTasks.removeValue(forKey: id)
            inbox.remove(id: id)
            fingerprints.removeValue(forKey: id)
            if auditingResolution {
                onAuditEvent?(.resolved(
                    kind: request.kind,
                    latencyMilliseconds: Self.latencyMilliseconds(for: request)
                ))
            }
        }
        if let selectedRequestID,
           inbox.presentation(for: selectedRequestID).request == nil {
            self.selectedRequestID = inbox.orderedRequests.first?.id
        }
        publishPresentation()
    }

    private func markFailed(
        id: CodexApprovalRequest.ID,
        message: String,
        errorCategory: CodexApprovalAuditErrorCategory
    ) {
        guard let request = inbox.presentation(for: id).request else { return }
        inbox.markFailed(id: id, message: message)
        confirmationTasks.removeValue(forKey: id)
        onAuditEvent?(.failed(kind: request.kind, errorCategory: errorCategory))
        publishPresentation()
    }

    private func publishPresentation() {
        guard let selectedRequestID,
              inbox.presentation(for: selectedRequestID).request != nil
        else {
            presentation = CodexApprovalPresentation(
                request: nil,
                pendingCount: inbox.orderedRequests.count,
                submissionState: .ready,
                pendingThreadIDs: Set(inbox.orderedRequests.map(\.threadID))
            )
            onPresentationChange?(presentation)
            return
        }
        presentation = inbox.presentation(for: selectedRequestID)
        onPresentationChange?(presentation)
    }

    private static func latencyMilliseconds(for request: CodexApprovalRequest) -> Int64 {
        let now = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        return max(0, now - request.startedAtMilliseconds)
    }
}
