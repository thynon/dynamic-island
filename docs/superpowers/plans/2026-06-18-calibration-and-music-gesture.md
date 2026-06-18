# Calibration And Music Gesture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a hidden notch/no-notch calibration overlay and route horizontal music skip feedback through a single cancellable state machine.

**Architecture:** Pure layout and gesture rules live in `DynamicIslandCore`. `IslandPanelController` maps AppKit scroll events into the core gesture machine and exposes simple overlay state. `IslandOverlayView` renders the calibration marks when the debug flag is enabled.

**Tech Stack:** SwiftPM, Swift 6, DynamicIslandCore, AppKit, SwiftUI.

---

### Task 1: Core Contracts

**Files:**
- Create: `Sources/DynamicIslandCore/IslandCalibrationLayout.swift`
- Create: `Sources/DynamicIslandCore/MusicSkipGestureStateMachine.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

- [ ] Add failing core checks for calibration layout and gesture state transitions.
- [ ] Run `swift run DynamicIslandCoreChecks` and confirm the new checks fail.
- [ ] Implement `IslandCalibrationLayout`.
- [ ] Implement `MusicSkipGestureStateMachine`.
- [ ] Run `swift run DynamicIslandCoreChecks` and confirm the checks pass.

### Task 2: Calibration UI

**Files:**
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift`
- Modify: `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
- Modify: `script/build_and_run.sh`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

- [ ] Add failing source-contract checks for `ISLAND_DEBUG_CALIBRATION`, `CalibrationOverlayView`, and build script support.
- [ ] Run `swift run DynamicIslandCoreChecks` and confirm the checks fail.
- [ ] Add calibration state to `IslandOverlayState`.
- [ ] Render `CalibrationOverlayView` inside the clipped shell.
- [ ] Add `--debug-calibration` to the launch script.
- [ ] Run `swift run DynamicIslandCoreChecks`.

### Task 3: Controller Gesture Integration

**Files:**
- Modify: `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

- [ ] Add failing source-contract checks that the controller owns `MusicSkipGestureStateMachine` and no longer owns separate horizontal skip direction and pending direction variables.
- [ ] Run `swift run DynamicIslandCoreChecks` and confirm the checks fail.
- [ ] Replace the horizontal skip booleans with the core state machine.
- [ ] Keep vertical and hidden-state behavior unchanged.
- [ ] Run `swift run DynamicIslandCoreChecks`.

### Task 4: Full Verification

**Files:**
- Modify: `MEMORY.md`

- [ ] Run `swift build --product DynamicIsland`.
- [ ] Run `./script/build_and_run.sh --verify`.
- [ ] Launch `./script/build_and_run.sh --debug-calibration` and capture a screenshot.
- [ ] Launch `./script/build_and_run.sh`.
- [ ] Check the DynamicIsland process CPU.
- [ ] Record the change and verification in `MEMORY.md`.
