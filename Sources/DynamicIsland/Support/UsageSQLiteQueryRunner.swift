import Foundation
import DynamicIslandCore

protocol SQLiteJSONQueryRunning: Sendable {
    func query(databaseURL: URL, sql: String) async throws -> Data
}

struct SystemSQLiteJSONQueryRunner: SQLiteJSONQueryRunning {
    func query(databaseURL: URL, sql: String) async throws -> Data {
        let cancellationState = SQLiteProcessCancellationState()
        return try await withTaskCancellationHandler(operation: {
            let data = try await Task.detached(priority: .utility) {
                defer { cancellationState.finish() }
                guard !cancellationState.isCancelled else {
                    throw CancellationError()
                }

                let executablePath = "/usr/bin/sqlite3"
                guard FileManager.default.isExecutableFile(atPath: executablePath) else {
                    throw SQLiteJSONQueryError.executableUnavailable
                }

                let process = Process()
                let standardOutput = Pipe()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = ["-batch", "-readonly", "-json", databaseURL.path, sql]
                process.standardOutput = standardOutput
                process.standardError = FileHandle.nullDevice

                guard !cancellationState.install(
                    process: process,
                    standardOutput: standardOutput.fileHandleForReading
                ) else {
                    throw CancellationError()
                }

                do {
                    try process.run()
                } catch {
                    guard !cancellationState.isCancelled else {
                        throw CancellationError()
                    }
                    throw SQLiteJSONQueryError.launchFailed
                }
                cancellationState.stopProcessIfCancelled()

                let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                cancellationState.markProcessExited()
                guard !cancellationState.isCancelled else {
                    throw CancellationError()
                }
                guard process.terminationStatus == 0 else {
                    throw SQLiteJSONQueryError.nonzeroExit(process.terminationStatus)
                }
                return data
            }.value
            try Task.checkCancellation()
            return data
        }, onCancel: {
            cancellationState.cancel()
        })
    }
}

private final class SQLiteProcessCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var standardOutput: FileHandle?
    private var cancelled = false
    private var finished = false
    private var processExited = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func install(process: Process, standardOutput: FileHandle) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return true }
        self.process = process
        self.standardOutput = standardOutput
        processExited = false
        return cancelled
    }

    func stopProcessIfCancelled() {
        lock.lock()
        defer { lock.unlock() }
        guard cancelled, !finished else { return }
        terminateProcessLocked()
    }

    func markProcessExited() {
        lock.lock()
        processExited = true
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        cancelled = true
        terminateProcessLocked()
    }

    func finish() {
        lock.lock()
        finished = true
        standardOutput?.closeFile()
        process = nil
        standardOutput = nil
        lock.unlock()
    }

    private func terminateProcessLocked() {
        if !processExited, process?.isRunning == true {
            process?.terminate()
        }
    }

}

enum SQLiteJSONQueryError: Error, Equatable, Sendable {
    case executableUnavailable
    case launchFailed
    case nonzeroExit(Int32)
}

protocol UsageEntrySource: Sendable {
    func load(in window: UsageQueryWindow) async throws -> UsageSourceBatch
}

struct UsageSourceFailure: Error, Sendable {
    let warning: UsageWarningCategory
}
