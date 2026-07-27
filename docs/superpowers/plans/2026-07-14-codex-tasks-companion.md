# Codex Tasks Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans and superpowers:test-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved expanded Tasks layout with a static 32pt pixel pet, Codex identity, current-conversation total tokens, and a sanitized realtime progress timeline.

**Architecture:** Extend the pure Core snapshot with bounded progress-event and companion-state models, derive those events during the existing cached rollout parse, and render them through focused SwiftUI summary, pet, and timeline views. Keep Codex source data read-only, preserve dismissal/approval behavior, and reuse the existing Tasks content frame and polling lifecycle.

**Tech Stack:** Swift 6, SwiftPM, Foundation, AppKit, SwiftUI `Canvas`, existing source-contract/Core checks.

## Global Constraints

- Keep the `850×200` open shell, 32pt camera-safe top band, and current navigation geometry unchanged.
- Use a 32pt static pixel pet drawn from a 16×16 grid at 2pt integer scale.
- Show cumulative tokens for the focused Codex conversation, not a cross-thread sum.
- Show at most three recent distinct progress events and never render prompt text, assistant text, raw tool names, arguments, output, paths, or filenames.
- Keep Codex SQLite and rollout JSONL read-only.
- Preserve approval display, completed-task shatter, local dismissal, five-second Undo, 10-second completion retention, and 60-second stale cutoff.
- Add no dependency, framework, permission, continuous animation, or new persistence.
- Preserve unrelated dirty-worktree changes and stage nothing automatically.

---

### Task 1: Model sanitized session progress and pet state

**Files:**
- Create: `Sources/DynamicIslandCore/CodexSessionProgress.swift`
- Modify: `Sources/DynamicIslandCore/CodexStatusBarSnapshot.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**
- Produces: `CodexSessionProgressEvent`, `CodexSessionProgressEvent.Kind`, `CodexCompanionState`, `CodexTaskStatus.progressEvents`, `CodexTaskStatus.companionState`

- [ ] **Step 1: Write failing Core behavior checks**

Add assertions that construct events and task states directly:

```swift
let started = CodexSessionProgressEvent(
    id: "started-1",
    kind: .started,
    occurredAt: 1_700_000_000
)
expectEqual(started.displayText, "开始处理会话", "session progress owns sanitized copy")

let toolTask = CodexTaskStatus(
    id: "thread",
    activityState: .runningTool,
    progressEvents: [started]
)
expectEqual(toolTask.companionState, .tool, "running tools select the terminal pet pose")
expectEqual(toolTask.progressEvents, [started], "task snapshots carry bounded rollout progress")
```

Also require the source to contain no raw `arguments` or message-content field
on `CodexSessionProgressEvent`.

- [ ] **Step 2: Run the checks and observe the intended failure**

Run: `swift run DynamicIslandCoreChecks`

Expected: FAIL because the progress model, task field, and companion mapping do
not exist.

- [ ] **Step 3: Add the minimal Core model**

Create an event enum with exact cases:

```swift
public struct CodexSessionProgressEvent: Equatable, Identifiable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case started, thinking, tool, responding, compacting
        case waitingApproval, retrying, completed
    }

    public let id: String
    public let kind: Kind
    public let occurredAt: TimeInterval?
    public let displayText: String
}

public enum CodexCompanionState: String, Equatable, Sendable {
    case idle, thinking, tool, done
}
```

Give the event initializer a default allowlisted label for each `Kind`, accept
an optional already-sanitized display label, add `progressEvents` to
`CodexTaskStatus`, and map activity states to the four companion states. A task
with `.idle` maps to `.done`; an unavailable/no-task surface uses `.idle` in the
view.

- [ ] **Step 4: Run the checks and confirm they pass**

Run: `swift run DynamicIslandCoreChecks`

Expected: `DynamicIslandCoreChecks passed`.

---

### Task 2: Derive a bounded privacy-safe timeline from rollout events

**Files:**
- Modify: `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**
- Consumes: `CodexSessionProgressEvent`, `CodexTaskStatus.progressEvents`
- Produces: `RolloutState.progressEvents`, `appendProgressEvent(kind:occurredAt:displayText:)`, `sanitizedToolProgressText(_:)`

