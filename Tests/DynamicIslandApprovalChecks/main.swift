import Foundation
import DynamicIslandCore

private final class LineRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [Data] = []

    func append(_ line: Data) {
        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
    }

    func snapshot() -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

private final class FakeApprovalConnection: CodexApprovalConnection, @unchecked Sendable {
    let events: AsyncStream<CodexAppServerApprovalEvent>

    private let eventContinuation: AsyncStream<CodexAppServerApprovalEvent>.Continuation
    private let lock = NSLock()
    private var recordedResponses: [(CodexJSONRPCRequestID, CodexApprovalDecision)] = []

    init() {
        var continuation: AsyncStream<CodexAppServerApprovalEvent>.Continuation?
        events = AsyncStream { continuation = $0 }
        eventContinuation = continuation!
    }

    func send(_ event: CodexAppServerApprovalEvent) {
        eventContinuation.yield(event)
    }

    func respond(
        to requestID: CodexJSONRPCRequestID,
        decision: CodexApprovalDecision
    ) async throws {
        lock.withLock {
            recordedResponses.append((requestID, decision))
        }
    }

    func responses() -> [(CodexJSONRPCRequestID, CodexApprovalDecision)] {
        lock.withLock { recordedResponses }
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        Foundation.exit(1)
    }
}

private func managedRequest(
    id: CodexJSONRPCRequestID?,
    threadID: String,
    turnID: String,
    itemID: String,
    source: CodexApprovalSource = .managedAppServer,
    kind: CodexApprovalKind = .command,
    decisions: [CodexApprovalDecision]? = nil,
    reviewSummary: String? = nil,
    startedAtMilliseconds: Int64
) -> CodexApprovalRequest {
    CodexApprovalRequest(
        requestID: id,
        threadID: threadID,
        turnID: turnID,
        itemID: itemID,
        approvalID: nil,
        kind: kind,
        startedAtMilliseconds: startedAtMilliseconds,
        source: source,
        availableDecisions: decisions ?? (kind == .permissions ? [] : [.decline, .accept, .acceptForSession]),
        reviewSummary: reviewSummary
    )
}

private func envelopeData(_ object: [String: Any]) throws -> Data {
    var data = try JSONSerialization.data(withJSONObject: object)
    data.append(0x0A)
    return data
}

private func approvalEnvelope(
    id: Any,
    method: String,
    threadID: String,
    turnID: String,
    itemID: String,
    command: String? = nil,
    startedAtMilliseconds: Int64 = 1
) -> [String: Any] {
    var params: [String: Any] = [
        "threadId": threadID,
        "turnId": turnID,
        "itemId": itemID,
        "startedAtMs": startedAtMilliseconds
    ]
    if let command {
        params["command"] = command
    }
    return [
        "id": id,
        "method": method,
        "params": params
    ]
}

private func fileChanges(path: String, diff: String) -> [[String: Any]] {
    [[
        "path": path,
        "diff": diff,
        "kind": ["type": "update"]
    ]]
}

@main
private enum DynamicIslandApprovalChecks {
    @MainActor
    static func main() async throws {
        try await testWireIDsAndActiveRequestGate()
        try await testCommandContextGate()
        try await testFileContextBeforeAndAfterRequest()
        try await testResolvedFileContextDoesNotCarryForward()
        try await testConnectionBindingAndOnceOnlySubmission()
        try await testPassiveAndTargetedResolution()
        try await testMultipleRequestsKeepIndependentState()
        try await testSelectionMissLeavesManagedInboxAvailableForPassiveFallback()
        try await testManagedRequestPresentationHasOneNewRequestEdge()
        try await testSubmissionStaysBoundToClickedRequest()
        testApplicationOpenFailureLifecycle()
        try await testPrivacySafeAuditEvents()
        testAutoPresentationPolicy()
        try await testTimeoutAndDisconnectNeverResend()
        print("DynamicIslandApprovalChecks passed")
    }

