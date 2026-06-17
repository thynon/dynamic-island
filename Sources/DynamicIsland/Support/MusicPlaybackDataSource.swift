import AppKit
import Foundation
import DynamicIslandCore

struct MusicPlaybackSnapshot: Equatable, Sendable {
    let isPlaying: Bool
    let waveform: AudioPlaybackSnapshot
    let artworkData: Data?

    static let idle = MusicPlaybackSnapshot(isPlaying: false, waveform: .idle, artworkData: nil)

    static func playing(artworkData: Data? = nil) -> MusicPlaybackSnapshot {
        MusicPlaybackSnapshot(isPlaying: true, waveform: syntheticWaveform(), artworkData: artworkData)
    }

    private static func syntheticWaveform() -> AudioPlaybackSnapshot {
        let levels = (0..<12).map { index -> Double in
            let progress = Double(index) / 11.0
            let envelope = 0.34 + (sin(progress * .pi) * 0.30)
            let carrier = sin((progress * .pi * 5.0) + 0.45)
            let texture = sin((progress * .pi * 13.0) - 0.65) * 0.20
            return (carrier + texture) * envelope
        }
        return AudioPlaybackSnapshot(levels: levels)
    }
}

protocol MusicPlaybackDataSource: Sendable {
    func currentSnapshot() async -> MusicPlaybackSnapshot
}

final class ScriptableMusicPlaybackDataSource: MusicPlaybackDataSource, @unchecked Sendable {
    private let players = [
        ScriptableMusicPlayer(appName: "Music", bundleIdentifier: "com.apple.Music"),
        ScriptableMusicPlayer(appName: "Spotify", bundleIdentifier: "com.spotify.client")
    ]
    private let lock = NSLock()
    private var cachedSnapshot = MusicPlaybackSnapshot.idle
    private var cachedDate: Date?

    func currentSnapshot() async -> MusicPlaybackSnapshot {
        let cached = withLockedState {
            (snapshot: cachedSnapshot, date: cachedDate)
        }

        if let date = cached.date, Date().timeIntervalSince(date) <= 1.0 {
            return cached.snapshot
        }

        let players = players
        let nextSnapshot = await Task.detached(priority: .utility) {
            for player in players where Self.isPlayerRunning(bundleIdentifier: player.bundleIdentifier) {
                if let snapshot = Self.playingSnapshot(for: player) {
                    return snapshot
                }
            }
            return MusicPlaybackSnapshot.idle
        }.value

        withLockedState {
            cachedSnapshot = nextSnapshot
            cachedDate = Date()
        }
        return nextSnapshot
    }

    private func withLockedState<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static func isPlayerRunning(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier == bundleIdentifier
        }
    }

    private static func playingSnapshot(for player: ScriptableMusicPlayer) -> MusicPlaybackSnapshot? {
        switch player.appName {
        case "Music":
            return musicPlayingSnapshot(appName: player.appName)
        case "Spotify":
            return spotifyPlayingSnapshot(appName: player.appName)
        default:
            return isPlaying(appName: player.appName) ? .playing() : nil
        }
    }

    private static func musicPlayingSnapshot(appName: String) -> MusicPlaybackSnapshot? {
        let artworkURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-current-artwork-\(UUID().uuidString)")
        let escapedAppName = escapedAppleScriptString(appName)
        let escapedPath = escapedAppleScriptString(artworkURL.path)
        let script = """
        set artworkData to missing value
        if application "\(escapedAppName)" is running then
            tell application "\(escapedAppName)"
                try
                    if player state is playing then
                        try
                            set artworkData to data of artwork 1 of current track
                        end try
                    else
                        return "idle"
                    end if
                end try
            end tell
            if artworkData is not missing value then
                set fileReference to missing value
                try
                    set artworkPath to "\(escapedPath)"
                    set outputFile to POSIX file artworkPath
                    set fileReference to open for access outputFile with write permission
                    set eof of fileReference to 0
                    write artworkData to fileReference
                    close access fileReference
                on error
                    try
                        if fileReference is not missing value then close access fileReference
                    end try
                end try
            end if
            return "playing"
        end if
        return "idle"
        """

        defer {
            try? FileManager.default.removeItem(at: artworkURL)
        }

        guard runAppleScript(script) == "playing" else {
            return nil
        }

        return .playing(artworkData: try? Data(contentsOf: artworkURL))
    }

    private static func spotifyPlayingSnapshot(appName: String) -> MusicPlaybackSnapshot? {
        let escapedAppName = escapedAppleScriptString(appName)
        let script = """
        if application "\(escapedAppName)" is running then
            tell application "\(escapedAppName)"
                try
                    if player state is playing then
                        try
                            return "playing\t" & (artwork url of current track)
                        on error
                            return "playing\t"
                        end try
                    end if
                end try
            end tell
        end if
        return "idle\t"
        """

        let output = runAppleScript(script)
        let parts = output.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.first == "playing" else {
            return nil
        }

        let artworkData = parts.dropFirst().first
            .map(String.init)
            .flatMap(remoteArtworkData)
        return .playing(artworkData: artworkData)
    }

    private static func isPlaying(appName: String) -> Bool {
        let escapedAppName = escapedAppleScriptString(appName)
        let script = """
        if application "\(escapedAppName)" is running then
            tell application "\(escapedAppName)"
                try
                    if player state is playing then return "playing"
                end try
            end tell
        end if
        return "idle"
        """

        return runAppleScript(script) == "playing"
    }

    private static func runAppleScript(_ source: String) -> String {
        var errorInfo: NSDictionary?
        guard
            let appleScript = NSAppleScript(source: source),
            let output = appleScript.executeAndReturnError(&errorInfo).stringValue
        else {
            return ""
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func remoteArtworkData(from urlString: String) -> Data? {
        guard let url = URL(string: urlString), ["http", "https"].contains(url.scheme?.lowercased()) else {
            return nil
        }

        return try? Data(contentsOf: url)
    }

    private static func escapedAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private struct ScriptableMusicPlayer: Sendable {
    let appName: String
    let bundleIdentifier: String
}
