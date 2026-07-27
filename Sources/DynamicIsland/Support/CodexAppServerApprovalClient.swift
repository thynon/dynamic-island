import Foundation
import CoreFoundation
import DynamicIslandCore

protocol CodexApprovalConnection: Sendable {
    var events: AsyncStream<CodexAppServerApprovalEvent> { get }

    func respond(
        to requestID: CodexJSONRPCRequestID,
        decision: CodexApprovalDecision
    ) async throws
}

enum CodexAppServerApprovalClientError: Error, Equatable {
    case executableUnavailable
    case alreadyStarted
    case notConnected
    case requestUnavailable
    case invalidMessage
    case initializationRejected
}

enum CodexAppServerApprovalEvent: Equatable, Sendable {
    case request(CodexApprovalRequest)
    case resolved(threadID: String, requestID: CodexJSONRPCRequestID)
    case turnEnded(threadID: String, turnID: String)
    case disconnected
}

actor CodexAppServerApprovalClient: CodexApprovalConnection {
    typealias WriteLine = @Sendable (Data) throws -> Void

    private struct ManagedApprovalFingerprint: Equatable, Hashable, Sendable {
        let source: String
        let requestID: CodexJSONRPCRequestID
        let threadID: String
        let turnID: String
        let itemID: String
        let approvalID: String?
    }

    private struct RoutingIdentity: Equatable, Hashable, Sendable {
        let requestID: CodexJSONRPCRequestID
        let threadID: String
    }

    private struct ItemIdentity: Equatable, Hashable, Sendable {
        let threadID: String
        let turnID: String
        let itemID: String
    }

    private struct PendingApproval: Sendable {
        let fingerprint: ManagedApprovalFingerprint
        let kind: CodexApprovalKind
        let startedAtMilliseconds: Int64
        let commandReviewSummary: String?

        var itemIdentity: ItemIdentity {
            ItemIdentity(
                threadID: fingerprint.threadID,
                turnID: fingerprint.turnID,
                itemID: fingerprint.itemID
            )
        }
    }

    private struct ActiveResponseCapability: Sendable {
        let routingIdentity: RoutingIdentity
        let generation: UInt64
    }

    nonisolated let events: AsyncStream<CodexAppServerApprovalEvent>

    private let eventContinuation: AsyncStream<CodexAppServerApprovalEvent>.Continuation
    private let injectedWriteLine: WriteLine?
    private var process: Process?
    private var standardInput: FileHandle?
    private var readerTask: Task<Void, Never>?
    private var lineBuffer = Data()
    private var pendingApprovals: [RoutingIdentity: PendingApproval] = [:]
    private var lastRequests: [RoutingIdentity: CodexApprovalRequest] = [:]
    private var fileReviewSummaries: [ItemIdentity: String] = [:]
    private var activeResponseCapabilities: [CodexJSONRPCRequestID: ActiveResponseCapability] = [:]
    private var respondedRoutingIdentities: Set<RoutingIdentity> = []
    private var connectionGeneration: UInt64 = 0
    private var activeConnectionGeneration: UInt64?
    private var hasStarted = false
    private var didSendInitialized = false

    init() {
        var continuation: AsyncStream<CodexAppServerApprovalEvent>.Continuation?
        events = AsyncStream { continuation = $0 }
        eventContinuation = continuation!
        injectedWriteLine = nil
    }

    init(writeLine: @escaping WriteLine) {
        var continuation: AsyncStream<CodexAppServerApprovalEvent>.Continuation?
        events = AsyncStream { continuation = $0 }
        eventContinuation = continuation!
        injectedWriteLine = writeLine
        connectionGeneration = 1
        activeConnectionGeneration = 1
        hasStarted = true
    }

    deinit {
        readerTask?.cancel()
        eventContinuation.finish()
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    static func resolveExecutable(
        fileManager: FileManager = .default
    ) -> URL? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates.first(where: fileManager.isExecutableFile(atPath:)).map {
            URL(fileURLWithPath: $0)
        }
    }

    func start() throws {
        guard !hasStarted, process == nil, injectedWriteLine == nil else {
            throw CodexAppServerApprovalClientError.alreadyStarted
        }
        hasStarted = true
        guard let executableURL = Self.resolveExecutable() else {
            throw CodexAppServerApprovalClientError.executableUnavailable
        }

        connectionGeneration &+= 1
        let generation = connectionGeneration
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let child = Process()
        child.executableURL = executableURL
        child.arguments = ["app-server", "--listen", "stdio://"]
        child.standardInput = inputPipe
        child.standardOutput = outputPipe
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] _ in
            Task {
                await self?.connectionDidEnd(generation: generation)
            }
        }

        do {
            try child.run()
        } catch {
            throw CodexAppServerApprovalClientError.executableUnavailable
        }

        process = child
        standardInput = inputPipe.fileHandleForWriting
        activeConnectionGeneration = generation
        didSendInitialized = false
        clearManagedState()
        startReader(
            outputPipe.fileHandleForReading,
            generation: generation
        )

        do {
            try writeJSONObject([
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "dynamic_island",
                        "title": "Dynamic Island",
                        "version": Self.bundleVersion
                    ]
                ]
            ])
        } catch {
            child.terminate()
            throw error
        }
    }

    func stop() {
        guard let generation = activeConnectionGeneration else { return }
        activeConnectionGeneration = nil
        readerTask?.cancel()
        readerTask = nil
        try? standardInput?.close()
        standardInput = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        lineBuffer.removeAll(keepingCapacity: false)
        clearManagedState()
        eventContinuation.yield(.disconnected)
        connectionGeneration = max(connectionGeneration, generation)
    }

    func respond(
        to requestID: CodexJSONRPCRequestID,
        decision: CodexApprovalDecision
    ) async throws {
        guard let generation = activeConnectionGeneration else {
            throw CodexAppServerApprovalClientError.notConnected
        }
        guard let capability = activeResponseCapabilities[requestID],
              capability.generation == generation,
              pendingApprovals[capability.routingIdentity] != nil,
              !respondedRoutingIdentities.contains(capability.routingIdentity)
        else {
            throw CodexAppServerApprovalClientError.requestUnavailable
        }

        activeResponseCapabilities.removeValue(forKey: requestID)
        respondedRoutingIdentities.insert(capability.routingIdentity)
        try writeJSONObject([
            "id": Self.jsonValue(for: requestID),
            "result": ["decision": decision.rawValue]
        ])
    }

    func ingest(_ data: Data) {
        guard activeConnectionGeneration != nil else { return }
        lineBuffer.append(data)
        while let newlineIndex = lineBuffer.firstIndex(of: 0x0A) {
            let line = Data(lineBuffer[..<newlineIndex])
            lineBuffer.removeSubrange(...newlineIndex)
            handleLine(line)
        }
    }

    private static var bundleVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? "0"
    }

    private static func jsonValue(for requestID: CodexJSONRPCRequestID) -> Any {
        switch requestID {
        case .integer(let value):
            return NSNumber(value: value)
        case .string(let value):
            return value
        }
    }

    private func writeJSONObject(_ object: [String: Any]) throws {
        guard activeConnectionGeneration != nil else {
            throw CodexAppServerApprovalClientError.notConnected
        }
        guard JSONSerialization.isValidJSONObject(object) else {
            throw CodexAppServerApprovalClientError.invalidMessage
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)

        if let injectedWriteLine {
            try injectedWriteLine(data)
            return
        }
        guard let standardInput else {
            throw CodexAppServerApprovalClientError.notConnected
        }
        try standardInput.write(contentsOf: data)
    }

    private func startReader(
        _ output: FileHandle,
        generation: UInt64
    ) {
        readerTask = Task.detached(priority: .utility) { [weak self] in
            do {
                while !Task.isCancelled {
                    guard let data = try output.read(upToCount: 4_096), !data.isEmpty else {
                        await self?.connectionDidEnd(generation: generation)
                        return
                    }
                    await self?.ingest(data)
                }
            } catch {
                await self?.connectionDidEnd(generation: generation)
            }
        }
    }

    private func handleLine(_ data: Data) {
        guard !data.isEmpty,
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if isInitializeResponse(envelope) {
            guard envelope["error"] == nil else {
                connectionFailedInitialization()
                return
            }
            guard !didSendInitialized else { return }
            do {
                try writeJSONObject([
                    "method": "initialized",
                    "params": [String: Any]()
                ])
                didSendInitialized = true
            } catch {
                connectionFailedInitialization()
            }
            return
        }

        guard let method = envelope["method"] as? String,
              let params = envelope["params"] as? [String: Any]
        else { return }

        switch method {
        case "item/commandExecution/requestApproval",
             "item/fileChange/requestApproval",
             "item/permissions/requestApproval":
            receiveApproval(method: method, envelope: envelope, params: params)
        case "item/started", "item/completed":
            receiveFileItemContext(params: params)
        case "item/fileChange/patchUpdated":
            receiveFilePatchContext(params: params)
        case "serverRequest/resolved":
            receiveResolution(params: params)
        case "turn/completed", "turn/aborted", "turn/cancelled", "turn/failed":
            receiveTurnEnd(params: params)
        default:
            break
        }
    }

    private func isInitializeResponse(_ envelope: [String: Any]) -> Bool {
        guard let requestID = Self.requestID(from: envelope["id"]) else { return false }
        return requestID == .integer(0)
            && (envelope["result"] != nil || envelope["error"] != nil)
    }

    private func receiveApproval(
        method: String,
        envelope: [String: Any],
        params: [String: Any]
    ) {
        guard let requestID = Self.requestID(from: envelope["id"]),
              let threadID = params["threadId"] as? String,
              let turnID = params["turnId"] as? String,
              let itemID = params["itemId"] as? String
        else { return }

        let kind: CodexApprovalKind
        let commandReviewSummary: String?
        switch method {
        case "item/commandExecution/requestApproval":
            kind = .command
            commandReviewSummary = Self.nonEmptyString(params["command"])
        case "item/fileChange/requestApproval":
            kind = .fileChange
            commandReviewSummary = nil
        case "item/permissions/requestApproval":
            kind = .permissions
            commandReviewSummary = nil
        default:
            return
        }

        let approvalID = params["approvalId"] as? String
        let fingerprint = ManagedApprovalFingerprint(
            source: "managedAppServer",
            requestID: requestID,
            threadID: threadID,
            turnID: turnID,
            itemID: itemID,
            approvalID: approvalID
        )
        let routingIdentity = RoutingIdentity(
            requestID: requestID,
            threadID: threadID
        )
        pendingApprovals[routingIdentity] = PendingApproval(
            fingerprint: fingerprint,
            kind: kind,
            startedAtMilliseconds: Self.int64(from: params["startedAtMs"]) ?? 0,
            commandReviewSummary: commandReviewSummary
        )
        publishRequest(for: routingIdentity)
    }

    private func receiveFileItemContext(params: [String: Any]) {
        guard let threadID = params["threadId"] as? String,
              let turnID = params["turnId"] as? String,
              let item = params["item"] as? [String: Any],
              item["type"] as? String == "fileChange",
              let itemID = item["id"] as? String
        else { return }
        updateFileContext(
            Self.fileReviewSummary(from: item["changes"]),
            for: ItemIdentity(threadID: threadID, turnID: turnID, itemID: itemID)
        )
    }

    private func receiveFilePatchContext(params: [String: Any]) {
        guard let threadID = params["threadId"] as? String,
              let turnID = params["turnId"] as? String,
              let itemID = params["itemId"] as? String
        else { return }
        updateFileContext(
            Self.fileReviewSummary(from: params["changes"]),
            for: ItemIdentity(threadID: threadID, turnID: turnID, itemID: itemID)
        )
    }

    private func updateFileContext(
        _ reviewSummary: String?,
        for itemIdentity: ItemIdentity
    ) {
        if let reviewSummary {
            fileReviewSummaries[itemIdentity] = reviewSummary
        } else {
            fileReviewSummaries.removeValue(forKey: itemIdentity)
        }
        for routingIdentity in pendingApprovals.keys where
            pendingApprovals[routingIdentity]?.itemIdentity == itemIdentity {
            publishRequest(for: routingIdentity)
        }
    }

    private func publishRequest(for routingIdentity: RoutingIdentity) {
        guard let pending = pendingApprovals[routingIdentity] else { return }

        let availableDecisions: [CodexApprovalDecision]
        let reviewSummary: String?
        switch pending.kind {
        case .command:
            reviewSummary = pending.commandReviewSummary
            availableDecisions = reviewSummary == nil
                ? []
                : [.decline, .accept, .acceptForSession]
        case .fileChange:
            reviewSummary = fileReviewSummaries[pending.itemIdentity]
            availableDecisions = reviewSummary == nil
                ? []
                : [.decline, .accept, .acceptForSession]
        case .permissions:
            reviewSummary = nil
            availableDecisions = []
        }

        let request = CodexApprovalRequest(
            requestID: pending.fingerprint.requestID,
            threadID: pending.fingerprint.threadID,
            turnID: pending.fingerprint.turnID,
            itemID: pending.fingerprint.itemID,
            approvalID: pending.fingerprint.approvalID,
            kind: pending.kind,
            startedAtMilliseconds: pending.startedAtMilliseconds,
            source: .managedAppServer,
            availableDecisions: availableDecisions,
            reviewSummary: reviewSummary
        )
        guard lastRequests[routingIdentity] != request else { return }
        lastRequests[routingIdentity] = request

        if request.canRespondInline,
           !respondedRoutingIdentities.contains(routingIdentity),
           let generation = activeConnectionGeneration {
            activeResponseCapabilities[request.requestID!] = ActiveResponseCapability(
                routingIdentity: routingIdentity,
                generation: generation
            )
        } else if activeResponseCapabilities[request.requestID!]?.routingIdentity == routingIdentity {
            activeResponseCapabilities.removeValue(forKey: request.requestID!)
        }
        eventContinuation.yield(.request(request))
    }

    private func receiveResolution(params: [String: Any]) {
        guard let threadID = params["threadId"] as? String,
              let requestID = Self.requestID(from: params["requestId"])
        else { return }
        let routingIdentity = RoutingIdentity(
            requestID: requestID,
            threadID: threadID
        )
        removePendingApproval(routingIdentity)
        eventContinuation.yield(.resolved(threadID: threadID, requestID: requestID))
    }

    private func receiveTurnEnd(params: [String: Any]) {
        guard let threadID = params["threadId"] as? String else { return }
        let turnID = (params["turnId"] as? String)
            ?? ((params["turn"] as? [String: Any])?["id"] as? String)
        guard let turnID else { return }

        let endedRoutingIdentities = pendingApprovals.compactMap {
            $0.value.fingerprint.threadID == threadID && $0.value.fingerprint.turnID == turnID
                ? $0.key
                : nil
        }
        endedRoutingIdentities.forEach(removePendingApproval)
        fileReviewSummaries = fileReviewSummaries.filter {
            $0.key.threadID != threadID || $0.key.turnID != turnID
        }
        eventContinuation.yield(.turnEnded(threadID: threadID, turnID: turnID))
    }

    private func removePendingApproval(_ routingIdentity: RoutingIdentity) {
        let removedPending = pendingApprovals.removeValue(forKey: routingIdentity)
        lastRequests.removeValue(forKey: routingIdentity)
        respondedRoutingIdentities.remove(routingIdentity)
        if activeResponseCapabilities[routingIdentity.requestID]?.routingIdentity == routingIdentity {
            activeResponseCapabilities.removeValue(forKey: routingIdentity.requestID)
        }
        if let removedPending, removedPending.kind == .fileChange {
            let itemIdentity = removedPending.itemIdentity
            let isStillReferenced = pendingApprovals.values.contains {
                $0.kind == .fileChange && $0.itemIdentity == itemIdentity
            }
            if !isStillReferenced {
                fileReviewSummaries.removeValue(forKey: itemIdentity)
            }
        }
    }

    private func connectionFailedInitialization() {
        guard activeConnectionGeneration != nil else { return }
        activeConnectionGeneration = nil
        readerTask?.cancel()
        readerTask = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        standardInput = nil
        lineBuffer.removeAll(keepingCapacity: false)
        clearManagedState()
        eventContinuation.yield(.disconnected)
    }

    private func connectionDidEnd(generation: UInt64) {
        guard activeConnectionGeneration == generation else { return }
        activeConnectionGeneration = nil
        readerTask?.cancel()
        readerTask = nil
        process = nil
        try? standardInput?.close()
        standardInput = nil
        lineBuffer.removeAll(keepingCapacity: false)
        clearManagedState()
        eventContinuation.yield(.disconnected)
    }

    private func clearManagedState() {
        pendingApprovals.removeAll()
        lastRequests.removeAll()
        fileReviewSummaries.removeAll()
        activeResponseCapabilities.removeAll()
        respondedRoutingIdentities.removeAll()
    }

    private static func requestID(from value: Any?) -> CodexJSONRPCRequestID? {
        if let value = value as? String {
            return .string(value)
        }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let value = Int64(number.stringValue)
        else { return nil }
        return .integer(value)
    }

    private static func int64(from value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        return Int64(number.stringValue)
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return value
    }

    private static func fileReviewSummary(from value: Any?) -> String? {
        guard let changes = value as? [[String: Any]] else { return nil }
        let summaries = changes.compactMap { change -> String? in
            guard let path = nonEmptyString(change["path"]),
                  let diff = nonEmptyString(change["diff"])
            else { return nil }
            return "\(path)\n\(diff)"
        }
        guard !summaries.isEmpty else { return nil }
        return summaries.joined(separator: "\n\n")
    }
}