    private static func testWireIDsAndActiveRequestGate() async throws {
        let recorder = LineRecorder()
        let client = CodexAppServerApprovalClient(writeLine: recorder.append)

        try await client.ingest(envelopeData(approvalEnvelope(
            id: 61,
            method: "item/commandExecution/requestApproval",
            threadID: "thread",
            turnID: "turn",
            itemID: "integer-item",
            command: "true"
        )))
        try await client.respond(to: .integer(61), decision: .accept)

        try await client.ingest(envelopeData(approvalEnvelope(
            id: "abc",
            method: "item/commandExecution/requestApproval",
            threadID: "thread",
            turnID: "turn",
            itemID: "string-item",
            command: "true"
        )))
        try await client.respond(to: .string("abc"), decision: .decline)

        let lines = recorder.snapshot()
        expect(lines.count == 2, "integer and string requests each write once")
        let integerEnvelope = try JSONSerialization.jsonObject(with: lines[0]) as? [String: Any]
        let stringEnvelope = try JSONSerialization.jsonObject(with: lines[1]) as? [String: Any]
        expect(integerEnvelope?["id"] is NSNumber, "integer request id stays a JSON number")
        expect(integerEnvelope?["id"] as? Int64 == 61, "integer request id value is preserved")
        expect(stringEnvelope?["id"] as? String == "abc", "string request id stays a JSON string")

        do {
            try await client.respond(to: .integer(999), decision: .accept)
            expect(false, "unknown request id must be rejected")
        } catch CodexAppServerApprovalClientError.requestUnavailable {
        }
        expect(recorder.snapshot().count == 2, "unknown request id writes nothing")

        try await client.ingest(envelopeData(approvalEnvelope(
            id: true,
            method: "item/commandExecution/requestApproval",
            threadID: "thread",
            turnID: "turn",
            itemID: "bool-item",
            command: "true"
        )))
        do {
            try await client.respond(to: .integer(1), decision: .accept)
            expect(false, "Bool request id must not become integer 1")
        } catch CodexAppServerApprovalClientError.requestUnavailable {
        }
        expect(recorder.snapshot().count == 2, "Bool request id writes nothing")

        try await client.ingest(envelopeData(approvalEnvelope(
            id: 77,
            method: "item/commandExecution/requestApproval",
            threadID: "thread",
            turnID: "resolved-turn",
            itemID: "resolved-item",
            command: "true"
        )))
        try await client.ingest(envelopeData([
            "method": "serverRequest/resolved",
            "params": ["threadId": "thread", "requestId": 77]
        ]))
        do {
            try await client.respond(to: .integer(77), decision: .accept)
            expect(false, "resolved request id must be stale")
        } catch CodexAppServerApprovalClientError.requestUnavailable {
        }

        try await client.ingest(envelopeData(approvalEnvelope(
            id: 78,
            method: "item/commandExecution/requestApproval",
            threadID: "thread",
            turnID: "ended-turn",
            itemID: "ended-item",
            command: "true"
        )))
        try await client.ingest(envelopeData([
            "method": "turn/completed",
            "params": ["threadId": "thread", "turnId": "ended-turn"]
        ]))
        do {
            try await client.respond(to: .integer(78), decision: .accept)
            expect(false, "ended turn request id must be stale")
        } catch CodexAppServerApprovalClientError.requestUnavailable {
        }
        expect(recorder.snapshot().count == 2, "resolved and ended requests write nothing")

        try await client.ingest(envelopeData(approvalEnvelope(
            id: 79,
            method: "item/commandExecution/requestApproval",
            threadID: "thread",
            turnID: "disconnected-turn",
            itemID: "disconnected-item",
            command: "true"
        )))
        await client.stop()
        do {
            try await client.respond(to: .integer(79), decision: .accept)
            expect(false, "disconnected request id must be stale")
        } catch CodexAppServerApprovalClientError.notConnected {
        }
        expect(recorder.snapshot().count == 2, "disconnected request writes nothing")

        do {
            try await client.start()
            expect(false, "one client instance must not start a second connection")
        } catch CodexAppServerApprovalClientError.alreadyStarted {
        }
    }

