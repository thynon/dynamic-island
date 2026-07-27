# Island Top Anchor and Data Aligned Drawer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the expanded island fixed to the screen top during Tasks disclosure resizing and make the Data range drawer a centered 72pt column directly below its trigger.

**Architecture:** Preserve the controller-owned adaptive panel sizing and all existing animations, but make `IslandOverlayView` fill its HostingView and top-leading align the animated fixed-size canvas. Independently reuse `triggerWidth` for the Data drawer and overlay the selected checkmark so every range label remains geometrically centered.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSPanel`/`NSHostingView`, macOS 14+ fallback materials, macOS 26 Liquid Glass, source-contract checks in `DynamicIslandCoreChecks`.

## Global Constraints

- Tasks disclosure must keep the island top edge, top 32pt band, Files button, and primary navigation fixed on every frame.
- Keep `CodexTasksAdaptiveLayout`, controller-owned panel resizing, the current height budget, and the local child-row transition unchanged.
- Preserve the controller order that grows `NSPanel` before the SwiftUI shell so the bottom is not clipped.
- The Data trigger remains exactly `72 × 24pt` with an `8pt` continuous radius, centered label, and fixed trailing double-chevron.
- The Data drawer uses the same `72pt` width and the same left and right edges as the trigger.
- Every Data option label is geometrically centered; the selected checkmark is a leading overlay that does not affect label layout.
- Do not keep a `Color.clear` placeholder for unselected options.
- Preserve the 5pt trigger-to-drawer gap, 12pt drawer radius, independent drawer identity, `.materialize` transition, and no explicit native-glass background.
- Preserve range selection, refresh, external click, `Escape`, feature switching, collapse, and hidden-state close semantics.
- Do not add timers, prewarming, continuous animation, dependencies, frameworks, permissions, or global input listeners.
- Do not change Tasks data, hierarchy, selection, Data queries, statistics, or time ranges.
- Preserve precise `IslandShape` hit testing, the top-band camera-housing contract, Reduce Motion, Reduce Transparency, and macOS 14/15 fallback behavior.

## File Map

- Modify `Sources/DynamicIsland/Views/IslandOverlayView.swift`: fill the HostingView and top-anchor the existing animated canvas.
- Modify `Sources/DynamicIsland/Views/DataPrimaryContentView.swift`: reuse `triggerWidth` for the drawer and center option labels independently of the checkmark.
- Modify `Tests/DynamicIslandCoreChecks/main.swift`: add failing source contracts for both fixes while retaining all existing interaction and glass contracts.
- Modify `MEMORY.md`: record the final verified geometry and rollback boundary only after real-pointer acceptance.

---

### Task 1: Pin the animated island canvas to the HostingView top

**Files:**
- Modify: `Tests/DynamicIslandCoreChecks/main.swift:1627-1636`
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift:449-485`

**Interfaces:**
- Consumes: existing `canvasWidth`, `canvasHeight`, `IslandOverlayView.body`, controller-owned `codexTasksDetailExpansionHeight`, and `IslandTrackingHostingView`.
- Produces: no new type or callback; the existing root canvas gains a stable HostingView-sized top-leading wrapper.

- [ ] **Step 1: Write the failing top-anchor source contract**

Add this assertion beside the existing stable primary-canvas checks:

```swift
expectEqual(
    overlay.contains(
        ".frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)\n        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"
    ),
    true,
    "the animated canvas fills its HostingView and remains pinned to the screen top during Tasks height changes"
)
```

Keep the existing assertions that require adaptive Tasks height, controller resizing, and
`.animation(tasksHeightAnimation, value: state.codexTasksDetailExpansionHeight)`.

- [ ] **Step 2: Run the core checks and confirm the new contract fails**

Run:

```bash
swift run DynamicIslandCoreChecks
```

Expected: FAIL only for “the animated canvas fills its HostingView and remains pinned to the screen top during Tasks height changes”.

- [ ] **Step 3: Top-anchor the existing fixed-size canvas**

At the end of `IslandOverlayView.body`, retain the existing canvas frame and add one outer fill frame:

```swift
.frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
```

Do not change `setCodexTasksDetailExpansionHeight(_:)`, `expandedWindowFrame`, `tasksHeightAnimation`, `CodexTasksAdaptiveLayout`, or the child-row transition.

- [ ] **Step 4: Run Task 1 verification**

