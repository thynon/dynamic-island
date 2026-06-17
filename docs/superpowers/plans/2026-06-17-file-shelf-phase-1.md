# File Shelf Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Group temporary shelf files by type and show a persistent dashed shelf boundary.

**Architecture:** File type classification lives in `IslandCore` so it is testable without UI dependencies. `TemporaryFileShelfView` renders only non-empty category sections inside one dashed rounded shelf range, while preserving existing Open, Remove, Clear, and drag-out behavior.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, AppKit file icons, `IslandCoreChecks`.

---

### Task 1: Core File Category Model

**Files:**
- Modify: `Sources/IslandCore/TemporaryFileShelf.swift`
- Modify: `Tests/IslandCoreChecks/main.swift`

- [x] **Step 1: Write the failing test**

Add checks that `.png`, `.xlsx`, `.pptx`, `.key`, `.pdf`, and unknown extensions map to the expected shelf categories.

- [x] **Step 2: Run test to verify it fails**

Run: `swift run IslandCoreChecks`
Expected: FAIL because `TemporaryShelfFileCategory` and `category` do not exist yet.

- [x] **Step 3: Write minimal implementation**

Add `TemporaryShelfFileCategory` and derive each `TemporaryShelfItem.category` from the normalized lowercase extension.

- [x] **Step 4: Run test to verify it passes**

Run: `swift run IslandCoreChecks`
Expected: PASS.

### Task 2: Grouped Shelf Rendering And Dashed Bounds

**Files:**
- Modify: `Sources/Island/Views/TemporaryFileShelfView.swift`
- Modify: `Tests/IslandCoreChecks/main.swift`

- [x] **Step 1: Write the failing test**

Add source checks that the view references `TemporaryShelfFileCategory`, renders category counts, uses `groupedItems`, and applies a dashed `StrokeStyle` around the non-empty shelf body.

- [x] **Step 2: Run test to verify it fails**

Run: `swift run IslandCoreChecks`
Expected: FAIL because the current view renders one mixed grid and has no non-empty dashed shelf bounds.

- [x] **Step 3: Write minimal implementation**

Group items by category order: Images, Documents, Spreadsheets, Presentations, Other. Render only non-empty groups, show title and count, and keep the existing tile layout/actions inside a dashed rounded boundary.

- [x] **Step 4: Run test to verify it passes**

Run: `swift run IslandCoreChecks`
Expected: PASS.

### Task 3: Verification And Memory

**Files:**
- Modify: `MEMORY.md`

- [x] **Step 1: Build the app**

Run: `swift build --product Island`
Expected: build succeeds.

- [x] **Step 2: Restart the app**

Run: `./script/build_and_run.sh`
Expected: build/sign/package/start succeeds.

- [x] **Step 3: Check process health**

Run:

```bash
pid=$(pgrep -x Island | head -n 1)
ps -o pid,stat,pcpu,pmem,etime,command -p "$pid"
```

Expected: Island is running without sustained high CPU.

- [x] **Step 4: Record project memory**

Append a dated entry to `MEMORY.md` with what Phase 1 changed, verification results, and rollback notes.
