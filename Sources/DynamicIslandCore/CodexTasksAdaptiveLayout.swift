import CoreGraphics

public struct CodexTasksAdaptiveLayout: Equatable, Sendable {
    public static let visibleAgentRowLimit = 5
    public static let agentRowHeight: CGFloat = 26
    public static let groupTopSpacing: CGFloat = 10
    public static let maximumExtraHeight: CGFloat =
        groupTopSpacing + (agentRowHeight * CGFloat(visibleAgentRowLimit))

    public static func extraHeight(agentCount: Int) -> CGFloat {
        guard agentCount > 0 else { return 0 }
        let visibleCount = min(agentCount, visibleAgentRowLimit)
        return groupTopSpacing + (CGFloat(visibleCount) * agentRowHeight)
    }
}
