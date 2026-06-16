import CoreGraphics

public struct IslandTopStatusBandLayout: Equatable, Sendable {
    public let shellWidth: CGFloat
    public let bandHeight: CGFloat
    public let guardInset: CGFloat
    public let leftStatusRegion: CGRect
    public let cameraHousingRegion: CGRect
    public let rightInfoRegion: CGRect
    public let statusDotFrame: CGRect
    public let audioWaveformFrame: CGRect

    public init(metrics: NotchMetrics) {
        shellWidth = metrics.openWidth
        bandHeight = metrics.closedHeight
        guardInset = metrics.closedStatusDotGuardInset

        let cameraMinX = (metrics.openWidth - metrics.cameraHousingWidth) / 2
        cameraHousingRegion = CGRect(
            x: cameraMinX,
            y: 0,
            width: metrics.cameraHousingWidth,
            height: metrics.closedHeight
        )

        let leftMinX = metrics.openTopCornerRadius + guardInset
        let leftMaxX = cameraHousingRegion.minX - guardInset
        leftStatusRegion = CGRect(
            x: leftMinX,
            y: guardInset,
            width: max(0, leftMaxX - leftMinX),
            height: max(0, metrics.closedHeight - (guardInset * 2))
        )

        let rightMinX = cameraHousingRegion.maxX + guardInset
        let rightMaxX = metrics.openWidth - metrics.openTopCornerRadius - guardInset
        rightInfoRegion = CGRect(
            x: rightMinX,
            y: guardInset,
            width: max(0, rightMaxX - rightMinX),
            height: max(0, metrics.closedHeight - (guardInset * 2))
        )

        statusDotFrame = CGRect(
            x: metrics.expandedStatusDotCenterX - (metrics.expandedStatusDotHaloDiameter / 2),
            y: metrics.expandedStatusDotCenterY - (metrics.expandedStatusDotHaloDiameter / 2),
            width: metrics.expandedStatusDotHaloDiameter,
            height: metrics.expandedStatusDotHaloDiameter
        )

        let defaultCostBadgeWidth: CGFloat = 86
        let waveformGapBeforeCost: CGFloat = 8
        let waveformWidth = min(
            metrics.expandedAudioWaveformSize.width,
            max(1, rightInfoRegion.width - defaultCostBadgeWidth - waveformGapBeforeCost)
        )
        audioWaveformFrame = CGRect(
            x: rightInfoRegion.maxX - defaultCostBadgeWidth - waveformGapBeforeCost - waveformWidth,
            y: metrics.expandedAudioWaveformCenterY - (metrics.expandedAudioWaveformSize.height / 2),
            width: waveformWidth,
            height: metrics.expandedAudioWaveformSize.height
        )
    }

    public func costBadgeFrame(width: CGFloat, height: CGFloat) -> CGRect {
        let resolvedWidth = min(max(1, width.rounded()), max(1, rightInfoRegion.width))
        let resolvedHeight = min(max(1, height.rounded()), max(1, rightInfoRegion.height))
        return CGRect(
            x: rightInfoRegion.maxX - resolvedWidth,
            y: rightInfoRegion.midY - (resolvedHeight / 2),
            width: resolvedWidth,
            height: resolvedHeight
        )
    }
}

public extension NotchMetrics {
    var expandedTopStatusBandLayout: IslandTopStatusBandLayout {
        IslandTopStatusBandLayout(metrics: self)
    }
}
