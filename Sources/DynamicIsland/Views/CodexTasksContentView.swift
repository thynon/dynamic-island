import SwiftUI
import DynamicIslandCore

struct CodexTasksContentView: View {
    let snapshot: CodexStatusBarSnapshot
    let dismissedTaskKeys: Set<String>
    let isActive: Bool
    let isApprovalAttachmentPresented: Bool
    let approvalPresentation: CodexApprovalPresentation
    let onDeleteTask: @MainActor (CodexTaskStatus) -> Void
    let onUndoTask: @MainActor (CodexTaskStatus) -> Void
    let onTaskSelection: @MainActor (String) -> Void
    let onExpansionHeightChange: @MainActor (CGFloat) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Binding private var selectedTaskID: String?
    @State private var pendingUndoTask: CodexTaskStatus?
    @State private var undoSequence = 0
    @State private var expandedRootID: String?

    private let animationProfile = IslandAnimationProfile.default
    private let summaryCardHeight: CGFloat = 54
    private let maxVisibleProgressEventCount = 3
    private let expandedVisibleProgressEventCount = 8
    private let sessionBrowserWidth: CGFloat = 252

    init(
        snapshot: CodexStatusBarSnapshot,
        dismissedTaskKeys: Set<String>,
        isActive: Bool,
        isApprovalAttachmentPresented: Bool,
        approvalPresentation: CodexApprovalPresentation,
        selectedTaskID: Binding<String?>,
        onDeleteTask: @escaping @MainActor (CodexTaskStatus) -> Void,
        onUndoTask: @escaping @MainActor (CodexTaskStatus) -> Void,
        onTaskSelection: @escaping @MainActor (String) -> Void,
        onExpansionHeightChange: @escaping @MainActor (CGFloat) -> Void
    ) {
        self.snapshot = snapshot
        self.dismissedTaskKeys = dismissedTaskKeys
        self.isActive = isActive
        self.isApprovalAttachmentPresented = isApprovalAttachmentPresented
        self.approvalPresentation = approvalPresentation
        self._selectedTaskID = selectedTaskID
        self.onDeleteTask = onDeleteTask
        self.onUndoTask = onUndoTask
        self.onTaskSelection = onTaskSelection
        self.onExpansionHeightChange = onExpansionHeightChange
    }

    private var taskRows: [CodexTaskStatus] {
        snapshot.tasks.filter { !dismissedTaskKeys.contains($0.dismissalKey) }
    }

    private var primaryTasks: [CodexTaskStatus] {
        taskRows.filter { !$0.isSubagent }
    }

    private var focusedTask: CodexTaskStatus? {
        if let selectedTaskID,
           let selectedTask = taskRows.first(where: { $0.id == selectedTaskID })
        {
            return selectedTask
        }
        return primaryTasks.first ?? taskRows.first
    }

    private var visibleProgressEvents: [CodexSessionProgressEvent] {
        guard let focusedTask else { return [] }
        if expandedRootID == nil {
            return Array(focusedTask.progressEvents.suffix(maxVisibleProgressEventCount))
        }
        return Array(focusedTask.progressEvents.suffix(expandedVisibleProgressEventCount))
    }

    private var expandedAgentCount: Int {
        guard let expandedRootID else { return 0 }
        return orderedAgents(for: expandedRootID).count
    }

    private var undoAnimation: Animation {
        .easeOut(duration: accessibilityReduceMotion ? animationProfile.reducedMotionFadeDuration : 0.18)
    }

    private var undoTransition: AnyTransition {
        accessibilityReduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }

    private var disclosureAnimation: Animation? {
        guard !accessibilityReduceMotion else { return nil }
        return .spring(
            response: animationProfile.primaryFeatureSelectionResponse,
            dampingFraction: 1,
            blendDuration: 0
        )
    }

    private func orderedAgents(for rootID: String) -> [CodexTaskStatus] {
        let agents = taskRows.filter { $0.isSubagent && $0.rootThreadID == rootID }
        var ordered: [CodexTaskStatus] = []
        var insertedIDs: Set<String> = []

        func appendChildren(of parentID: String) {
            for agent in agents where agent.parentThreadID == parentID && !insertedIDs.contains(agent.id) {
                insertedIDs.insert(agent.id)
                ordered.append(agent)
                appendChildren(of: agent.id)
            }
        }

        appendChildren(of: rootID)
        for agent in agents where !insertedIDs.contains(agent.id) {
            insertedIDs.insert(agent.id)
            ordered.append(agent)
        }
        return ordered
    }

    @MainActor
    private func synchronizeSelection() {
        let resolvedSelection = CodexTaskSelectionPolicy.resolvedSelection(
            selectedTaskID: selectedTaskID,
            visibleTaskIDs: taskRows.map(\.id),
            pendingApprovalThreadIDs: approvalPresentation.pendingThreadIDs,
            fallbackTaskID: primaryTasks.first?.id ?? taskRows.first?.id
        )
        if selectedTaskID != resolvedSelection {
            selectedTaskID = resolvedSelection
        }
        guard let selectedTaskID = resolvedSelection,
              let selectedTask = taskRows.first(where: { $0.id == selectedTaskID })
        else { return }
        if selectedTask.isSubagent,
           let rootThreadID = selectedTask.rootThreadID
        {
            expandedRootID = rootThreadID
        }
    }

