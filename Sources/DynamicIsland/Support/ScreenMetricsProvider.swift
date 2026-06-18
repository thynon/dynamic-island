import AppKit
import DynamicIslandCore

enum ScreenMetricsProvider {
    static func metrics(for screen: NSScreen?) -> NotchMetrics {
        profile(for: screen)
    }

    static func profile(
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

        if let cachedProfile = store.cachedProfile(matching: signature) {
            return cachedProfile.metrics
        }

        let profile = DisplayProfile(signature: signature)
        store.save(profile)
        return profile.metrics
    }
}
