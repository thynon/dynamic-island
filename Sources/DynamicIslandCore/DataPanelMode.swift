import Foundation

public enum DataPanelMode: String, CaseIterable, Equatable, Sendable {
    case trends
    case overview
    case all

    public static let defaultMode: DataPanelMode = .all

    public var label: String {
        switch self {
        case .trends:
            return "Trends"
        case .overview:
            return "Overview"
        case .all:
            return "All"
        }
    }

    public var refreshCadenceSeconds: Int {
        switch self {
        case .trends, .all:
            return 30
        case .overview:
            return 3600
        }
    }

    public func shouldRefreshUsage(elapsedSeconds: TimeInterval) -> Bool {
        elapsedSeconds >= TimeInterval(refreshCadenceSeconds)
    }

    public var showsTrendLayer: Bool {
        self == .trends || self == .all
    }

    public var showsOverviewLayer: Bool {
        self == .overview || self == .all
    }
}
