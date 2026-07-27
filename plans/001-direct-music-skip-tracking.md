# 001 — Make music-skip tracking direct

- **Status**: DONE
- **Commit**: 41b751d
- **Severity**: HIGH
- **Category**: Interruptibility
- **Estimated scope**: 3 files, about 35 lines

## Problem

The horizontal music-skip feedback is animated toward every incoming trackpad
sample instead of following the gesture 1:1. The controller wraps both tracking
and armed progress in animation transactions:

```swift
// Sources/DynamicIsland/Controllers/IslandPanelController.swift:1067 — current
case .tracking(let direction, let progress):
    withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.82)) {
        overlayState.musicSkipFeedbackDirection = direction
        overlayState.musicSkipGestureProgress = progress
        overlayState.isMusicSkipArmed = false
    }
case .armed(let direction, let progress):
    // ...
    withAnimation(.easeOut(duration: 0.10)) {
        overlayState.musicSkipFeedbackDirection = direction
        overlayState.musicSkipGestureProgress = progress
        overlayState.isMusicSkipArmed = true
    }
```

The view then adds a second spring to the same continuously changing value:

```swift
// Sources/DynamicIsland/Views/IslandOverlayView.swift:430 — current
.animation(.interactiveSpring(response: 0.18, dampingFraction: 0.82), value: state.musicSkipGestureProgress)
```

Each delta therefore retargets one or two springs. The visible edge can lag
behind the finger, and a quick rollback can still appear to travel toward the
old target after the state machine has already cancelled it.

## Target

Tracking progress must be written without animation. The state machine remains
the source of direction, arming, cancellation, and phase-ended commit.

```swift
// target
case .tracking(let direction, let progress):
    overlayState.musicSkipFeedbackDirection = direction
    overlayState.musicSkipGestureProgress = progress
    overlayState.isMusicSkipArmed = false

case .armed(let direction, let progress):
    // keep the existing first-arm log
    overlayState.musicSkipFeedbackDirection = direction
    overlayState.musicSkipGestureProgress = progress
    withAnimation(.easeOut(duration: 0.10)) {
        overlayState.isMusicSkipArmed = true
    }
```

Remove the view-level animation keyed to `musicSkipGestureProgress`. Keep the
existing spring only for cancellation/reset, where the system is settling after
the finger releases or rolls back. Do not change the 50pt commit distance, 38pt
cancel distance, direction lock, cooldown, or `.ended` commit rule.

## Repo conventions to follow

- Gesture truth lives in `Sources/DynamicIslandCore/MusicSkipGestureStateMachine.swift`.
- The controller already distinguishes live tracking from settle paths in
  `applyHorizontalMusicSkipGestureState` and `resetScrollGesture`.
- Tests use `expectEqual()` and source-section checks in
  `Tests/DynamicIslandCoreChecks/main.swift`.

## Steps

1. In `Tests/DynamicIslandCoreChecks/main.swift`, extract the `.tracking` and
   `.armed` switch sections and add failing checks that live progress sections
   do not contain `withAnimation`, while the armed-state boolean still gets a
   short feedback animation.
2. Add a failing check that `IslandOverlayView.swift` does not contain an
   `.animation(... value: state.musicSkipGestureProgress)` modifier.
3. Run `swift run DynamicIslandCoreChecks` and confirm the new checks fail for
   the expected spring-wrapped tracking code.
4. Edit `IslandPanelController.swift` so direction/progress assignments are
   direct in `.tracking` and `.armed`; animate only the armed boolean.
5. Remove the progress-keyed animation modifier from `IslandOverlayView.swift`.
6. Re-run the core checks, then build and use the real phase-aware trackpad path.

## Boundaries

- Do NOT change `MusicSkipGestureStateMachine` thresholds or state transitions.
- Do NOT add velocity-based commit; the project explicitly requires arming and
  phase-ended commit.
- Do NOT remove the spring used for cancel/reset settling.
- Do NOT touch vertical hide/show behavior in this plan.
- Preserve the user's existing uncommitted pointer-passthrough changes.

## Verification

- **Mechanical**: `swift run DynamicIslandCoreChecks` must first fail on the new
  assertions, then pass after the production edit. Follow with
  `swift build --product DynamicIsland`.
- **Feel check**: run `./script/build_and_run.sh --debug-music-signal`, send a
  `playing` signal, and use a real trackpad. Confirm the expanding edge and glyph
  track every horizontal delta without catch-up lag; reversing before release
  cancels immediately; release before arming settles smoothly; armed release
  still commits only on `.ended`.
- **Performance**: sample the process after repeated partial swipes and confirm
  CPU returns to the normal settled range.
- **Done when**: live progress is direct, only settle paths animate, all existing
  gesture contracts still pass, and real-device rollback has no visible chase.
