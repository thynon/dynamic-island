# Synchronized Linear Primary Entrance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for the source-contract change and preserve the existing dirty workspace.

**Goal:** Make Files and all right-side primary controls enter simultaneously with one linear timing contract and no stagger.

**Architecture:** Keep the existing top-band frames and separate SwiftUI views. Replace the spring/stagger entrance tokens with one shared duration token, then have both `PrimaryFeatureSwitcher` and `FilesPrimaryFeatureButton` construct the same delayed linear entrance. Mount both in one stable open-canvas top-band layer and mask that layer by the animated shell width, so the controls retain shell clipping without inheriting its horizontal spring. Main content, selection, press, collapse, and Reduce Motion paths remain unchanged.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM source-contract checks.

## Global Constraints

- Preserve the `IslandTopStatusBandLayout` frames and camera-safe regions.
- Start all five top entry points after `0.34s` and animate them for `0.18s`.
- Retain the existing `6pt` vertical source offset.
- Keep the five top entry points fixed on screen X while the centered shell
  width spring settles; preserve shell clipping and do not change their
  top-band layout frames.
- Do not change primary-content entrance, selection, press, collapse, or Reduce Motion behavior.
- Do not stage, commit, or revert unrelated working-tree changes.

---

### Task 1: Synchronize the top navigation tier

**Files:**
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`
- Modify: `Sources/DynamicIslandCore/IslandAnimationProfile.swift`
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift`
- Modify: `docs/superpowers/specs/2026-07-14-expanded-content-motion-design.md`
- Modify: `plans/012-animate-expanded-primary-content.md`
- Modify: `plans/README.md`
- Modify: `MEMORY.md`

**Interfaces:**
- Consumes: `IslandAnimationProfile.default.primaryFeatureEntranceStartDelay`
- Produces: `IslandAnimationProfile.default.primaryFeatureEntranceDuration`

- [x] **Step 1: Write the failing source-contract checks**

Require `primaryFeatureEntranceDuration: 0.18`, require both top entry views to
use `.linear(duration: animationProfile.primaryFeatureEntranceDuration)`, and
forbid `primaryFeatureStaggerDelay`, indexed entrance helpers, and entrance
spring tokens.

- [x] **Step 2: Verify the checks fail for the expected reason**

Run: `swift run DynamicIslandCoreChecks`

Expected: FAIL because the current code still contains the staggered spring and
does not contain the shared duration token.

- [x] **Step 3: Implement the minimal shared linear entrance**

Replace the four entrance spring/stagger profile fields with:

```swift
public let primaryFeatureEntranceDuration: Double
public let primaryFeatureEntranceStartDelay: Double
```

Set the default duration to `0.18`. In both top entry views, use:

```swift
Animation.linear(duration: animationProfile.primaryFeatureEntranceDuration)
    .delay(animationProfile.primaryFeatureEntranceStartDelay)
```

The switcher applies the animation to the whole `HStack`, not each button.

- [x] **Step 4: Verify the checks pass**

Run: `swift run DynamicIslandCoreChecks`

Expected: `DynamicIslandCoreChecks passed`.

- [x] **Step 5: Verify the executable and runtime**

Run:

```bash
swift build --product DynamicIsland
git diff --check
./script/build_and_run.sh
```

Expected: build and launch succeed; only the main repository app remains
running. Capture ordered debug frames and confirm Files plus all four right-side
controls become visible in the same frame window without a sequential cascade.

---

### Task 2: Anchor the synchronized entrance in screen space

**Files:**
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift`

**Interface:**
- Produces: `primaryFeatureScreenXCompensation`

- [x] **Step 1: Write failing source-contract checks**

Require both top-control mounts to live in one stable open-canvas layer, require
that layer to retain the canonical top-band height, and forbid a second
animated horizontal compensation offset.

- [x] **Step 2: Verify the checks fail for the expected reason**

Run: `swift run DynamicIslandCoreChecks`

Expected: FAIL because the stable canvas layer is absent.

- [x] **Step 3: Implement the minimal shared compensation**

Move both mounts out of the animated-width shell subtree into one canvas layer
without changing their canonical `.position(...)` values. Mask the layer with
the shell width so collapse cannot leave controls floating outside the shell.

Runtime frame checks rejected an earlier inverse-offset prototype because the
child entrance transaction delayed that offset and produced a visible
left-to-right slide. The final implementation contains no horizontal control
animation.

- [x] **Step 4: Verify the checks pass**

Run: `swift run DynamicIslandCoreChecks`

Expected: `DynamicIslandCoreChecks passed`.

- [x] **Step 5: Verify the composed path and runtime**

Capture the same ordered debug frames and confirm the Files and right-side
control X midpoints remain stable while their Y midpoints move down. Re-run the
executable build, interaction smoke test, CPU sampling, and final launch.
