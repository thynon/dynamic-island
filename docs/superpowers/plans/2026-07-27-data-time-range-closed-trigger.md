# Data Time Range Closed Trigger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Data time-range capsule with the approved closed rounded-rectangle selector while preserving the existing Liquid Glass menu and cold-first-open fix.

**Architecture:** Keep `DataPrimaryContentView` as the only UI owner of this visual change. Reuse one `triggerShape` for native glass clipping, fallback rendering, and hit testing; render the current value in the geometric center and overlay a fixed trailing double-chevron so the icon cannot shift the text.

**Tech Stack:** Swift 6, SwiftUI, AppKit-hosted macOS 14+ application, macOS 26 Liquid Glass availability path, source-contract checks in `DynamicIslandCoreChecks`.

## Global Constraints

- The trigger remains exactly `72 × 24pt`.
- The trigger is a continuous rounded rectangle with an `8pt` corner radius, not a capsule.
- The current range text is geometrically centered in the whole trigger.
- The trigger has no leading circle, color marker, gradient, or other leading icon.
- A fixed up/down double-chevron occupies the trailing area and is hidden from accessibility.
- macOS 26 continues to use `.glassEffect(.regular.interactive())` with no explicit background, fill, or Material under the trigger.
- macOS 14/15 and Reduce Transparency keep the existing fallback behavior, clipped to the same trigger shape.
- The independent drawer, `.materialize` transition, range selection, refresh, close semantics, and all Data query behavior remain unchanged.
- Do not add state, timers, prewarming, continuous animation, dependencies, frameworks, or permissions.
- Shared animation timing remains owned by `IslandAnimationProfile.default`; this change adds no timing value.
- Preserve the top 32pt status-band and camera-housing layout contracts.

## File Map

- Modify `Sources/DynamicIsland/Views/DataPrimaryContentView.swift`: define the shared trigger shape and render the approved closed selector.
- Modify `Tests/DynamicIslandCoreChecks/main.swift`: replace the old capsule contract and lock the new shape, centered label, fixed double-chevron, and no-leading-marker requirements.
- Modify `MEMORY.md`: record the final UI decision and verified rollback boundary after runtime acceptance.

---

### Task 1: Implement the closed Data time-range trigger

**Files:**
- Modify: `Tests/DynamicIslandCoreChecks/main.swift:2379-2566`
- Modify: `Sources/DynamicIsland/Views/DataPrimaryContentView.swift:18-27`
- Modify: `Sources/DynamicIsland/Views/DataPrimaryContentView.swift:294-400`

**Interfaces:**
- Consumes: existing `selectedTimeRange`, `isTimeRangeDrawerPresented`, `setDrawerPresented(_:)`, `controlForeground`, `fallbackBackground(_:)`, and `IslandPressButtonStyle`.
- Produces: `private var triggerShape: RoundedRectangle`; the existing `timeRangeTrigger` remains a `some View` property with the same callbacks and accessibility label.

- [ ] **Step 1: Replace the capsule assertions with failing closed-trigger contracts**

In `testDataPrimaryContentViewContracts()`, replace the native capsule assertion and its ordering marker:

```swift
expectEqual(dataView.contains("private var triggerShape: RoundedRectangle"), true, "Data centralizes the closed trigger shape")
expectEqual(dataView.contains("RoundedRectangle(cornerRadius: 8, style: .continuous)"), true, "time trigger uses the approved 8pt continuous radius")
expectEqual(nativeControlsSection.contains(".glassEffect(.regular.interactive(), in: triggerShape)"), true, "time trigger uses interactive closed-shape glass")
```

Change the native ordering marker from:

```swift
".glassEffect(.regular.interactive(), in: Capsule"
```

to:

```swift
".glassEffect(.regular.interactive(), in: triggerShape)"
```

Add these assertions beside the existing trigger and fallback contracts:

```swift
expectEqual(triggerSection.contains("ZStack"), true, "time trigger overlays its trailing affordance without shifting the centered value")
expectEqual(triggerSection.contains(".frame(maxWidth: .infinity, alignment: .center)"), true, "current range is geometrically centered")
expectEqual(triggerSection.contains("Image(systemName: \"chevron.up.chevron.down\")"), true, "time trigger uses a fixed up-down selector affordance")
expectEqual(triggerSection.contains("isTimeRangeDrawerPresented ? \"chevron.up\" : \"chevron.down\""), false, "time trigger no longer swaps a single chevron")
expectEqual(triggerSection.contains(".frame(maxWidth: .infinity, alignment: .trailing)"), true, "double chevron owns the trailing area")
expectEqual(triggerSection.contains(".accessibilityHidden(true)"), true, "decorative double chevron is hidden from accessibility")
expectEqual(triggerSection.contains("Circle()"), false, "time trigger has no leading circle marker")
expectEqual(triggerSection.contains("LinearGradient"), false, "time trigger has no leading color gradient")
expectEqual(triggerSection.contains(".contentShape(triggerShape)"), true, "time trigger hit testing follows the closed shape")
expectEqual(fallbackControlsSection.contains("fallbackBackground(triggerShape)"), true, "fallback trigger uses the shared closed shape")
expectEqual(fallbackControlsSection.contains("triggerShape\n                        .stroke"), true, "fallback trigger stroke uses the shared closed shape")
```

- [ ] **Step 2: Run the core checks and confirm the new contracts fail**

Run:

```bash
swift run DynamicIslandCoreChecks
```

Expected: FAIL messages for the new `triggerShape`, centered `ZStack`, fixed double-chevron, and fallback-shape assertions, plus the replaced native glass assertion.

- [ ] **Step 3: Add one shared continuous rounded-rectangle shape**

