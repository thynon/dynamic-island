# File Shelf Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add simple File Shelf selection: click to select one item, click empty shelf area to clear, and drag a visible rectangle to select multiple visible items.

**Architecture:** Selection state lives in `IslandCore` as a small value model so removal and clear behavior can be tested without SwiftUI. `IslandOverlayState` carries selected IDs and passes selection callbacks into `TemporaryFileShelfView`. The SwiftUI view owns only pointer geometry for the active rectangle gesture and reports selected item IDs back through callbacks.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI gestures, `IslandCoreChecks`.

---

### Task 1: Core Selection State

**Files:**
- Modify: `Sources/IslandCore/TemporaryFileShelf.swift`
- Modify: `Tests/IslandCoreChecks/main.swift`

- [x] **Step 1: Write the failing test**

Add tests for a `TemporaryFileShelfSelection` value that can select one ID, clear selection, and remove stale IDs when shelf items are removed or cleared.

- [x] **Step 2: Run test to verify it fails**

Run: `swift run IslandCoreChecks`
Expected: FAIL because `TemporaryFileShelfSelection` does not exist.

- [x] **Step 3: Write minimal implementation**

Add `TemporaryFileShelfSelection` with `selectedItemIDs`, `selectOnly(_:)`, `clear()`, and `retainOnly(itemIDs:)`.

- [x] **Step 4: Run test to verify it passes**

Run: `swift run IslandCoreChecks`
Expected: PASS.

### Task 2: Overlay State And Selection Sync

**Files:**
- Modify: `Sources/Island/Controllers/IslandPanelController.swift`
- Modify: `Sources/Island/Views/IslandOverlayView.swift`
- Modify: `Tests/IslandCoreChecks/main.swift`

- [x] **Step 1: Write the failing test**

Add source checks that overlay state carries `fileShelfSelectedItemIDs`, controller has select/clear callbacks, and remove/clear operations sync selection.

- [x] **Step 2: Run test to verify it fails**

Run: `swift run IslandCoreChecks`
Expected: FAIL because selected IDs are not wired.

- [x] **Step 3: Write minimal implementation**

Add selected IDs to overlay state and controller. When one item is selected, store only that ID. When empty area is clicked, clear selection. When item list changes, retain only existing IDs.

- [x] **Step 4: Run test to verify it passes**

Run: `swift run IslandCoreChecks`
Expected: PASS.

### Task 3: Click Selection And Stable Highlight

**Files:**
- Modify: `Sources/Island/Views/TemporaryFileShelfView.swift`
- Modify: `Tests/IslandCoreChecks/main.swift`

- [x] **Step 1: Write the failing test**

Add source checks that `TemporaryFileShelfView` receives `selectedItemIDs`, calls `onSelectItem`, calls `onClearSelection`, and renders `isSelected` without changing tile frame size.

- [x] **Step 2: Run test to verify it fails**

Run: `swift run IslandCoreChecks`
Expected: FAIL because the view has no selection API.

- [x] **Step 3: Write minimal implementation**

Pass selected IDs into the view, add click/tap selection on each tile, add empty-space clear on the shelf boundary, and render selected tile highlight using overlay/fill only.

- [x] **Step 4: Run test to verify it passes**

Run: `swift run IslandCoreChecks`
Expected: PASS.

### Task 4: Rectangle Selection

**Files:**
- Modify: `Sources/Island/Views/TemporaryFileShelfView.swift`
- Modify: `Tests/IslandCoreChecks/main.swift`

- [x] **Step 1: Write the failing test**

Add source checks for `selectionDragThreshold = 5`, `selectionRect`, `shelfItemFrames`, `GeometryReader`, `DragGesture`, and no auto-scroll implementation.

- [x] **Step 2: Run test to verify it fails**

Run: `swift run IslandCoreChecks`
Expected: FAIL because rectangle selection is not implemented.

- [x] **Step 3: Write minimal implementation**

Track item frames in a named coordinate space. A drag starting in empty shelf area begins rectangle selection only after movement reaches `5pt`. Select visible item IDs whose frames intersect the rectangle. Show a translucent selection rectangle. Do not auto-scroll.

- [x] **Step 4: Run test to verify it passes**

Run: `swift run IslandCoreChecks`
Expected: PASS.

### Task 5: Verification And Memory

**Files:**
- Modify: `MEMORY.md`

- [x] **Step 1: Build and run checks**

Run:

```bash
swift run IslandCoreChecks
swift build --product Island
./script/build_and_run.sh
```

Expected: all succeed.

- [x] **Step 2: Check process health**

Run:

```bash
pid=$(pgrep -x Island | head -n 1)
ps -o pid,stat,pcpu,pmem,etime,command -p "$pid"
```

Expected: Island is running without sustained high CPU.

- [x] **Step 3: Record project memory**

Append a dated entry to `MEMORY.md` summarizing Phase 2 selection behavior, verification, and rollback.
