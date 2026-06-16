import CoreGraphics
import Foundation

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
        minScale: 0.82,
        maxScale: 1.18,
        minOpacity: 0.25,
        maxOpacity: 1.0,
        minBlurRadius: 1.2,
        maxBlurRadius: 4.0,
        duration: 2.0
    )

    public static let warning = StatusDotBreathingProfile(
        isActive: true,
        minScale: 0.85,
        maxScale: 1.15,
        minOpacity: 0.15,
        maxOpacity: 1.0,
        minBlurRadius: 1.0,
        maxBlurRadius: 3.5,
        duration: 2.4
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

public enum CodexTaskActivityHeuristic {
    private static let terminalEventTypes: Set<String> = [
        "task_complete",
        "turn_aborted"
    ]
    private static let activeEventTypes: Set<String> = [
        "task_started"
    ]
    private static let transientActivityEventTypes: Set<String> = [
        "token_count",
        "agent_message",
        "tool_call",
        "function_call",
        "context_compacted"
    ]
    private static let transientActivityWindowSeconds: TimeInterval = 20
    private static let lifecycleActivityWindowSeconds: TimeInterval = 300

    public static func state(
        recentEventTypes: [String],
        secondsSinceLatestWrite: TimeInterval?
    ) -> TaskActivityState {
        let normalizedEventTypes = recentEventTypes.map { $0.lowercased() }

        for eventType in normalizedEventTypes.reversed() {
            if terminalEventTypes.contains(eventType) {
                return .idle
            }
            if activeEventTypes.contains(eventType) {
                guard
                    let secondsSinceLatestWrite,
                    secondsSinceLatestWrite <= lifecycleActivityWindowSeconds
                else {
                    return .idle
                }
                return .running
            }
        }

        guard
            let secondsSinceLatestWrite,
            secondsSinceLatestWrite <= transientActivityWindowSeconds,
            normalizedEventTypes.contains(where: transientActivityEventTypes.contains)
        else {
            return .idle
        }

        return .running
    }
}

public enum CodexTaskActivityEvent {
    public static func eventType(in line: String) -> String? {
        guard
            let data = line.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let topLevelType = json["type"] as? String
        else {
            return nil
        }

        switch topLevelType {
        case "event_msg", "response_item":
            guard let payload = json["payload"] as? [String: Any] else {
                return nil
            }
            return payload["type"] as? String
        default:
            return topLevelType
        }
    }
}

public enum TaskActivityOverridePolicy {
    public static func effectiveState(
        _ state: TaskActivityState?,
        modificationDate: Date?,
        now: Date = Date(),
        freshnessSeconds: TimeInterval = 300
    ) -> TaskActivityState? {
        guard let state else {
            return nil
        }

        guard let modificationDate else {
            return state
        }

        let age = now.timeIntervalSince(modificationDate)
        guard age <= freshnessSeconds else {
            return nil
        }

        return state
    }
}
