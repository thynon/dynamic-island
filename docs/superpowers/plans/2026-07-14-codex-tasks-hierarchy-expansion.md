# Codex Tasks Hierarchy and Adaptive Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans and superpowers:test-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Group subagents under their primary Codex session and let one group extend the expanded Island downward without clipping, layout compression, or hit-test mismatch.

**Architecture:** Extend `CodexTaskStatus` with sanitized hierarchy metadata, query primary threads separately from a bounded recursive descendant set, and render a stable master-detail accordion in Tasks. A pure Core height contract supplies one extra-height value shared by SwiftUI layout, the AppKit panel canvas, and precise shell hit testing.

**Tech Stack:** Swift 6, SwiftPM, Foundation, SQLite JSON1 through `/usr/bin/sqlite3`, SwiftUI, AppKit, existing Core/source-contract checks.

## Global Constraints

- Keep the base expanded shell at 850×200 points and the top 32-point camera-safe band unchanged.
- Allow only one primary-session group to open at a time.
- Use fixed 26-point agent rows, show up to five rows through shell growth, and cap extra height at 140 points; overflow scrolls locally.
- Keep Codex SQLite and rollout JSONL read-only and never expose raw prompts, task instructions, paths, arguments, or tool output.
- Preserve approval, dismissal, Undo, completion retention, stale cutoff, polling cadence, Files, music, and gesture behavior.
- Add no dependency, permission, persistence, continuous animation, or polling loop.
- Preserve unrelated dirty-worktree changes and do not stage or commit automatically.

---

### Task 1: Model hierarchy and adaptive height in Core

**Files:**
- Create: `Sources/DynamicIslandCore/CodexTasksAdaptiveLayout.swift`
- Modify: `Sources/DynamicIslandCore/CodexStatusBarSnapshot.swift`
- Modify: `Sources/DynamicIslandCore/IslandPrimaryContentLayout.swift`
- Test: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**
- Produces: `CodexTaskStatus.parentThreadID`, `rootThreadID`, `agentNickname`, `agentDepth`, `isSubagent`
- Produces: `CodexTasksAdaptiveLayout.extraHeight(agentCount:)`, `maximumExtraHeight`
- Produces: `IslandPrimaryContentLayout.init(metrics:shellHeight:)`

- [ ] Write failing Core checks for root/subagent identity, nickname fallback, 0/1/5/8-agent height values, and a taller Tasks content frame.
- [ ] Run `swift run DynamicIslandCoreChecks`; expect compilation/assertion failure because the new interfaces do not exist.
- [ ] Add the minimal immutable hierarchy fields and pure height/layout calculations.
- [ ] Re-run `swift run DynamicIslandCoreChecks`; expect `DynamicIslandCoreChecks passed`.

### Task 2: Query primary sessions and descendants without flat mixing

**Files:**
- Modify: `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift`
- Test: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**
- Consumes: the Task 1 hierarchy fields
- Produces: eight bounded root records plus up to 24 recursively related agent records with immediate and root IDs

- [ ] Add failing source-contract checks for `thread_source`, `parent_thread_id`, `root_thread_id`, `agent_nickname`, recursive `agent_tree`, separate limits 8 and 24, and absence of the old `LIMIT 4`.
- [ ] Run Core checks; expect failure on the missing hierarchy query.
- [ ] Replace only `readLatestThreadRecords()` and its record mapping; keep rollout parsing, caching, retention, and approval logic unchanged.
- [ ] Prefer the first non-subagent as the snapshot primary task and pass hierarchy metadata into every visible status.
- [ ] Re-run Core checks; expect pass.

### Task 3: Render stable primary groups and subagent disclosure

**Files:**
- Modify: `Sources/DynamicIsland/Views/CodexTasksContentView.swift`
- Modify: `Sources/DynamicIsland/Views/CodexStatusBarView.swift`
- Modify: `Sources/DynamicIsland/Views/IslandOverlayState.swift`
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift`
- Test: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**
- Produces: stable selected root/agent state, one open group, fixed rows, disclosure control, local scrolling, and `onExpansionHeightChange(CGFloat)`

- [ ] Add failing checks for root-only top-level rows, `chevron.down`, one `expandedRootID`, agent indentation/depth, persistent selection, five-row height cap, and detail switching.
- [ ] Run Core checks; expect failure on the absent master-detail UI.
- [ ] Implement the left primary-session list and selected right detail without changing the existing summary/timeline privacy or dismissal behavior.
- [ ] Reset the open group when Tasks becomes inactive and recompute height when the selected group's visible agent count changes.
- [ ] Re-run Core checks; expect pass.

### Task 4: Synchronize visible shell, panel canvas, and hit testing

**Files:**
- Modify: `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**
- Consumes: `IslandOverlayState.codexTasksDetailExpansionHeight`
- Produces: `setCodexTasksDetailExpansionHeight(_:)` and dynamic expanded window size

- [ ] Add failing checks that the same extra height feeds shell height, dynamic primary-content layout, `windowSize`, and `currentShellHeightForHitTesting`.
- [ ] Run Core checks; expect failure because the panel remains fixed at 200 points.
- [ ] Grow the transparent canvas before shell expansion, delay canvas shrink until shell collapse settles, and reset detail height on Tasks exit/outer collapse.
- [ ] Re-run Core checks; expect pass.

### Task 5: Launch and verify the real interaction

**Files:**
- Modify: `MEMORY.md`

**Interfaces:**
- Produces: a runnable local app with verified hierarchy, motion, hit testing, and bounded CPU

- [ ] Run `swift run DynamicIslandCoreChecks`, `swift build --product DynamicIsland`, and `git diff --check`.
- [ ] Run `./script/build_and_run.sh` and inspect only the Island app/capture hook.
- [ ] Confirm roots stay top-level, one group expands, nested agents stay grouped, the top edge stays fixed, and all expanded pixels accept pointer input.
- [ ] Switch away from Tasks and collapse the Island; confirm the shell returns to 200 points.
- [ ] Sample settled CPU and report exact evidence without staging or committing.
- [ ] Add a newest-first project event with reason, changed files, verification, risk, and rollback instructions.
