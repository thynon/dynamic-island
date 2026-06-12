import CoreGraphics

public enum StatusDotAnimationKind: Equatable, Sendable {
    case hidden
    case breathingGlow
    case fastPulse
}

public struct StatusDotBreathingProfile: Equatable, Sendable {
    public let isActive: Bool
    public let minScale: CGFloat
    public let maxScale: CGFloat
    public let minOpacity: Double
    public let maxOpacity: Double
    public let minBlurRadius: CGFloat
    public let maxBlurRadius: CGFloat
    public let duration: Double

    public init(
        isActive: Bool,
        minScale: CGFloat,
        maxScale: CGFloat,
        minOpacity: Double,
        maxOpacity: Double,
        minBlurRadius: CGFloat,
        maxBlurRadius: CGFloat,
        duration: Double
    ) {
        self.isActive = isActive
        self.minScale = minScale
        self.maxScale = maxScale
        self.minOpacity = minOpacity
        self.maxOpacity = maxOpacity
        self.minBlurRadius = minBlurRadius
        self.maxBlurRadius = maxBlurRadius
        self.duration = duration
    }

    public func clipDiameter(for style: StatusDotSoftGlowStyle) -> CGFloat {
        style.renderClipDiameter
    }

    public static let idle = StatusDotBreathingProfile(
        isActive: false,
        minScale: 0.96,
        maxScale: 0.96,
        minOpacity: 0,
        maxOpacity: 0,
        minBlurRadius: 1.9,
        maxBlurRadius: 1.9,
        duration: 3.0
    )

    public static let running = StatusDotBreathingProfile(
        isActive: true,
        minScale: 1.0,
        maxScale: 1.0,
        minOpacity: 0,
        maxOpacity: 1.0,
        minBlurRadius: 2.5,
        maxBlurRadius: 2.5,
        duration: 1.8
    )

    public static let warning = StatusDotBreathingProfile(
        isActive: true,
        minScale: 1.0,
        maxScale: 1.0,
        minOpacity: 0,
        maxOpacity: 1.0,
        minBlurRadius: 2.6,
        maxBlurRadius: 2.6,
        duration: 2.2
    )

    public static let error = StatusDotBreathingProfile(
        isActive: true,
        minScale: 0.20,
        maxScale: 1.0,
        minOpacity: 0,
        maxOpacity: 1.0,
        minBlurRadius: 0.35,
        maxBlurRadius: 2.25,
        duration: 0.7
    )
}

public enum TaskActivityState: String, CaseIterable, Equatable, Sendable {
    case idle
    case thinking
    case running
    case compacting
    case warning
    case error

    public var breathingProfile: StatusDotBreathingProfile {
        switch self {
        case .idle:
            return .idle
        case .thinking, .running, .compacting:
            return .running
        case .warning:
            return .warning
        case .error:
            return .error
        }
    }

    public var statusDotAnimationKind: StatusDotAnimationKind {
        switch self {
        case .idle:
            return .hidden
        case .thinking, .running, .compacting, .warning:
            return .breathingGlow
        case .error:
            return .fastPulse
        }
    }

    public init?(debugValue: String) {
        let normalized = debugValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else {
            return nil
        }

        if ["context_compression", "context-compression", "compressing", "compaction"].contains(normalized) {
            self = .compacting
            return
        }

        self.init(rawValue: normalized)
    }
}