    private static func testCommandContextGate() async throws {
        let client = CodexAppServerApprovalClient(writeLine: { _ in })
        var iterator = client.events.makeAsyncIterator()

        try await client.ingest(envelopeData(approvalEnvelope(
            id: 1,
            method: "item/commandExecution/requestApproval",
            threadID: "thread",
            turnID: "turn",
            itemID: "missing"
        )))
        guard case .request(let missingCommand)? = await iterator.next() else {
            expect(false, "missing command emits a visible request")
            return
        }
        expect(!missingCommand.canRespondInline, "missing command is not actionable")
        expect(missingCommand.availableDecisions.isEmpty, "missing command has no decisions")
        expect(missingCommand.reviewSummary == nil, "missing command has no review text")

        try await client.ingest(envelopeData(approvalEnvelope(
            id: 2,
            method: "item/commandExecution/requestApproval",
            threadID: "thread",
            turnID: "turn",
            itemID: "empty",
            command: "  \n"
        )))
        guard case .request(let emptyCommand)? = await iterator.next() else {
            expect(false, "empty command emits a visible request")
            return
        }
        expect(emptyCommand.availableDecisions.isEmpty, "whitespace command has no decisions")

        let rawCommand = "printf 'approved context'"
        try await client.ingest(envelopeData(approvalEnvelope(
            id: 3,
            method: "item/commandExecution/requestApproval",
            threadID: "thread",
            turnID: "turn",
            itemID: "valid",
            command: rawCommand
        )))
        guard case .request(let validCommand)? = await iterator.next() else {
            expect(false, "valid command emits a request")
            return
        }
        expect(validCommand.canRespondInline, "non-empty command is actionable")
        expect(validCommand.reviewSummary == rawCommand, "raw command exists only in transient review data")

        try await client.ingest(envelopeData(approvalEnvelope(
            id: 4,
            method: "item/permissions/requestApproval",
            threadID: "thread",
            turnID: "turn",
            itemID: "permissions"
        )))
        guard case .request(let permissionsRequest)? = await iterator.next() else {
            expect(false, "permissions request remains visible")
            return
        }
        expect(!permissionsRequest.canRespondInline, "permissions request is never actionable")
        expect(permissionsRequest.availableDecisions.isEmpty, "permissions request exposes no decision response")
    }

