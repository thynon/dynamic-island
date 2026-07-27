import CoreGraphics

public struct IslandPrimaryContentLayout: Equatable, Sendable {
    public let shellWidth: CGFloat
    public let shellHeight: CGFloat
    public let tasksContentFrame: CGRect
    public let filesContentFrame: CGRect

    public init(metrics: NotchMetrics, shellHeight: CGFloat? = nil) {
        let resolvedShellHeight = max(metrics.openHeight, shellHeight ?? metrics.openHeight)
        shellWidth = metrics.openWidth
        self.shellHeight = resolvedShellHeight

        let contentTopInset = CGFloat(8)
        let topY = metrics.closedHeight + contentTopInset
        let horizontalInset = metrics.expandedHorizontalContentPadding
        let bottomInset = metrics.expandedContentBottomGuard + 10
        let contentWidth = max(1, metrics.openWidth - (horizontalInset * 2))
        tasksContentFrame = CGRect(
            x: horizontalInset,
            y: topY,
            width: contentWidth,
            height: max(1, resolvedShellHeight - topY - bottomInset)
        )
        filesContentFrame = CGRect(
            x: horizontalInset,
            y: topY,
            width: contentWidth,
            height: max(1, resolvedShellHeight - topY - contentTopInset)
        )
    }
}

public extension NotchMetrics {
    var expandedPrimaryContentLayout: IslandPrimaryContentLayout {
        IslandPrimaryContentLayout(metrics: self)
    }
}