    private func requiresManualApproval(_ task: CodexTaskStatus) -> Bool {
        task.approvalState.requiresManualApproval
            || approvalPresentation.pendingThreadIDs.contains(task.id)
    }

    @MainActor
    private func reportExpansionHeight() {
        let height = isActive
            ? CodexTasksAdaptiveLayout.extraHeight(agentCount: expandedAgentCount)
            : 0
        onExpansionHeightChange(height)
    }

    @MainActor
    private func toggleRoot(_ root: CodexTaskStatus) {
        let nextExpandedRootID = expandedRootID == root.id ? nil : root.id
        selectedTaskID = root.id
        withAnimation(disclosureAnimation) {
            expandedRootID = nextExpandedRootID
        }
        onTaskSelection(root.id)
        reportExpansionHeight()
    }

    private func dismissTask(_ task: CodexTaskStatus) {
        guard !task.activityState.isWorking, task.approvalState == .none else { return }
        withAnimation(undoAnimation) {
            pendingUndoTask = task
        }
        onDeleteTask(task)
        scheduleUndoExpiry()
    }

    private func undoDismissal() {
        guard let task = pendingUndoTask else { return }
        undoSequence += 1
        withAnimation(undoAnimation) {
            pendingUndoTask = nil
        }
        onUndoTask(task)
    }

    private func scheduleUndoExpiry() {
        undoSequence += 1
        let sequence = undoSequence
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard undoSequence == sequence else { return }
            withAnimation(undoAnimation) {
                pendingUndoTask = nil
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            sessionBrowser
                .frame(width: sessionBrowserWidth)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 5) {
                CodexStatusBarView(
                    task: focusedTask,
                    totalTokens: focusedTask?.totalTokens ?? snapshot.totalTokens,
                    visibleTaskCount: primaryTasks.count,
                    isApprovalAttachmentPresented: isApprovalAttachmentPresented,
                    approvalPresentation: approvalPresentation,
                    onDelete: {
                        guard let task = focusedTask else { return }
                        dismissTask(task)
                    }
                )
                .frame(height: summaryCardHeight)

                sessionTimeline
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            if pendingUndoTask != nil {
                HStack(spacing: 7) {
                    Text("已隐藏")
                        .foregroundStyle(.white.opacity(0.76))

                    Button("撤销", action: undoDismissal)
                        .buttonStyle(IslandPressButtonStyle())
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(.black.opacity(0.88), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 0.7)
                )
                .padding(.trailing, 8)
                .padding(.bottom, 7)
                .transition(undoTransition)
            }
        }
        .onAppear {
            synchronizeSelection()
            reportExpansionHeight()
        }
        .onChange(of: taskRows.map(\.id)) { _, _ in
            synchronizeSelection()
            if let expandedRootID,
               !primaryTasks.contains(where: { $0.id == expandedRootID })
            {
                self.expandedRootID = nil
            }
            reportExpansionHeight()
        }
        .onChange(of: selectedTaskID) { _, _ in
            synchronizeSelection()
            reportExpansionHeight()
        }
        .onChange(of: approvalPresentation.pendingThreadIDs) { _, _ in
            synchronizeSelection()
            reportExpansionHeight()
        }
        .onChange(of: expandedAgentCount) { _, _ in
            reportExpansionHeight()
        }
        .onChange(of: isActive) { _, isActive in
            if !isActive {
                expandedRootID = nil
                onExpansionHeightChange(0)
            } else {
                synchronizeSelection()
                reportExpansionHeight()
            }
        }
        .onDisappear {
            onExpansionHeightChange(0)
        }
        .accessibilityElement(children: .contain)
    }

