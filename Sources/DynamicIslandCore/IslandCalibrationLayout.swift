import CoreGraphics

public struct IslandCalibrationLayout: Equatable, Sendable {
    public let shellBounds: CGRect
    public let contentBoundaryFrame: CGRect
    public let cameraHousingForbiddenRegion: CGRect?
    public let leftSafeRegion: CGRect
    public let rightSafeRegion: CGRect

    public init(metrics: NotchMetrics, hasCameraHousing: Bool) {
        shellBounds = CGRect(x: 0, y: 0, width: metrics.openWidth, height: metrics.openHeight)
        contentBoundaryFrame = shellBounds.insetBy(dx: metrics.contentBoundaryInset, dy: metrics.contentBoundaryInset)

        let topBandLayout = metrics.expandedTopStatusBandLayout
        cameraHousingForbiddenRegion = hasCameraHousing ? topBandLayout.cameraHousingRegion : nil
        leftSafeRegion = topBandLayout.leftStatusRegion
        rightSafeRegion = topBandLayout.rightInfoRegion
    }
}