Run:

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
git diff --check
```

Expected: all commands exit `0`; the diff contains only the new contract and one root-frame modifier.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
./script/safe_git_save.sh "fix: pin Tasks disclosure to island top" \
  Tests/DynamicIslandCoreChecks/main.swift \
  Sources/DynamicIsland/Views/IslandOverlayView.swift
```

Expected: one commit containing only Task 1.

---

### Task 2: Align and center the Data range drawer

**Files:**
- Modify: `Tests/DynamicIslandCoreChecks/main.swift:2379-2585`
- Modify: `Sources/DynamicIsland/Views/DataPrimaryContentView.swift:18-23`
- Modify: `Sources/DynamicIsland/Views/DataPrimaryContentView.swift:298-368`
- Modify: `Sources/DynamicIsland/Views/DataPrimaryContentView.swift:423-460`

**Interfaces:**
- Consumes: Task 1 without code dependency; existing `triggerWidth`, `drawerShape`, `timeRangeDrawerContent`, `selectedTimeRange`, native glass, fallback material, and drawer callbacks.
- Produces: no new public interface; both drawer paths use `triggerWidth`, and `timeRangeOption(_:)` uses centered overlay layout.

- [ ] **Step 1: Write the failing same-column and centered-option contracts**

Add or update these assertions in `testDataPrimaryContentViewContracts()`:

```swift
expectEqual(dataView.contains("private let drawerWidth"), false, "Data has no wider drawer constant that can overhang the trigger")
expectEqual(nativeControlsSection.contains(".frame(width: triggerWidth)"), true, "native drawer uses the exact trigger width")
expectEqual(fallbackControlsSection.contains(".frame(width: triggerWidth)"), true, "fallback drawer uses the exact trigger width")
expectEqual(optionSection.contains("ZStack"), true, "range options overlay selection decoration without shifting text")
expectEqual(optionSection.contains(".frame(maxWidth: .infinity, alignment: .center)"), true, "every range label is centered in the trigger-width column")
expectEqual(
    markersAppearInOrder(
        [
            "Image(systemName: \"checkmark\")",
            ".frame(maxWidth: .infinity, alignment: .leading)",
            ".accessibilityHidden(true)"
        ],
        in: optionSection
    ),
    true,
    "selected checkmark is a leading accessibility-hidden overlay"
)
expectEqual(optionSection.contains("HStack(spacing: 5)"), false, "range text is not offset by a horizontal marker layout")
expectEqual(optionSection.contains("Color.clear"), false, "unselected ranges do not reserve a fake leading marker")
```

Retain the existing `drawerGap`, offset, `.materialize`, independent identity, native-background, option-row glass, close-semantics, and selected-row background assertions.

- [ ] **Step 2: Run the core checks and confirm the new contracts fail**

Run:

```bash
swift run DynamicIslandCoreChecks
```

Expected: FAIL for the wider drawer constant, both `triggerWidth` drawer frames, the centered option layout, and removal of `Color.clear`.

- [ ] **Step 3: Remove the wider drawer width**

Delete:

```swift
private let drawerWidth: CGFloat = 104
```

In both `nativeLiquidGlassControls` and `fallbackControls`, change only the drawer frame:

```swift
.frame(width: triggerWidth)
```

Keep `.overlay(alignment: .topTrailing)` and:

```swift
.offset(
    x: -(controlHeight + controlSpacing),
    y: controlHeight + drawerGap
)
```

With equal widths, this existing right-edge anchor also aligns the left edges.

- [ ] **Step 4: Center option text independently of the selected checkmark**

Replace only the label layout in `timeRangeOption(_:)` with:

```swift
ZStack {
    Text(range.displayName)
        .frame(maxWidth: .infinity, alignment: .center)

    if range == selectedTimeRange {
        Image(systemName: "checkmark")
            .font(.system(size: 7, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }
}
.font(.system(size: 9.5, weight: range == selectedTimeRange ? .semibold : .medium, design: .rounded))
.foregroundStyle(
    range == selectedTimeRange
        ? Color(red: 0.48, green: 0.70, blue: 1)
        : controlForeground
)
.padding(.horizontal, 5)
.frame(height: controlHeight)
.contentShape(Rectangle())
```

Keep the existing Button action, `IslandPressButtonStyle`, and accessibility label unchanged.

- [ ] **Step 5: Run Task 2 verification**

