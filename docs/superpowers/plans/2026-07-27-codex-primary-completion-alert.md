# Codex Primary Session Completion Triple Alert Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect each new successful primary Codex turn once, then emit one coalesced sequence of three closed-shell hover pulses and three macOS default alert sounds.

**Architecture:** `CodexStatusSignalSource` preserves an explicit terminal outcome in the existing Core task snapshot. A pure `CodexPrimaryCompletionTracker` establishes a startup baseline, excludes subagents and non-success outcomes, and returns the number of new primary completions in each snapshot. `IslandPanelController` owns the finite three-beat side effect, while `IslandOverlayState` and `IslandOverlayView` expose an independent pulse flag that reuses the existing hover geometry without mutating pointer hover.

**Tech Stack:** Swift 6 · SwiftPM · macOS 14+ · AppKit `NSSound` · SwiftUI · existing `DynamicIslandCoreChecks`

## Global Constraints

- Only successful primary sessions trigger feedback; subagents, aborted turns, cancelled turns, and failed turns never trigger it.
- The first non-empty Codex snapshot establishes a baseline and never alerts for historical completions.
- Several new primary completions in one snapshot produce one triple sequence.
- A new primary completion observed while a sequence is active is coalesced into that sequence; it does not restart, extend, or queue another sequence.
- Closed and visible shells receive three hover pulses plus three sounds; expanded or hidden shells receive sounds only and are never forced to change state.
- File-drop targeting and active/armed music-skip feedback are visual priorities; completion remains sound-only when either owns the shell.
- Use `NSSound.beep()` so macOS chooses the user's current default alert sound. Do not add bundled audio, TCC permissions, or dependencies.
- Pulse timing lives only in `IslandAnimationProfile.default`.
- Do not add a permanent timer, `repeatForever`, background animation, notification inbox, or completion persistence.
- Keep `DynamicIslandCore` free of AppKit and SwiftUI.
- Preserve the physical camera-housing exclusion and existing `IslandTopStatusBandLayout`.
- Logs contain only aggregate completion count, visual-enabled state, and beat count; never log titles, IDs, prompts, paths, or agent names.
- Every task uses RED → GREEN TDD and ends with `swift run DynamicIslandCoreChecks`, `swift build --product DynamicIsland`, and `git diff --check`.

---

### Task 1: Preserve explicit Codex terminal outcomes

**Files:**
- Modify: `Sources/DynamicIslandCore/CodexStatusBarSnapshot.swift:3-127`
- Modify: `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift:26-54`
- Modify: `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift:238-289`
- Modify: `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift:408-578`
- Test: `Tests/DynamicIslandCoreChecks/main.swift:406-915`

**Interfaces:**
- Consumes: existing `CodexTaskStatus`, rollout `task_complete`, `turn_aborted`, `turn_cancelled`, `turn_failed`, and app-server terminal methods.
- Produces: `CodexTurnTerminalOutcome`, `CodexTaskStatus.terminalOutcome`, and `RolloutState.terminalOutcome` for Task 2.

- [ ] **Step 1: Write failing outcome-model and parser contracts**

In `testCodexStatusBarContracts()`, add:

