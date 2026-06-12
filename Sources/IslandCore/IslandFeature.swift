public enum IslandFeature: String, CaseIterable, Equatable, Sendable {
    case status
    case stats
    case tools

    public static let defaultFeature: IslandFeature = .stats

    public var label: String {
        switch self {
        case .status:
            return "Status"
        case .stats:
            return "Stats"
        case .tools:
            return "Tools"
        }
    }
}