Run:

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
git diff --check
```

Expected: all commands exit `0`; the drawer material, transition, identity, offset, gap, close paths, and trigger implementation are unchanged.

- [ ] **Step 6: Commit Task 2**

Run:

```bash
./script/safe_git_save.sh "fix: align Data drawer below range trigger" \
  Tests/DynamicIslandCoreChecks/main.swift \
  Sources/DynamicIsland/Views/DataPrimaryContentView.swift
```

Expected: one commit containing only Task 2.

---

### Task 3: Validate both runtime fixes and record the accepted result

**Files:**
- Modify: `MEMORY.md:90`
- Verify: `Sources/DynamicIsland/Views/IslandOverlayView.swift`
- Verify: `Sources/DynamicIsland/Views/DataPrimaryContentView.swift`

**Interfaces:**
- Consumes: Task 1 and Task 2 commits plus the existing packaging script.
- Produces: real-pointer runtime evidence, settled CPU evidence, and one rollback-focused project-memory event; no production interface.

- [ ] **Step 1: Build, package, and cold-launch**

Run:

```bash
./script/build_and_run.sh
```

Expected: build, signing, packaging, and launch succeed; `pgrep -x DynamicIsland` returns the new process from this worktree.

- [ ] **Step 2: Perform real-pointer Tasks acceptance**

On the freshly launched process:

1. Hover and expand the island.
2. In Tasks, expand and collapse a primary session containing one child at least five times.
3. Record the interaction at sufficient frame rate to compare the Files button, primary navigation, and shell top edge.

Accept only if the top edge and top-band controls remain fixed in every frame while the bottom edge grows downward and child rows animate locally. Reject if the whole canvas moves down then returns, if the bottom clips, or if transparent space captures pointer input.

- [ ] **Step 3: Perform real-pointer Data acceptance**

1. Open Data for the first time in the same cold process.
2. Hover and click the `72 × 24pt` trigger.
3. Confirm the drawer is exactly the same width with both vertical edges aligned.
4. Confirm all four labels are centered and the selected checkmark does not shift “今日”.
5. Select another range, reopen, and repeat open/close five times.
6. Test refresh, outside click, `Escape`, feature switch, and collapse.

Accept only if the first opening has no white flash or stall and all existing interaction behavior remains correct.

If Computer Use again returns `AXError.notImplemented` for the transparent nonactivating panel, preserve that evidence and obtain the recording from the user. Do not infer visual acceptance from source or build output.

- [ ] **Step 4: Sample settled process health**

After closing the drawer and leaving the app still, run:

```bash
island_pid=$(pgrep -x DynamicIsland | head -n 1)
for sample in 1 2 3 4 5 6 7 8 9 10; do
  ps -o pid,stat,pcpu,pmem,etime,command -p "$island_pid"
  sleep 1
done
```

Expected: the process remains healthy; transient polling activity may settle, but CPU must not remain elevated across the sample set.

- [ ] **Step 5: Add the verified project-memory event**

Only after both real-pointer checks pass, insert this event immediately above the newest existing event in `MEMORY.md`:

```markdown
### 2026-07-27 - top-anchored-tasks-and-aligned-data-drawer
- Reason: Real-pointer acceptance exposed a whole-island displacement during
  Tasks disclosure and a 32pt left overhang in the Data time-range drawer.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Views/DataPrimaryContentView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
- Result: The animated canvas now fills its HostingView and stays top-leading
  anchored while the adaptive Tasks shell grows downward. The Data drawer now
  shares the 72pt trigger width; each range label is centered and its selected
  checkmark is a non-layout leading overlay. Independent Liquid Glass
  materialization and all existing interaction semantics remain intact.
- Verify: `swift run DynamicIslandCoreChecks`, `swift build --product
  DynamicIsland`, `./script/build_and_run.sh`, repeated real-pointer Tasks and
  Data interactions, first-open white-flash review, and settled CPU sampling
  passed.
- Rollback: Revert the root HostingView fill frame and same-width option layout
  only; preserve adaptive Tasks sizing, the closed trigger, and the independent
  first-open Liquid Glass fix.
```

Do not write this success event while either visual check is pending.

- [ ] **Step 6: Re-run checks and commit the verified memory**

Run:

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
git diff --check
./script/safe_git_save.sh "docs: record anchored island and Data drawer verification" MEMORY.md
```

Expected: all verification commands exit `0`; the final commit contains only `MEMORY.md`.