    @MainActor
    private static func testFileContextBeforeAndAfterRequest() async throws {
        let beforeClient = CodexAppServerApprovalClient(writeLine: { _ in })
        var beforeIterator = beforeClient.events.makeAsyncIterator()
        try await beforeClient.ingest(envelopeData([
            "method": "item/started",
            "params": [
                "threadId": "thread-before",
                "turnId": "turn-before",
                "startedAtMs": 1,
                "item": [
                    "id": "file-before",
                    "type": "fileChange",
                    "status": "inProgress",
                    "changes": fileChanges(path: "/tmp/before.txt", diff: "@@ before")
                ]
            ]
        ]))
        try await beforeClient.ingest(envelopeData(approvalEnvelope(
            id: 10,
            method: "item/fileChange/requestApproval",
            threadID: "thread-before",
            turnID: "turn-before",
            itemID: "file-before"
        )))
        guard case .request(let beforeRequest)? = await beforeIterator.next() else {
            expect(false, "file context before request emits approval")
            return
        }
        expect(beforeRequest.canRespondInline, "matching item/started file changes enable decisions")
        expect(beforeRequest.reviewSummary?.contains("/tmp/before.txt") == true, "file path stays in transient review data")
        expect(beforeRequest.reviewSummary?.contains("@@ before") == true, "file diff stays in transient review data")

        let completedClient = CodexAppServerApprovalClient(writeLine: { _ in })
        var completedIterator = completedClient.events.makeAsyncIterator()
        try await completedClient.ingest(envelopeData([
            "method": "item/completed",
            "params": [
                "threadId": "thread-completed",
                "turnId": "turn-completed",
                "item": [
                    "id": "file-completed",
                    "type": "fileChange",
                    "status": "completed",
                    "changes": fileChanges(path: "/tmp/completed.txt", diff: "@@ completed")
                ]
            ]
        ]))
        try await completedClient.ingest(envelopeData(approvalEnvelope(
            id: 11,
            method: "item/fileChange/requestApproval",
            threadID: "thread-completed",
            turnID: "turn-completed",
            itemID: "file-completed"
        )))
        guard case .request(let completedRequest)? = await completedIterator.next() else {
            expect(false, "file context from item/completed emits approval")
            return
        }
        expect(completedRequest.canRespondInline, "matching item/completed file changes enable decisions")

        let recorder = LineRecorder()
        let afterClient = CodexAppServerApprovalClient(writeLine: recorder.append)
        let coordinator = CodexApprovalCoordinator(
            connection: afterClient,
            confirmationTimeoutNanoseconds: 1_000_000_000
        )
        try await afterClient.ingest(envelopeData(approvalEnvelope(
            id: 12,
            method: "item/fileChange/requestApproval",
            threadID: "thread-after",
            turnID: "turn-after",
            itemID: "file-after"
        )))
        await waitUntil("file request without context reaches coordinator") {
            coordinator.presentation.request?.requestID == .integer(12)
        }
        expect(coordinator.presentation.request?.canRespondInline == false, "file request is gated before matching context")

        for mismatchedParams: [String: Any] in [
            [
                "threadId": "other-thread",
                "turnId": "turn-after",
                "itemId": "file-after",
                "changes": fileChanges(path: "/tmp/wrong.txt", diff: "@@ wrong")
            ],
            [
                "threadId": "thread-after",
                "turnId": "other-turn",
                "itemId": "file-after",
                "changes": fileChanges(path: "/tmp/wrong.txt", diff: "@@ wrong")
            ],
            [
                "threadId": "thread-after",
                "turnId": "turn-after",
                "itemId": "other-item",
                "changes": fileChanges(path: "/tmp/wrong.txt", diff: "@@ wrong")
            ]
        ] {
            try await afterClient.ingest(envelopeData([
                "method": "item/fileChange/patchUpdated",
                "params": mismatchedParams
            ]))
        }
        try await afterClient.ingest(envelopeData([
            "method": "item/fileChange/patchUpdated",
            "params": [
                "threadId": "thread-after",
                "turnId": "turn-after",
                "itemId": "file-after",
                "changes": []
            ]
        ]))
        try await Task.sleep(nanoseconds: 5_000_000)
        expect(coordinator.presentation.request?.canRespondInline == false, "mismatched or empty changes cannot grant file capability")

        try await afterClient.ingest(envelopeData([
            "method": "item/fileChange/patchUpdated",
            "params": [
                "threadId": "thread-after",
                "turnId": "turn-after",
                "itemId": "file-after",
                "changes": fileChanges(path: "/tmp/after.txt", diff: "@@ after")
            ]
        ]))
        await waitUntil("late file context updates the same routing request") {
            coordinator.presentation.request?.canRespondInline == true
        }
        let routingID = coordinator.presentation.request!.id
        try await coordinator.submit(.accept, for: routingID)
        expect(recorder.snapshot().count == 1, "late context enables exactly one response")

        try await afterClient.ingest(envelopeData([
            "method": "item/fileChange/patchUpdated",
            "params": [
                "threadId": "thread-after",
                "turnId": "turn-after",
                "itemId": "file-after",
                "changes": fileChanges(path: "/tmp/after.txt", diff: "@@ updated")
            ]
        ]))
        await waitUntil("new file context refreshes transient review data") {
            coordinator.presentation.request?.reviewSummary?.contains("@@ updated") == true
        }
        expect(coordinator.presentation.request?.id == routingID, "context update preserves routing identity")
        expect(coordinator.presentation.submissionState == .submitting(.accept), "context update preserves once-only state")
        do {
            try await coordinator.submit(.accept, for: routingID)
            expect(false, "context update must not reopen submission")
        } catch CodexApprovalCoordinatorError.alreadySubmitting {
        }
        expect(recorder.snapshot().count == 1, "context update never writes twice")
    }

    private static func testResolvedFileContextDoesNotCarryForward() async throws {
        let client = CodexAppServerApprovalClient(writeLine: { _ in })
        var iterator = client.events.makeAsyncIterator()
        try await client.ingest(envelopeData([
            "method": "item/fileChange/patchUpdated",
            "params": [
                "threadId": "resolved-thread",
                "turnId": "resolved-turn",
                "itemId": "resolved-file",
                "changes": fileChanges(path: "/tmp/resolved.txt", diff: "@@ old context")
            ]
        ]))
        try await client.ingest(envelopeData(approvalEnvelope(
            id: 40,
            method: "item/fileChange/requestApproval",
            threadID: "resolved-thread",
            turnID: "resolved-turn",
            itemID: "resolved-file"
        )))
        guard case .request(let firstRequest)? = await iterator.next() else {
            expect(false, "file request receives current matching context")
            return
        }
        expect(firstRequest.canRespondInline, "first request is actionable with fresh file context")

        try await client.ingest(envelopeData([
            "method": "serverRequest/resolved",
            "params": ["threadId": "resolved-thread", "requestId": 40]
        ]))
        guard case .resolved? = await iterator.next() else {
            expect(false, "resolved event is emitted")
            return
        }

        try await client.ingest(envelopeData(approvalEnvelope(
            id: 41,
            method: "item/fileChange/requestApproval",
            threadID: "resolved-thread",
            turnID: "resolved-turn",
            itemID: "resolved-file"
        )))
        guard case .request(let secondRequest)? = await iterator.next() else {
            expect(false, "same item can request approval again")
            return
        }
        expect(!secondRequest.canRespondInline, "resolved file context cannot grant a later request")
        expect(secondRequest.reviewSummary == nil, "resolved raw path and diff are no longer retained")
    }