In `DataPrimaryContentView`, place this next to `drawerShape`:

```swift
private var triggerShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
}
```

Do not change `triggerWidth`, `controlHeight`, `controlSpacing`, `drawerGap`, or `drawerShape`.

- [ ] **Step 4: Apply the shared shape to native glass and fallback rendering**

Change the native trigger modifier to:

```swift
timeRangeTrigger
    .glassEffect(.regular.interactive(), in: triggerShape)
    .glassEffectID(DataGlassEffectID.trigger, in: glassNamespace)
```

Change only the trigger portion of `fallbackControls` to:

```swift
timeRangeTrigger
    .background {
        fallbackBackground(triggerShape)
    }
    .overlay(
        triggerShape
            .stroke(fallbackStrokeColor, lineWidth: colorSchemeContrast == .increased ? 1 : 0.7)
    )
    .shadow(color: .black.opacity(0.24), radius: 4, y: 2)
```

Leave the circular refresh button and `drawerShape` unchanged.

- [ ] **Step 5: Center the current value and overlay the fixed double-chevron**

Replace only the label body of `timeRangeTrigger` with:

```swift
ZStack {
    Text(selectedTimeRange.displayName)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .center)

    Image(systemName: "chevron.up.chevron.down")
        .font(.system(size: 7, weight: .bold))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 7)
        .accessibilityHidden(true)
}
.font(.system(size: 9.5, weight: .semibold, design: .rounded))
.foregroundStyle(controlForeground)
.frame(width: triggerWidth, height: controlHeight)
.contentShape(triggerShape)
```

Keep the existing Button action, `IslandPressButtonStyle`, help text, and accessibility label unchanged.

- [ ] **Step 6: Run focused verification**

Run:

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
git diff --check
```

Expected: all commands exit `0`; no Data drawer, refresh, range-selection, or unrelated source changes appear in the diff.

- [ ] **Step 7: Commit the implementation**

Run:

```bash
./script/safe_git_save.sh "fix: close Data time range trigger" \
  Tests/DynamicIslandCoreChecks/main.swift \
  Sources/DynamicIsland/Views/DataPrimaryContentView.swift
```

Expected: one commit containing only the source-contract and trigger-view changes.

---

### Task 2: Validate cold interaction and record the final decision

**Files:**
- Modify: `MEMORY.md:90`
- Verify: `Sources/DynamicIsland/Views/DataPrimaryContentView.swift`

**Interfaces:**
- Consumes: the Task 1 commit and the existing `script/build_and_run.sh` packaging path.
- Produces: runtime evidence for the closed trigger and one rollback-focused project-memory event; no new production interface.

- [ ] **Step 1: Build, sign, package, and cold-launch the app**

Run:

```bash
./script/build_and_run.sh
```

Expected: Swift build, signing, packaging, and app launch succeed; `pgrep -x DynamicIsland` returns a process.

- [ ] **Step 2: Exercise the exact cold interaction path**

On the freshly launched process:

1. Hover the island for the first time and expand it.
2. Open the Data page for the first time.
3. Hover the closed time-range trigger.
4. Click it once to open the drawer, choose another range, then reopen it.
5. Repeat open and close five times.

Accept only if:

- the closed trigger is a compact rounded rectangle with no left marker;
- the current value stays visually centered;
- the fixed double-chevron remains at the right without shifting the label;
- hover and press retain the existing interactive Liquid Glass effect;
- the first drawer presentation has no white flash;
- neither first hover nor first click visibly stalls;
- the trigger does not resize, disappear, or morph into the drawer;
- the independent drawer, refresh button, selection, and closing behavior still work.

If UI automation cannot click the transparent nonactivating panel, record that limitation and obtain this visual interaction check from the user; do not report visual acceptance from build output alone.

- [ ] **Step 3: Sample settled process health**

After closing the drawer and leaving the page still, run:

```bash
island_pid=$(pgrep -x DynamicIsland | head -n 1)
for sample in 1 2 3 4 5; do
  ps -o pid,stat,pcpu,pmem,etime,command -p "$island_pid"
  sleep 1
done
```

Expected: the process remains healthy and CPU does not stay elevated across all five settled samples. Preserve the observed values for the completion report.

- [ ] **Step 4: Add the verified project-memory event**

Insert this event immediately above `cold-first-hover-click-hitch-removal` in `MEMORY.md` after the runtime checks pass:

```markdown
### 2026-07-27 - data-time-range-closed-liquid-glass-trigger
- Reason: The Data time-range entry needed the compact closed selector style
  from the user's macOS reference, without its leading color marker.
- Changed:
  - `Sources/DynamicIsland/Views/DataPrimaryContentView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
- Result: The 72 by 24pt entry now uses one 8pt continuous rounded rectangle,
  geometrically centered range text, and a fixed trailing up-down chevron. Native
  and fallback paths share the same shape; the independent Liquid Glass drawer
  and its cold-first-open materialize fix remain unchanged.
- Verify: `swift run DynamicIslandCoreChecks`, `swift build --product
  DynamicIsland`, `./script/build_and_run.sh`, cold first-hover/click visual
  checks, repeated drawer interaction, and settled process sampling passed.
- Rollback: Revert only the trigger shape and label layout if the closed control
  is rejected; preserve the independent drawer and first-white-flash fix.
```

Do not add this success event if the cold interaction check is still pending.

- [ ] **Step 5: Re-run checks after the memory-only change**

Run:

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
git diff --check
```

Expected: all commands exit `0`.

- [ ] **Step 6: Commit the verified memory event**

Run:

```bash
./script/safe_git_save.sh "docs: record Data closed trigger verification" MEMORY.md
```

Expected: one documentation commit containing only the verified event.

