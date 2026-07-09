import SwiftUI
import DynamicIslandCore

struct CodexTasksContentView: View {
    let snapshot: CodexStatusBarSnapshot

    private let maxVisibleTaskCount = 4
    private let approvalSlotWidth: CGFloat = 68
    private let statusColumnWidth: CGFloat = 260

    private var visibleTasks: ArraySlice<CodexTaskStatus> {
        taskRows.prefix(maxVisibleTaskCount)
    }

    private var taskRows: [CodexTaskStatus] {
        snapshot.tasks
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
                    approvalSlotWidth: approvalSlotWidth
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .accessibilityElement(children: .contain)
    }
}
