import Foundation

enum IslandPrimaryFeature: String, CaseIterable, Equatable, Identifiable {
    case files
    case tasks
    case data
    case tools
    case settings

    var id: String { rawValue }

    static var rightNavigationCases: [IslandPrimaryFeature] {
        [.tasks, .data, .tools, .settings]
    }

    var title: String {
        switch self {
        case .files:
            "Files"
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
