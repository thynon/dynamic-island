import Foundation

public struct IslandAnimationProfile: Equatable, Sendable {
    public let expandResponse: Double
    public let expandDampingFraction: Double
    public let expandBlendDuration: Double
    public let collapseDuration: Double
    public let musicAccessoryTransitionDuration: Double
    public let musicSkipFeedbackDismissDuration: Double
    public let trackInfoTransitionDuration: Double
    public let hideTransitionDuration: Double
    public let reducedMotionFadeDuration: Double
    public let primaryFeatureEntranceDuration: Double
    public let primaryFeatureEntranceStartDelay: Double
    public let primaryContentEntranceDelay: Double
    public let primaryContentTransitionDistance: Double
    public let primaryFeatureButtonSlideDistance: Double
    public let primaryFeatureSelectionResponse: Double
    public let primaryFeatureSelectionDamping: Double
    public let primaryFeatureButtonPressScale: Double
    public let primaryFeatureButtonPressDuration: Double
    public let primaryFeatureButtonReleaseDuration: Double
    public let dataRangeDrawerResponse: Double
    public let dataRangeDrawerDampingFraction: Double
    public let attachedElementCollapseDuration: Double
    public let collapseCanvasDelay: Double

    public init(
        expandResponse: Double,
        expandDampingFraction: Double,
        expandBlendDuration: Double,
        collapseDuration: Double,
        musicAccessoryTransitionDuration: Double,
        musicSkipFeedbackDismissDuration: Double,
        trackInfoTransitionDuration: Double,
        hideTransitionDuration: Double,
        reducedMotionFadeDuration: Double,
        primaryFeatureEntranceDuration: Double,
        primaryFeatureEntranceStartDelay: Double,
        primaryContentEntranceDelay: Double,
        primaryContentTransitionDistance: Double,
        primaryFeatureButtonSlideDistance: Double,
        primaryFeatureSelectionResponse: Double,
        primaryFeatureSelectionDamping: Double,
        primaryFeatureButtonPressScale: Double,
        primaryFeatureButtonPressDuration: Double,
        primaryFeatureButtonReleaseDuration: Double,
        dataRangeDrawerResponse: Double,
        dataRangeDrawerDampingFraction: Double,
        attachedElementCollapseDuration: Double,
        collapseCanvasDelay: Double
    ) {
        self.expandResponse = expandResponse
        self.expandDampingFraction = expandDampingFraction
        self.expandBlendDuration = expandBlendDuration
        self.collapseDuration = collapseDuration
        self.musicAccessoryTransitionDuration = musicAccessoryTransitionDuration
        self.musicSkipFeedbackDismissDuration = musicSkipFeedbackDismissDuration
        self.trackInfoTransitionDuration = trackInfoTransitionDuration
        self.hideTransitionDuration = hideTransitionDuration
        self.reducedMotionFadeDuration = reducedMotionFadeDuration
        self.primaryFeatureEntranceDuration = primaryFeatureEntranceDuration
        self.primaryFeatureEntranceStartDelay = primaryFeatureEntranceStartDelay
        self.primaryContentEntranceDelay = primaryContentEntranceDelay
        self.primaryContentTransitionDistance = primaryContentTransitionDistance
        self.primaryFeatureButtonSlideDistance = primaryFeatureButtonSlideDistance
        self.primaryFeatureSelectionResponse = primaryFeatureSelectionResponse
        self.primaryFeatureSelectionDamping = primaryFeatureSelectionDamping
        self.primaryFeatureButtonPressScale = primaryFeatureButtonPressScale
        self.primaryFeatureButtonPressDuration = primaryFeatureButtonPressDuration
        self.primaryFeatureButtonReleaseDuration = primaryFeatureButtonReleaseDuration
        self.dataRangeDrawerResponse = dataRangeDrawerResponse
        self.dataRangeDrawerDampingFraction = dataRangeDrawerDampingFraction
        self.attachedElementCollapseDuration = attachedElementCollapseDuration
        self.collapseCanvasDelay = collapseCanvasDelay
    }

    public static let `default` = IslandAnimationProfile(
        expandResponse: 0.38,
        expandDampingFraction: 0.82,
        expandBlendDuration: 0,
        collapseDuration: 0.14,
        musicAccessoryTransitionDuration: 0.22,
        musicSkipFeedbackDismissDuration: 0.18,
        trackInfoTransitionDuration: 0.22,
        hideTransitionDuration: 0.22,
        reducedMotionFadeDuration: 0.20,
        primaryFeatureEntranceDuration: 0.18,
        primaryFeatureEntranceStartDelay: 0.34,
        primaryContentEntranceDelay: 0.40,
        primaryContentTransitionDistance: 6,
        primaryFeatureButtonSlideDistance: 6,
        primaryFeatureSelectionResponse: 0.30,
        primaryFeatureSelectionDamping: 1.0,
        primaryFeatureButtonPressScale: 0.96,
        primaryFeatureButtonPressDuration: 0.12,
        primaryFeatureButtonReleaseDuration: 0.08,
        dataRangeDrawerResponse: 0.30,
        dataRangeDrawerDampingFraction: 0.80,
        attachedElementCollapseDuration: 0.14,
        collapseCanvasDelay: 0.14
    )
}