- [ ] **Step 1: Write failing parser source-contract checks**

Require the parser to recognize `agent_reasoning`, `agent_message`, tool calls,
approval requests, retry/error, compaction, and terminal events; require an
allowlist function and a bounded `progressEventLimit`. Forbid copying
`payload["arguments"]`, `payload["message"]`, or response content into the
event initializer.

- [ ] **Step 2: Run the checks and observe the intended failure**

Run: `swift run DynamicIslandCoreChecks`

Expected: FAIL because rollout progress extraction is absent.

- [ ] **Step 3: Extend the existing cached rollout pass**

Add a small event buffer to `RolloutState` and this dedupe behavior:

```swift
private func appendProgressEvent(
    kind: CodexSessionProgressEvent.Kind,
    occurredAt: TimeInterval?,
    displayText: String? = nil,
    to state: inout RolloutState
) {
    let resolvedText = displayText ?? kind.defaultDisplayText
    if state.progressEvents.last?.kind == kind,
       state.progressEvents.last?.displayText == resolvedText {
        return
    }
    let sequence = state.progressEvents.count
    state.progressEvents.append(
        CodexSessionProgressEvent(
            id: "\(kind.rawValue)-\(Int((occurredAt ?? 0) * 1000))-\(sequence)",
            kind: kind,
            occurredAt: occurredAt,
            displayText: resolvedText
        )
    )
    state.progressEvents = Array(state.progressEvents.suffix(progressEventLimit))
}
```

Map only known tool categories:

```swift
private func sanitizedToolProgressText(_ name: String?) -> String {
    switch name?.lowercased() {
    case "exec", "exec_command": "运行命令"
    case "apply_patch": "修改文件"
    case "view_image": "查看图像"
    case "imagegen", "image_gen": "生成图像"
    case "wait": "等待工具"
    default: "运行工具"
    }
}
```

Pass `state.progressEvents` into `CodexTaskStatus`. Reuse
`eventTimestamp(_:)`; do not add another file read or polling loop.

- [ ] **Step 4: Run the checks and confirm they pass**

Run: `swift run DynamicIslandCoreChecks`

Expected: `DynamicIslandCoreChecks passed`.

---

### Task 3: Draw the static 32pt Codex pixel pet

**Files:**
- Create: `Sources/DynamicIsland/Views/CodexPixelPetView.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**
- Consumes: `CodexCompanionState`
- Produces: `CodexPixelPetView(state:)`

- [ ] **Step 1: Write failing view source-contract checks**

Require `Canvas`, `gridSize = 16`, `pixelScale: CGFloat = 2`, a fixed
`.frame(width: 32, height: 32)`, state-specific `tool` and `done` pixels, and
an accessibility label. Forbid `TimelineView`, `Timer`, `repeatForever`, and
`ProgressView`.

- [ ] **Step 2: Run the checks and observe the intended failure**

Run: `swift run DynamicIslandCoreChecks`

Expected: FAIL because the pet view does not exist.

- [ ] **Step 3: Implement one integer-grid Canvas**

Define a private `Pixel` value with integer `x`, `y`, and palette role. Build a
shared cat body plus small state overlays, and draw every pixel with:

```swift
context.fill(
    Path(CGRect(
        x: CGFloat(pixel.x) * pixelScale,
        y: CGFloat(pixel.y) * pixelScale,
        width: pixelScale,
        height: pixelScale
    )),
    with: .color(color(for: pixel.role))
)
```

Use only off-white, cool gray, graphite, mint-cyan, and a restrained blue for
the terminal pose. Expose one combined accessibility label derived from state.

- [ ] **Step 4: Run the checks and confirm they pass**

Run: `swift run DynamicIslandCoreChecks`

Expected: `DynamicIslandCoreChecks passed`.

---

### Task 4: Replace the row-only Tasks surface with the approved summary and timeline

**Files:**
- Modify: `Sources/DynamicIsland/Views/CodexStatusBarView.swift`
- Modify: `Sources/DynamicIsland/Views/CodexTasksContentView.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**
- Consumes: `CodexPixelPetView(state:)`, `CodexTaskStatus.progressEvents`, `CodexTaskStatus.companionState`
- Produces: focused summary card, installed Codex icon fallback, three-row `会话进程` timeline

