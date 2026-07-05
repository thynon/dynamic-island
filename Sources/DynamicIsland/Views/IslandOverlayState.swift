import DynamicIslandCore
import SwiftUI

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
    @Published var musicPlayback: MusicPlaybackSnapshot = .idle
    @Published var temporaryFileShelf = TemporaryFileShelf()
    @Published var temporaryFileShelfSelectedItemIDs: Set<TemporaryShelfItem.ID> = []
    @Published var temporaryFileShelfFilter: TemporaryFileShelfFilter = .all
    @Published var isFileShelfOverlayVisible = false
    @Published var isFileShelfPinnedOpen = false
    @Published var isFileDropTargetActive = false
    @Published var selectedPrimaryFeature: IslandPrimaryFeature = .tasks
}