    @MainActor
    private static func testConnectionBindingAndOnceOnlySubmission() async throws {
        let ownedConnection = FakeApprovalConnection()
        let unrelatedConnection = FakeApprovalConnection()
        let coordinator = CodexApprovalCoordinator(
            connection: ownedConnection,
            confirmationTimeoutNanoseconds: 1_000_000_000
        )
        let request = managedRequest(
            id: .string("bound"),
            threadID: "thread",
            turnID: "turn",
            itemID: "item",
            startedAtMilliseconds: 1
        )

        unrelatedConnection.send(.request(request))
        try await Task.sleep(nanoseconds: 5_000_000)
        expect(coordinator.presentation == .hidden, "events from another connection cannot grant capability")

        ownedConnection.send(.request(request))
        await waitUntil("owned connection request becomes visible") {
            coordinator.presentation.request?.requestID == .string("bound")
        }
        let requestID = coordinator.presentation.request!.id
        try await coordinator.submit(.accept, for: requestID)
        do {
            try await coordinator.submit(.accept, for: requestID)
            expect(false, "double-click must not submit twice")
        } catch CodexApprovalCoordinatorError.alreadySubmitting {
        }
        expect(ownedConnection.responses().count == 1, "owned connection receives one response")
        expect(unrelatedConnection.responses().isEmpty, "unrelated connection receives no response")
    }

    @MainActor
    private static func testPassiveAndTargetedResolution() async throws {
        let passiveConnection = FakeApprovalConnection()
        let passiveCoordinator = CodexApprovalCoordinator(connection: passiveConnection)
        passiveConnection.send(.request(managedRequest(
            id: nil,
            threadID: "desktop-thread",
            turnID: "desktop-turn",
            itemID: "",
            source: .passiveObservation,
            startedAtMilliseconds: 1
        )))
        await waitUntil("passive request becomes visible") {
            passiveCoordinator.presentation.request?.threadID == "desktop-thread"
        }
        do {
            try await passiveCoordinator.submit(
                .decline,
                for: passiveCoordinator.presentation.request!.id
            )
            expect(false, "passive request must return capability error")
        } catch CodexApprovalCoordinatorError.capabilityUnavailable {
        }
        expect(passiveConnection.responses().isEmpty, "passive request writes nothing")

        let connection = FakeApprovalConnection()
        let coordinator = CodexApprovalCoordinator(connection: connection)
        connection.send(.request(managedRequest(
            id: .integer(21),
            threadID: "thread",
            turnID: "turn-1",
            itemID: "item-1",
            startedAtMilliseconds: 1
        )))
        connection.send(.request(managedRequest(
            id: .string("second"),
            threadID: "thread",
            turnID: "turn-2",
            itemID: "item-2",
            startedAtMilliseconds: 2
        )))
        await waitUntil("two managed requests become visible") {
            coordinator.presentation.pendingCount == 2
        }
        connection.send(.resolved(threadID: "thread", requestID: .integer(21)))
        await waitUntil("targeted resolution removes only one request") {
            coordinator.presentation.pendingCount == 1
        }
        expect(coordinator.presentation.request?.requestID == .string("second"), "unrelated request remains after targeted resolution")
    }

