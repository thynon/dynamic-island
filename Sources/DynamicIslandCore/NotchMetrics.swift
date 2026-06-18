import CoreGraphics

public struct StatusDotSoftGlowStyle: Equatable, Sendable {
    public let haloDiameter: CGFloat
    public let outerSourceDiameter: CGFloat
    public let mediumHaloDiameter: CGFloat
    public let ringDiameter: CGFloat
    public let coreDiameter: CGFloat
    public let outerBlurRadius: CGFloat
    public let mediumBlurRadius: CGFloat
    public let ringBlurRadius: CGFloat
    public let ringLineWidth: CGFloat
    public let coreShadowRadius: CGFloat
    public let coreShadowOpacity: CGFloat
    public let highlightDiameter: CGFloat
    public let highlightOpacity: CGFloat
    public let solidCoreOpacity: CGFloat

    public var renderClipDiameter: CGFloat {
        haloDiameter
    }

    public init(
        haloDiameter: CGFloat,
        outerSourceDiameter: CGFloat,
        mediumHaloDiameter: CGFloat,
        ringDiameter: CGFloat,
        coreDiameter: CGFloat,
        outerBlurRadius: CGFloat,
        mediumBlurRadius: CGFloat,
        ringBlurRadius: CGFloat,
        ringLineWidth: CGFloat,
        coreShadowRadius: CGFloat,
        coreShadowOpacity: CGFloat,
        highlightDiameter: CGFloat,
        highlightOpacity: CGFloat,
        solidCoreOpacity: CGFloat
    ) {
        self.haloDiameter = haloDiameter
        self.outerSourceDiameter = outerSourceDiameter
        self.mediumHaloDiameter = mediumHaloDiameter
        self.ringDiameter = ringDiameter
        self.coreDiameter = coreDiameter
        self.outerBlurRadius = outerBlurRadius
        self.mediumBlurRadius = mediumBlurRadius
        self.ringBlurRadius = ringBlurRadius
        self.ringLineWidth = ringLineWidth
        self.coreShadowRadius = coreShadowRadius
        self.coreShadowOpacity = coreShadowOpacity
        self.highlightDiameter = highlightDiameter
        self.highlightOpacity = highlightOpacity
        self.solidCoreOpacity = solidCoreOpacity
    }

    public static func previousSoftGlow(haloDiameter: CGFloat) -> StatusDotSoftGlowStyle {
        let halo = max(1, haloDiameter.rounded())
        let core = min(2.2, max(1.6, halo * 0.20))
        let ring = max(core + 5.8, halo * 0.84)
        return StatusDotSoftGlowStyle(
            haloDiameter: halo,
            outerSourceDiameter: max(core + 6.8, halo * 0.92),
            mediumHaloDiameter: max(core + 4.8, halo * 0.72),
            ringDiameter: ring,
            coreDiameter: core,
            outerBlurRadius: max(1.8, halo * 0.20),
            mediumBlurRadius: max(0.8, halo * 0.10),
            ringBlurRadius: 0.8,
            ringLineWidth: 1.0,
            coreShadowRadius: 0,
            coreShadowOpacity: 0,
            highlightDiameter: 0,
            highlightOpacity: 0,
            solidCoreOpacity: 0
        )
    }
}

public struct NotchMetrics: Equatable, Sendable {
    public static let defaultCameraHousingWidth: CGFloat = 185
    public static let defaultClosedHeight: CGFloat = 32
    public static let defaultMusicTrackInfoShellHeight: CGFloat = 72
    public static let statusSlotWidth: CGFloat = 37.5
    public static let musicStatusSlotWidth: CGFloat = 82.5
    public static let openWidth: CGFloat = 650
    public static let openHeight: CGFloat = 230
    public static let closedOuterCornerRadius: CGFloat = 30
    public static let defaultClosedConcaveTopRadius: CGFloat = 18
    public static let defaultOpenTopCornerRadius: CGFloat = 16
    public static let closedInnerCornerRadius: CGFloat = 7
    public static let openBottomCornerRadius: CGFloat = 24
    public static let defaultContentBoundaryInset: CGFloat = 5
    public static let defaultClosedStatusDotHaloDiameter: CGFloat = 10
    public static let defaultClosedCompletionBounceDrop: CGFloat = 14
    public static let defaultClosedCompletionBounceSlack: CGFloat = defaultClosedCompletionBounceDrop + 2
    public static let defaultExpandedStatusDotLeadingInset: CGFloat = 25
    public static let defaultExpandedAudioWaveformWidth: CGFloat = 128
    public static let defaultExpandedAudioWaveformHeight: CGFloat = 22
    public static let defaultExpandedAudioWaveformLeadingInset: CGFloat = 80
    public static let defaultStatusDotDirectionalOvershootOffset: CGFloat = 0
    public static let compactNotchedReferenceWidth: CGFloat = 1512
    public static let compactNotchedReferenceHeight: CGFloat = 982
    private static let openWidthReductionPerSide: CGFloat = 25

