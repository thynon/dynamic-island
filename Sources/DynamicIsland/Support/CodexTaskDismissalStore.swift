import Foundation

@MainActor
final class CodexTaskDismissalStore {
    static let defaultURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Dynamic Island/codex-task-dismissals.json")

    private let fileURL: URL
    private let retentionDuration: TimeInterval = 7 * 24 * 60 * 60
    private var dismissedAtByKey: [String: Date]

    init(fileURL: URL = CodexTaskDismissalStore.defaultURL, now: Date = Date()) {
        self.fileURL = fileURL
        self.dismissedAtByKey = Self.load(from: fileURL)
        prune(now: now)
    }

    func activeKeys(now: Date = Date()) -> Set<String> {
        prune(now: now)
        return Set(dismissedAtByKey.keys)
    }

    func dismiss(_ key: String, now: Date = Date()) {
        guard !key.isEmpty else { return }
        dismissedAtByKey[key] = now
        save()
    }

    func restore(_ key: String) {
        guard dismissedAtByKey.removeValue(forKey: key) != nil else { return }
        save()
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-retentionDuration)
        let originalCount = dismissedAtByKey.count
        dismissedAtByKey = dismissedAtByKey.filter { $0.value >= cutoff }
        if dismissedAtByKey.count != originalCount {
            save()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(dismissedAtByKey).write(to: fileURL, options: [.atomic])
        } catch {
            return
        }
    }

    private static func load(from fileURL: URL) -> [String: Date] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Date].self, from: data)) ?? [:]
    }
}