```swift
let successfulTerminalTask = CodexTaskStatus(
    id: "completed-primary",
    title: "Completed",
    activityState: .idle,
    turnID: "turn-completed",
    completedAt: 1_700_000_010,
    terminalOutcome: .completed
)
expectEqual(
    successfulTerminalTask.terminalOutcome,
    .completed,
    "Codex task snapshots preserve an explicit successful terminal outcome"
)
expectEqual(
    snapshot.contains("public enum CodexTurnTerminalOutcome"),
    true,
    "Core distinguishes successful, aborted, cancelled, and failed terminal turns"
)
expectEqual(
    signalSource.contains("var terminalOutcome: CodexTurnTerminalOutcome?"),
    true,
    "rollout state retains the explicit terminal outcome"
)
expectEqual(
    signalSource.contains("terminalOutcome: rolloutState?.terminalOutcome"),
    true,
    "terminal outcome reaches the Core task snapshot"
)
expectEqual(
    signalSource.contains("completeTurn(outcome: .completed"),
    true,
    "task_complete and turn/completed map to successful completion"
)
expectEqual(
    signalSource.contains("completeTurn(outcome: .aborted"),
    true,
    "aborted terminal events remain distinguishable"
)
expectEqual(
    signalSource.contains("completeTurn(outcome: .cancelled"),
    true,
    "cancelled terminal events remain distinguishable"
)
expectEqual(
    signalSource.contains("completeTurn(outcome: .failed"),
    true,
    "failed terminal events remain distinguishable"
)
let taskStartedSection = sourceSlice(
    signalSource,
    from: "case \"task_started\":",
    until: "case \"task_complete\":"
)
expectEqual(
    taskStartedSection.contains("state.terminalOutcome = nil"),
    true,
    "a new turn clears the previous terminal outcome"
)
expectEqual(
    taskStartedSection.contains("state.completedAt = nil"),
    true,
    "a new turn clears the previous completion timestamp"
)
```

- [ ] **Step 2: Run the Core checks and confirm RED**

Run:

```bash
swift run DynamicIslandCoreChecks
```

Expected: compilation fails because `terminalOutcome` and
`CodexTurnTerminalOutcome.completed` do not exist.

- [ ] **Step 3: Add the Core terminal model**

Above `CodexTaskStatus`, add:

```swift
public enum CodexTurnTerminalOutcome: String, Equatable, Sendable {
    case completed
    case aborted
    case cancelled
    case failed
}
```

Add to `CodexTaskStatus`:

```swift
public let terminalOutcome: CodexTurnTerminalOutcome?
```

Add the defaulted initializer parameter after `completedAt`:

```swift
terminalOutcome: CodexTurnTerminalOutcome? = nil,
```

Assign it:

```swift
self.terminalOutcome = terminalOutcome
```

- [ ] **Step 4: Propagate exact outcomes through the rollout parser**

Add to `RolloutState`:

```swift
var terminalOutcome: CodexTurnTerminalOutcome?
```

Pass it into `CodexTaskStatus`:

```swift
terminalOutcome: rolloutState?.terminalOutcome,
```

In `task_started`, clear prior terminal fields before entering `.running`:

```swift
state.completedAt = nil
state.durationMilliseconds = nil
state.terminalOutcome = nil
```

Replace each terminal call with an explicit outcome:

```swift
case "task_complete":
    completeTurn(outcome: .completed, payload: payload, event: event, state: &state)
case "turn_aborted":
    completeTurn(outcome: .aborted, payload: payload, event: event, state: &state)
case "turn_failed":
    completeTurn(outcome: .failed, payload: payload, event: event, state: &state)
case "turn_cancelled":
    completeTurn(outcome: .cancelled, payload: payload, event: event, state: &state)
```

Split the app-server combined case:

```swift
case "turn/completed":
    completeTurn(outcome: .completed, payload: payload, event: event, state: &state)
case "turn/aborted":
    completeTurn(outcome: .aborted, payload: payload, event: event, state: &state)
case "turn/cancelled":
    completeTurn(outcome: .cancelled, payload: payload, event: event, state: &state)
case "turn/failed":
    completeTurn(outcome: .failed, payload: payload, event: event, state: &state)
```

Change `completeTurn` to:

```swift
private func completeTurn(
    outcome: CodexTurnTerminalOutcome,
    payload: [String: Any],
    event: [String: Any],
    state: inout RolloutState
) {
    let completedAt = doubleValue(payload["completed_at"])
        ?? eventTimestamp(event)
        ?? Date().timeIntervalSince1970
    state.completedAt = completedAt
    state.terminalOutcome = outcome
    if let durationMilliseconds = intValue(payload["duration_ms"]) {
        state.durationMilliseconds = durationMilliseconds
    } else if let startedAt = state.startedAt {
        state.durationMilliseconds = max(0, Int(((completedAt - startedAt) * 1000).rounded()))
    }
    state.lifecycle = .terminal
    state.activityState = .idle
    state.approvalState = .none
    appendProgressEvent(
        kind: .completed,
        occurredAt: completedAt,
        displayText: completionProgressText(payload: payload, event: event),
        to: &state
    )
}
```