    public let cameraHousingWidth: CGFloat
    public let closedHeight: CGFloat
    public let statusSlotWidth: CGFloat
    public let openWidth: CGFloat
    public let openHeight: CGFloat
    public let closedTopCornerRadius: CGFloat
    public let openTopCornerRadius: CGFloat
    public let closedBottomCornerRadius: CGFloat
    public let openBottomCornerRadius: CGFloat

    public var closedShellWidth: CGFloat {
        cameraHousingWidth + (statusSlotWidth * 2)
    }

    public var musicClosedShellWidth: CGFloat {
        cameraHousingWidth + (Self.musicStatusSlotWidth * 2)
    }

    public var musicTrackInfoShellHeight: CGFloat {
        Self.defaultMusicTrackInfoShellHeight
    }

    public var statusDotCenterXFromShellCenter: CGFloat {
        -(cameraHousingWidth / 2) - (statusSlotWidth / 2)
    }

    public var cameraHousingLeftEdgeX: CGFloat {
        statusSlotWidth
    }

    public var cameraHousingRightEdgeX: CGFloat {
        statusSlotWidth + cameraHousingWidth
    }

    public var musicCameraHousingLeftEdgeX: CGFloat {
        Self.musicStatusSlotWidth
    }

    public var musicCameraHousingRightEdgeX: CGFloat {
        Self.musicStatusSlotWidth + cameraHousingWidth
    }

    public var closedStatusDotGuardInset: CGFloat {
        Self.defaultContentBoundaryInset
    }

    public var closedConcaveTopRadius: CGFloat {
        Self.defaultClosedConcaveTopRadius
    }

    public var closedStatusDotHaloDiameter: CGFloat {
        Self.defaultClosedStatusDotHaloDiameter
    }

    public var statusDotDirectionalOvershootOffset: CGFloat {
        Self.defaultStatusDotDirectionalOvershootOffset
    }

    public var expandedStatusDotHaloDiameter: CGFloat {
        closedStatusDotHaloDiameter
    }

    public var statusDotSoftGlowStyle: StatusDotSoftGlowStyle {
        .previousSoftGlow(haloDiameter: closedStatusDotHaloDiameter)
    }

    public var closedStatusDotCenterX: CGFloat {
        cameraHousingLeftEdgeX - closedStatusDotGuardInset - (closedStatusDotHaloDiameter / 2)
    }

    public var closedStatusDotCenterY: CGFloat {
        closedHeight / 2
    }

    public var closedMusicAccessoryGuardInset: CGFloat {
        Self.defaultContentBoundaryInset
    }

    public var closedMusicAccessorySize: CGFloat {
        min(18, max(0, closedMusicAccessorySafeMaxX - closedMusicAccessorySafeMinX))
    }

    public var closedLeftMusicAccessoryCenterX: CGFloat {
        (closedMusicAccessorySafeMinX + closedMusicAccessorySafeMaxX) / 2
    }

    public var closedRightMusicAccessoryCenterX: CGFloat {
        musicClosedShellWidth - closedLeftMusicAccessoryCenterX
    }

    public var closedMusicAccessoryCenterY: CGFloat {
        closedHeight / 2
    }

    private var closedMusicAccessoryVisibleEdgeInset: CGFloat {
        min(
            max(closedTopCornerRadius, closedBottomCornerRadius),
            Self.musicStatusSlotWidth - (closedMusicAccessoryGuardInset * 2)
        )
    }

    private var closedMusicAccessorySafeMinX: CGFloat {
        closedMusicAccessoryVisibleEdgeInset + closedMusicAccessoryGuardInset
    }

    private var closedMusicAccessorySafeMaxX: CGFloat {
        musicCameraHousingLeftEdgeX - closedMusicAccessoryGuardInset
    }

    public var expandedStatusDotCenterX: CGFloat {
        Self.defaultExpandedStatusDotLeadingInset
    }

    public var expandedStatusDotCenterY: CGFloat {
        closedStatusDotCenterY
    }

    public var expandedMusicArtworkCenterX: CGFloat {
        48
    }

    public var expandedMusicWaveformCenterX: CGFloat {
        90
    }

    public var expandedMusicAccessoryCenterY: CGFloat {
        closedMusicAccessoryCenterY
    }

    public var expandedAudioWaveformSize: CGSize {
        CGSize(
            width: Self.defaultExpandedAudioWaveformWidth,
            height: Self.defaultExpandedAudioWaveformHeight
        )
    }

    public var closedAudioWaveformCenterX: CGFloat {
        expandedAudioWaveformCenterX
    }

    public var closedAudioWaveformCenterY: CGFloat {
        closedStatusDotCenterY
    }

    public var expandedAudioWaveformCenterX: CGFloat {
        Self.defaultExpandedAudioWaveformLeadingInset + (expandedAudioWaveformSize.width / 2)
    }

