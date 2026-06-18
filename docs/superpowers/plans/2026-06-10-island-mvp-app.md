# Island MVP App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a runnable macOS MVP that shows a notch-aligned island shell and q-bouncy expansion effect on a 14-inch MacBook Pro.

**Architecture:** Use a SwiftPM macOS GUI app. AppKit owns the borderless top-center panel and screen-safe-area positioning; SwiftUI owns the animated island surface and demo content. A small `DynamicIslandCore` target holds display-derived metrics so the critical notch sizing logic is testable.

**Tech Stack:** Swift 6, SwiftPM, AppKit, SwiftUI, XCTest.

---

### Task 1: Package And Metric Tests

**Files:**
- Create: `Package.swift`
- Create: `Tests/DynamicIslandCoreChecks/NotchMetricsTests.swift`
- Create: `Sources/DynamicIslandCore/NotchMetrics.swift`

- [ ] **Step 1: Write failing tests for 14-inch notch metrics**

Create `Tests/DynamicIslandCoreChecks/NotchMetricsTests.swift` with tests that expect:
- local screen width `1512`, auxiliary areas `663` and `664`, safe top `32`
- camera housing width `185`
- closed shell width `245`
- open size `640×190`

- [ ] **Step 2: Run tests and verify the target is missing**

Run: `swift run DynamicIslandCoreChecks`

Expected: fail because the package/core target does not exist yet.

- [ ] **Step 3: Add SwiftPM package and metric model**

Create `Package.swift` with `DynamicIslandCore`, `DynamicIsland`, and `DynamicIslandCoreChecks`. Implement `NotchMetrics` with deterministic fallback values and a `fromDisplay` factory.

- [ ] **Step 4: Run tests and verify they pass**

Run: `swift run DynamicIslandCoreChecks`

Expected: all tests pass.

### Task 2: Native Panel Shell

**Files:**
- Create: `Sources/DynamicIsland/App/IslandMain.swift`
- Create: `Sources/DynamicIsland/Controllers/AppDelegate.swift`
- Create: `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
- Create: `Sources/DynamicIsland/Support/ScreenMetricsProvider.swift`

- [ ] **Step 1: Add AppKit entry point**

Create a SwiftPM GUI entry point that starts `NSApplication`, installs `AppDelegate`, sets accessory activation, and creates a status-bar quit menu.

- [ ] **Step 2: Add top-center borderless panel**

Create `IslandPanelController` using `NSPanel` with transparent background, status-bar level, and a fixed window size large enough for the expanded island.

- [ ] **Step 3: Read current screen metrics**

Use `NSScreen.safeAreaInsets.top` and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` to build `NotchMetrics`.

### Task 3: SwiftUI Island Effect

**Files:**
- Create: `Sources/DynamicIsland/Views/IslandOverlayView.swift`
- Create: `Sources/DynamicIsland/Views/IslandShape.swift`
- Create: compact shell subviews under `Sources/DynamicIsland/Views/`

- [ ] **Step 1: Add animatable notch shape**

Create a SwiftUI `Shape` with separate top and bottom corner radii, matching the Boring Notch-style rounded container.

- [ ] **Step 2: Add collapsed and expanded UI**

Collapsed state: `245×32`, center camera area empty, left slot empty, right slot shows a green dot. Expanded state: `640×190`, content starts below the 32-point camera housing, with high-contrast left and right demo slots.

- [ ] **Step 3: Add q-bouncy interaction**

Use `interactiveSpring(response: 0.38, dampingFraction: 0.8)` for hover and `spring(response: 0.42, dampingFraction: 0.8)` for toggle expansion.

### Task 4: Build And Run Entry

**Files:**
- Create: `script/build_and_run.sh`
- Create: `.codex/environments/environment.toml`
- Modify: `AGENTS.md`
- Modify: `MEMORY.md`
- Create/Modify: `.gitignore`

- [ ] **Step 1: Add build/run script**

Build with `swift build`, stage `dist/Dynamic Island.app`, generate `Info.plist`, launch with `/usr/bin/open -n`, and support `--verify`.

- [ ] **Step 2: Add Codex Run action**

Wire `.codex/environments/environment.toml` to `./script/build_and_run.sh`.

- [ ] **Step 3: Verify app build and launch**

Run:
- `swift test`
- `swift run DynamicIslandCoreChecks`
- `./script/build_and_run.sh --verify`

Expected: checks pass and `pgrep -x DynamicIsland` finds the running app. `swift test` is not used in this environment because the installed Swift toolchain does not expose XCTest or Swift Testing.

- [ ] **Step 4: Update project docs and memory**

Record the new SwiftPM app entry points and MVP status.