- [ ] **Step 5: Verify Task 1**

Run:

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
git diff --check
```

Expected: all exit `0`; existing completion copy and 10-second retention are
unchanged.

- [ ] **Step 6: Commit Task 1**

```bash
./script/safe_git_save.sh "feat: preserve Codex terminal outcomes" \
  Sources/DynamicIslandCore/CodexStatusBarSnapshot.swift \
  Sources/DynamicIsland/Support/CodexStatusSignalSource.swift \
  Tests/DynamicIslandCoreChecks/main.swift
```

---

### Task 2: Add the pure primary-completion tracker

**Files:**
- Create: `Sources/DynamicIslandCore/CodexPrimaryCompletionTracker.swift`
- Test: `Tests/DynamicIslandCoreChecks/main.swift:1084`
- Test: `Tests/DynamicIslandCoreChecks/main.swift:3581`

**Interfaces:**
- Consumes: `CodexTaskStatus.id`, `.isSubagent`, `.turnID`, `.completedAt`, and `.terminalOutcome` from Task 1.
- Produces: `CodexPrimaryCompletionTracker.init()` and `mutating func consume(_ tasks: [CodexTaskStatus]) -> Int` for Task 4.

- [ ] **Step 1: Write failing tracker behavior checks**

Add this test after `testCodexStatusBarContracts()`:

```swift
private func testCodexPrimaryCompletionTracker() {
    func task(
        id: String,
        turnID: String?,
        completedAt: TimeInterval?,
        outcome: CodexTurnTerminalOutcome?,
        parentThreadID: String? = nil
    ) -> CodexTaskStatus {
        CodexTaskStatus(
            id: id,
            title: id,
            activityState: outcome == nil ? .thinking : .idle,
            parentThreadID: parentThreadID,
            turnID: turnID,
            completedAt: completedAt,
            terminalOutcome: outcome
        )
    }

    var startupTracker = CodexPrimaryCompletionTracker()
    expectEqual(startupTracker.consume([]), 0, "an empty startup snapshot does not establish a false completion")
    expectEqual(
        startupTracker.consume([
            task(
                id: "historical",
                turnID: "old-turn",
                completedAt: 100,
                outcome: .completed
            )
        ]),
        0,
        "the first usable snapshot establishes a silent historical baseline"
    )

    var transitionTracker = CodexPrimaryCompletionTracker()
    let runningPrimary = task(
        id: "root",
        turnID: "turn-1",
        completedAt: nil,
        outcome: nil
    )
    let completedPrimary = task(
        id: "root",
        turnID: "turn-1",
        completedAt: 200,
        outcome: .completed
    )
    expectEqual(transitionTracker.consume([runningPrimary]), 0, "a working primary establishes a baseline")
    expectEqual(transitionTracker.consume([completedPrimary]), 1, "a new successful primary completion triggers once")
    expectEqual(transitionTracker.consume([completedPrimary]), 0, "the retained completion row never retriggers")

    let failedPrimary = task(
        id: "failed-root",
        turnID: "failed-turn",
        completedAt: 210,
        outcome: .failed
    )
    let completedSubagent = task(
        id: "child",
        turnID: "child-turn",
        completedAt: 211,
        outcome: .completed,
        parentThreadID: "root"
    )
    expectEqual(
        transitionTracker.consume([completedPrimary, failedPrimary, completedSubagent]),
        0,
        "failed primaries and successful subagents never trigger completion feedback"
    )

    var batchTracker = CodexPrimaryCompletionTracker()
    let runningA = task(id: "a", turnID: "a-1", completedAt: nil, outcome: nil)
    let runningB = task(id: "b", turnID: "b-1", completedAt: nil, outcome: nil)
    expectEqual(batchTracker.consume([runningA, runningB]), 0, "working primaries establish one usable baseline")
    let completedA = task(id: "a", turnID: "a-1", completedAt: 300, outcome: .completed)
    let completedB = task(id: "b", turnID: "b-1", completedAt: 301, outcome: .completed)
    expectEqual(batchTracker.consume([completedA, completedB, completedSubagent]), 2, "two primary completions form one count-two batch")
    expectEqual(batchTracker.consume([completedA, completedB]), 0, "the same batch remains deduplicated")
    let completedANextTurn = task(id: "a", turnID: "a-2", completedAt: 400, outcome: .completed)
    expectEqual(batchTracker.consume([completedANextTurn, completedB]), 1, "the same primary can complete a later turn")

    var timestampFallbackTracker = CodexPrimaryCompletionTracker()
    expectEqual(timestampFallbackTracker.consume([runningPrimary]), 0, "fallback tracker establishes a working baseline")
    let fallbackOne = task(id: "fallback", turnID: nil, completedAt: 500.125, outcome: .completed)
    let fallbackTwo = task(id: "fallback", turnID: nil, completedAt: 501.125, outcome: .completed)
    expectEqual(timestampFallbackTracker.consume([fallbackOne]), 1, "completedAt identifies a successful turn without turnID")
    expectEqual(timestampFallbackTracker.consume([fallbackOne]), 0, "the completedAt fallback deduplicates repeats")
    expectEqual(timestampFallbackTracker.consume([fallbackTwo]), 1, "a later completion timestamp creates a new identity")
}
```

Add this call before `testCodexAppServerApprovalContracts()`:

```swift
testCodexPrimaryCompletionTracker()
```

- [ ] **Step 2: Run Core checks and confirm RED**

```bash
swift run DynamicIslandCoreChecks
```

Expected: compilation fails with `cannot find 'CodexPrimaryCompletionTracker' in scope`.

- [ ] **Step 3: Implement the minimal pure tracker**

Create `Sources/DynamicIslandCore/CodexPrimaryCompletionTracker.swift`:

```swift
import Foundation

