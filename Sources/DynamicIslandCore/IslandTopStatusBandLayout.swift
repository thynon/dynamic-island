import CoreGraphics

public struct IslandTopStatusBandLayout: Equatable, Sendable {
    public let shellWidth: CGFloat
    public let bandHeight: CGFloat
    public let guardInset: CGFloat
    public let leftStatusRegion: CGRect
    public let cameraHousingRegion: CGRect
    public let rightInfoRegion: CGRect

    public init(metrics: NotchMetrics) {
        shellWidth = metrics.openWidth
        bandHeight = metrics.closedHeight
        guardInset = metrics.contentBoundaryInset

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

    }

    public func fileShelfButtonFrame(width: CGFloat, height: CGFloat) -> CGRect {
        let resolvedWidth = min(max(1, width.rounded()), max(1, leftStatusRegion.width))
        let resolvedHeight = min(max(1, height.rounded()), max(1, leftStatusRegion.height))
        return CGRect(
            x: leftStatusRegion.maxX - resolvedWidth,
            y: leftStatusRegion.midY - (resolvedHeight / 2),
            width: resolvedWidth,
            height: resolvedHeight
        )
    }

    public func primaryNavigationFrame(width: CGFloat, height: CGFloat) -> CGRect {
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
