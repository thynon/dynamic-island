import DynamicIslandCore
import SwiftUI

enum FilesDisplayMode: String, CaseIterable, Equatable, Identifiable {
    case auto
    case pinned
    case untilEmpty

    var id: String { rawValue }

    var systemImageName: String {
        switch self {
        case .auto:
            "arrow.down.right.circle"
        case .pinned:
            "pin.fill"
        case .untilEmpty:
            "tray.full.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .auto:
            "Auto close Files"
        case .pinned:
            "Keep Files open"
        case .untilEmpty:
            "Keep Files open until empty"
        }
    }
}

@MainActor
final class IslandOverlayState: ObservableObject {
    @Published var isExpanded = false
    @Published var usesOpenCanvas = false
    @Published var isShellHidden = false
    @Published var isHovered = false
    @Published var isTrackInfoPresented = false
    @Published var musicSkipFeedbackDirection: MusicSkipDirection?
    @Published var musicSkipGestureProgress: CGFloat = 0
    @Published var isMusicSkipArmed = false
    @Published var isCalibrationOverlayVisible = false
    @Published var calibrationHasCameraHousing = false
    @Published var isTopBandEnergyEffectEnabled = false
    @Published var codexStatusBarSnapshot: CodexStatusBarSnapshot = .unavailable
    @Published var musicPlayback: MusicPlaybackSnapshot = .idle
    @Published var temporaryFileShelf = TemporaryFileShelf()
    @Published var temporaryFileShelfSelectedItemIDs: Set<TemporaryShelfItem.ID> = []
    @Published var airDropUndoItemCount = 0
    @Published var temporaryFileShelfFilter: TemporaryFileShelfFilter = .all
    @Published var isFileShelfOverlayVisible = false
    @Published var isFileShelfPinnedOpen = false
    @Published var isFileDropTargetActive = false
    @Published var filesDisplayMode: FilesDisplayMode = .pinned
    @Published var selectedPrimaryFeature: IslandPrimaryFeature = .tasks
}
