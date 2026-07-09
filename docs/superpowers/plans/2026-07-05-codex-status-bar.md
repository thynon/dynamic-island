# Codex Status Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a Claude-style Codex status bar inside the expanded debug calibration left safe region.

**Architecture:** Keep formatting and display policy in `DynamicIslandCore`, read local Codex state in the App layer, and render a compact SwiftUI view in the existing top status band contract. The Codex hook reads `~/.codex/state_5.sqlite` for thread metadata and the latest rollout JSONL for active turn timing/token/status events; it never writes raw conversation content to DynamicIsland logs.

**Tech Stack:** Swift 6, SwiftPM, AppKit, SwiftUI, local `/usr/bin/sqlite3`, JSONL parsing with `JSONSerialization`.

## Global Constraints

- DynamicIslandCore stays free of AppKit and SwiftUI imports.
- Top-band UI uses `IslandTopStatusBandLayout`; no hardcoded camera-housing overlap.
- Codex status polling is enabled only while calibration debug mode is visible.
- Logs must not include raw Codex prompts, transcript text, file paths, or thread titles.
- No new production dependencies or TCC permissions.

---

### Task 1: Core Snapshot And Layout Contract

**Files:**
- Create: `Sources/DynamicIslandCore/CodexStatusBarSnapshot.swift`
- Modify: `Sources/DynamicIslandCore/IslandTopStatusBandLayout.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**
- Produces: `CodexStatusBarSnapshot`, `CodexStatusBarSnapshot.ActivityState`, `formattedElapsedTime`, `formattedTokenCount`, `runningTasksText`.
- Produces: `IslandTopStatusBandLayout.codexStatusFrame(width:height:) -> CGRect`.

- [ ] Write failing core and source-contract checks.
- [ ] Run `swift run DynamicIslandCoreChecks` and confirm failure mentions missing Codex status types/frame.
- [ ] Add the snapshot model and top-band frame helper.
- [ ] Re-run `swift run DynamicIslandCoreChecks`.

### Task 2: Codex Local Status Source

**Files:**
- Create: `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift`
- Modify: `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
- Modify: `Sources/DynamicIsland/Views/IslandOverlayState.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**
- Produces: `CodexStatusSignalSource.currentSnapshot() -> CodexStatusBarSnapshot`.
- Consumes: `CodexStatusBarSnapshot` from Task 1.

- [ ] Write failing source-contract checks for sqlite thread metadata, rollout JSONL token/status parsing, calibration-only polling, and redacted logging.
- [ ] Run `swift run DynamicIslandCoreChecks` and confirm failure mentions missing source/polling.
- [ ] Implement the source with `/usr/bin/sqlite3`, thread metadata query, latest token_count event parsing, and active task timing.
- [ ] Wire controller polling only while calibration mode is visible.
- [ ] Re-run `swift run DynamicIslandCoreChecks`.

### Task 3: SwiftUI Status Bar In Green Safe Region

**Files:**
- Create: `Sources/DynamicIsland/Views/CodexStatusBarView.swift`
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**
- Consumes: `state.codexStatusBarSnapshot`.
- Produces: compact view with spinner, elapsed time, token count, running task count, and activity text.

- [ ] Write failing source-contract checks for `CodexStatusBarView` and `codexStatusFrame`.
- [ ] Run `swift run DynamicIslandCoreChecks` and confirm failure mentions missing view/placement.
- [ ] Implement the SwiftUI view using the extracted Claude status-bar behavior in native SwiftUI.
- [ ] Place it in `layout.leftStatusRegion` via `codexStatusFrame`.
- [ ] Run `swift run DynamicIslandCoreChecks`, `swift build --product DynamicIsland`, and debug launch.