public struct CodexPrimaryCompletionTracker: Sendable {
    private var hasEstablishedBaseline = false
    private var observedCompletionKeys: Set<String> = []

    public init() {}

    public mutating func consume(_ tasks: [CodexTaskStatus]) -> Int {
        let primaryTasks = tasks.filter { !$0.isSubagent }
        guard !primaryTasks.isEmpty else { return 0 }

        let currentCompletionKeys = Set(
            primaryTasks.compactMap(\.successfulCompletionKey)
        )

        guard hasEstablishedBaseline else {
            hasEstablishedBaseline = true
            observedCompletionKeys.formUnion(currentCompletionKeys)
            return 0
        }

        let newCompletionKeys = currentCompletionKeys.subtracting(observedCompletionKeys)
        observedCompletionKeys.formUnion(currentCompletionKeys)
        return newCompletionKeys.count
    }
}

private extension CodexTaskStatus {
    var successfulCompletionKey: String? {
        guard terminalOutcome == .completed, let completedAt else { return nil }
        let turnComponent: String
        if let turnID, !turnID.isEmpty {
            turnComponent = "turn:\(turnID)"
        } else {
            turnComponent = "completed:\(Int((completedAt * 1000).rounded()))"
        }
        return "\(id):\(turnComponent)"
    }
}
```

- [ ] **Step 4: Verify Task 2**

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
git diff --check
```

Expected: all exit `0`; the tracker imports no UI framework.

- [ ] **Step 5: Commit Task 2**

```bash
./script/safe_git_save.sh "feat: track successful primary completions" \
  Sources/DynamicIslandCore/CodexPrimaryCompletionTracker.swift \
  Tests/DynamicIslandCoreChecks/main.swift
```

---

### Task 3: Add the independent completion hover pulse

**Files:**
- Modify: `Sources/DynamicIslandCore/IslandAnimationProfile.swift:3-102`
- Modify: `Sources/DynamicIsland/Views/IslandOverlayState.swift:34-65`
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift:128-152`
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift:673-705`
- Test: `Tests/DynamicIslandCoreChecks/main.swift:1940-2090`

**Interfaces:**
- Consumes: existing hover scale/shadow geometry and Reduce Motion environment.
- Produces: `IslandOverlayState.isCompletionHoverPulseActive`,
  `IslandAnimationProfile.completionFeedbackPulseActiveDuration`, and
  `IslandAnimationProfile.completionFeedbackBeatInterval` for Task 4.

