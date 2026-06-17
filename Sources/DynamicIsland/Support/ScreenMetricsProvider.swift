import AppKit
import DynamicIslandCore

enum ScreenMetricsProvider {
    struct Result {
        let metrics: NotchMetrics
        let shouldShowCalibrationCaption: Bool
    }

    static func metrics(for screen: NSScreen?) -> NotchMetrics {
        profile(for: screen).metrics
    }

    static func profile(
        for screen: NSScreen?,
        store: DisplayProfileStore = DisplayProfileStore()
    ) -> Result {
        guard let screen else {
            return Result(metrics: .preview14Inch, shouldShowCalibrationCaption: false)
        }

        let signature = DisplaySignature(
            frameWidth: Double(screen.frame.width),
            frameHeight: Double(screen.frame.height),
            safeAreaTopInset: Double(screen.safeAreaInsets.top),
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea.map { Double($0.width) },
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea.map { Double($0.width) },
            backingScaleFactor: Double(screen.backingScaleFactor)
        )

        if let cachedProfile = store.cachedProfile(matching: signature) {
            return Result(metrics: cachedProfile.metrics, shouldShowCalibrationCaption: false)
        }

        let profile = DisplayProfile(signature: signature)
        store.save(profile)
        return Result(metrics: profile.metrics, shouldShowCalibrationCaption: true)
    }
}
