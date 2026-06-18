# File Shelf Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an in-memory, 24-hour temporary file shelf that opens when files are dragged to the Island notch area and can be reopened from a top-left safe-band `Files` button.

**Architecture:** Keep shelf data in `DynamicIslandCore` as pure value types, expose an in-memory app store in `Sources/DynamicIsland/Support`, and connect drag/drop through `IslandTrackingHostingView` plus `IslandPanelController`. `IslandOverlayView` owns only visual state and delegates shelf actions back to the controller.

**Tech Stack:** Swift 6, SwiftPM, AppKit dragging APIs, SwiftUI views, existing `DynamicIslandCoreChecks`.

---

### Task 1: Core Shelf Model

**Files:**
- Create: `Sources/DynamicIslandCore/TemporaryFileShelf.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

- [ ] Add failing checks for add, dedupe, remove, clear, and 24-hour expiry.
- [ ] Run `swift run DynamicIslandCoreChecks` and confirm the new types are missing.
- [ ] Add `TemporaryShelfItem` and `TemporaryFileShelf` in `DynamicIslandCore`.
- [ ] Run `swift run DynamicIslandCoreChecks` and confirm the checks pass.

### Task 2: App Store

**Files:**
- Create: `Sources/DynamicIsland/Support/TemporaryFileShelfStore.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

- [ ] Add source checks that the app store has no persistence file path or JSON write path.
- [ ] Run `swift run DynamicIslandCoreChecks` and confirm failure.
- [ ] Add a `@MainActor` in-memory store that maps file URLs into `TemporaryFileShelf`.
- [ ] Run `swift run DynamicIslandCoreChecks`.

### Task 3: Drag-And-Drop Entry Point

**Files:**
- Modify: `Sources/DynamicIsland/Views/IslandTrackingHostingView.swift`
- Modify: `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

- [ ] Add source checks for file pasteboard registration, delayed expansion, and cancellation on drag exit.
- [ ] Run `swift run DynamicIslandCoreChecks` and confirm failure.
- [ ] Register for `.fileURL`, detect file URLs, start a one-second hover task, expand to shelf overlay, and add dropped files.
- [ ] Run `swift run DynamicIslandCoreChecks`.

### Task 4: Overlay UI And Safe-Band Button

**Files:**
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift`
- Create: `Sources/DynamicIsland/Views/TemporaryFileShelfView.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

- [ ] Add source/layout checks for safe-band button placement and overlay precedence.
- [ ] Run `swift run DynamicIslandCoreChecks` and confirm failure.
- [ ] Add overlay state, render the `Files` button inside `leftStatusRegion` near the camera housing, and render the shelf view over the normal expanded content.
- [ ] Add open/remove/clear actions and click-to-open with `NSWorkspace`.
- [ ] Run `swift run DynamicIslandCoreChecks`.

### Task 5: Runtime Verification

**Files:**
- Modify: `MEMORY.md`

- [ ] Run `swift run DynamicIslandCoreChecks`.
- [ ] Run `swift build --product DynamicIsland`.
- [ ] Run `./script/build_and_run.sh`.
- [ ] Check Island process CPU with `ps`.
- [ ] Record the implementation in `MEMORY.md`.
