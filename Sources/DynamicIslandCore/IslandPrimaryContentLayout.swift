import CoreGraphics

public struct IslandPrimaryContentLayout: Equatable, Sendable {
    public let shellWidth: CGFloat
    public let shellHeight: CGFloat
    public let tasksContentFrame: CGRect

    public init(metrics: NotchMetrics) {
        shellWidth = metrics.openWidth
        shellHeight = metrics.openHeight

        let topY = metrics.closedHeight + 8
        let horizontalInset = metrics.expandedHorizontalContentPadding
        let bottomInset = metrics.expandedContentBottomGuard + 10
        tasksContentFrame = CGRect(
            x: horizontalInset,
            y: topY,
            width: max(1, metrics.openWidth - (horizontalInset * 2)),
            height: max(1, metrics.openHeight - topY - bottomInset)
        )
    }
}

public extension NotchMetrics {
    var expandedPrimaryContentLayout: IslandPrimaryContentLayout {
        IslandPrimaryContentLayout(metrics: self)
    }
}
