import Foundation
import IslandCore

protocol TaskActivityDataSource: Sendable {
    func currentState() async -> TaskActivityState
}

struct FileBackedTaskActivityDataSource: TaskActivityDataSource {
    static let defaultStateFileURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Island/task-activity-state.txt")

    let stateFileURL: URL

    init(stateFileURL: URL = Self.defaultStateFileURL) {
        self.stateFileURL = stateFileURL
    }

    func currentState() async -> TaskActivityState {
        let url = stateFileURL
        return await Task.detached(priority: .utility) {
            Self.readState(from: url) ?? .idle
        }.value
    }

    static func readState(from url: URL = Self.defaultStateFileURL) -> TaskActivityState? {
        guard
            let rawValue = try? String(contentsOf: url, encoding: .utf8),
            let state = TaskActivityState(debugValue: rawValue)
        else {
            return nil
        }

        return state
    }
}

struct CodexTaskActivityDataSource: TaskActivityDataSource {
    private static let defaultSessionsDirectory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)

    let sessionsDirectory: URL
    let stateFileURL: URL

    init(
        sessionsDirectory: URL = Self.defaultSessionsDirectory,
        stateFileURL: URL = FileBackedTaskActivityDataSource.defaultStateFileURL
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.stateFileURL = stateFileURL
    }

    func currentState() async -> TaskActivityState {
        let sessionsDirectory = sessionsDirectory
        let stateFileURL = stateFileURL
        return await Task.detached(priority: .utility) {
            let explicitState = FileBackedTaskActivityDataSource.readState(from: stateFileURL)
            let modificationDate = Self.stateFileModificationDate(stateFileURL)
            if let explicitState = TaskActivityOverridePolicy.effectiveState(
                explicitState,
                modificationDate: modificationDate
            ) {
                return explicitState
            }

            return Self.detectCodexSessionState(sessionsDirectory: sessionsDirectory)
        }.value
    }

    private static func detectCodexSessionState(sessionsDirectory: URL) -> TaskActivityState {
        guard let latestFile = latestSessionFile(in: sessionsDirectory) else {
            return .idle
        }

        let secondsSinceLatestWrite = latestFile.modificationDate.map {
            max(0, Date().timeIntervalSince($0))
        }
        let eventTypes = recentEventTypes(from: latestFile.url)
        return CodexTaskActivityHeuristic.state(
            recentEventTypes: eventTypes,
            secondsSinceLatestWrite: secondsSinceLatestWrite
        )
    }

    private static func latestSessionFile(in directory: URL) -> (url: URL, modificationDate: Date?)? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var latest: (url: URL, modificationDate: Date?)?
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            guard
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                values.isRegularFile == true
            else {
                continue
            }

            let modificationDate = values.contentModificationDate
            if let currentLatest = latest {
                let currentTime = currentLatest.modificationDate ?? .distantPast
                if (modificationDate ?? .distantPast) > currentTime {
                    latest = (fileURL, modificationDate)
                }
            } else {
                latest = (fileURL, modificationDate)
            }
        }

        return latest
    }

    private static func stateFileModificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func recentEventTypes(from fileURL: URL, maxBytes: UInt64 = 96 * 1024) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return []
        }
        defer {
            try? handle.close()
        }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let offset = fileSize > maxBytes ? fileSize - maxBytes : 0
        try? handle.seek(toOffset: offset)
        guard
            let data = try? handle.readToEnd(),
            let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        return text
            .split(separator: "\n")
            .suffix(80)
            .compactMap { CodexTaskActivityEvent.eventType(in: String($0)) }
    }
}
