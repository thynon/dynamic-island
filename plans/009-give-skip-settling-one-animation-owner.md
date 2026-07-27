# 009 — Give music-skip settling one animation owner

- **Status**: DONE
- **Commit**: 41b751d
- **Severity**: MEDIUM
- **Category**: Interruptibility
- **Estimated scope**: 2 files, about 10 lines

## Problem

The controller correctly writes live progress directly, then owns cancellation
and committed-dismiss settling with explicit animation transactions:

```swift
// Sources/DynamicIsland/Controllers/IslandPanelController.swift:1095 — current
withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.82)) {
    overlayState.musicSkipGestureProgress = 0
    overlayState.musicSkipFeedbackDirection = nil
    overlayState.isMusicSkipArmed = false
}

// Sources/DynamicIsland/Controllers/IslandPanelController.swift:1187 — current
withAnimation(.easeOut(duration: animationProfile.musicSkipFeedbackDismissDuration)) {
    overlayState.musicSkipGestureProgress = 0
    overlayState.musicSkipFeedbackDirection = nil
}
```

The root view also installs a fixed animation for the same direction change:

```swift
// Sources/DynamicIsland/Views/IslandOverlayView.swift:448 — current
.animation(
    accessibilityReduceMotion
        ? .easeOut(duration: animationProfile.reducedMotionFadeDuration)
        : .easeInOut(duration: 0.16),
    value: state.musicSkipFeedbackDirection
)
```

The local modifier can override the controller transaction when direction
returns to nil, so a dynamic spring settle and a fixed tween compete for the
shell edge, glyph, and opacity.

## Target

Remove the view-level animation keyed to `musicSkipFeedbackDirection`. Keep
live tracking unanimated and keep the controller as the single owner:

- direct writes for `.tracking` and progress while `.armed`;
- 0.10s ease-out for armed emphasis only;
- interactive spring for rollback/cancel/reset;
- shared ease-out duration for committed feedback dismissal.

Conditional glyph insertion/removal must inherit the controller transaction;
do not add a replacement view-level animation.

## Repo conventions to follow

- Gesture state and thresholds remain in `MusicSkipGestureStateMachine`.
- State-changing animation ownership belongs in the controller for this path.
- The existing plan 001 direct-tracking checks remain intact.

## Steps

1. Add a failing assertion that `IslandOverlayView.swift` contains no animation
   keyed to `state.musicSkipFeedbackDirection`.
2. Run `swift run DynamicIslandCoreChecks` and confirm the assertion fails.
3. Remove only that view-level modifier.
4. Re-run checks, build, and use a real trackpad for rollback/commit feel.

## Boundaries

- Do NOT change commit/cancel thresholds, cooldown, or phase-ended commit.
- Do NOT remove controller-owned cancel/reset springs.
- Do NOT animate live progress.
- Do NOT change glyph geometry or shell expansion distance.

## Verification

- **Mechanical**: `swift run DynamicIslandCoreChecks` and
  `swift build --product DynamicIsland`.
- **Feel check**: partially swipe and reverse; the edge and glyph must return in
  one continuous spring. Arm then reverse; no fixed-duration hitch may appear.
  Commit on `.ended`; the dwell and ease-out dismissal must remain unchanged.
- **Done when**: every skip phase has exactly one animation owner and live
  progress remains 1:1.
