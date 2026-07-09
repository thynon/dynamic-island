import CoreGraphics

public struct IslandPrimaryContentLayout: Equatable, Sendable {
    public let shellWidth: CGFloat
    public let shellHeight: CGFloat
    public let tasksContentFrame: CGRect
    public let filesContentFrame: CGRect

    public init(metrics: NotchMetrics) {
        shellWidth = metrics.openWidth
        shellHeight = metrics.openHeight

        let contentTopInset = CGFloat(8)
        let topY = metrics.closedHeight + contentTopInset
        let horizontalInset = metrics.expandedHorizontalContentPadding
        let bottomInset = metrics.expandedContentBottomGuard + 10
        let contentWidth = max(1, metrics.openWidth - (horizontalInset * 2))
        tasksContentFrame = CGRect(
            x: horizontalInset,
            y: topY,
            width: contentWidth,
            height: max(1, metrics.openHeight - topY - bottomInset)
        )
        filesContentFrame = CGRect(
            x: horizontalInset,
            y: topY,
            width: contentWidth,
            height: max(1, metrics.openHeight - topY - contentTopInset)
        )
    }
}

public extension NotchMetrics {
    var expandedPrimaryContentLayout: IslandPrimaryContentLayout {
        IslandPrimaryContentLayout(metrics: self)
    }
}
