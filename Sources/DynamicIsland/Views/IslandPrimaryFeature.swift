import Foundation

enum IslandPrimaryFeature: String, CaseIterable, Equatable, Identifiable {
    case tasks
    case data
    case tools
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks:
            "Tasks"
        case .data:
            "Data"
        case .tools:
            "Tools"
        case .settings:
            "Settings"
        }
    }
}
