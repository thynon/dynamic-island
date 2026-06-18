import Foundation
import DynamicIslandCore

@MainActor
final class IslandInteractionLogger {
    let sessionID: String
    let logURL: URL

    private let fileHandle: FileHandle?
    private let encoderDateFormatter = ISO8601DateFormatter()

    init(now: Date = Date(), processID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        sessionID = Self.makeSessionID(now: now, processID: processID)
        logURL = Self.defaultLogDirectory
            .appendingPathComponent("session-\(sessionID).jsonl", isDirectory: false)
        encoderDateFormatter.timeZone = .current
        encoderDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        try? FileManager.default.createDirectory(
            at: Self.defaultLogDirectory,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: logURL)
    }

    deinit {
        try? fileHandle?.close()
    }

    func log(_ event: String, metadata: [String: Any] = [:], now: Date = Date()) {
        guard let fileHandle else { return }

        var record = metadata
        record["timestamp"] = encoderDateFormatter.string(from: now)
        record["sessionID"] = sessionID
        record["event"] = event
        record["pid"] = ProcessInfo.processInfo.processIdentifier

        guard
            JSONSerialization.isValidJSONObject(record),
            let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        else {
            return
        }

        fileHandle.seekToEndOfFile()
        fileHandle.write(data)
        fileHandle.write(Data([0x0A]))
    }

    static func sanitizedFileMetadata(for fileURLs: [URL]) -> [[String: Any]] {
        fileURLs.map { fileURL in
            let fileExtension = fileURL.pathExtension.isEmpty ? "" : fileURL.pathExtension.lowercased()
            return [
                "extension": fileExtension,
                "category": TemporaryShelfFileCategory.from(fileExtension: fileExtension).rawValue,
                "nameLength": fileURL.lastPathComponent.count,
                "pathFingerprint": pathFingerprint(fileURL.path)
            ]
        }
    }

    private static var defaultLogDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DynamicIsland", isDirectory: true)
    }

    private static func makeSessionID(now: Date, processID: Int32) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: now))-\(processID)"
    }

    private static func pathFingerprint(_ value: String) -> String {
        let bytes = Array(value.utf8)
        var hash: UInt64 = 14_695_981_039_346_656_037

        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }

        return String(format: "%016llx", hash)
    }
}
