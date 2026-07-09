import SwiftUI
import DynamicIslandCore

struct CodexStatusBarView: View {
    let task: CodexTaskStatus
    let rowHeight: CGFloat
    let statusColumnWidth: CGFloat
    let approvalSlotWidth: CGFloat

    private var statusText: String {
        "\(task.activityState.displayText) · \(task.formattedElapsedTime) · \(task.formattedTokenCount) tokens"
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(task.activityState.isWorking ? Color.white.opacity(0.82) : Color.white.opacity(0.28))
                    .frame(width: 6, height: 6)

                Text(task.title)
                    .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(statusText)
                .font(.system(size: statusFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(task.activityState.isWorking ? 0.78 : 0.55))
                .lineLimit(1)
                .truncationMode(.tail)
                .epitaxyThinkingShimmer(isActive: task.activityState.isWorking)
                .frame(width: statusColumnWidth, alignment: .leading)

            approvalBadge
                .frame(width: approvalSlotWidth, height: rowHeight, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .clipped()
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var approvalBadge: some View {
        if task.approvalState.isVisible {
            Text(task.approvalState.displayText)
                .font(.system(size: approvalFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(approvalTint.opacity(task.approvalState == .autoReviewing ? 0.7 : 0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 7)
                .frame(maxWidth: approvalSlotWidth, minHeight: approvalBadgeHeight, maxHeight: approvalBadgeHeight)
                .background(approvalTint.opacity(0.13), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(approvalTint.opacity(0.24), lineWidth: 0.7)
                )
        } else {
            Color.clear
        }
    }

    private var accessibilityText: String {
        if task.approvalState.isVisible {
            return "\(task.title), \(statusText), \(task.approvalState.accessibilityText)"
        }
        return "\(task.title), \(statusText)"
    }

    private var titleFontSize: CGFloat {
        switch rowHeight {
        case ..<27:
            10.5
        case ..<32:
            11.5
        default:
            12.5
        }
    }

    private var statusFontSize: CGFloat {
        return 9.5
    }

    private var approvalFontSize: CGFloat {
        rowHeight < 27 ? 9 : 9.5
    }

    private var approvalBadgeHeight: CGFloat {
        rowHeight < 27 ? 16 : 18
    }

    private var approvalTint: Color {
        task.approvalState == .autoReviewing
            ? Color.white
            : Color(red: 1, green: 0.74, blue: 0.34)
    }
}

private extension View {
    func epitaxyThinkingShimmer(isActive: Bool) -> some View {
        opacity(isActive ? 0.82 : 1)
    }
}
