import Foundation

public enum CodexReasoningEffort: String, Equatable, Sendable {
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max

    public var triggersEnergyTail: Bool {
        self == .xhigh || self == .max
    }

    public static func fromCodexConfig(_ config: String) -> CodexReasoningEffort? {
        for rawLine in config.split(whereSeparator: \.isNewline) {
            let line = rawLine
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard line.hasPrefix("model_reasoning_effort") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            return fromRawValue(String(parts[1]))
        }
        return nil
    }

    public static func fromCcSwitchProviderSettingsConfig(_ settingsConfig: String) -> CodexReasoningEffort? {
        guard let data = settingsConfig.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let config = dictionary["config"] as? String
        else {
            return fromCodexConfig(settingsConfig)
        }
        return fromCodexConfig(config)
    }

    public static func fromReasoningEffortValue(_ rawValue: String) -> CodexReasoningEffort? {
        fromRawValue(rawValue)
    }

    private static func fromRawValue(_ rawValue: String) -> CodexReasoningEffort? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")

        switch normalized {
        case "minimal":
            return .minimal
        case "low":
            return .low
        case "medium":
            return .medium
        case "high":
            return .high
        case "xhigh":
            return .xhigh
        case "max":
            return .max
        case "none", "off", "disabled":
            return nil
        default:
            return nil
        }
    }
}
