import CoreGraphics

public struct NotchMetrics: Equatable, Sendable {
    public static let defaultCameraHousingWidth: CGFloat = 185
    public static let defaultClosedHeight: CGFloat = 32
    public static let defaultMusicTrackInfoShellHeight: CGFloat = 72
    public static let defaultStatusSlotWidth: CGFloat = 37.5
    public static let musicStatusSlotWidth: CGFloat = 82.5
    public static let defaultOpenWidth: CGFloat = 850
    public static let defaultOpenHeight: CGFloat = 200
    public static let closedOuterCornerRadius: CGFloat = 30
    public static let defaultClosedConcaveTopRadius: CGFloat = 18
    public static let defaultOpenTopCornerRadius: CGFloat = 16
    public static let closedInnerCornerRadius: CGFloat = 7
    public static let defaultOpenBottomCornerRadius: CGFloat = 24
    public static let defaultContentBoundaryInset: CGFloat = 5
    public static let defaultClosedCanvasBottomSlack: CGFloat = 16
    public static let compactNotchedReferenceWidth: CGFloat = 1512
    public static let compactNotchedReferenceHeight: CGFloat = 982

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

    public var contentBoundaryInset: CGFloat {
        Self.defaultContentBoundaryInset
    }

    public var closedConcaveTopRadius: CGFloat {
        Self.defaultClosedConcaveTopRadius
    }

    public var closedMusicAccessoryGuardInset: CGFloat {
        contentBoundaryInset
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

    public var expandedMusicArtworkCenterX: CGFloat {
        48
    }

    public var expandedMusicWaveformCenterX: CGFloat {
        90
    }

    public var expandedMusicAccessoryCenterY: CGFloat {
        closedMusicAccessoryCenterY
    }

    public var expandedContentGuardInset: CGFloat {
        contentBoundaryInset
    }

    public var expandedHorizontalContentPadding: CGFloat {
        openTopCornerRadius + expandedContentGuardInset
    }

    public var expandedContentBottomEdgeInset: CGFloat {
        contentBoundaryInset
    }

    public var expandedContentBottomCornerClearance: CGFloat {
        contentBoundaryInset
    }

    public var expandedContentBottomGuard: CGFloat {
        contentBoundaryInset
    }

    public var closedCanvasWindowSize: CGSize {
        CGSize(width: closedShellWidth, height: closedHeight + Self.defaultClosedCanvasBottomSlack)
    }

    public var openCanvasWindowSize: CGSize {
        CGSize(width: openWidth, height: openHeight + Self.defaultClosedCanvasBottomSlack)
    }

    /// 闭合状态下悬停区域水平扩展量（左右各扩展，用于命中检测和画布宽度计算）
    public static let closedHoverHorizontalSlack: CGFloat = 22
    /// 闭合状态下悬停区域底部扩展量（用于画布高度计算）
    public static let closedHoverBottomSlack: CGFloat = 10
    /// 音乐跳过手势触发时 shell 向两侧扩展的最大像素值
    public static let musicSkipEdgeExpansionMax: CGFloat = 50
    /// 闭合画布水平扩展量（保证两侧跳过反馈有足够空间）
    public static let closedCanvasHorizontalSlack: CGFloat = max(closedHoverHorizontalSlack, musicSkipEdgeExpansionMax * 2)

    public static let preview14Inch = NotchMetrics(
        cameraHousingWidth: defaultCameraHousingWidth,
        closedHeight: defaultClosedHeight
    )

    public init(
        cameraHousingWidth: CGFloat,
        closedHeight: CGFloat,
        statusSlotWidth: CGFloat = Self.defaultStatusSlotWidth,
        openWidth: CGFloat = Self.defaultOpenWidth,
        openHeight: CGFloat = Self.defaultOpenHeight,
        closedTopCornerRadius: CGFloat = Self.closedOuterCornerRadius,
        openTopCornerRadius: CGFloat = Self.defaultOpenTopCornerRadius,
        closedBottomCornerRadius: CGFloat = Self.closedInnerCornerRadius,
        openBottomCornerRadius: CGFloat = Self.defaultOpenBottomCornerRadius
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
            return CGSize(width: defaultOpenWidth, height: defaultOpenHeight)
        }

        let width = min(680, max(560, frameWidth * 0.38)).rounded()
        let height = min(230, max(210, frameHeight * 0.20)).rounded()
        return CGSize(width: width, height: height)
    }
}
