import AppKit
import DynamicIslandCore

enum ScreenMetricsProvider {
    static func metrics(for screen: NSScreen?) -> NotchMetrics {
        resolvedMetrics(for: screen)
    }

    private static func resolvedMetrics(
        for screen: NSScreen?,
        store: DisplayProfileStore = DisplayProfileStore()
    ) -> NotchMetrics {
        guard let screen else {
            return .preview14Inch
        }

        let signature = DisplaySignature(
            frameWidth: Double(screen.frame.width),
            frameHeight: Double(screen.frame.height),
            safeAreaTopInset: Double(screen.safeAreaInsets.top),
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea.map { Double($0.width) },
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea.map { Double($0.width) },
            backingScaleFactor: Double(screen.backingScaleFactor)
        )

        let freshProfile = DisplayProfile(signature: signature)
        if let cachedProfile = store.cachedProfile(matching: signature),
           cachedProfile.metrics == freshProfile.metrics {
            return cachedProfile.metrics
        }

        store.save(freshProfile)
        return freshProfile.metrics
    }
}
