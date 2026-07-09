import Foundation
import DynamicIslandCore

struct CodexReasoningEffortSignal: Equatable, Sendable {
    enum Source: String, Equatable, Sendable {
        case ccSwitchRealtime
        case codexState
        case ccSwitch
        case codexConfig
        case unavailable
    }

    let effort: CodexReasoningEffort?
    let source: Source

    var triggersEnergyTail: Bool {
        effort?.triggersEnergyTail ?? false
    }
}

struct CodexReasoningEffortSignalSource {
    private let homeDirectoryURL: URL
    private let fileManager: FileManager
    private let sqliteExecutableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    private let ccSwitchRealtimeSignalRelativePath = ".cc-switch/codex-reasoning-signal.json"
    private let temporaryRealtimeSignalURL = URL(fileURLWithPath: "/tmp/codex-reasoning-signal.json")
    private let realtimeSignalMaximumAge: TimeInterval = 60
    private let codexStateDatabaseRelativePath = ".codex/state_5.sqlite"
    private let ccSwitchDatabaseRelativePath = ".cc-switch/cc-switch.db"
    private let ccSwitchSettingsRelativePath = ".cc-switch/settings.json"
    private let codexConfigRelativePath = ".codex/config.toml"

    init(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.homeDirectoryURL = homeDirectoryURL
        self.fileManager = fileManager
    }

    func currentSignal() -> CodexReasoningEffortSignal {
        if let signal = readCcSwitchRealtimeSignal() {
            return signal
        }

        if fileManager.fileExists(atPath: codexStateDatabaseURL.path),
           let effort = readLatestCodexThreadEffort()
        {
            return CodexReasoningEffortSignal(effort: effort, source: .codexState)
        }

        if fileManager.fileExists(atPath: ccSwitchDatabaseURL.path),
           let effort = readCcSwitchCurrentCodexEffort()
        {
            return CodexReasoningEffortSignal(effort: effort, source: .ccSwitch)
        }

        if let effort = readCodexConfigEffort() {
            return CodexReasoningEffortSignal(effort: effort, source: .codexConfig)
        }

        return CodexReasoningEffortSignal(effort: nil, source: .unavailable)
    }

    private var codexStateDatabaseURL: URL {
        homeDirectoryURL.appendingPathComponent(codexStateDatabaseRelativePath)
    }

    private var ccSwitchDatabaseURL: URL {
        homeDirectoryURL.appendingPathComponent(ccSwitchDatabaseRelativePath)
    }

    private var ccSwitchRealtimeSignalURL: URL {
        homeDirectoryURL.appendingPathComponent(ccSwitchRealtimeSignalRelativePath)
    }

    private var ccSwitchSettingsURL: URL {
        homeDirectoryURL.appendingPathComponent(ccSwitchSettingsRelativePath)
    }

    private var codexConfigURL: URL {
        homeDirectoryURL.appendingPathComponent(codexConfigRelativePath)
    }

    private func readCcSwitchRealtimeSignal() -> CodexReasoningEffortSignal? {
        for url in [ccSwitchRealtimeSignalURL, temporaryRealtimeSignalURL] {
            guard let signal = readRealtimeSignal(from: url) else { continue }
            return signal
        }
        return nil
    }

    private func readRealtimeSignal(from url: URL) -> CodexReasoningEffortSignal? {
        guard realtimeSignalIsFresh(at: url) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return nil
        }

        let active = dictionary["active"] as? Bool
        if active == false {
            return CodexReasoningEffortSignal(effort: nil, source: .ccSwitchRealtime)
        }

        let rawEffort = dictionary["reasoningEffort"] as? String
            ?? dictionary["effort"] as? String
            ?? (dictionary["reasoning"] as? [String: Any])?["effort"] as? String

        guard let rawEffort else { return nil }
        return CodexReasoningEffortSignal(
            effort: CodexReasoningEffort.fromReasoningEffortValue(rawEffort),
            source: .ccSwitchRealtime
        )
    }

    private func realtimeSignalIsFresh(at url: URL) -> Bool {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            let modificationDate = attributes[.modificationDate] as? Date
        else {
            return false
        }
        return Date().timeIntervalSince(modificationDate) <= realtimeSignalMaximumAge
    }

    private func readLatestCodexThreadEffort() -> CodexReasoningEffort? {
        let query = """
        SELECT reasoning_effort FROM threads WHERE archived=0 AND reasoning_effort IS NOT NULL AND reasoning_effort != '' ORDER BY updated_at_ms DESC LIMIT 1;
        """
        guard let rawEffort = runSQLiteQuery(query, databaseURL: codexStateDatabaseURL), !rawEffort.isEmpty else {
            return nil
        }
        return CodexReasoningEffort.fromReasoningEffortValue(rawEffort)
    }

    private func readCcSwitchCurrentCodexEffort() -> CodexReasoningEffort? {
        let currentProviderQuery = """
        SELECT json_extract(settings_config, '$.config') FROM providers WHERE app_type='codex' AND is_current=1 LIMIT 1;
        """
        if let effort = effortFromCcSwitchQuery(currentProviderQuery) {
            return effort
        }

        guard let providerID = readCurrentProviderCodexID() else { return nil }
        let providerIDQuery = """
        SELECT json_extract(settings_config, '$.config') FROM providers WHERE app_type='codex' AND id='\(escapedSQLLiteral(providerID))' LIMIT 1;
        """
        return effortFromCcSwitchQuery(providerIDQuery)
    }

    private func effortFromCcSwitchQuery(_ query: String) -> CodexReasoningEffort? {
        guard let config = runSQLiteQuery(query, databaseURL: ccSwitchDatabaseURL), !config.isEmpty else { return nil }
        return CodexReasoningEffort.fromCodexConfig(config)
            ?? CodexReasoningEffort.fromCcSwitchProviderSettingsConfig(config)
    }

    private func readCurrentProviderCodexID() -> String? {
        guard let data = try? Data(contentsOf: ccSwitchSettingsURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return nil
        }
        return dictionary["currentProviderCodex"] as? String
    }

    private func readCodexConfigEffort() -> CodexReasoningEffort? {
        guard let config = try? String(contentsOf: codexConfigURL, encoding: .utf8) else { return nil }
        return CodexReasoningEffort.fromCodexConfig(config)
    }

    private func runSQLiteQuery(_ query: String, databaseURL: URL) -> String? {
        guard fileManager.fileExists(atPath: sqliteExecutableURL.path) else { return nil }

        let process = Process()
        process.executableURL = sqliteExecutableURL
        process.arguments = [
            "-batch",
            "-noheader",
            databaseURL.path,
            query
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func escapedSQLLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
