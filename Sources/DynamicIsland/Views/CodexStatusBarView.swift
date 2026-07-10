import SwiftUI
import DynamicIslandCore

struct CodexStatusBarView: View {
    let task: CodexTaskStatus
    let rowHeight: CGFloat
    let statusColumnWidth: CGFloat
    let approvalSlotWidth: CGFloat
    let onDelete: @MainActor () -> Void

    @State private var isHovering = false
    @State private var isShattering = false

    private var statusText: String {
        "\(task.activityState.displayText) · \(task.formattedElapsedTime) · \(task.formattedTokenCount) tokens"
    }

    private var canDelete: Bool {
        !task.activityState.isWorking && task.approvalState == .none
    }

    private var showsDeleteButton: Bool {
        canDelete && isHovering && !isShattering
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
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
            .opacity(isShattering ? 0 : 1)

            if isShattering {
                TaskShatterEffectView()
                    .transition(.opacity)
            }

            if showsDeleteButton {
                Button(action: beginDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white.opacity(0.96), .black.opacity(0.68))
                        .frame(width: 16, height: 16)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .padding(.trailing, 5)
                .transition(.opacity.combined(with: .scale(scale: 0.72, anchor: .topTrailing)))
                .accessibilityLabel("删除已完成任务")
            }
        }
        .contentShape(Rectangle())
        .clipped()
        .onHover { isInside in
            withAnimation(.easeOut(duration: isInside ? 0.12 : 0.16)) {
                isHovering = isInside
            }
        }
        .animation(.easeOut(duration: 0.14), value: showsDeleteButton)
        .accessibilityLabel(accessibilityText)
    }

    private func beginDelete() {
        guard canDelete, !isShattering else { return }
        isHovering = false
        withAnimation(.easeOut(duration: 0.22)) {
            isShattering = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            onDelete()
        }
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

private struct TaskShatterEffectView: View {
    private struct Particle: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let angle: Double
        let width: CGFloat
        let delay: Double
    }

    private let particles: [Particle] = [
        Particle(id: 0, x: -54, y: -7, angle: -26, width: 7, delay: 0),
        Particle(id: 1, x: -38, y: 8, angle: 18, width: 5, delay: 0.01),
        Particle(id: 2, x: -21, y: -9, angle: 42, width: 4, delay: 0.02),
        Particle(id: 3, x: -7, y: 7, angle: -14, width: 6, delay: 0.03),
        Particle(id: 4, x: 11, y: -8, angle: 23, width: 5, delay: 0.01),
        Particle(id: 5, x: 26, y: 8, angle: -35, width: 7, delay: 0.02),
        Particle(id: 6, x: 43, y: -6, angle: 12, width: 4, delay: 0.04),
        Particle(id: 7, x: 57, y: 6, angle: -22, width: 6, delay: 0.03),
    ]

    @State private var isBursting = false

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.86))
                    .frame(width: particle.width, height: 2)
                    .rotationEffect(.degrees(particle.angle))
                    .offset(
                        x: isBursting ? particle.x : 0,
                        y: isBursting ? particle.y : 0
                    )
                    .scaleEffect(isBursting ? 0.35 : 1)
                    .opacity(isBursting ? 0 : 0.92)
                    .animation(
                        .easeOut(duration: 0.24).delay(particle.delay),
                        value: isBursting
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear {
            isBursting = true
        }
    }
}
