import Foundation
import IslandCore

struct ClaudeTaskActivityDataSource: TaskActivityDataSource {
    private let pollInterval: UInt64

    init(pollInterval: UInt64 = 1_000_000_000) {
        self.pollInterval = pollInterval
    }

    func currentState() async -> TaskActivityState {
        await Task.detached(priority: .utility) {
            ClaudeTaskActivityDataSource.detectActivity()
        }.value
    }

    private static func detectActivity() -> TaskActivityState {
        // First check if Claude Desktop or Codex processes are running
        if !runningClaudeProcesses().isEmpty {
            return .running
        }

        // Fallback: check the state file (for debugging via set_task_activity.sh)
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Island/task-activity-state.txt")
        if
            let rawValue = try? String(contentsOf: fileURL, encoding: .utf8),
            let state = TaskActivityState(debugValue: rawValue),
            state != .idle
        {
            return state
        }

        return .idle
    }

    private static func runningClaudeProcesses() -> [(name: String, pid: Int, cpuUsage: Double)] {
        let task = Process()
        if #available(macOS 10.13, *) {
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
        } else {
            task.launchPath = "/bin/ps"
        }
        task.arguments = ["-eo", "pid,pcpu,args", "-r"]

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = Pipe()

        do {
            if #available(macOS 10.13, *) {
                try task.run()
            } else {
                task.launch()
            }
            task.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: outputData, encoding: .utf8) else {
                return []
            }

            return output.split(separator: "\n").compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("PID") else { return nil }

                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 3 else { return nil }

                let pid = Int(parts[0]) ?? 0
                let cpu = Double(parts[1]) ?? 0
                let name = String(parts[2...].joined(separator: " "))

                let lowerName = name.lowercased()
                guard lowerName.contains("claude") || lowerName.contains("codex") else {
                    return nil
                }
                // Don't match our own Island process
                guard !lowerName.contains("island") else {
                    return nil
                }

                return (name, pid, cpu)
            }
        } catch {
            return []
        }
    }
}