- [ ] **Step 1: Write failing pulse/profile source contracts**

In `testCurrentShellSourceContracts()`, add:

```swift
let overlayStateSource = source("Sources/DynamicIsland/Views/IslandOverlayState.swift")
expectEqual(
    overlayStateSource.contains("@Published var isCompletionHoverPulseActive = false"),
    true,
    "completion feedback owns a state independent from pointer hover"
)
expectEqual(
    animationProfileSource.contains("public let completionFeedbackPulseActiveDuration: Double"),
    true,
    "completion pulse duration lives in the shared animation profile"
)
expectEqual(
    animationProfileSource.contains("public let completionFeedbackBeatInterval: Double"),
    true,
    "completion beat interval lives in the shared animation profile"
)
expectEqual(
    animationProfileSource.contains("completionFeedbackPulseActiveDuration: 0.18"),
    true,
    "completion hover remains briefly visible on each beat"
)
expectEqual(
    animationProfileSource.contains("completionFeedbackBeatInterval: 0.60"),
    true,
    "completion beats stay audibly and visually distinct"
)
expectEqual(
    overlay.contains("state.isCompletionHoverPulseActive"),
    true,
    "the closed shell can render an independent completion hover pulse"
)
expectEqual(
    overlay.contains("value: state.isCompletionHoverPulseActive"),
    true,
    "completion hover transitions use their own finite animation value"
)
expectEqual(
    overlay.contains("animationProfile.completionFeedbackPulseActiveDuration"),
    true,
    "the completion view reads shared pulse timing"
)
```

- [ ] **Step 2: Run Core checks and confirm RED**

```bash
swift run DynamicIslandCoreChecks
```

Expected: the new source contracts fail because the pulse state and timing do
not exist.

- [ ] **Step 3: Add centralized timing**

Add two stored properties and initializer parameters to `IslandAnimationProfile`:

```swift
public let completionFeedbackPulseActiveDuration: Double
public let completionFeedbackBeatInterval: Double
```

Assign them in `init`, and add to `.default`:

```swift
completionFeedbackPulseActiveDuration: 0.18,
completionFeedbackBeatInterval: 0.60,
```

- [ ] **Step 4: Add the independent overlay state and view gate**

Add to `IslandOverlayState`:

```swift
@Published var isCompletionHoverPulseActive = false
```

In `IslandOverlayView`, add:

```swift
private var showsCompletionHoverPulse: Bool {
    state.isCompletionHoverPulseActive && !isExpanded && !state.isShellHidden
}
```

Update `showsHoverPreview`:

```swift
private var showsHoverPreview: Bool {
    (
        state.isHovered
            || (state.isFileDropTargetActive && !isExpanded)
            || showsCompletionHoverPulse
    )
        && !isExpanded
        && !state.isShellHidden
}
```

Beside the existing hover animations, add:

```swift
.animation(
    .easeOut(
        duration: accessibilityReduceMotion
            ? animationProfile.reducedMotionFadeDuration
            : animationProfile.completionFeedbackPulseActiveDuration
    ),
    value: state.isCompletionHoverPulseActive
)
```

Do not change pointer hit testing, `isHovered`, shell expansion, file-drop
callbacks, or music-skip state.

- [ ] **Step 5: Verify Task 3**

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
git diff --check
```

Expected: all exit `0`; there is still no timer or `repeatForever` completion
path.

- [ ] **Step 6: Commit Task 3**

```bash
./script/safe_git_save.sh "feat: add completion hover pulse state" \
  Sources/DynamicIslandCore/IslandAnimationProfile.swift \
  Sources/DynamicIsland/Views/IslandOverlayState.swift \
  Sources/DynamicIsland/Views/IslandOverlayView.swift \
  Tests/DynamicIslandCoreChecks/main.swift
