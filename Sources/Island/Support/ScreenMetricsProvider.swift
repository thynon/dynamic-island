import AppKit
import IslandCore

enum ScreenMetricsProvider {
    static func metrics(for screen: NSScreen?) -> NotchMetrics {
        guard let screen else {
            return .preview14Inch
        }

        return NotchMetrics.fromDisplay(
            frameWidth: screen.frame.width,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width,
            safeAreaTopInset: screen.safeAreaInsets.top
        )
    }
}
