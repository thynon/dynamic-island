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
    public static let statusSlotWidth: CGFloat = 30
    public static let openWidth: CGFloat = 700
    public static let openHeight: CGFloat = 230
    public static let overshootWidth: CGFloat = 732
    public static let overshootHeight: CGFloat = 254
    public static let topCornerRadius: CGFloat = 16
    public static let closedBottomCornerRadius: CGFloat = 17
    public static let openBottomCornerRadius: CGFloat = 24
    public static let defaultClosedStatusDotGuardInset: CGFloat = 2
    public static let defaultClosedStatusDotHaloDiameter: CGFloat = 10
    public static let defaultExpandedStatusDotLeadingInset: CGFloat = 25
    public static let defaultStatusDotDirectionalOvershootOffset: CGFloat = 0
    public static let defaultExpandedContentTopSpacerHeight: CGFloat = 34
    public static let defaultExpandedContentSectionSpacing: CGFloat = 6
    public static let defaultExpandedHeaderHeight: CGFloat = 30
    public static let defaultExpandedDemoSlotHeight: CGFloat = 122
    public static let defaultExpandedStatusChipHeight: CGFloat = 24
    public static let defaultExpandedStatusChipCornerRadius: CGFloat = 8
    public static let defaultExpandedContentGuardInset: CGFloat = 6
    public static let defaultExpandedContentBottomEdgeInset: CGFloat = 2
    public static let defaultExpandedContentBottomCornerClearance: CGFloat = defaultExpandedContentBottomEdgeInset
    public static let defaultExpandedContentBottomGuard: CGFloat = defaultExpandedContentBottomEdgeInset

    public let cameraHousingWidth: CGFloat
    public let closedHeight: CGFloat
    public let statusSlotWidth: CGFloat
    public let openWidth: CGFloat
    public let openHeight: CGFloat
    public let overshootWidth: CGFloat
    public let overshootHeight: CGFloat
    public let closedTopCornerRadius: CGFloat
    public let openTopCornerRadius: CGFloat
    public let closedBottomCornerRadius: CGFloat
    public let openBottomCornerRadius: CGFloat

    public var closedShellWidth: CGFloat {
        cameraHousingWidth + (statusSlotWidth * 2)
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

    public var closedStatusDotGuardInset: CGFloat {
        Self.defaultClosedStatusDotGuardInset
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

    public var expandedStatusDotCenterX: CGFloat {
        Self.defaultExpandedStatusDotLeadingInset
    }

    public var expandedStatusDotCenterY: CGFloat {
        closedStatusDotCenterY
    }

    public var expandedContentTopSpacerHeight: CGFloat {
        Self.defaultExpandedContentTopSpacerHeight
    }

    public var expandedContentSectionSpacing: CGFloat {
        Self.defaultExpandedContentSectionSpacing
    }

    public var expandedHeaderHeight: CGFloat {
        Self.defaultExpandedHeaderHeight
    }

    public var expandedDemoSlotHeight: CGFloat {
        Self.defaultExpandedDemoSlotHeight
    }

    public var expandedStatusChipHeight: CGFloat {
        Self.defaultExpandedStatusChipHeight
    }

    public var expandedStatusChipCornerRadius: CGFloat {
        Self.defaultExpandedStatusChipCornerRadius
    }

    public var expandedContentGuardInset: CGFloat {
        Self.defaultExpandedContentGuardInset
    }

    public var expandedHorizontalContentPadding: CGFloat {
        openTopCornerRadius + expandedContentGuardInset
    }

    public var expandedContentBottomEdgeInset: CGFloat {
        Self.defaultExpandedContentBottomEdgeInset
    }

    public var expandedContentBottomCornerClearance: CGFloat {
        Self.defaultExpandedContentBottomCornerClearance
    }

    public var expandedContentBottomGuard: CGFloat {
        Self.defaultExpandedContentBottomGuard
    }

    public var closedWindowSize: CGSize {
        CGSize(width: closedShellWidth, height: closedHeight)
    }

    public var openWindowSize: CGSize {
        CGSize(width: openWidth, height: openHeight)
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
        overshootWidth: CGFloat = Self.overshootWidth,
        overshootHeight: CGFloat = Self.overshootHeight,
        closedTopCornerRadius: CGFloat = Self.topCornerRadius,
        openTopCornerRadius: CGFloat = Self.topCornerRadius,
        closedBottomCornerRadius: CGFloat = Self.closedBottomCornerRadius,
        openBottomCornerRadius: CGFloat = Self.openBottomCornerRadius
    ) {
        let resolvedCameraHousingWidth = max(1, cameraHousingWidth.rounded())
        let resolvedClosedHeight = max(1, closedHeight.rounded())
        let resolvedStatusSlotWidth = max(1, statusSlotWidth.rounded())
        let resolvedClosedShellWidth = resolvedCameraHousingWidth + (resolvedStatusSlotWidth * 2)
        let resolvedOpenWidth = max(resolvedClosedShellWidth, openWidth.rounded())
        let resolvedOpenHeight = max(resolvedClosedHeight, openHeight.rounded())

        self.cameraHousingWidth = resolvedCameraHousingWidth
        self.closedHeight = resolvedClosedHeight
        self.statusSlotWidth = resolvedStatusSlotWidth
        self.openWidth = resolvedOpenWidth
        self.openHeight = resolvedOpenHeight
        self.overshootWidth = max(resolvedOpenWidth, overshootWidth.rounded())
        self.overshootHeight = max(resolvedOpenHeight, overshootHeight.rounded())
        self.closedTopCornerRadius = max(0, closedTopCornerRadius.rounded())
        self.openTopCornerRadius = max(0, openTopCornerRadius.rounded())
        self.closedBottomCornerRadius = max(0, closedBottomCornerRadius.rounded())
        self.openBottomCornerRadius = max(0, openBottomCornerRadius.rounded())
    }

    public static func fromDisplay(
        frameWidth: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?,
        safeAreaTopInset: CGFloat
    ) -> NotchMetrics {
        let housingWidth: CGFloat
        if let left = auxiliaryTopLeftWidth, let right = auxiliaryTopRightWidth {
            housingWidth = max(defaultCameraHousingWidth, frameWidth - left - right)
        } else {
            housingWidth = defaultCameraHousingWidth
        }

        let height = safeAreaTopInset > 0 ? safeAreaTopInset : defaultClosedHeight

        return NotchMetrics(
            cameraHousingWidth: housingWidth,
            closedHeight: height
        )
    }
}