```

---

### Task 4: Schedule one coalesced three-beat alert

**Files:**
- Modify: `Sources/DynamicIsland/Controllers/IslandPanelController.swift:14-83`
- Modify: `Sources/DynamicIsland/Controllers/IslandPanelController.swift:193-214`
- Modify: `Sources/DynamicIsland/Controllers/IslandPanelController.swift:2099-2153`
- Test: `Tests/DynamicIslandCoreChecks/main.swift:406-1083`

**Interfaces:**
- Consumes: `CodexPrimaryCompletionTracker.consume(_:)` from Task 2 and the
  overlay/profile properties from Task 3.
- Produces: `startCodexCompletionFeedback(primaryCompletionCount:)`, exactly
  three `NSSound.beep()` beats, coalescing, and sanitized lifecycle logs.

- [ ] **Step 1: Write failing Controller contracts**

In `testCodexStatusBarContracts()`, derive:

```swift
let completionFeedbackSection = sourceSlice(
    controller,
    from: "private func startCodexCompletionFeedback(",
    until: "private func applyDebugMusicSignal"
)
```

Add:

```swift
expectEqual(
    controller.contains("private var codexPrimaryCompletionTracker = CodexPrimaryCompletionTracker()"),
    true,
    "the panel owns one completion baseline for its polling lifetime"
)
expectEqual(
    controller.contains("private var codexCompletionFeedbackTask: Task<Void, Never>?"),
    true,
    "the panel owns one cancellable finite completion sequence"
)
expectEqual(
    markersAppearInOrder(
        [
            "codexStatusSignalSource.currentSnapshot()",
            "codexPrimaryCompletionTracker.consume(snapshot.tasks)",
            "overlayState.codexStatusBarSnapshot = snapshot",
            "startCodexCompletionFeedback(primaryCompletionCount:"
        ],
        in: controller
    ),
    true,
    "polling detects a new primary completion before starting one coalesced sequence"
)
expectEqual(
    completionFeedbackSection.contains("guard codexCompletionFeedbackTask == nil else"),
    true,
    "an active triple sequence coalesces later completions"
)
expectEqual(
    controller.contains("private static let codexCompletionFeedbackBeatCount = 3"),
    true,
    "completion feedback has exactly three finite beats"
)
expectEqual(
    completionFeedbackSection.contains("for beatIndex in 0..<Self.codexCompletionFeedbackBeatCount"),
    true,
    "completion feedback iterates only the fixed beat count"
)
expectEqual(
    completionFeedbackSection.contains("NSSound.beep()"),
    true,
    "each completion beat uses the macOS default alert sound"
)
expectEqual(
    completionFeedbackSection.contains("animationProfile.completionFeedbackPulseActiveDuration"),
    true,
    "the controller uses shared pulse timing"
)
expectEqual(
    completionFeedbackSection.contains("animationProfile.completionFeedbackBeatInterval"),
    true,
    "the controller uses the shared beat interval"
)
expectEqual(
    completionFeedbackSection.contains("!isExpanded"),
    true,
    "expanded shells keep completion feedback sound-only"
)
expectEqual(
    completionFeedbackSection.contains("!overlayState.isShellHidden"),
    true,
    "hidden shells keep completion feedback sound-only"
)
expectEqual(
    completionFeedbackSection.contains("!overlayState.isFileDropTargetActive"),
    true,
    "file-drop feedback keeps visual priority"
)
expectEqual(
    completionFeedbackSection.contains("!overlayState.isMusicSkipArmed"),
    true,
    "armed music skip keeps visual priority"
)
expectEqual(
    completionFeedbackSection.contains("overlayState.musicSkipFeedbackDirection == nil"),
    true,
    "active music skip keeps visual priority"
)
expectEqual(
    completionFeedbackSection.contains("Timer"),
    false,
    "completion feedback does not install a timer"
)
expectEqual(
    completionFeedbackSection.contains("repeatForever"),
    false,
    "completion feedback never creates an infinite animation"
)
expectEqual(
    completionFeedbackSection.contains("\"codex.completion.feedback.started\""),
    true,
    "completion feedback logs a sanitized start"
)
expectEqual(
    completionFeedbackSection.contains("\"codex.completion.feedback.coalesced\""),
    true,
    "coalesced completions are observable without extra alerts"
)
expectEqual(
    completionFeedbackSection.contains("\"codex.completion.feedback.finished\""),
    true,
    "completion feedback logs finite cleanup"
)
for forbidden in ["\"threadID\"", "\"turnID\"", "\"title\"", "\"agent\""] {
    expectEqual(
        completionFeedbackSection.contains(forbidden),
        false,
        "completion feedback logs omit sensitive \(forbidden) metadata"
    )
}
expectEqual(
    controller.contains("codexCompletionFeedbackTask?.cancel()"),
    true,
    "controller teardown cancels completion feedback"
)
```

- [ ] **Step 2: Run Core checks and confirm RED**

```bash
swift run DynamicIslandCoreChecks
```

Expected: only the new Controller completion-feedback contracts fail.

- [ ] **Step 3: Add Controller state and polling integration**

Add:

```swift
private static let codexCompletionFeedbackBeatCount = 3
private var codexPrimaryCompletionTracker = CodexPrimaryCompletionTracker()
private var codexCompletionFeedbackTask: Task<Void, Never>?
```

Cancel the task in `deinit`:

```swift
codexCompletionFeedbackTask?.cancel()
```

After reading each snapshot, before publishing it, consume the task list:

```swift
let newPrimaryCompletionCount = codexPrimaryCompletionTracker.consume(snapshot.tasks)
```

After publishing the snapshot and handling approval state:

```swift
if newPrimaryCompletionCount > 0 {
    startCodexCompletionFeedback(
        primaryCompletionCount: newPrimaryCompletionCount
    )
}
```

- [ ] **Step 4: Implement the finite three-beat sequence**

Add immediately before `applyDebugMusicSignal`:

```swift
private func startCodexCompletionFeedback(primaryCompletionCount: Int) {
    guard primaryCompletionCount > 0 else { return }
    guard codexCompletionFeedbackTask == nil else {
        interactionLogger.log("codex.completion.feedback.coalesced", metadata: [
            "primaryCompletionCount": primaryCompletionCount
        ])
        return
    }

    let visualEnabled = !isExpanded
        && !overlayState.isShellHidden
        && !overlayState.isFileDropTargetActive
        && !overlayState.isMusicSkipArmed
        && overlayState.musicSkipFeedbackDirection == nil
    let pulseDuration = animationProfile.completionFeedbackPulseActiveDuration
    let restDuration = max(
        0,
        animationProfile.completionFeedbackBeatInterval - pulseDuration
    )

    interactionLogger.log("codex.completion.feedback.started", metadata: [
        "primaryCompletionCount": primaryCompletionCount,
        "visualEnabled": visualEnabled
    ])

    codexCompletionFeedbackTask = Task { [weak self] in
        var playedBeatCount = 0

        for beatIndex in 0..<Self.codexCompletionFeedbackBeatCount {
            guard let self, !Task.isCancelled else { break }
            if visualEnabled {
                self.overlayState.isCompletionHoverPulseActive = true
            }
            NSSound.beep()
            playedBeatCount += 1

            do {
                try await Task.sleep(
                    nanoseconds: UInt64(pulseDuration * 1_000_000_000)
                )
            } catch {
                break
            }

            guard let self else { return }
            self.overlayState.isCompletionHoverPulseActive = false

            guard beatIndex + 1 < Self.codexCompletionFeedbackBeatCount else {
                continue
            }
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(restDuration * 1_000_000_000)
                )
            } catch {
                break
            }
        }

        guard let self else { return }
        self.overlayState.isCompletionHoverPulseActive = false
        self.codexCompletionFeedbackTask = nil
        self.interactionLogger.log("codex.completion.feedback.finished", metadata: [
            "beatCount": playedBeatCount
        ])
    }
}
```

If Swift 6 reports an isolation or weak-self lifetime error, preserve the exact
behavior with a private `finishCodexCompletionFeedback(beatCount:)` MainActor
helper. Do not replace the finite task with a Timer or infinite animation.

- [ ] **Step 5: Verify Task 4**

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
git diff --check
```