    @MainActor
    private static func testTimeoutAndDisconnectNeverResend() async throws {
        let connection = FakeApprovalConnection()
        let coordinator = CodexApprovalCoordinator(
            connection: connection,
            confirmationTimeoutNanoseconds: 20_000_000
        )
        connection.send(.request(managedRequest(
            id: .integer(30),
            threadID: "thread",
            turnID: "turn",
            itemID: "item",
            startedAtMilliseconds: 1
        )))
        await waitUntil("timeout test request becomes visible") {
            coordinator.presentation.request?.requestID == .integer(30)
        }
        try await coordinator.submit(
            .decline,
            for: coordinator.presentation.request!.id
        )
        await waitUntil("timeout publishes unconfirmed state") {
            coordinator.presentation.submissionState == .failed("未确认，请在 Codex 中检查")
        }
        expect(connection.responses().count == 1, "timeout never resends")

        connection.send(.disconnected)
        await waitUntil("disconnect clears managed capability") {
            coordinator.presentation == .hidden
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        expect(connection.responses().count == 1, "disconnect never resends")
    }

    @MainActor
    private static func testMultipleRequestsKeepIndependentState() async throws {
        let connection = FakeApprovalConnection()
        let coordinator = CodexApprovalCoordinator(
            connection: connection,
            confirmationTimeoutNanoseconds: 1_000_000_000
        )
        let requestA = managedRequest(
            id: .integer(71),
            threadID: "thread-a",
            turnID: "turn-a",
            itemID: "item-a",
            startedAtMilliseconds: 10
        )
        let requestB = managedRequest(
            id: .integer(72),
            threadID: "thread-b",
            turnID: "turn-b",
            itemID: "item-b",
            startedAtMilliseconds: 20
        )

        connection.send(.request(requestB))
        connection.send(.request(requestA))
        await waitUntil("two requests enter one ordered inbox") {
            coordinator.orderedRequests.count == 2
        }
        expect(
            coordinator.orderedRequests.map(\.threadID) == ["thread-a", "thread-b"],
            "multiple approvals are ordered by startedAt"
        )

        coordinator.selectRequest(threadID: "thread-a")
        expect(coordinator.presentation.request?.id == requestA.id, "thread selection presents request A")
        try await coordinator.submit(.accept, for: requestA.id)
        expect(
            coordinator.presentation.submissionState == .submitting(.accept),
            "request A owns its submitting state"
        )

        coordinator.selectRequest(threadID: "thread-b")
        expect(coordinator.presentation.request?.id == requestB.id, "switching threads presents request B")
        expect(coordinator.presentation.submissionState == .ready, "request B keeps its own ready state")

        coordinator.selectRequest(threadID: "thread-a")
        expect(
            coordinator.presentation.submissionState == .submitting(.accept),
            "switching back preserves request A submission"
        )
        expect(connection.responses().count == 1, "switching requests never duplicates A response")

        coordinator.selectRequest(threadID: "thread-b")
        connection.send(.resolved(threadID: "thread-a", requestID: .integer(71)))
        await waitUntil("resolving A leaves B visible") {
            coordinator.presentation.pendingCount == 1
        }
        expect(coordinator.presentation.request?.id == requestB.id, "targeted resolution never clears request B")
    }

    @MainActor
    private static func testSelectionMissLeavesManagedInboxAvailableForPassiveFallback() async throws {
        let connection = FakeApprovalConnection()
        let coordinator = CodexApprovalCoordinator(connection: connection)
        connection.send(.request(managedRequest(
            id: .integer(81),
            threadID: "managed-a",
            turnID: "turn-a",
            itemID: "item-a",
            startedAtMilliseconds: 1
        )))
        await waitUntil("managed request is available before selecting a passive thread") {
            coordinator.presentation.request?.threadID == "managed-a"
        }

        let didSelectManagedRequest = coordinator.selectRequest(threadID: "passive-b")
        expect(!didSelectManagedRequest, "a thread without a managed request must allow passive fallback")
        expect(coordinator.presentation.request == nil, "selection miss never leaves another thread's managed request mounted")
        expect(coordinator.presentation.pendingCount == 1, "selection miss preserves the managed inbox")
    }

    @MainActor
    private static func testManagedRequestPresentationHasOneNewRequestEdge() async throws {
        let connection = FakeApprovalConnection()
        let coordinator = CodexApprovalCoordinator(connection: connection)
        var newRequestIDs: [CodexApprovalRequest.ID] = []
        var auditEvents: [CodexApprovalAuditEvent] = []
        coordinator.onNewRequest = { request in
            newRequestIDs.append(request.id)
        }
        coordinator.onAuditEvent = { event in
            auditEvents.append(event)
        }

        let original = managedRequest(
            id: .integer(82),
            threadID: "edge-thread",
            turnID: "edge-turn",
            itemID: "edge-item",
            reviewSummary: "first transient summary",
            startedAtMilliseconds: 1
        )
        connection.send(.request(original))
        await waitUntil("new managed request emits one UI edge") {
            newRequestIDs.count == 1
        }

        let metadataUpdate = managedRequest(
            id: .integer(82),
            threadID: "edge-thread",
            turnID: "edge-turn",
            itemID: "edge-item",
            reviewSummary: "updated transient summary",
            startedAtMilliseconds: 1
        )
        connection.send(.request(metadataUpdate))
        await waitUntil("metadata update refreshes presentation data") {
            coordinator.presentation.request?.reviewSummary == "updated transient summary"
        }
        _ = coordinator.selectRequest(threadID: "edge-thread")

        expect(newRequestIDs == [original.id], "metadata and selection updates never retrigger auto-presentation")
        let presentedCount = auditEvents.reduce(into: 0) { count, event in
            if case .presented = event { count += 1 }
        }
        expect(presentedCount == 0, "coordinator cannot log UI presentation before an attachment is actually visible")
    }

    @MainActor
    private static func testSubmissionStaysBoundToClickedRequest() async throws {
        let connection = FakeApprovalConnection()
        let coordinator = CodexApprovalCoordinator(
            connection: connection,
            confirmationTimeoutNanoseconds: 1_000_000_000
        )
        let requestA = managedRequest(
            id: .integer(83),
            threadID: "clicked-a",
            turnID: "turn-a",
            itemID: "item-a",
            startedAtMilliseconds: 1
        )
        let requestB = managedRequest(
            id: .integer(84),
            threadID: "selected-b",
            turnID: "turn-b",
            itemID: "item-b",
            startedAtMilliseconds: 2
        )
        connection.send(.request(requestA))
        connection.send(.request(requestB))
        await waitUntil("two requests are ready for request-bound submission") {
            coordinator.orderedRequests.count == 2
        }

        _ = coordinator.selectRequest(threadID: requestA.threadID)
        let clickedRequestID = coordinator.presentation.request!.id
        _ = coordinator.selectRequest(threadID: requestB.threadID)
        try await coordinator.submit(.accept, for: clickedRequestID)

        expect(connection.responses().map(\.0) == [.integer(83)], "clicking A can only write A's transport id")
        expect(coordinator.presentation.request?.id == requestB.id, "request-bound submission never changes the user's B selection")
        expect(coordinator.presentation.submissionState == .ready, "B remains ready after A submission")
        _ = coordinator.selectRequest(threadID: requestA.threadID)
        expect(coordinator.presentation.submissionState == .submitting(.accept), "A retains its own submitting state")
    }

    private static func testApplicationOpenFailureLifecycle() {
        let requestA = CodexApprovalRequest.passive(
            threadID: "open-a",
            turnID: "turn-a",
            kind: .command,
            startedAtMilliseconds: 1
        )
        let requestB = CodexApprovalRequest.passive(
            threadID: "open-b",
            turnID: "turn-b",
            kind: .fileChange,
            startedAtMilliseconds: 2
        )
        var state = CodexApprovalApplicationOpenState()

        let attemptA = state.begin(requestID: requestA.id)
        expect(
            state.complete(attemptA, currentRequestID: requestA.id, succeeded: false) == .failed,
            "a failed activation is applied only to its current request"
        )
        expect(state.hasFailure(for: requestA.id), "failure persists across passive refreshes of the same request")

        state.requestDidChange(to: requestB.id)
        expect(!state.hasFailure(for: requestA.id), "selecting a new request clears the previous static failure")

        let staleAttemptA = state.begin(requestID: requestA.id)
        expect(
            state.complete(staleAttemptA, currentRequestID: requestB.id, succeeded: false) == .ignored,
            "A completion cannot contaminate the current B request"
        )
        expect(!state.hasFailure(for: requestB.id), "ignored A completion leaves B clean")

        let retryB = state.begin(requestID: requestB.id)
        expect(
            state.complete(retryB, currentRequestID: requestB.id, succeeded: true) == .succeeded,
            "a matching retry success clears the current attempt"
        )
        expect(!state.hasFailure(for: requestB.id), "successful activation has no static failure")
    }

    @MainActor
    private static func testPrivacySafeAuditEvents() async throws {
        let connection = FakeApprovalConnection()
        let coordinator = CodexApprovalCoordinator(connection: connection)
        var auditEvents: [CodexApprovalAuditEvent] = []
        coordinator.onAuditEvent = { event in
            auditEvents.append(event)
        }
        let rawSentinel = "RAW_COMMAND_/private/tmp/secret.diff"
        connection.send(.request(managedRequest(
            id: .string("audit-request-id"),
            threadID: "audit-thread",
            turnID: "audit-turn",
            itemID: "raw-item-id",
            reviewSummary: rawSentinel,
            startedAtMilliseconds: 1
        )))
        await waitUntil("audit request is detected") {
            auditEvents.contains { event in
                if case .detected = event { return true }
                return false
            }
        }
        try await coordinator.submit(
            .decline,
            for: coordinator.presentation.request!.id
        )
        connection.send(.resolved(threadID: "audit-thread", requestID: .string("audit-request-id")))
        await waitUntil("audit resolution is emitted") {
            auditEvents.contains { event in
                if case .resolved = event { return true }
                return false
            }
        }

        var sawDetected = false
        var sawPresented = false
        var sawDecision = false
        var sawResolved = false
        for event in auditEvents {
            switch event {
            case .detected(let kind, let source, let pendingCount, let threadIDLength):
                sawDetected = kind == .command
                    && source == .managedAppServer
                    && pendingCount == 1
                    && threadIDLength == "audit-thread".count
            case .presented(let kind, let inlineCapable):
                sawPresented = sawPresented || (kind == .command && inlineCapable)
            case .decisionSent(let decision, let kind):
                sawDecision = decision == .decline && kind == .command
            case .resolved(let kind, let latencyMilliseconds):
                sawResolved = kind == .command && latencyMilliseconds >= 0
            case .failed:
                break
            }
        }
        expect(sawDetected, "audit records only safe detection metadata")
        expect(!sawPresented, "coordinator never claims an attachment was presented")
        expect(sawDecision, "audit records only the decision wire value and kind")
        expect(sawResolved, "audit records a non-negative sanitized latency")
        let auditDump = auditEvents.map { String(describing: $0) }.joined(separator: "|")
        expect(!auditDump.contains(rawSentinel), "audit events never carry raw review content")
        expect(!auditDump.contains("audit-request-id"), "audit events never carry raw request ids")
        expect(!auditDump.contains("raw-item-id"), "audit events never carry raw item ids")
    }

    private static func testAutoPresentationPolicy() {
        expect(
            CodexApprovalAutoPresentationPolicy.action(
                isShellHidden: true,
                isFilesPinned: false,
                isExpanded: false
            ) == .ignore,
            "hidden shells never auto-present an approval"
        )
        expect(
            CodexApprovalAutoPresentationPolicy.action(
                isShellHidden: false,
                isFilesPinned: true,
                isExpanded: false
            ) == .selectTaskOnly,
            "pinned Files preserves its visible feature while recording task selection"
        )
        expect(
            CodexApprovalAutoPresentationPolicy.action(
                isShellHidden: false,
                isFilesPinned: false,
                isExpanded: false
            ) == .selectTasksAndExpand,
            "a visible collapsed shell selects Tasks and expands"
        )
        expect(
            CodexApprovalAutoPresentationPolicy.action(
                isShellHidden: false,
                isFilesPinned: false,
                isExpanded: true
            ) == .selectTasks,
            "an expanded shell only selects Tasks"
        )
        expect(!CodexTaskStatus.ApprovalState.autoReviewing.requiresManualApproval, "auto review is not a manual approval")
        expect(CodexTaskStatus.ApprovalState.pendingCommand.requiresManualApproval, "command approval is manual")
        expect(CodexTaskStatus.ApprovalState.autoReviewing.displayText == "审查中", "auto review uses explicit in-progress copy")
    }

    @MainActor
    private static func waitUntil(
        _ message: String,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<200 {
            if condition() {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        expect(false, message)
    }
}