    public var expandedAudioWaveformCenterY: CGFloat {
        closedAudioWaveformCenterY
    }

    public var expandedContentGuardInset: CGFloat {
        Self.defaultContentBoundaryInset
    }

    public var expandedHorizontalContentPadding: CGFloat {
        openTopCornerRadius + expandedContentGuardInset
    }

    public var expandedContentBottomEdgeInset: CGFloat {
        Self.defaultContentBoundaryInset
    }

    public var expandedContentBottomCornerClearance: CGFloat {
        Self.defaultContentBoundaryInset
    }

    public var expandedContentBottomGuard: CGFloat {
        Self.defaultContentBoundaryInset
    }

    public var closedCompletionBounceDrop: CGFloat {
        Self.defaultClosedCompletionBounceDrop
    }

    public var closedCompletionFeedbackWindowSize: CGSize {
        CGSize(width: closedShellWidth, height: closedHeight + Self.defaultClosedCompletionBounceSlack)
    }

    public var openCompletionFeedbackWindowSize: CGSize {
        CGSize(width: openWidth, height: openHeight + Self.defaultClosedCompletionBounceSlack)
    }

    public static let preview14Inch = NotchMetrics(
        cameraHousingWidth: defaultCameraHousingWidth,
        closedHeight: defaultClosedHeight
    )

    public init(
        cameraHousingWidth: CGFloat,
        closedHeight: CGFloat,
        statusSlotWidth: CGFloat = Self.statusSlotWidth,
        openWidth: CGFloat = Self.openWidth,
        openHeight: CGFloat = Self.openHeight,
        closedTopCornerRadius: CGFloat = Self.closedOuterCornerRadius,
        openTopCornerRadius: CGFloat = Self.defaultOpenTopCornerRadius,
        closedBottomCornerRadius: CGFloat = Self.closedInnerCornerRadius,
        openBottomCornerRadius: CGFloat = Self.openBottomCornerRadius
    ) {
        let resolvedCameraHousingWidth = max(1, cameraHousingWidth.rounded())
        let resolvedClosedHeight = max(1, closedHeight.rounded())
        let resolvedStatusSlotWidth = max(0, statusSlotWidth)
        let resolvedClosedShellWidth = resolvedCameraHousingWidth + (resolvedStatusSlotWidth * 2)
        let resolvedOpenWidth = max(resolvedClosedShellWidth, openWidth.rounded())
        let resolvedOpenHeight = max(resolvedClosedHeight, openHeight.rounded())

        self.cameraHousingWidth = resolvedCameraHousingWidth
        self.closedHeight = resolvedClosedHeight
        self.statusSlotWidth = resolvedStatusSlotWidth
        self.openWidth = resolvedOpenWidth
        self.openHeight = resolvedOpenHeight
        self.closedTopCornerRadius = max(0, closedTopCornerRadius)
        self.openTopCornerRadius = max(0, openTopCornerRadius)
        self.closedBottomCornerRadius = max(0, closedBottomCornerRadius)
        self.openBottomCornerRadius = max(0, openBottomCornerRadius)
    }

    public static func fromDisplay(
        frameWidth: CGFloat,
        frameHeight: CGFloat = compactNotchedReferenceHeight,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?,
        safeAreaTopInset: CGFloat
    ) -> NotchMetrics {
        let hasCameraHousing = safeAreaTopInset > 0
            && auxiliaryTopLeftWidth != nil
            && auxiliaryTopRightWidth != nil
        let housingWidth: CGFloat
        if hasCameraHousing, let left = auxiliaryTopLeftWidth, let right = auxiliaryTopRightWidth {
            housingWidth = max(defaultCameraHousingWidth, frameWidth - left - right)
        } else {
            housingWidth = defaultCameraHousingWidth
        }

        let height = safeAreaTopInset > 0 ? safeAreaTopInset : defaultClosedHeight
        let openSize = recommendedOpenSize(
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            hasCameraHousing: hasCameraHousing
        )

        return NotchMetrics(
            cameraHousingWidth: housingWidth,
            closedHeight: height,
            openWidth: openSize.width,
            openHeight: openSize.height
        )
    }

    private static func recommendedOpenSize(
        frameWidth: CGFloat,
        frameHeight: CGFloat,
        hasCameraHousing: Bool
    ) -> CGSize {
        if hasCameraHousing {
            let totalWidthReduction = openWidthReductionPerSide * 2
            let maxWidth = max(openWidth, min(frameWidth - 80, 820) - totalWidthReduction)
            let preferredWidth = max(openWidth, (frameWidth * 0.45) - totalWidthReduction)
            let width = min(maxWidth, preferredWidth).rounded()
            let height = min(252, max(openHeight, frameHeight * 0.21)).rounded()
            return CGSize(width: width, height: height)
        }

        let width = min(680, max(560, frameWidth * 0.38)).rounded()
        let height = min(230, max(210, frameHeight * 0.20)).rounded()
        return CGSize(width: width, height: height)
    }
}
