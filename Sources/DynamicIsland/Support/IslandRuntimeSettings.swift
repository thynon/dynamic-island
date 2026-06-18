import Combine
import Foundation

@MainActor
final class IslandRuntimeSettings: ObservableObject {
    @Published var isFileShelfEnabled = true
    @Published var isMusicModeEnabled = true
    @Published var isCalibrationModeEnabled = false
    @Published var gestureSensitivity: Double = 1
    @Published var hideAnimationStrength: Double = 1

    var gestureThresholdMultiplier: Double {
        1 / max(0.6, min(1.6, gestureSensitivity))
    }

    var hideAnimationScale: Double {
        max(0.7, min(1.4, hideAnimationStrength))
    }

    func reset() {
        isFileShelfEnabled = true
        isMusicModeEnabled = true
        isCalibrationModeEnabled = false
        gestureSensitivity = 1
        hideAnimationStrength = 1
    }
}
