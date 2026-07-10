import Foundation

public struct IslandAnimationProfile: Equatable, Sendable {
    public let expandResponse: Double
    public let expandDampingFraction: Double
    public let expandBlendDuration: Double
    public let collapseDuration: Double
    public let primaryFeatureEntranceResponse: Double
    public let primaryFeatureEntranceDampingFraction: Double
    public let primaryFeatureEntranceBlendDuration: Double
    public let primaryFeatureEntranceStartDelay: Double
    public let primaryFeatureStaggerDelay: Double
    public let primaryFeatureButtonSlideDistance: Double
    public let primaryFeatureSelectionResponse: Double
    public let primaryFeatureSelectionDamping: Double
    public let primaryFeatureButtonPressScale: Double
    public let primaryFeatureButtonPressDuration: Double
    public let attachedElementCollapseDuration: Double
    public let collapseCanvasDelay: Double

    public init(
        expandResponse: Double,
        expandDampingFraction: Double,
        expandBlendDuration: Double,
        collapseDuration: Double,
        primaryFeatureEntranceResponse: Double,
        primaryFeatureEntranceDampingFraction: Double,
        primaryFeatureEntranceBlendDuration: Double,
        primaryFeatureEntranceStartDelay: Double,
        primaryFeatureStaggerDelay: Double,
        primaryFeatureButtonSlideDistance: Double,
        primaryFeatureSelectionResponse: Double,
        primaryFeatureSelectionDamping: Double,
        primaryFeatureButtonPressScale: Double,
        primaryFeatureButtonPressDuration: Double,
        attachedElementCollapseDuration: Double,
        collapseCanvasDelay: Double
    ) {
        self.expandResponse = expandResponse
        self.expandDampingFraction = expandDampingFraction
        self.expandBlendDuration = expandBlendDuration
        self.collapseDuration = collapseDuration
        self.primaryFeatureEntranceResponse = primaryFeatureEntranceResponse
        self.primaryFeatureEntranceDampingFraction = primaryFeatureEntranceDampingFraction
        self.primaryFeatureEntranceBlendDuration = primaryFeatureEntranceBlendDuration
        self.primaryFeatureEntranceStartDelay = primaryFeatureEntranceStartDelay
        self.primaryFeatureStaggerDelay = primaryFeatureStaggerDelay
        self.primaryFeatureButtonSlideDistance = primaryFeatureButtonSlideDistance
        self.primaryFeatureSelectionResponse = primaryFeatureSelectionResponse
        self.primaryFeatureSelectionDamping = primaryFeatureSelectionDamping
        self.primaryFeatureButtonPressScale = primaryFeatureButtonPressScale
        self.primaryFeatureButtonPressDuration = primaryFeatureButtonPressDuration
        self.attachedElementCollapseDuration = attachedElementCollapseDuration
        self.collapseCanvasDelay = collapseCanvasDelay
    }

    public static let `default` = IslandAnimationProfile(
        expandResponse: 0.38,
        expandDampingFraction: 0.82,
        expandBlendDuration: 0,
        collapseDuration: 0.14,
        primaryFeatureEntranceResponse: 0.35,
        primaryFeatureEntranceDampingFraction: 0.88,
        primaryFeatureEntranceBlendDuration: 0,
        primaryFeatureEntranceStartDelay: 0.34,
        primaryFeatureStaggerDelay: 0.03,
        primaryFeatureButtonSlideDistance: 6,
        primaryFeatureSelectionResponse: 0.28,
        primaryFeatureSelectionDamping: 0.75,
        primaryFeatureButtonPressScale: 0.96,
        primaryFeatureButtonPressDuration: 0.12,
        attachedElementCollapseDuration: 0.14,
        collapseCanvasDelay: 0.14
    )
}