Expected: all exit `0`; `git diff` contains only the Controller integration and
its source contracts.

- [ ] **Step 6: Commit Task 4**

```bash
./script/safe_git_save.sh "feat: alert on primary Codex completion" \
  Sources/DynamicIsland/Controllers/IslandPanelController.swift \
  Tests/DynamicIslandCoreChecks/main.swift
```

---

### Task 5: Run integration review and runtime acceptance

**Files:**
- Modify after successful runtime acceptance only: `MEMORY.md`
- Verify: all files changed by Tasks 1-4

**Interfaces:**
- Consumes: the completed feature from Tasks 1-4.
- Produces: verified packaged application behavior and one rollback-ready project memory event.

- [ ] **Step 1: Run fresh automated verification**

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
git diff --check 2d3fcb7..HEAD
```

Expected: all exit `0`.

- [ ] **Step 2: Build, sign, package, and cold-launch**

```bash
./script/build_and_run.sh
```

Then confirm:

```bash
island_pid=$(pgrep -x DynamicIsland | head -n 1)
ps -o pid,stat,pcpu,pmem,etime,command -p "$island_pid"
```

Expected: one healthy process running the application from this feature
worktree.

- [ ] **Step 3: Validate the runtime behavior**

Use a real primary Codex turn and confirm:

1. cold startup emits no completion sound or pulse for retained historical rows;
2. successful primary completion produces exactly three default sounds;
3. when the shell is closed and visible, the same three beats produce hover
   pulse feedback;
4. a subagent completion produces no sound and no pulse;
5. expanded or hidden completion does not change shell state and remains
   sound-only;
6. feedback state returns to false after the third beat.

Inspect the newest session JSONL and confirm it contains only sanitized
`codex.completion.feedback.started`, optional `coalesced`, and `finished`
metadata.

- [ ] **Step 4: Sample settled CPU**

```bash
island_pid=$(pgrep -x DynamicIsland | head -n 1)
for sample_index in 1 2 3 4 5 6 7 8 9 10; do
  ps -o pid=,stat=,pcpu=,pmem=,etime=,command= -p "$island_pid"
  sleep 1
