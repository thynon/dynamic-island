public enum AudioWaveformPresentationMode: Equatable, Sendable {
    case idle
    case audioLevels
}

public struct AudioPlaybackSnapshot: Equatable, Sendable {
    public let levels: [Double]
    public let presentationMode: AudioWaveformPresentationMode

    public init(levels: [Double], presentationMode: AudioWaveformPresentationMode? = nil) {
        self.levels = levels.map { max(-1, min(1, $0)) }
        self.presentationMode = presentationMode ?? (levels.isEmpty ? .idle : .audioLevels)
    }

    public var isWaveformActive: Bool {
        switch presentationMode {
        case .audioLevels:
            return !levels.isEmpty && levels.contains { abs($0) > 0.015 }
        case .idle:
            return false
        }
    }

    public static let idle = AudioPlaybackSnapshot(levels: [])
    public static let defaultFallback = idle
}

public typealias AudioPlaybackState = AudioPlaybackSnapshot
