import AppKit
import SwiftUI
import DynamicIslandCore

struct CodexStatusBarView: View {
    let task: CodexTaskStatus?
    let totalTokens: Int
    let visibleTaskCount: Int
    let isApprovalAttachmentPresented: Bool
    let approvalPresentation: CodexApprovalPresentation
    let onDelete: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isHovering = false
    @State private var isShattering = false

    private let animationProfile = IslandAnimationProfile.default
    private let approvalTokenOffset: CGFloat = 10

    private var statusText: String {
        guard let task else { return "Idle" }
        return "\(task.activityState.displayText) · \(task.formattedElapsedTime)"
    }

    private var canDelete: Bool {
        guard let task else { return false }
        return !task.activityState.isWorking && task.approvalState == .none
    }

    private var showsDeleteButton: Bool {
        canDelete && isHovering && !isShattering
    }

    private var deleteButtonTransition: AnyTransition {
        accessibilityReduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 11) {
                CodexPixelPetView(state: task?.companionState ?? .idle)

                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1, height: 34)

                VStack(alignment: .leading, spacing: 5) {
                    identityLine
                    taskLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                tokenSummary
                    .padding(.trailing, canDelete ? 16 : 0)
                    .offset(x: isApprovalAttachmentPresented ? -approvalTokenOffset : 0)
                    .animation(
                        accessibilityReduceMotion
                            ? nil
                            : .spring(
                                response: animationProfile.primaryFeatureSelectionResponse,
                                dampingFraction: animationProfile.primaryFeatureSelectionDamping,
                                blendDuration: 0
                            ),
                        value: isApprovalAttachmentPresented
                    )
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 0.7)
            )
            .opacity(isShattering ? 0 : 1)

            if isShattering && !accessibilityReduceMotion {
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
                .buttonStyle(IslandPressButtonStyle())
                .padding(.top, 3)
                .padding(.trailing, 4)
                .transition(deleteButtonTransition)
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
        .animation(
            .easeOut(duration: accessibilityReduceMotion ? animationProfile.reducedMotionFadeDuration : 0.14),
            value: showsDeleteButton
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var identityLine: some View {
        HStack(spacing: 6) {
            CodexApplicationIconView()

            Text("Codex")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))

            if task?.activityState.isWorking == true {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(red: 0.34, green: 0.92, blue: 0.76))
                        .frame(width: 4, height: 4)
                    Text("LIVE")
                }
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.5, green: 1, blue: 0.84))
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(Color(red: 0.14, green: 0.42, blue: 0.34).opacity(0.72), in: Capsule())
            } else if task != nil {
                Text("DONE")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }

            if visibleTaskCount > 1 {
                Text("\(visibleTaskCount) 个会话")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
    }

    private var taskLine: some View {
        HStack(spacing: 7) {
            Text(task?.agentDisplayName ?? "暂无活跃会话")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1, height: 11)

            Text(statusText)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(task?.activityState.isWorking == true ? 0.7 : 0.48))
                .lineLimit(1)

            approvalBadge
        }
    }

    private var safeApprovalSummary: String? {
        if let request = approvalPresentation.request,
           request.threadID == task?.id {
            switch request.kind {
            case .command:
                return "命令待审批"
            case .fileChange:
                return "文件变更待审批"
            case .permissions:
                return "权限待审批"
            }
        }

        guard let approvalState = task?.approvalState else { return nil }
        switch approvalState {
        case .pending:
            return "操作待审批"
        case .pendingCommand:
            return "命令待审批"
        case .pendingFileChange:
            return "文件变更待审批"
        case .pendingPermissions:
            return "权限待审批"
        case .autoReviewing:
            return "审查中"
        case .none:
            return nil
        }
    }

    private var approvalBadgeText: String? {
        if approvalPresentation.pendingCount > 1 {
            return "\(approvalPresentation.pendingCount) 个待审批"
        }
        return safeApprovalSummary
    }

    private var tokenSummary: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("TOTAL TOKENS")
                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.42))

            Text(CodexStatusBarSnapshot.formatTokenCount(totalTokens))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
        }
        .frame(minWidth: 78, alignment: .trailing)
    }

    @ViewBuilder
    private var approvalBadge: some View {
        if let task, let approvalBadgeText {
            let badgeText = approvalBadgeText.isEmpty
                ? task.approvalState.displayText
                : approvalBadgeText
            Text(badgeText)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(approvalTint(for: task).opacity(task.approvalState == .autoReviewing ? 0.7 : 0.92))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(approvalTint(for: task).opacity(0.13), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(approvalTint(for: task).opacity(0.24), lineWidth: 0.7)
                )
        }
    }

    private func approvalTint(for task: CodexTaskStatus) -> Color {
        task.approvalState.requiresManualApproval || approvalPresentation.request?.threadID == task.id
            ? Color(red: 1, green: 0.74, blue: 0.34)
            : Color.white
    }

    private var accessibilityText: String {
        guard let task else {
            return "Codex，暂无活跃会话，累计 \(CodexStatusBarSnapshot.formatTokenCount(totalTokens)) tokens"
        }
        if let approvalBadgeText {
            return "Codex，\(task.agentDisplayName)，\(statusText)，\(approvalBadgeText)，累计 \(CodexStatusBarSnapshot.formatTokenCount(totalTokens)) tokens"
        }
        return "Codex，\(task.agentDisplayName)，\(statusText)，累计 \(CodexStatusBarSnapshot.formatTokenCount(totalTokens)) tokens"
    }

    private func beginDelete() {
        guard canDelete, !isShattering else { return }
        isHovering = false
        let transitionDuration = accessibilityReduceMotion ? animationProfile.reducedMotionFadeDuration : 0.22
        let deleteDelayNanoseconds: UInt64 = accessibilityReduceMotion ? 200_000_000 : 280_000_000
        withAnimation(.easeOut(duration: transitionDuration)) {
            isShattering = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: deleteDelayNanoseconds)
            guard !Task.isCancelled else { return }
            onDelete()
        }
    }
}

@MainActor
private struct CodexApplicationIconView: View {
    private static let appIcon: NSImage? = {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.openai.codex"
        ) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: applicationURL.path)
    }()

    var body: some View {
        Group {
            if let appIcon = Self.appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .saturation(0)
            } else {
                Image(systemName: "terminal.fill")
                    .symbolRenderingMode(.monochrome)
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
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