done
```

Expected: transient polling or alert work settles; CPU does not remain high and
there is no continuing animation after the third beat.

- [ ] **Step 5: Request a final independent review**

Review the fixed range:

```bash
git diff --stat 2d3fcb7..HEAD
git diff 2d3fcb7..HEAD
```

The reviewer must check:

- success-only primary filtering;
- startup baseline and deduplication;
- subagent exclusion;
- exact fixed three-beat sequencing and active coalescing;
- hidden/expanded/drag/gesture priority;
- system-default sound API;
- no persistent timer or animation;
- privacy-safe logging;
- CoreChecks and runtime evidence.

Fix all Critical and Important findings, then rerun Steps 1-4.

- [ ] **Step 6: Record the accepted project event**

Only after the real completion sequence is heard and seen, add above the newest
event in `MEMORY.md`:

```md
### 2026-07-27 - primary-session-completion-triple-alert
- Reason: Successful primary Codex turns needed a short system-level completion signal without notifying for subagents or failed/cancelled turns.
- Changed:
  - `Sources/DynamicIslandCore/CodexStatusBarSnapshot.swift`
  - `Sources/DynamicIslandCore/CodexPrimaryCompletionTracker.swift`
  - `Sources/DynamicIslandCore/IslandAnimationProfile.swift`
  - `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayState.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
- Result: Each newly observed successful primary turn triggers one coalesced finite sequence of three hover pulses and three macOS default alert sounds. Startup history, subagents, aborted/cancelled/failed turns, and repeated polls do not alert. Expanded, hidden, file-drop, and music-skip states retain priority.
- Verify: RED/GREEN Core checks, the packaged app, real primary/subagent completion behavior, sanitized logs, and settled CPU sampling passed.
- Rollback: Remove the terminal outcome propagation, primary completion tracker, completion pulse state/profile values, and Controller feedback task. Preserve existing Tasks status parsing, normal hover, hidden priority, and all unrelated features.
```

- [ ] **Step 7: Commit the accepted runtime record**

```bash
./script/safe_git_save.sh "docs: record primary completion alert validation" MEMORY.md
```
