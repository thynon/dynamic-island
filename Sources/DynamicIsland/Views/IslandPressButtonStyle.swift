import SwiftUI
import DynamicIslandCore

struct IslandPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    private let animationProfile = IslandAnimationProfile.default

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                accessibilityReduceMotion
                    ? 1.0
                    : (configuration.isPressed ? animationProfile.primaryFeatureButtonPressScale : 1.0)
            )
            .opacity(accessibilityReduceMotion && configuration.isPressed ? 0.72 : 1)
            .animation(
                .easeOut(
                    duration: accessibilityReduceMotion
                        ? animationProfile.reducedMotionFadeDuration
                        : (configuration.isPressed
                            ? animationProfile.primaryFeatureButtonPressDuration
                            : animationProfile.primaryFeatureButtonReleaseDuration)
                ),
                value: configuration.isPressed
            )
    }
}
