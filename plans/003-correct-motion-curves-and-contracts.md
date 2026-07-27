# 003 — Correct motion curves and timing contracts

- **Status**: DONE
- **Commit**: 41b751d
- **Severity**: HIGH
- **Category**: Easing & duration; Cohesion & tokens
- **Estimated scope**: 4 files, about 80 lines

## Problem

Several non-gesture state changes use curves that delay feedback or disagree
about the same state's duration.

```swift
// Sources/DynamicIsland/Controllers/IslandPanelController.swift:1181 — current
withAnimation(.easeIn(duration: 0.18)) {
    self.overlayState.musicSkipGestureProgress = 0
    self.overlayState.musicSkipFeedbackDirection = nil
}
```

`easeIn` is always wrong for UI exit feedback because it starts slow while the
user is watching.

```swift
// Sources/DynamicIsland/Controllers/IslandPanelController.swift:1712 — current
withAnimation(.linear(duration: 0.22)) {
    overlayState.isTrackInfoPresented = true
}
```

Track-info entry/exit is not constant motion, so `linear` has no physical
acceleration or deceleration.

```swift
// Sources/DynamicIsland/Controllers/IslandPanelController.swift:289 — current
private var hideAnimationDuration: TimeInterval {
    0.22 * runtimeSettings.hideAnimationScale
}

// Sources/DynamicIsland/Views/IslandOverlayView.swift:432 — current
.animation(.easeInOut(duration: 0.22), value: state.isShellHidden)
```

The controller schedules mouse passthrough using a runtime-scaled duration, but
the view overrides the visual state with a fixed 0.22s animation. At non-default
settings the visual and interaction contracts drift.

```swift
// Sources/DynamicIslandCore/IslandAnimationProfile.swift:68 — current
primaryFeatureSelectionResponse: 0.28,
primaryFeatureSelectionDamping: 0.75,
```

The frequently used, non-momentum feature-selection highlight has visible
under-damped bounce. Apple-style default UI motion is critically damped; bounce
is reserved for momentum-driven interactions.

## Target

Add named timing values to `IslandAnimationProfile` and use one owner per state:

```swift
// target defaults
musicAccessoryTransitionDuration: 0.22,
musicSkipFeedbackDismissDuration: 0.18,
trackInfoTransitionDuration: 0.22,
hideTransitionDuration: 0.22,
primaryFeatureSelectionResponse: 0.30,
primaryFeatureSelectionDamping: 1.0,
```

Apply these rules:

- Music accessory insertion/removal: `easeOut`, 0.22s.
- Committed skip feedback exit: `easeOut`, 0.18s.
- Track-info enter and exit: `easeOut`, 0.22s; use the same token for delayed
  panel-frame shrink.
- Hide/show: controller-owned `easeOut` using
  `hideTransitionDuration * hideAnimationScale`; remove the fixed view-level
  animation keyed to `isShellHidden` so pointer passthrough and visuals share
  one duration.
- Feature selection highlight: response 0.30, damping 1.0, no overshoot.
- Remove the redundant animation keyed directly to
  `musicPlayback.isPlaying`; the `showsMusicAccessories` transition owns that
  visibility change.

## Repo conventions to follow

- Shared motion values belong to
  `Sources/DynamicIslandCore/IslandAnimationProfile.swift`.
- The controller already owns state-changing `withAnimation` transactions for
  hide/show and track info.
- Keep the deliberately under-damped, user-approved primary-feature *entrance*
  spring unchanged; only the selection highlight becomes critically damped.

## Steps

1. Add failing checks for the new profile fields and exact default values.
2. Add failing checks that production source contains no `.easeIn(` and no
   `.linear(duration: 0.22)` in the music-feedback path.
3. Add failing checks that the view no longer has a fixed animation keyed to
   `state.isShellHidden`, while the controller uses the runtime-scaled profile
   duration and `easeOut`.
4. Add a failing numeric assertion that
   `primaryFeatureSelectionDamping == 1.0` and response is `0.30`.
5. Run `swift run DynamicIslandCoreChecks` and confirm the new checks fail.
6. Extend `IslandAnimationProfile` initializer, stored properties, and default.
7. Replace the controller's skip-dismiss, track-info, and hide/show literals.
8. Update `IslandOverlayView` to use `easeOut` for
   `showsMusicAccessories`, remove the redundant playback-state animation, and
   remove view-owned track-info/hidden-state overrides.

## Boundaries

- Do NOT change the shell expansion spring or the deliberately delayed primary
  feature entrance.
- Do NOT change runtime setting ranges.
- Do NOT change when track info appears or its 2.5s dwell time.
- Do NOT change skip cooldown or feedback dwell time.
- Do NOT consolidate unrelated Codex/Files animation literals in this plan.

## Verification

- **Mechanical**: red/green `swift run DynamicIslandCoreChecks`, followed by
  `swift build --product DynamicIsland` and `git diff --check`.
- **Feel check**: switch primary features repeatedly; the highlight must glide
  without overshoot. Trigger track changes and committed skips; entry/exit must
  begin immediately and decelerate into rest. Test hide-animation setting at
  0.7, 1.0, and 1.4; the shell must finish visually when click passthrough is
  enabled, with no early dead zone or late click capture.
- **Done when**: no `easeIn` remains in UI motion, track info is non-linear,
  selection is critically damped, and hide visual/interaction timing has one
  shared contract.