- [ ] **Step 1: Write failing layout and preservation checks**

Require exact visible copy `Codex`, `LIVE`, `TOTAL TOKENS`, and `会话进程`;
require `prefix(3)`, `formattedTokenCount`, `com.openai.codex`, the 54pt summary
height, local `HH:mm` formatting, and `暂无会话进程`. Keep assertions for
approval display, completion deletion guard, shatter effect, local dismissal,
Undo, no `ProgressView`, and no `repeatForever`. Remove obsolete expectations
for four equal task rows and the 260pt status column.

- [ ] **Step 2: Run the checks and observe the intended failure**

Run: `swift run DynamicIslandCoreChecks`

Expected: FAIL because the old row-only layout is still present.

- [ ] **Step 3: Build the summary card in `CodexStatusBarView`**

Change the interface to:

```swift
struct CodexStatusBarView: View {
    let task: CodexTaskStatus?
    let totalTokens: Int
    let visibleTaskCount: Int
    let onDelete: @MainActor () -> Void
}
```

Use a 32pt pet at left; resolve the Codex icon through
`NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")`
with `terminal.fill` fallback; place title/activity/elapsed time in the flexible
center; put `TOTAL TOKENS` and monospaced formatted digits at the trailing edge.
Keep the existing approval badge and completed hover-delete/shatter behavior.

- [ ] **Step 4: Build the three-row timeline in `CodexTasksContentView`**

Filter dismissed tasks, focus the first visible task, and render:

```swift
VStack(spacing: 5) {
    CodexStatusBarView(
        task: focusedTask,
        totalTokens: focusedTask?.totalTokens ?? snapshot.totalTokens,
        visibleTaskCount: taskRows.count,
        onDelete: { dismissFocusedTask() }
    )
    .frame(height: 54)

    sessionTimeline
}
```

Use the newest three progress events, local `HH:mm`, a restrained vertical
line, state dots, and trailing badges. Retain the current five-second Undo
overlay and do not construct a fake `CodexTaskStatus` when no task exists.

- [ ] **Step 5: Run the checks and confirm they pass**

Run: `swift run DynamicIslandCoreChecks`

Expected: `DynamicIslandCoreChecks passed`.

---

### Task 5: Integrate, visually verify, and record the project event

**Files:**
- Modify: `MEMORY.md`

**Interfaces:**
- Consumes: completed Tasks companion UI and rollout progress parser
- Produces: verified app bundle and rollback-ready project memory entry

- [ ] **Step 1: Run executable and diff verification**

Run:

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
git diff --check
./script/build_and_run.sh
```

Expected: Core checks pass, the executable builds, the diff has no whitespace
errors, and the main repository app launches.

- [ ] **Step 2: Capture and inspect the expanded Tasks UI**

Use the existing `ISLAND_DEBUG_PRIMARY_FEATURE_FRAME_CAPTURE_DIR` hook. Confirm
the 32pt pet and identity group align left, total tokens align right, all three
timeline rows stay within the content frame, and no content crosses the camera
housing or bottom rounded-corner guard.

- [ ] **Step 3: Verify live data and privacy**

Compare the displayed total with the current thread's read-only Codex state and
confirm timeline updates follow rollout event categories. Inspect source and
logs to confirm no raw prompt, response, arguments, tool output, paths, or
filenames are published.

- [ ] **Step 4: Sample settled CPU**

Sample the running process in both expanded Tasks and collapsed states. Expect
idle values in the project's normal low-single-digit range with no repeating
pet-render work.

- [ ] **Step 5: Add a concise newest-first `MEMORY.md` event**

Record reason, exact changed files, final behavior, verification evidence, and
the rollback boundary. Do not rewrite or remove the existing 2026-07-14 motion
events.