    private var sessionBrowser: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text("主会话")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))

                Text("\(primaryTasks.count)")
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .padding(.leading, 4)
            .frame(height: 12)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    if primaryTasks.isEmpty {
                        Text("暂无活跃会话")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.36))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        ForEach(primaryTasks) { root in
                            let agents = orderedAgents(for: root.id)
                            VStack(spacing: 2) {
                                CodexPrimarySessionRow(
                                    task: root,
                                    agentCount: agents.count,
                                    isSelected: focusedTask?.id == root.id,
                                    isExpanded: expandedRootID == root.id,
                                    requiresManualApproval: requiresManualApproval(root),
                                    onSelect: {
                                        selectedTaskID = root.id
                                        onTaskSelection(root.id)
                                    },
                                    onToggle: { toggleRoot(root) }
                                )

                                if expandedRootID == root.id {
                                    ForEach(agents) { agent in
                                        CodexAgentSessionRow(
                                            task: agent,
                                            isSelected: focusedTask?.id == agent.id,
                                            requiresManualApproval: requiresManualApproval(agent),
                                            onSelect: {
                                                selectedTaskID = agent.id
                                                onTaskSelection(agent.id)
                                            }
                                        )
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var sessionTimeline: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("会话进程")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))
                .padding(.leading, 4)
                .frame(height: 12)

            if visibleProgressEvents.isEmpty {
                Text("暂无会话进程")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.36))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(visibleProgressEvents.enumerated()), id: \.element.id) { index, event in
                            CodexSessionProgressRow(
                                event: event,
                                isCurrent: index == visibleProgressEvents.count - 1,
                                taskActivityState: focusedTask?.activityState ?? .unavailable
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CodexPrimarySessionRow: View {
    let task: CodexTaskStatus
    let agentCount: Int
    let isSelected: Bool
    let isExpanded: Bool
    let requiresManualApproval: Bool
    let onSelect: @MainActor () -> Void
    let onToggle: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Button(action: onSelect) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(
                            requiresManualApproval
                                ? Color(red: 1, green: 0.74, blue: 0.34)
                                : (task.activityState.isWorking ? Color(red: 0.34, green: 0.92, blue: 0.76) : .white.opacity(0.28))
                        )
                        .frame(width: 5, height: 5)

                    Text(task.title)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(isSelected ? 0.92 : 0.62))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 3)

                    if agentCount > 0 {
                        Text("\(agentCount)")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.leading, 9)
                .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(IslandPressButtonStyle())

            if agentCount > 0 {
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(isExpanded ? 0.78 : 0.46))
                        .frame(width: 24, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(IslandPressButtonStyle())
                .accessibilityLabel(isExpanded ? "收起子代理" : "展开 \(agentCount) 个子代理")
            }
        }
        .padding(.trailing, agentCount > 0 ? 2 : 8)
        .background(
            Color.white.opacity(isSelected ? 0.075 : 0.028),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(isSelected ? 0.12 : 0.04), lineWidth: 0.7)
        )
    }
}

private struct CodexAgentSessionRow: View {
    let task: CodexTaskStatus
    let isSelected: Bool
    let requiresManualApproval: Bool
    let onSelect: @MainActor () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text("└")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.22))

                Circle()
                    .fill(
                        requiresManualApproval
                            ? Color(red: 1, green: 0.74, blue: 0.34)
                            : (task.activityState.isWorking ? Color(red: 0.36, green: 0.58, blue: 1) : .white.opacity(0.24))
                    )
                    .frame(width: 4, height: 4)

                Text(task.agentDisplayName)
                    .font(.system(size: 9.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(isSelected ? 0.88 : 0.52))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(task.formattedTokenCount)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .monospacedDigit()
            }
            .padding(.leading, min(10 + CGFloat(max(1, task.agentDepth)) * 8, 34))
            .padding(.trailing, 9)
            .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
            .contentShape(Rectangle())
            .background(
                Color.white.opacity(isSelected ? 0.06 : 0.015),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
        }
        .buttonStyle(IslandPressButtonStyle())
        .accessibilityLabel("子代理 \(task.agentDisplayName)，\(task.activityState.displayText)")
    }
}

private struct CodexSessionProgressRow: View {
    let event: CodexSessionProgressEvent
    let isCurrent: Bool
    let taskActivityState: CodexStatusBarSnapshot.ActivityState

    private var isActivelyWorking: Bool {
        isCurrent && taskActivityState.isWorking
    }

    private var formattedEventTime: String {
        guard let occurredAt = event.occurredAt else { return "--:--" }
        let components = Calendar.current.dateComponents(
            [.hour, .minute],
            from: Date(timeIntervalSince1970: occurredAt)
        )
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private var statusText: String {
        if isActivelyWorking, event.kind == .waitingApproval {
            return "待审"
        }
        if isActivelyWorking, event.kind == .retrying {
            return "重试"
        }
        return isActivelyWorking ? "进行中" : "完成"
    }

    private var accentColor: Color {
        if isActivelyWorking, event.kind == .waitingApproval {
            return Color(red: 1, green: 0.74, blue: 0.34)
        }
        if isActivelyWorking, event.kind == .retrying {
            return Color(red: 0.36, green: 0.58, blue: 1)
        }
        if isActivelyWorking {
            return Color(red: 0.34, green: 0.92, blue: 0.76)
        }
        return Color.white.opacity(0.42)
    }

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 1, height: 20)

                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle()
                            .stroke(.black.opacity(0.7), lineWidth: 1)
                    )
            }
            .frame(width: 10, height: 20)

            Text(formattedEventTime)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 36, alignment: .leading)

            Text(event.displayText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(statusText)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(accentColor.opacity(isActivelyWorking ? 0.95 : 0.75))
                .padding(.horizontal, 7)
                .frame(height: 16)
                .background(accentColor.opacity(isActivelyWorking ? 0.14 : 0.08), in: Capsule())
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20)
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(formattedEventTime)，\(event.displayText)，\(statusText)")
    }
}
