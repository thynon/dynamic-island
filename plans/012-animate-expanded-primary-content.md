# 012 — Animate expanded primary content from its source

- **Status**: DONE
- **Commit**: 41b751d
- **Severity**: MEDIUM
- **Category**: Physicality & origin
- **Estimated scope**: 3 files, about 65 lines

## Problem

Tasks and Files appear at their final position with only opacity, and start at
the same `0.34s` moment as the first navigation control:

```swift
// Sources/DynamicIsland/Views/IslandOverlayView.swift:326 — current
if isExpanded && isPrimaryContentEntranceActive && state.selectedPrimaryFeature == .tasks {
    CodexTasksContentView(/* ... */)
        .transition(.opacity)
}
```

The content has no spatial connection to its top-band trigger. The existing
navigation entrance damping is `0.88`, which adds overshoot to controls that
have no gesture momentum. Reduce Motion also disables the selection transaction
entirely, so expanded feature switches snap.

## Target

- Keep shell geometry animation unchanged.
- Keep top controls at the settled-shell delay (`0.34s`). Per the user's later
  visual review, all right-side controls and the Files icon now share one
  `0.18s` linear entrance with no per-control stagger.
- Start the current content container at `0.40s`.
- Normal motion: opacity plus `y: -6pt` offset, spring response `0.30`, damping
  `1.0`.
- Collapse: return along the same path with `0.14s easeOut`.
- Expanded Tasks/Files switching: same transition with no entrance delay.
- Reduce Motion: zero delay, opacity only, `0.20s easeOut`.

```swift
private var primaryContentTransition: AnyTransition {
    accessibilityReduceMotion
        ? .opacity
        : .opacity.combined(
            with: .offset(y: -animationProfile.primaryContentTransitionDistance)
        )
}

private var primaryContentEntranceAnimation: Animation {
    accessibilityReduceMotion
        ? .easeOut(duration: animationProfile.reducedMotionFadeDuration)
        : .spring(
            response: animationProfile.primaryFeatureSelectionResponse,
            dampingFraction: animationProfile.primaryFeatureSelectionDamping
        )
}
```

## Repo conventions to follow

- Store all new values in `IslandAnimationProfile.default`.
- Animate only opacity and transform offsets.
- Keep `primaryFeatureEntranceStartDelay >= expandResponse * 0.85`.
- Do not animate task rows or file tiles.

## Steps

1. Add failing checks for `primaryContentEntranceDelay: 0.40`, transition
   distance `6`, entrance damping `1.0`, source-anchored transition, symmetric
   exit, and reduced-motion fade.
2. Run `swift run DynamicIslandCoreChecks`; expect the new checks to fail.
3. Extend `IslandAnimationProfile` with the two content tokens and update its
   initializer/default.
4. Replace Tasks/Files `.transition(.opacity)` with the shared content
   transition and replace the selection animation with the shared entrance
   animation.
5. Update `schedulePrimaryContentEntrance` so expansion uses the delayed spring,
   collapse uses the fast exit, and already-mounted content is not replayed when
   accessibility settings change.
6. Re-run `swift run DynamicIslandCoreChecks`; expect all checks to pass.

## Boundaries

- Do not change shell dimensions or top-band frames.
- Do not add per-item animation.
- Do not animate Data/Tools/Settings placeholder content.
- Do not add blur or Metal work to the content transition.

## Verification

- **Mechanical**: `swift run DynamicIslandCoreChecks` exits 0.
- **Feel check**: at normal speed the shell leads, controls follow, and current
  content resolves from the top-band source without bounce. At 10% playback the
  enter/exit path is symmetric. With Reduce Motion, only opacity changes.
- **Done when**: expanded content has a visible source and rapid switching never
  restarts from an unrelated position.
