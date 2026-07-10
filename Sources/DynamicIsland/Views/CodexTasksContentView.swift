import SwiftUI
import DynamicIslandCore

struct CodexTasksContentView: View {
    let snapshot: CodexStatusBarSnapshot
    let dismissedTaskKeys: Set<String>
    let onDeleteTask: @MainActor (CodexTaskStatus) -> Void
    let onUndoTask: @MainActor (CodexTaskStatus) -> Void

    @State private var pendingUndoTask: CodexTaskStatus?
    @State private var undoSequence = 0

    private let maxVisibleTaskCount = 4
    private let approvalSlotWidth: CGFloat = 68
    private let statusColumnWidth: CGFloat = 260

    private var visibleTasks: ArraySlice<CodexTaskStatus> {
        taskRows.prefix(maxVisibleTaskCount)
    }

    private var taskRows: [CodexTaskStatus] {
        snapshot.tasks.filter { !dismissedTaskKeys.contains($0.dismissalKey) }
    }

    private func dismissTask(_ task: CodexTaskStatus) {
        guard !task.activityState.isWorking, task.approvalState == .none else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            pendingUndoTask = task
        }
        onDeleteTask(task)
        scheduleUndoExpiry()
    }

    private func undoDismissal() {
        guard let task = pendingUndoTask else { return }
        undoSequence += 1
        withAnimation(.easeOut(duration: 0.18)) {
            pendingUndoTask = nil
        }
        onUndoTask(task)
    }

    private func scheduleUndoExpiry() {
        undoSequence += 1
        let sequence = undoSequence
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard undoSequence == sequence else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                pendingUndoTask = nil
            }
        }
    }

    private var rowHeight: CGFloat {
        switch taskRows.count {
        case 0, 1:
            34
        case 2:
            30
        default:
            24
        }
    }

    private var rowSpacing: CGFloat {
        taskRows.count >= 3 ? 5 : 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(Array(visibleTasks)) { task in
                CodexStatusBarView(
                    task: task,
                    rowHeight: rowHeight,
                    statusColumnWidth: statusColumnWidth,
                    approvalSlotWidth: approvalSlotWidth,
                    onDelete: { dismissTask(task) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            if pendingUndoTask != nil {
                HStack(spacing: 7) {
                    Text("已隐藏")
                        .foregroundStyle(.white.opacity(0.76))

                    Button("撤销", action: undoDismissal)
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(.black.opacity(0.82), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 0.7)
                )
                .padding(.trailing, 8)
                .padding(.bottom, 7)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .accessibilityElement(children: .contain)
    }
}
