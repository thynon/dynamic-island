import CoreGraphics

public struct CodexTasksApprovalLayout: Equatable, Sendable {
    public static let sessionBrowserWidth: CGFloat = 252
    public static let detailSpacing: CGFloat = 8
    public static let dividerWidth: CGFloat = 1
    public static let summaryHeight: CGFloat = 54
    public static let attachmentWidth: CGFloat = 124

    public let summaryFrame: CGRect
    public let attachmentFrame: CGRect
    public let additionalCanvasWidth: CGFloat
    public let rejectButtonWidth: CGFloat = 42
    public let approveSplitButtonWidth: CGFloat = 68

    public init(metrics: NotchMetrics, shellHeight: CGFloat? = nil) {
        let content = IslandPrimaryContentLayout(metrics: metrics, shellHeight: shellHeight).tasksContentFrame
        let detailMinX = content.minX
            + Self.sessionBrowserWidth
            + Self.detailSpacing
            + Self.dividerWidth
            + Self.detailSpacing
        summaryFrame = CGRect(
            x: detailMinX,
            y: content.minY,
            width: content.maxX - detailMinX,
            height: Self.summaryHeight
        )
        attachmentFrame = CGRect(
            x: summaryFrame.maxX,
            y: summaryFrame.minY,
            width: Self.attachmentWidth,
            height: Self.summaryHeight
        )
        additionalCanvasWidth = max(0, attachmentFrame.maxX - metrics.openWidth)
    }
}
