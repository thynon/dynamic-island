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
            guard
                let rawValue = try? String(contentsOf: url, encoding: .utf8),
                let state = TaskActivityState(debugValue: rawValue)
            else {
                return .idle
            }

            return state
        }.value
    }
}
