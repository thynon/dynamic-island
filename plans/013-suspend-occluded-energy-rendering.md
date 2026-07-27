# 013 — Suspend occluded top-band energy rendering

- **Status**: DONE
- **Commit**: 41b751d
- **Severity**: MEDIUM
- **Category**: Performance
- **Estimated scope**: 2 files, about 18 lines

## Problem

`TopBandEnergyEffectNSView` observes window occlusion changes, but its timer
checks only `window.isVisible`. An ordered-visible yet fully occluded window can
continue drawing Metal frames at 12Hz.

```swift
// Sources/DynamicIsland/Views/TopBandEnergyEffectView.swift:157 — current
guard renderTimer == nil, window?.isVisible == true, metalView != nil else { return }
```

## Target

Centralize one renderability predicate requiring the window to be ordered
visible and have `.visible` in its `occlusionState`. Use it when starting,
maintaining, and synchronizing the timer.

## Repo conventions to follow

- Keep the deliberate 12Hz timer and existing visibility notification.
- Do not change shader output or pipeline caching.

## Steps

1. Add a failing source check for `window.occlusionState.contains(.visible)` in
   the timer lifecycle.
2. Run `swift run DynamicIslandCoreChecks`; expect failure.
3. Add the shared renderability predicate and use it in `startRenderTimer`,
   `renderFrame`, and `syncRenderTimerWithWindowVisibility`.
4. Re-run the core checks.

## Boundaries

- Do not change Metal resources, colors, burst timing, or frame rate.

## Verification

- **Mechanical**: core checks and app build exit 0.
- **Feel check**: energy resumes when the island becomes visible and stops when
  the app is ordered out or fully occluded.
- **Done when**: no 12Hz draw loop remains active for an occluded window.
