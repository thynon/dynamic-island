import Foundation
import IslandCore

enum ClaudeUsageDataSource {
    static func loadEvents(
        projectsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    ) async -> [CodexUsageEvent] {
        await Task.detached(priority: .utility) {
            ClaudeUsageDataSource.loadEventsSync(projectsDirectory: projectsDirectory)
        }.value
    }

    static func loadEventsSince(
        _ earliestDate: Date,
        projectsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    ) async -> [CodexUsageEvent] {
        let all = await loadEvents(projectsDirectory: projectsDirectory)
        return all.filter { $0.timestamp >= earliestDate }
    }

    private static func loadEventsSync(
        projectsDirectory: URL
    ) -> [CodexUsageEvent] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var events: [CodexUsageEvent] = []

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            events.append(contentsOf: parseSessionFile(fileURL))
        }

        return events
    }

    private static func parseSessionFile(_ fileURL: URL) -> [CodexUsageEvent] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return []
        }
        defer { try? handle.close() }

        var events: [CodexUsageEvent] = []
        var remainder = Data()

        while let chunk = try? handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            var buffer = remainder
            buffer.append(chunk)

            var lineStart = buffer.startIndex
            while let newlineIndex = buffer[lineStart...].firstIndex(of: 10) {
                let lineData = Data(buffer[lineStart..<newlineIndex])
                processLine(lineData, events: &events)
                lineStart = buffer.index(after: newlineIndex)
            }

            remainder = Data(buffer[lineStart...])
        }

        if !remainder.isEmpty {
            processLine(remainder, events: &events)
        }

        return events
    }

    private static func processLine(_ data: Data, events: inout [CodexUsageEvent]) {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any]
        else {
            return
        }

        let inputTokens = usage["input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
        let outputTokens = usage["output_tokens"] as? Int ?? 0

        let model = message["model"] as? String

        let timestamp: Date
        if let tsString = json["timestamp"] as? String {
            timestamp = Self.parseTimestamp(tsString) ?? Date()
        } else {
            timestamp = Date()
        }

        events.append(
            CodexUsageEvent(
                timestamp: timestamp,
                usage: CodexTokenUsage(
                    inputTokens: inputTokens,
                    cachedInputTokens: cacheRead + cacheCreation,
                    outputTokens: outputTokens,
                    reasoningOutputTokens: 0,
                    totalTokens: inputTokens + outputTokens
                ),
                model: model
            )
        )
    }

    private static func parseTimestamp(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
