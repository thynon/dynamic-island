import SwiftUI
import DynamicIslandCore

struct CodexApprovalActionView: View {
    let presentation: CodexApprovalPresentation
    let onDecision: @MainActor (CodexApprovalDecision, CodexApprovalRequest.ID) -> Void
    let onOpenCodexApproval: @MainActor (CodexApprovalRequest.ID) -> Void
    let onRetry: @MainActor (CodexApprovalRequest.ID) -> Void

    @State private var approvalDetails: String?

    private var request: CodexApprovalRequest? {
        presentation.request
    }

    private var canRespondInline: Bool {
        request?.canRespondInline == true
    }

    private var canAcceptForSession: Bool {
        request?.availableDecisions.contains(.acceptForSession) == true
    }

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(width: 1, height: 30)

            actionContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            Color.black,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 8,
                topTrailingRadius: 8,
                style: .continuous
            )
        )
        .popover(isPresented: approvalDetailsBinding, arrowEdge: .bottom) {
            Text(approvalDetails ?? "")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .textSelection(.enabled)
                .padding(12)
                .frame(width: 280, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("审批详情，\(approvalDetails ?? "")")
        }
        .onChange(of: presentation.request?.id) { _, _ in
            approvalDetails = nil
        }
        .onChange(of: presentation.request?.reviewSummary) { _, _ in
            approvalDetails = nil
        }
    }

    @ViewBuilder
    private var actionContent: some View {
        switch presentation.submissionState {
        case .submitting:
            Text("提交中…")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 110, height: 30)
        case .failed(let message):
            HStack(spacing: 4) {
                Text(message.isEmpty ? "提交失败" : message)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.52).opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("重试", action: retry)
                    .buttonStyle(IslandPressButtonStyle())
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 110, height: 30)
        case .ready:
            if canRespondInline {
                decisionButtons
            } else {
                Button("前往 Codex", action: openCodexApproval)
                    .buttonStyle(IslandPressButtonStyle())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 110, height: 30)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }

    private var decisionButtons: some View {
        HStack(spacing: 6) {
            Button("拒绝") {
                submit(.decline)
            }
            .buttonStyle(IslandPressButtonStyle())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.58).opacity(0.94))
            .frame(width: 42, height: 30)
            .background(
                Color(red: 0.45, green: 0.12, blue: 0.12).opacity(0.24),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(red: 1, green: 0.45, blue: 0.42).opacity(0.28), lineWidth: 0.7)
            )

            if canAcceptForSession {
                HStack(spacing: 0) {
                    approveButton(width: 50)

                    Menu {
                        if let reviewSummary = request?.reviewSummary, !reviewSummary.isEmpty {
                            Button("查看审批详情") {
                                approvalDetails = reviewSummary
                            }
                            Divider()
                        }

                        Button("同意，并在本次会话自动允许") {
                            submit(CodexApprovalDecision.acceptForSession)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(red: 0.52, green: 1, blue: 0.84).opacity(0.9))
                            .frame(width: 18, height: 30)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .frame(width: 68, height: 30)
                .background(
                    Color(red: 0.12, green: 0.38, blue: 0.30).opacity(0.58),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
            } else {
                approveButton(width: 68)
                    .background(
                        Color(red: 0.12, green: 0.38, blue: 0.30).opacity(0.58),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
            }
        }
    }

    private func approveButton(width: CGFloat) -> some View {
        Button("同意") {
            submit(.accept)
        }
        .buttonStyle(IslandPressButtonStyle())
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(Color(red: 0.52, green: 1, blue: 0.84).opacity(0.94))
        .frame(width: width, height: 30)
    }

    private var approvalDetailsBinding: Binding<Bool> {
        Binding(
            get: { approvalDetails != nil },
            set: { isPresented in
                if !isPresented {
                    approvalDetails = nil
                }
            }
        )
    }

    private func openCodexApproval() {
        guard let requestID = request?.id else { return }
        onOpenCodexApproval(requestID)
    }

    private func submit(_ decision: CodexApprovalDecision) {
        guard let requestID = request?.id else { return }
        let onDecision = { decision in
            self.onDecision(decision, requestID)
        }
        onDecision(decision)
    }

    private func retry() {
        guard let requestID = request?.id else { return }
        let onRetry = {
            self.onRetry(requestID)
        }
        onRetry()
    }
}
