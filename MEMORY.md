# MEMORY.md

This is the project-local event memory for `/Users/jayu/Documents/Codex/Island`.
It is intentionally written like a lightweight git log: newest entries first,
fact-based, and easy to use for rollback.

## Current Memory Rules

- Do not use global memory as project truth.
- Treat `AGENTS.md`, project docs, source files, and this file as the project context.
- This file records events, decisions, changed files, verification, and rollback notes.
- Keep entries concise. Do not turn this file back into a long rule dump.
- Replies no longer need to include the `cx` marker.

## Event Format

Each event should use this shape:

```md
### YYYY-MM-DD - short-title
- Reason:
- Changed:
- Result:
- Verify:
- Rollback:
```

## Events

### 2026-06-18 - rollback-horizontal-swipe-music-skip
- Reason: User requested rolling back to the state before the left/right swipe recommendation and feature.
- Changed:
  - `Sources/DynamicIsland/Views/IslandTrackingHostingView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIsland/Support/MusicPlaybackDataSource.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Views/ClosedMusicWaveformView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Removed horizontal scroll forwarding, gesture-axis locking, swipe-to-skip commands, skip feedback state, left/right skip icons, and the temporary dark/pink skip feedback styling. Vertical notch scroll hide/show remains active, including hidden-state priority and immediate hover restoration after downward reveal. Music metadata reveal, compact artwork, waveform, width, and radius tuning are unchanged.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; `./script/build_and_run.sh`; process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `0.3%` CPU after settling.
- Rollback: Reapply the horizontal-swipe events if left/right track skipping should return later.

### 2026-06-17 - align-skip-feedback-and-hide-motion-reference
- Reason: User provided a reference showing the skip feedback style and clarified that next-track feedback should show the next icon beside the waveform, previous-track feedback should show the previous icon to the left of the album artwork, and hide/show should close inward from both sides and reopen outward.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Views/ClosedMusicWaveformView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Skip feedback now uses a temporary dark shell style with pink waveform bars and icon placement tied to the existing album/waveform centers: previous icon left of artwork, next icon right of waveform. Hidden shell animation now scales horizontally toward the center instead of traveling upward, so restore expands outward from the center. A fallback cleanup path clears stuck skip feedback after horizontal gestures.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; `./script/build_and_run.sh`; screenshot confirmed the default music state returned to white shell/black waveform after restart; process check showed DynamicIsland at `0.0%` CPU after settling.
- Rollback: Restore fixed black waveform styling, remove `barColor`, remove `shellFillColor` and `hiddenShellHorizontalScale`, and return to the previous icon-center calculation if the darker reference style or inward/outward hide motion is not preferred.

### 2026-06-17 - refine-horizontal-swipe-with-gesture-lock
- Reason: User asked to stop the half-finished horizontal swipe work and reorganize it by stages: unified scroll entry, pointer hot-zone check, hidden-state priority, independent hover, accumulated gesture locking, start/commit thresholds, progress-driven icon feedback, and delayed gesture reset.
- Changed:
  - `Sources/DynamicIsland/Views/IslandTrackingHostingView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Support/MusicPlaybackDataSource.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: All scroll events enter `handleScroll(deltaX:deltaY:)`. The controller first requires `panel.frame.contains(NSEvent.mouseLocation)`, gives hidden state priority, accumulates deltas, locks each scroll sequence to `.horizontal` or `.vertical`, starts icon feedback at `8pt`, commits one skip at `48pt`, resets after `0.22s` of no scroll events, and keeps the existing vertical hide/show threshold at `0.8pt`. Overlay feedback now follows `musicSkipGestureProgress`. The previous-track command now rewinds `player position` to `0` before `previous track` so Music goes to the prior song instead of restarting the current one.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; `./script/build_and_run.sh`; Computer Use right-scroll on Dynamic Island advanced Music from `勋章 Medals` to `最熟悉的陌生人`; direct robust previous command returned Music from `最熟悉的陌生人` to `勋章 Medals`; Computer Use left-scroll did not reliably deliver a previous scroll event in this run; process check showed DynamicIsland at `0.0%` CPU after settling.
- Rollback: Restore the simpler non-accumulated `handleHorizontalMusicSkip(deltaX:deltaY:)` path and remove `ActiveScrollGesture`, accumulated deltas, progress state, and delayed reset if the staged gesture lock feels too heavy.

### 2026-06-17 - add-horizontal-swipe-music-skip
- Reason: User requested that when the cursor is over the notch/island, horizontal trackpad swipes switch music tracks: right swipe for next, left swipe for previous, with a directional side icon popping out.
- Changed:
  - `Sources/DynamicIsland/Views/IslandTrackingHostingView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIsland/Support/MusicPlaybackDataSource.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Scroll events now pass both `deltaX` and `deltaY`. Closed music state recognizes deliberate horizontal gestures only while music is playing, not hidden, and not expanded. Natural trackpad right-swipe (`deltaX < -6`) sends `next track`; left-swipe (`deltaX > 6`) sends `previous track`. A short-lived `skip.forward.fill` or `skip.backward.fill` icon appears on the corresponding side, and metadata cache is invalidated after successful commands.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; `./script/build_and_run.sh`; process check showed DynamicIsland running from `dist/Dynamic Island.app` at `0.9%` CPU after settling.
- Rollback: Remove `MusicSkipDirection`, `skipTrack`, `musicSkipFeedbackDirection`, and the horizontal branch in `handleScroll(deltaX:deltaY:)` to return to vertical scroll-only behavior.

### 2026-06-17 - remove-compact-artwork-extra-box
- Reason: User noticed a small square around the compact music artwork in both default and hover states.
- Changed:
  - `Sources/DynamicIsland/Views/ClosedMusicAvatarView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Removed the avatar's extra outline stroke and shadow so the compact artwork renders only the clipped album image or fallback glyph, avoiding a visible UI box on the white shell.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; `./script/build_and_run.sh`; default and hover screenshots captured; process check showed DynamicIsland running from `dist/Dynamic Island.app` at `0.1%` CPU after settling.
- Rollback: Restore the `RoundedRectangle.stroke` overlay and `.shadow` in `ClosedMusicAvatarView` if a visible artwork container is desired again.

### 2026-06-17 - keep-music-accessories-through-expanded-state
- Reason: User provided compact and expanded music-state references and requested centered song metadata, unchanged artwork/waveform size in expanded state, and smooth travel between compact and expanded positions.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The compact music artwork and waveform now stay mounted while music is playing, move to dedicated expanded left-header positions (`48pt` and `90pt`) during expansion, and keep the same `18pt` size. Track-change title and artist text are centered.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; `./script/build_and_run.sh`; screenshots captured default and expanded music states; process check showed DynamicIsland running from `dist/Dynamic Island.app` at `0.8%` CPU after settling.
- Rollback: Remove `expandedMusicArtworkCenterX`, `expandedMusicWaveformCenterX`, and the expanded music accessory position switching to return accessories to compact-only rendering.

### 2026-06-17 - add-track-change-info-reveal
- Reason: User requested that when the song changes, the compact music state expands downward, shows song title and artist, enlarges the artwork, then returns to the default state after `2.5s` with smooth linear animation.
- Changed:
  - `Sources/DynamicIsland/Support/MusicPlaybackDataSource.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Music snapshots now carry `title`, `artist`, and `trackIdentity`, with Music/Spotify AppleScript reading current track metadata. The controller detects track identity changes, expands the closed music canvas to `72pt` high, presents title/artist and enlarged artwork with `.linear(duration: 0.22)`, then dismisses after `2.5s` and restores the default compact music layout.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; process check showed DynamicIsland running from `dist/Dynamic Island.app` at `0.0%` CPU after startup settled.
- Rollback: Remove `isTrackInfoPresented`, track identity detection, and Music/Spotify title/artist parsing to return to artwork/waveform-only compact music state.

### 2026-06-17 - restore-hover-after-scroll-show
- Reason: User pointed out that after downward scroll restore, the pointer is still in the notch area, so the shell should immediately be in hover state instead of waiting for another mouse-enter event.
- Changed:
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: When hidden shell is restored, the panel re-enables mouse events, removes the hidden scroll monitor, and immediately sets `overlayState.isHovered = panel.frame.contains(NSEvent.mouseLocation)`.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; process check showed DynamicIsland running from `dist/Dynamic Island.app` at `0.0%` CPU after startup settled.
- Rollback: Remove the explicit hover sync if restore should always return to a non-hover visual state.

### 2026-06-17 - shorten-trackpad-hide-gesture
- Reason: User felt the trackpad upward gesture needed too much travel and the hide/show motion path felt too long for normal use.
- Changed:
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Scroll handling now uses a centralized `handleScroll(deltaY:)` with a low `0.8pt` activation threshold. Natural upward scrolling hides at `deltaY < -0.8`; natural downward scrolling restores at `deltaY > 0.8`. The visual hide offset was shortened from a full shell-height travel to `-12pt`, relying on opacity for invisibility and making the transition feel shorter.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; process check showed DynamicIsland running from `dist/Dynamic Island.app` at `0.0%` CPU after startup settled.
- Rollback: Restore the direct `setShellHidden(deltaY < 0)` handling and full-height hidden offset if a longer deliberate swipe is preferred.

### 2026-06-17 - make-hidden-shell-scroll-only
- Reason: User pointed out hidden state still was not truly non-interactive; it should remain invisible, non-hoverable, and non-clickable, with only a transparent scroll zone waiting for the downward restore gesture.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Hidden shell now disables SwiftUI hit testing and sets `panel.ignoresMouseEvents = true` after the hide transition, so hover and click events pass through. A hidden-only global scroll monitor checks whether the mouse is inside the panel frame and restores the shell only on the natural downward scroll gesture.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `1.0%` CPU after startup settled.
- Rollback: Remove the hidden scroll monitor and `panel.ignoresMouseEvents` toggling if the always-interactive transparent panel is preferred.

### 2026-06-17 - invert-trackpad-scroll-hide-direction
- Reason: User confirmed Apple trackpad natural scrolling made the previous direction feel reversed: the app's upward scroll matched the user's downward gesture. Hidden state should remain invisible/non-interactive until the user swipes down again.
- Changed:
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Natural trackpad `scrollingDeltaY < 0` now hides the shell, and `scrollingDeltaY > 0` shows it. Hidden shells still ignore hover reveal and expansion taps while keeping the transparent tracking zone alive for the down-swipe restore gesture.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; process check showed DynamicIsland running from `dist/Dynamic Island.app` at `0.0%` CPU after startup.
- Rollback: Change `setShellHidden(deltaY < 0)` back to `setShellHidden(deltaY > 0)` if using a non-natural scroll direction setup.

### 2026-06-17 - add-notch-scroll-hide-show
- Reason: User requested an interaction where moving the cursor to the notch/island area and swiping up hides the island, while swiping down shows it again, with a non-abrupt transition.
- Changed:
  - `Sources/DynamicIsland/Views/IslandTrackingHostingView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The panel remains present as a transparent top tracking zone, while the shell visually hides/shows via opacity, upward offset, and slight scale animation. `scrollingDeltaY > 0` hides the shell; downward scroll shows it again. Hiding also collapses expanded state and clears hover preview.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; process check showed DynamicIsland running from `dist/Dynamic Island.app` at `0.0%` CPU after startup.
- Rollback: Remove `isShellHidden`, `onScroll`, and `setShellHidden` to return to always-visible behavior.

### 2026-06-17 - rounded-static-artwork-and-core-animation-bars
- Reason: User provided a reference screenshot and requested the compact music artwork use a static rounded-corner album style, while still wanting the waveform bars animated with lower CPU cost.
- Changed:
  - `Sources/DynamicIsland/Views/ClosedMusicAvatarView.swift`
  - `Sources/DynamicIsland/Views/ClosedMusicWaveformView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Compact artwork is now a static rounded rectangle instead of a rotating circular disc. Compact waveform bars now animate through Core Animation `CALayer`/`CABasicAnimation` instead of SwiftUI `TimelineView` or Canvas redraws.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; process check showed DynamicIsland running from `dist/Dynamic Island.app` at `0.0%` CPU after startup; visual crop captured at `/tmp/dynamic-island-rounded-art-waveform-top.png`.
- Rollback: Restore circular artwork and the previous SwiftUI waveform view if the earlier disc visual is preferred.

### 2026-06-17 - widen-music-compact-shell-to-350
- Reason: User reviewed the `300pt` music compact state and requested `350pt` because `300pt` still felt small.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Music compact shell now derives to `350x32` from a `185pt` camera housing plus `82.5pt` side slots. Default compact width remains `260pt`, and compact music accessory size resolves to the `18pt` cap under the current `5pt` boundary.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; process check showed DynamicIsland running from `dist/Dynamic Island.app` at `0.0%` CPU after startup; visual crop captured at `/tmp/dynamic-island-music-350-top.png`.
- Rollback: Restore `musicStatusSlotWidth` to `57.5` and the music width/accessory-size expectations if the prior `300pt` music compact state should return.

### 2026-06-17 - set-shell-content-boundary-to-5pt
- Reason: User requested both default and expanded shell UI/text/function/layout boundaries use a `5pt` constraint, with rounded-corner handling and cleanup of unnecessary code.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Sources/DynamicIslandCore/IslandTopStatusBandLayout.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Views/IslandShape.swift`
  - `Sources/DynamicIsland/Views/ClosedMusicAvatarView.swift`
  - `Sources/DynamicIsland/Views/ClosedMusicWaveformView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Added a shared `defaultContentBoundaryInset = 5` and routed closed status guard, closed music accessory guard, expanded content guard, and expanded bottom guards through it. Expanded top regions still add `openTopCornerRadius + 5` where they sit near rounded top corners. At the current `260pt` closed/music width, compact music accessory usable size resolves to `0pt`; the overlay now skips rendering zero-size animated accessories to avoid invisible animation work.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; process check showed DynamicIsland running from `dist/Dynamic Island.app`, with CPU settling to about `0.4%` after startup.
- Rollback: Restore the previous `2pt` closed guard and `6pt` expanded guard constants if the tighter edge constraint should be reverted.

### 2026-06-17 - widen-default-compact-shell-to-260
- Reason: User requested the default closed shell width increase by another `10pt`.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Default closed shell now derives to `260x32` from a `185pt` camera housing plus `37.5pt` side slots. The shell remains one continuous shape; `outerRadius = 30`, `innerRadius = 7`, and `concaveTopRadius = 18` are unchanged.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; process check showed DynamicIsland running from `dist/Dynamic Island.app`, with CPU returning to about `0.1%` after startup.
- Rollback: Restore `statusSlotWidth` to `32.5` and the corresponding core-check expectations if the prior `250pt` default compact shell should return.

### 2026-06-17 - revert-explicit-camera-cutout
- Reason: User clarified that the explicit left/right camera cutout approach changed the default shell into a different visual model from the requested notch-fitting radius tuning.
- Changed:
  - `Sources/DynamicIsland/Views/IslandShape.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Removed the explicit `cameraCutoutWidth` path and returned the default shell to one continuous shape. Kept the existing default width and radius tuning path: closed shell width `250pt`, `outerRadius = 30`, `innerRadius = 7`, and `concaveTopRadius = 18`.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `0.1%` CPU.
- Rollback: Restore the `cameraCutoutWidth` and `addClosedSideSlot` implementation only if the user explicitly asks for a separated left/right slot model.

### 2026-06-17 - add-explicit-camera-cutout-to-closed-shell
- Reason: User provided a photo showing the widened default shell still did not align with the physical notch at the upper notch-adjacent corners, and asked for a more accurate approach.
- Changed:
  - `Sources/DynamicIsland/Views/IslandShape.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Closed shell now passes `cameraHousingWidth` into `IslandShape` and draws explicit left/right side slots with a camera cutout instead of relying only on the physical non-display notch to hide the center. Expanded shells still pass `0` cutout width and remain continuous. Existing default width, vertical position, `outerRadius = 30`, `innerRadius = 7`, and `concaveTopRadius = 18` remain unchanged.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; system window list showed Dynamic Island onscreen at `282x42`, process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `1.6%` CPU, and a top crop was captured at `/tmp/dynamic-island-cutout.png`.
- Rollback: Remove `cameraCutoutWidth` from `IslandShape` and `IslandOverlayView`, and return to the previous continuous closed shell path if the explicit cutout is worse on the physical screen.

### 2026-06-17 - widen-default-compact-shell-to-250
- Reason: User requested the default closed shell width increase by another `10pt`.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Default closed shell now derives to `250x32` from a `185pt` camera housing plus `32.5pt` side slots. Music closed shell remains `260pt`; `outerRadius = 30`, `innerRadius = 7`, and `concaveTopRadius = 18` are unchanged.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; system window list showed Dynamic Island onscreen at `282x42`, and process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `0.2%` CPU.
- Rollback: Restore `statusSlotWidth` to `27.5` and the corresponding core-check expectations if the prior `240pt` default compact shell should return.

### 2026-06-17 - widen-default-compact-shell-to-240
- Reason: User requested the default closed shell width increase by `10pt`.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Default closed shell now derives to `240x32` from a `185pt` camera housing plus `27.5pt` side slots. Music closed shell remains `260pt`; `outerRadius = 30`, `innerRadius = 7`, and `concaveTopRadius = 18` are unchanged.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; system window list showed Dynamic Island onscreen at `282x42`, and process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `0.0%` CPU.
- Rollback: Restore `statusSlotWidth` to `22.5` and the corresponding core-check expectations if the prior `230pt` default compact shell should return.

### 2026-06-17 - tune-compact-concave-top-radius-from-photo
- Reason: User provided a new photo showing the default shell still did not fully overlap the physical notch near the notch-adjacent upper inner corners.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Reduced `closedConcaveTopRadius` from `22pt` to `18pt` so the upper inner corner is shorter and less rounded, while keeping `outerRadius = 30`, `innerRadius = 7`, width, vertical position, and music logic unchanged.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; system window list showed Dynamic Island onscreen at `282x42`, and process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `0.4%` CPU.
- Rollback: Restore `defaultClosedConcaveTopRadius` and its test expectation to `22` if the previous upper inner corner depth is preferred.

### 2026-06-17 - tune-compact-shell-concave-top-radius-22
- Reason: User requested the newly added default `concaveTopRadius` change from `20pt` to `22pt`.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Default closed shell keeps the current width, vertical position, `outerRadius = 30`, and `innerRadius = 7`; only `closedConcaveTopRadius` changed to `22pt`.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; system window list showed Dynamic Island onscreen at `282x42`, and process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `0.7%` CPU.
- Rollback: Restore `defaultClosedConcaveTopRadius` and its test expectation to `20` if the prior concave top radius should return.

### 2026-06-17 - add-compact-shell-concave-top-radius
- Reason: User pointed to the notch-adjacent upper inner slot corners and requested a separate `concaveTopRadius`, suggesting an initial `18pt` to `22pt` trial range.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Sources/DynamicIsland/Views/IslandShape.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Added `closedConcaveTopRadius` with an initial `20pt` value. Closed outer radius remains `30pt`, inner radius remains `7pt`, and the new concave top radius controls the vertical depth of the notch-adjacent upper inner curve without changing width or vertical position.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; system window list showed Dynamic Island onscreen at `282x42`, and process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `2.0%` CPU.
- Rollback: Remove `closedConcaveTopRadius`, remove the `IslandShape` parameter, and route the shape back through the previous shared top-radius path if the independent concave corner should be disabled.

### 2026-06-17 - set-compact-shell-outer-radius-30
- Reason: User clarified the green-marked default shell corner should use `outerRadius = 30`, while the red-marked inner corner stays `innerRadius = 7`.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Default closed shell keeps the current `230x32` size and existing vertical position. Closed outer radius is now `30pt`; closed inner radius remains `7pt`.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; system window list showed Dynamic Island onscreen at `282x42`, and process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `1.7%` CPU.
- Rollback: Restore closed outer radius to `24` and compact music accessory size expectation to `9.5` if the prior corner tuning should return.

### 2026-06-17 - set-compact-shell-radii-24-7
- Reason: User requested the closed shell outer radius become `24pt` and inner radius become `7pt`.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Closed shell keeps the current `230x32` default size and existing vertical position. Closed outer radius is now `24pt`, inner radius is `7pt`, and compact music accessory safe size updates to about `9.5pt`.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; system window list showed Dynamic Island onscreen at `282x42`, and process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `0.2%` CPU.
- Rollback: Restore closed outer radius to `22`, inner radius to `6`, and compact music accessory size expectation to `11.5` if the prior corner tuning should return.

### 2026-06-17 - set-compact-shell-radii-22-6
- Reason: User requested the closed shell outer radius become `22pt`, inner radius become `6pt`, and vertical alignment either stay unchanged or move up only `1pt`; chose unchanged to avoid a larger visual move.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Closed shell keeps the current `230x32` default size and existing vertical position. Closed outer radius is now `22pt`, inner radius is `6pt`, and compact music accessory safe size updates to about `11.5pt`.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; system window list showed Dynamic Island onscreen at `282x42`, and process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `3.3%` CPU shortly after launch.
- Rollback: Restore closed outer radius to `22.86`, inner radius to `5.71`, and compact music accessory size expectation to `10.64` if the prior corner tuning should return.

### 2026-06-17 - refine-compact-shell-corner-radii
- Reason: User requested the closed shell outer corner radius change to `22.86pt` and inner corner radius change to `5.71pt`.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Closed shell keeps the current `230x32` default size, with outer radius `22.86pt` and inner radius `5.71pt`. The compact music accessory safe size updates to about `10.64pt` from the revised outer-radius guard.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh`; process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `1.1%` CPU.
- Rollback: Restore closed outer radius to `22.9`, inner radius to `5.7`, and compact music accessory size expectation to `10.6` if the prior corner tuning should return.

### 2026-06-17 - widen-default-compact-shell-to-230
- Reason: User requested the default closed shell width change to `230pt`.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Default closed shell now derives to `230x32` from a `185pt` camera housing plus `22.5pt` side slots. Music closed shell remains `260pt`, and the existing `22.9pt` outer / `5.7pt` inner closed radii are unchanged.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh`; process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `1.7%` CPU.
- Rollback: Restore `statusSlotWidth` to `17.5` and the corresponding core-check expectations if the prior `220pt` default compact shell should return.

### 2026-06-17 - widen-default-compact-shell-to-220
- Reason: User requested the default closed shell width change to `220pt`.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Default closed shell now derives to `220x32` from a `185pt` camera housing plus `17.5pt` side slots. Music closed shell remains `260pt`, and the existing `22.9pt` outer / `5.7pt` inner closed radii are unchanged.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh`; process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `0.1%` CPU.
- Rollback: Restore `statusSlotWidth` to `7.5` and the corresponding core-check expectations if the prior `200pt` default compact shell should return.

### 2026-06-17 - tune-default-compact-shell-radius
- Reason: User requested the default closed shell width become `200pt`, with outer corner radius `22.9pt` and inner corner radius `5.7pt`.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Sources/DynamicIsland/Views/IslandShape.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Default closed shell now derives to `200x32` from a `185pt` camera housing plus `7.5pt` side slots. Closed top/outer radius is `22.9pt`, closed bottom/inner radius is `5.7pt`, and the shape renderer preserves that paired radius instead of clamping each radius to half the shell height.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh`; process check showed DynamicIsland running from `dist/Dynamic Island.app` at about `0.9%` CPU.
- Rollback: Restore `statusSlotWidth` to `5`, closed top/bottom radii to `16`, and the previous `IslandShape` half-height radius clamp if the prior `195x32` compact shell should return.

### 2026-06-17 - rename-project-to-dynamic-island
- Reason: User requested the project name change to Dynamic Island and a cleaner local branch structure centered on `main`.
- Changed:
  - `Package.swift`
  - `Sources/DynamicIsland/`
  - `Sources/DynamicIslandCore/`
  - `Tests/DynamicIslandCoreChecks/`
  - `script/build_and_run.sh`
  - `script/set_task_activity.sh`
  - `docs/CODEX_GIT_WORKFLOW.md`
  - `docs/HANDOFF-2026-06-15.md`
  - `AGENTS.md`
  - `docs/superpowers/plans/2026-06-17-dynamic-island-rename-and-mainline.md`
  - `MEMORY.md`
- Result: The SwiftPM package, executable, module names, app display strings, bundle identifier, support directory, and user-facing status menu now use Dynamic Island / DynamicIsland naming, with legacy support-path fallback retained for cached display profiles. The work is being finished on a cleaned-up `main`-based local branch layout.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`; `./script/build_and_run.sh --verify`; `ps -o pid,stat,pcpu,pmem,etime,command -p $(pgrep -x DynamicIsland | head -n 1)` showed the renamed app running from `dist/Dynamic Island.app` at about `1.8%` CPU.
- Rollback: Revert the rename commit and restore the previous `Island` / `IslandCore` naming if the new branding should be backed out.

### 2026-06-17 - set-white-compact-shell-sizing
- Reason: User clarified the compact island background itself should become white, with closed height `32pt`, default width increased by `10pt`, music width increased by `10pt`, and closed corner radius set to `16pt`.
- Changed:
  - `Sources/IslandCore/NotchMetrics.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Sources/Island/Views/ClosedMusicAvatarView.swift`
  - `Sources/Island/Views/ClosedMusicWaveformView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Default closed shell is `195x32`, music closed shell is `260x32`, closed top and bottom radii are both `16pt`, the shell fill is white, and compact music accessories use black contrast on the white shell while preserving real artwork rendering.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; cleared display-profile cache; `./script/build_and_run.sh --verify`; visual crop confirmed the white compact shell at the top of the screen; CPU settled near idle.
- Rollback: Revert this event's changed files to return to the prior black compact shell with `185pt` default width and `250pt` music width.

### 2026-06-17 - restore-previous-empty-shell-hover-version
- Reason: User asked to restore the previous version after trying the physical-notch-matched default shell.
- Changed:
  - `Sources/IslandCore/NotchMetrics.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Restored the previous empty-shell hover behavior: closed shell width is back to `245` (`cameraHousingWidth + statusSlotWidth * 2`), mouse enter still does not auto-expand, and hover uses the prior subtle `scaleEffect` plus faint `.shadow`.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh --verify`; process check showed Island running from `dist/Island.app` near idle CPU.
- Rollback: Reapply `match-default-shell-to-physical-notch` if the physical-notch-matched closed shell is wanted again.

### 2026-06-17 - match-default-shell-to-physical-notch
- Reason: User felt the hover shadow looked visually detached, like a lower image layer, and clarified that the default shell should match the physical notch size, corner feel, and transition so it is not visibly an extra block until the cursor moves over it.
- Changed:
  - `Sources/IslandCore/NotchMetrics.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Closed shell width now matches `cameraHousingWidth` instead of adding side slots. Hover no longer uses SwiftUI external `.shadow`; it reveals the shell by subtly widening and lowering the black shape itself, with extra transparent window slack to avoid clipping. Click-to-expand remains available.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh --verify`; process check showed Island running from `dist/Island.app` near idle CPU.
- Rollback: Restore `closedShellWidth` to `cameraHousingWidth + statusSlotWidth * 2` and reintroduce external hover shadow if the wider always-visible shell is desired again.

### 2026-06-17 - change-empty-shell-hover-to-preview-only
- Reason: User provided full-screen reference screenshots showing that hover should only make the closed shell feel slightly larger with a faint shadow, not auto-expand into the large panel.
- Changed:
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Empty shell now tracks hover state separately from expanded state. Mouse enter sets a subtle closed-shell preview effect; it no longer calls `setExpanded(true)`. The closed transparent window keeps extra horizontal and bottom room so the hover scale and shadow are not clipped. Click-to-expand remains available.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh --verify`; process check showed Island running from `dist/Island.app` near idle CPU.
- Rollback: Restore mouse-enter to call `setExpanded(true)` and remove `isHovered`, hover scale/shadow, and closed hover slack if automatic hover expansion is wanted again.

### 2026-06-17 - strip-to-empty-expandable-shell
- Reason: User provided screenshots of the expanded Stats/content panel and collapsed status dot, then requested deleting those functions and content after making a fresh backup, leaving only an empty shell that can still expand normally.
- Changed:
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Sources/Island/Views/IslandTrackingHostingView.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Sources/Island/Controllers/AppDelegate.swift`
  - `script/build_and_run.sh`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Island now keeps the top black shell, notch-aware sizing, mouse hover expansion, tap-to-expand, menu-bar show/hide/quit, and app packaging. The visible status dot, waveform, Stats/Data panel, Files shelf, file-drop handling, task activity polling, audio polling, completion preview, and related TCC usage descriptions are removed from the active app path.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh --verify`; process check showed Island running from `dist/Island.app` near idle CPU after restart.
- Rollback: Restore these files from the user's backup or revert this event's changed files to bring back the Stats panel, status dot, waveform, File Shelf, task/audio polling, and completion feedback.

### 2026-06-17 - restore-expanded-island-to-pre-size-change
- Reason: User decided to roll back the expanded island size adjustment and return to the version before the `900x205` layout tuning.
- Changed:
  - `Sources/IslandCore/NotchMetrics.swift`
  - `Sources/IslandCore/DisplayProfile.swift`
  - `Sources/Island/Views/TemporaryFileShelfView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Expanded island sizing is back on the previous `700x230` contract, the old display-profile cache behavior is restored, and File Shelf keeps the second-stage filter/multidrag work without the compact 4-column density tuning.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; deleted stale `~/Library/Application Support/Island/display-profile.json`; restarted app and confirmed cache regenerated to `700x230`; CPU settled near idle after startup.
- Rollback: Reapply the `900x205` sizing and cache invalidation changes if the wider, shallower expanded shell is wanted again.

### 2026-06-17 - complete-file-shelf-phase-2-filter-and-multidrag
- Reason: User wanted Phase 2 finished before moving on: add the `All / Images / Documents / Sheets / Slides / Other` second-level filter in the File Shelf and fix multi-selected drag-out so external apps receive every selected file, not only one.
- Changed:
  - `docs/superpowers/plans/2026-06-17-file-shelf-phase-2.md`
  - `Sources/IslandCore/TemporaryFileShelf.swift`
  - `Sources/Island/Views/TemporaryFileShelfView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: File Shelf now has a compact filter bar below the header. Filtering changes only visible items; selected files persist across filter switches unless explicitly cleared. Dragging from a selected tile content area now starts an AppKit multi-item drag with one file URL drag item per selected file, improving compatibility with Finder, Desktop, and other file-accepting apps. Remove-on-success after external drop is still Phase 3.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`.
- Rollback: Remove `TemporaryFileShelfFilter`, restore `TemporaryFileShelfView` to unfiltered grouped rendering, and replace the AppKit drag-source bridge with the prior single-item drag path if the filter/multidrag behavior should be disabled.

### 2026-06-17 - fix-file-shelf-selected-drag-provider
- Reason: User reported that after rectangle-selecting multiple File Shelf items, dragging the selection still exported only one file. Root cause was that each tile's SwiftUI `.onDrag` always returned a provider for only the pressed item and did not consult `selectedItemIDs`.
- Changed:
  - `Sources/Island/Views/TemporaryFileShelfView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Dragging an unselected tile still exports only that tile. Dragging a selected tile now exports all currently selected file URLs through a multi-file `NSItemProvider` helper. This does not remove items from the shelf after drop; remove-on-success remains Phase 3a.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; process CPU check after restart showed Island running at about 1.6% CPU shortly after launch.
- Rollback: Restore the tile `.onDrag` body to a single `NSItemProvider(contentsOf: item.fileURL)` if multi-file selected drag should be disabled.

### 2026-06-17 - complete-file-shelf-phase-2-selection
- Reason: User asked to continue Phase 2 of the File Shelf roadmap: add selection state, click selection, empty-space clear, and rectangle selection without moving into Phase 3 drag-out removal.
- Changed:
  - `docs/superpowers/plans/2026-06-17-file-shelf-phase-2.md`
  - `Sources/IslandCore/TemporaryFileShelf.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Sources/Island/Views/TemporaryFileShelfView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Added `TemporaryFileShelfSelection` in IslandCore, wired selected item IDs through overlay/controller state, added click-to-select and empty-shelf clear behavior, highlighted selected tiles without changing size, and added rectangle selection over visible item frames with a 5pt threshold and no auto-scroll in Phase 2.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; process CPU check after restart showed Island running at about 2.4% CPU shortly after launch.
- Rollback: Remove `TemporaryFileShelfSelection`, strip selected ID state from overlay/controller/view, and restore the pre-selection File Shelf if Phase 2 should be removed.

### 2026-06-17 - tune-file-shelf-drag-sounds
- Reason: User approved the File Shelf interaction but clarified the sound mapping: dragging files into Island should use the previous sound, while dragging away or failing to complete the drop should keep the current cancellation sound.
- Changed:
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: File drag-in accept feedback now uses a one-shot `Glass` sound through `FileDragAcceptSound`; drag cancel/unsuccessful exit continues to use one-shot `Tink` through `FileDragCancelSound`. Visual file-drop bottom-edge feedback remains separate from Codex completion feedback.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; process CPU check after restart showed Island running at about 3.5% CPU shortly after launch.
- Rollback: Change `FileDragAcceptSound.name` back to the prior sound if the accept cue should differ from `Glass`.

### 2026-06-17 - restore-file-shelf-pinning-and-separate-drop-feedback
- Reason: User clarified that clicking `Files` must keep the File Shelf resident, and the previous fix incorrectly made it collapse on mouse exit. User also reported that file drag-in feedback was still not visible enough and the sound behavior still mixed with Codex completion feedback.
- Changed:
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: `Files` button mode is resident again: pinned File Shelf ignores mouse exit until the user clicks `Done`, clicks `Files` again, clears/removes all files, or another explicit close path runs. File drag-in now uses a dedicated `fileDropFeedbackTrigger` and one-shot `Pop` accept sound instead of Codex completion's delayed three-Glass sequence. Dragging away before drop uses one `Tink` cancel sound. Drag enter/drop no longer clears `isFileShelfPinnedOpen`, so adding files while the shelf is open preserves resident mode.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; process CPU check after restart showed Island running at about 1.5% CPU shortly after launch.
- Rollback: Restore mouse-exit collapse for `isFileShelfPinnedOpen`, route file drag enter back to `triggerCompletionFeedback()`, and remove `fileDropFeedbackTrigger`, `FileDragAcceptSound`, and the scoped drag feedback tests if the older transient overlay behavior is wanted again.

### 2026-06-17 - fix-file-shelf-return-and-drag-feedback
- Reason: User found that clicking `Files` trapped the app in the File Shelf overlay, prevented normal shrink behavior, and gave unclear feedback when dragging a file into Island then dragging it away. User also wanted the expanded File Shelf state to show the same bottom-edge q-bounce feedback when a file drag enters.
- Changed:
  - `Sources/IslandCore/NotchMetrics.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Sources/Island/Views/TemporaryFileShelfView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: File Shelf now has a `Done` action to return to the previous feature page without deleting temporary files. Clicking the active `Files` button toggles the overlay closed. Mouse exit no longer gets blocked by `isFileShelfPinnedOpen`, so the island can shrink normally. Drag-enter still triggers completion-style bounce, expanded state now allows the bottom edge to bounce, and drag-exit before drop cancels pending completion sounds and plays a distinct `Tink` cancel sound once.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; process CPU check after restart showed Island running at about 2.0% CPU shortly after launch.
- Rollback: Remove `onDismissFileShelf`/`Done`, restore the pinned-open mouse-exit guard, change expanded `bottomEdgeDrop` back to zero, remove `openCompletionFeedbackWindowSize`, and remove `FileDragCancelSound` if the File Shelf should return to the previous modal behavior.

### 2026-06-17 - complete-file-shelf-phase-1-categories
- Reason: User approved Phase 1 of the File Shelf roadmap: categorize temporary files so images, documents, spreadsheets, presentations, and other files are no longer mixed together, and show a dashed visible shelf range.
- Changed:
  - `docs/superpowers/plans/2026-06-17-file-shelf-phase-1.md`
  - `Sources/IslandCore/TemporaryFileShelf.swift`
  - `Sources/Island/Views/TemporaryFileShelfView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: `TemporaryShelfItem` now exposes `category` from normalized file extensions. The shelf view renders non-empty category sections in the approved order, shows each category count, and wraps the shelf content in a dashed rounded boundary while preserving Open, Remove, Clear, and drag-out behavior.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; process CPU check after launch showed Island running at about 3.0% CPU shortly after restart.
- Rollback: Remove `TemporaryShelfFileCategory` and `TemporaryShelfItem.category`, restore the single mixed `LazyVGrid` in `TemporaryFileShelfView`, and remove the Phase 1 tests if returning to an ungrouped shelf.

### 2026-06-17 - replace-file-shelf-drag-delay-with-completion-feedback
- Reason: User wanted to remove the 1s wait before file shelf drag recognition and instead use the existing Codex completion-style bottom bounce plus notification sound as the feedback cue.
- Changed:
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: File drag enter now immediately opens the file shelf overlay, marks the drop target active, and calls `triggerCompletionFeedback()` so the same bottom-edge bounce and Glass sound sequence is reused. The old file drag hover task and drag-specific 1s delay were removed.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; process CPU check after launch.
- Rollback: Reintroduce a drag hover task in `handleFileDragEntered` if delayed recognition is preferred again, and remove the drag-enter call to `triggerCompletionFeedback()`.

### 2026-06-17 - add-temporary-file-shelf-overlay
- Reason: User wanted a Mac notch-style temporary file shelf: dragging files to the notch and pausing about 1s should open a dedicated file shelf overlay, with a `Files` button in the expanded top-left safe band near the camera housing when temporary files exist.
- Changed:
  - `docs/superpowers/specs/2026-06-17-file-shelf-overlay-design.md`
  - `docs/superpowers/plans/2026-06-17-file-shelf-overlay.md`
  - `Sources/IslandCore/TemporaryFileShelf.swift`
  - `Sources/IslandCore/IslandTopStatusBandLayout.swift`
  - `Sources/Island/Support/TemporaryFileShelfStore.swift`
  - `Sources/Island/Views/IslandTrackingHostingView.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Sources/Island/Views/TemporaryFileShelfView.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Tests/IslandCoreChecks/main.swift`
- Result: Added an in-memory-only file shelf with 24h expiry, file URL dedupe, drag-hover delayed expansion, shelf overlay precedence over feature content, click-to-open/remove/clear actions, drag-out item providers, and a safe-band `Files` button placed from `IslandTopStatusBandLayout.fileShelfButtonFrame`.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; process CPU check after launch.
- Rollback: Remove the temporary shelf model/store/view, remove file-drag callbacks from `IslandTrackingHostingView`, remove file shelf state/actions from `IslandOverlayView` and `IslandPanelController`, and remove `fileShelfButtonFrame` from `IslandTopStatusBandLayout`.

### 2026-06-16 - refine-completion-bounce-selected-shell-only
- Reason: User clarified the completion animation should be the default closed island's bottom border bouncing downward, not the whole shell moving or scaling. The small status dot should not move with it, the bounce should run twice, and the notification sound should still play three times.
- Changed:
  - `Sources/IslandCore/NotchMetrics.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Sources/Island/Views/IslandShape.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Tests/IslandCoreChecks/main.swift`
- Result: Completion feedback now animates `IslandShape.bottomEdgeDrop` only in the closed state. The top edge, width, status dot, and attached content remain fixed, while the closed shell bottom border drops and returns twice. `NotchMetrics` owns the shared bounce drop and closed-state window slack. The existing three Glass sound playback remains unchanged.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; triggered `Preview Completion Bounce` from the status-bar menu; screenshot sampling showed the detected bottom edge moving from about `65` to `89/90` and returning to `65`.
- Rollback: Set `bottomEdgeDrop` to `0`, remove `closedCompletionBounceDrop`/`closedCompletionFeedbackWindowSize`, and return the closed panel size to `closedWindowSize` if bottom-border feedback should be disabled.

### 2026-06-16 - replace-completion-sweep-with-island-bounce
- Reason: User could not see the menu-bar line sweep after repeated attempts and chose a clearer completion cue: the collapsed island should bounce a few times, then play the system notification sound three times.
- Changed:
  - `Sources/Island/Controllers/AppDelegate.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - Removed `Sources/Island/Controllers/TaskCompletionSweepWindowController.swift`
  - Removed `Sources/Island/Views/TaskCompletionSweepView.swift`
- Result: Codex `task_complete` events and the status-bar preview now trigger the island shell itself to bounce three times and play the macOS Glass sound three times. The unreliable full-width white line sweep overlay is removed.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`.
- Rollback: Restore the removed sweep controller/view and route completion triggers back to the full-width overlay if the line sweep is wanted again.

### 2026-06-16 - move-completion-sweep-to-full-width-top-overlay
- Reason: User said the first sweep effect was still too small and not the menu-bar-wide completion sweep they wanted.
- Changed:
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Sources/Island/Controllers/TaskCompletionSweepWindowController.swift`
  - `Sources/Island/Controllers/AppDelegate.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Sources/Island/Views/TaskCompletionSweepView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The completion sweep is now driven by a dedicated transparent top overlay window spanning the full screen width. The overlay ignores mouse events, plays a one-shot left/right convergence toward the screen center, flashes briefly at the center, and then disappears. Menu preview and real Codex completion now share the same full-width trigger path.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`.
- Rollback: Remove `TaskCompletionSweepWindowController` and restore the sweep to the island window if the full-width overlay should be disabled.

### 2026-06-16 - add-menu-preview-for-completion-sweep
- Reason: User wanted a status-bar menu item to manually trigger the Codex completion sweep effect for visual verification.
- Changed:
  - `Sources/Island/Controllers/AppDelegate.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Added a `Preview Completion Sweep` status-bar menu item that calls a preview-only controller method. It increments a local preview ID and replays the one-shot sweep without changing Codex task state or cached display profile data.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`.
- Rollback: Remove the menu item and `previewCompletionSweep()` if the manual preview trigger is no longer needed.

### 2026-06-16 - add-codex-task-completion-sweep
- Reason: User wanted a menu-bar sweep completion effect: white lines from both sides converge toward the camera-housing center, briefly flash, then all lines disappear. The effect must trigger only when a Codex task completes.
- Changed:
  - `Sources/Island/Support/TaskActivityDataSource.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Sources/Island/Views/TaskCompletionSweepView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Added `TaskActivitySnapshot` with an optional `completionEventID`, derived from latest Codex `task_complete` events. `IslandPanelController` forwards new completion IDs once to `IslandOverlayState`, and `TaskCompletionSweepView` plays a one-shot two-sided white sweep with a small center flash before fading out.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; injected a temporary Codex JSONL `task_started`/`task_complete` preview event, then removed it; Island CPU returned near idle after the effect.
- Rollback: Remove `TaskCompletionSweepView`, restore `TaskActivityDataSource` to state-only polling, and stop forwarding `completionSweepID` if the completion animation should be disabled.

### 2026-06-16 - add-display-profile-debug-tools-panel
- Reason: User said there are three display adaptation phases and approved the final phase, then asked to run through the project and identify remaining optimization needs.
- Changed:
  - `Sources/Island/Views/DataPanelView.swift`
  - `Sources/Island/Support/DisplayProfileStore.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The `Tools` top-level feature is no longer an empty placeholder. It now shows a compact Display Profile debug panel with profile kind, closed/open dimensions, camera housing width, frame size, safe top inset, auxiliary left/right widths, backing scale, and the local `display-profile.json` cache path. `DisplayProfileStore` exposes `currentProfile()` for the panel.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; visual screenshot attempt confirmed the app stays collapsed until hover, so the panel is validated by source checks and build/runtime status.
- Rollback: Change the `tools` branch in `DataPanelView.featureContent` back to the placeholder and remove `DisplayProfileStore.currentProfile()` if the debug panel should be removed.

### 2026-06-16 - add-display-adaptation-profile-kinds
- Reason: User approved the next phase after first-run display calibration: use measured display data to adapt beyond the 14-inch MacBook Pro baseline.
- Changed:
  - `Sources/IslandCore/NotchMetrics.swift`
  - `Sources/IslandCore/DisplayProfile.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Added `DisplayProfileKind` with `notchedCompact`, `notchedLarge`, and `standardDisplay`. Compact notched displays keep the approved 14-inch `700x230` expanded shell; larger notched displays scale the expanded shell from screen size; non-notched/standard displays use a smaller top panel profile. The cached display profile now stores `displayKind`.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; confirmed current 14-inch cache rewrote with `displayKind: notchedCompact`, `openWidth: 700`, and `openHeight: 230`.
- Rollback: Remove `DisplayProfileKind`, return `NotchMetrics.fromDisplay` to fixed `openWidth/openHeight`, and delete the local `display-profile.json` if profile-kind adaptation should be disabled.

### 2026-06-16 - add-display-calibration-profile-cache
- Reason: User wanted first launch to show a small English loading/calibration caption below the camera housing while the app measures display data, then cache those measurements locally so later launches do not repeat the visible loading step on the same display.
- Changed:
  - `Sources/IslandCore/DisplayProfile.swift`
  - `Sources/Island/Support/DisplayProfileStore.swift`
  - `Sources/Island/Support/ScreenMetricsProvider.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Tests/IslandCoreChecks/main.swift`
- Result: Added a Codable display signature/profile model, persisted `~/Library/Application Support/Island/display-profile.json`, and made `ScreenMetricsProvider` prefer a matching cached profile. When a profile is newly measured, the overlay briefly shows `Calibrating display...` below the closed island; matching cached launches skip the caption and reuse cached metrics.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; confirmed `display-profile.json` was created; restarted again and confirmed the profile SHA-256 hash stayed unchanged on cache hit; Island process settled near idle CPU after startup.
- Rollback: Remove the display profile model/store, return `ScreenMetricsProvider.metrics(for:)` to direct runtime measurement, and delete `~/Library/Application Support/Island/display-profile.json` if cached display calibration should be disabled.

### 2026-06-16 - persist-selected-top-level-feature
- Reason: User asked the app to remember the last selected top-level feature instead of always opening `Stats`.
- Changed:
  - `Sources/Island/Views/DataPanelView.swift`
  - `Tests/IslandCoreChecks/main.swift`
- Result: `Status / Stats / Tools` selection is stored with `@AppStorage("island.selectedFeature")`; the app restores the last valid selection and falls back to `Stats` when the stored value is invalid or missing.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`.
- Rollback: Replace the persisted raw value with `@State private var feature: IslandFeature = .defaultFeature` if the app should always start on `Stats`.

### 2026-06-16 - save-clean-project-baseline
- Reason: User asked to overwrite the remaining side-terminal changes and save the cleanest current project state.
- Changed:
  - `MEMORY.md`
  - Git baseline
  - Ignored generated folders
- Result: The current cleaned source tree is intended to become the new repository baseline. Transient backup/build/output artifacts are removed from the workspace after verification.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; removed `.backup`, `.build`, `dist`, `output`, and `.superpowers` as transient workspace artifacts.
- Rollback: Use the Git commit before this baseline if the saved clean state needs to be undone.

### 2026-06-16 - cleanup-project-memory-and-legacy-claude-sources
- Reason: User confirmed project memory should use `MEMORY.md` going forward and asked to clean unnecessary files/code with senior engineering judgment.
- Changed:
  - `AGENTS.md`
  - `MEMORY.md`
  - `Sources/Island/Support/ClaudeTaskActivityDataSource.swift`
  - `Sources/Island/Support/ClaudeUsageDataSource.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - Finder/Playwright generated files
- Result: Project memory is standardized on `MEMORY.md`. Removed legacy Claude-only data sources so Codex usage and task activity stay on the current Codex/CC Switch paths instead of carrying unused, misleading implementation paths. Core checks now assert the legacy Claude usage source file is absent.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; `ps -o pid,stat,pcpu,pmem,etime,command -p $(pgrep -x Island | head -n 1)` showed Island running from `dist/Island.app` at about 2.2% CPU after restart.
- Rollback: Restore the deleted Claude source files only if the product explicitly adds Claude-specific stats or task activity as a separate selected feature.

### 2026-06-15 - remove-ecg-code-and-restore-static-default-waveform
- Reason: User clarified the default right-side stripe should be the original single static line and explicitly said not to keep ECG code.
- Changed:
  - `Sources/IslandCore/AudioPlaybackState.swift`
  - `Sources/IslandCore/ECGWaveformModel.swift`
  - `Sources/Island/Views/AudioWaveformView.swift`
  - `Sources/Island/Support/AudioPlaybackDataSource.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `docs/HANDOFF-2026-06-15.md`
  - `MEMORY.md`
- Result: Deleted `ECGWaveformModel.swift`, removed `.heartbeat` and `fallbackHeartbeat`, removed the ECG rendering branch, monitor scan head, ECG color, and glow-only fallback path. The no-player/default state now returns `AudioPlaybackSnapshot.defaultFallback`, which is `.idle`, so the right-side stripe is a static line unless real/synthetic music playback levels are present.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; `ps -o pid,stat,pcpu,pmem,etime,command -p $(pgrep -x Island | head -n 1)` showed Island running at about 0.5% CPU after restart.
- Rollback: Reintroduce ECG only from an explicit new user request; do not treat older ECG events as current desired behavior.

### 2026-06-15 - make-default-waveform-monitor-ecg
- Reason: User clarified the default waveform should be a real ECG monitor effect: flat baseline, P/QRS/T structure, continuous scan, and subtle afterglow, not a music spectrum, sine wave, water ripple, or random motion.
- Changed:
  - `Sources/IslandCore/AudioPlaybackState.swift`
  - `Sources/Island/Views/AudioWaveformView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Added `AudioPlaybackSnapshot.defaultFallback` as the default no-audio presentation and pointed `AudioWaveformView()` at it, so standalone/default waveform rendering uses the dedicated ECG fallback. Core checks now assert the default is ECG, the fallback is generated by `ECGWaveformModel`, the ECG branch keeps glow and disables shimmer, and music waveform rendering stays separate.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`.
- Rollback: Revert this event's changed files if the default no-audio waveform should return to an idle/static baseline.

### 2026-06-15 - add-super-detailed-handoff-document
- Reason: User asked to generate a super detailed handoff document for the current project state.
- Changed:
  - `docs/HANDOFF-2026-06-15.md`
  - `MEMORY.md`
- Result: Added a handoff document covering the product goal, current architecture, key source files, ECG/music waveform decisions, top-band layout constraints, verification commands, historical pitfalls, rollback strategy, and recommended next-step order.
- Verify: Documentation-only change; checked the file was created and readable.
- Rollback: Remove `docs/HANDOFF-2026-06-15.md` and this event if the handoff document should be regenerated from scratch.

### 2026-06-15 - restore-monitor-style-ecg-waveform-fallback
- Reason: User clarified the desired fallback is a hospital ECG monitor trace, not ordinary waves, audio spectrum bars, or decorative ripples.
- Changed:
  - `Sources/IslandCore/AudioPlaybackState.swift`
  - `Sources/Island/Support/AudioPlaybackDataSource.swift`
  - `Sources/Island/Views/AudioWaveformView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Restored a dedicated `.heartbeat` presentation mode for `AudioPlaybackSnapshot.fallbackHeartbeat`. When no supported player is actively playing, the privacy-friendly AppleScript data source returns the ECG fallback. `AudioWaveformView` now renders that fallback through `ECGWaveformModel.heartbeatLevels` in a separate branch with a thin line and subtle glow, while real music playback still uses the audio-level waveform branch. Tests now require a mostly flat baseline with occasional P-Q-R-S-T heartbeat structure.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; `ps -o pid,stat,pcpu,pmem,etime,command -p $(pgrep -x Island | head -n 1)` showed Island running at about 0.7% CPU after restart.
- Rollback: Revert this event's changed files or restore `fallbackHeartbeat` to `.idle` and remove the `ecgWaveform` branch if the fallback should return to a static baseline.

### 2026-06-15 - disable-heartbeat-waveform-fallback
- Reason: User said the heartbeat waveform effect was wrong and asked to stop it.
- Changed:
  - `Sources/IslandCore/AudioPlaybackState.swift`
  - `Sources/Island/Support/AudioPlaybackDataSource.swift`
  - `Sources/Island/Views/AudioWaveformView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The no-player/no-music fallback now returns `.idle` and renders only a static baseline. `AudioWaveformView` no longer has an ECG/heartbeat rendering branch, so continuous heartbeat animation is not shown when no supported player is playing. Music playback can still use the audio-level waveform path.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; `ps -o pid,stat,pcpu,pmem,etime,command -p $(pgrep -x Island | head -n 1)` showed Island running at about 2% CPU after restart.
- Rollback: Restore the previous `fallbackHeartbeat` presentation and ECG rendering branch if a heartbeat-style idle animation is intentionally reintroduced later.

### 2026-06-15 - fix-ecg-absolute-time-cpu-spin
- Reason: User reported hovering over the island showed the macOS spinning cursor and the island did not expand.
- Changed:
  - `Sources/IslandCore/ECGWaveformModel.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Root cause was `ECGWaveformModel.heartbeatLevels` using `TimelineView`'s absolute `timeIntervalSinceReferenceDate` as a beat index and then summing every historical beat up to that index. That made each frame loop over hundreds of millions of beats, pinning Island at about 100% CPU. The model now normalizes phase into a short repeating window, keeping ECG variation while making work constant-time. Added a regression check that absolute timeline time returns quickly.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; `ps -o pid,stat,pcpu,pmem,etime,command -p $(pgrep -x Island | head -n 1)` now shows around 1% CPU after restart.
- Rollback: Revert the ECG model only if removing natural ECG cadence variation; do not restore historical beat accumulation.

### 2026-06-15 - pause-hidden-waveform-to-fix-hover-spin
- Reason: User reported the app could not open normally and the cursor kept spinning when hovering over the island.
- Changed:
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Root cause was that the audio waveform `TimelineView` kept animating even when the waveform was hidden in the collapsed island via `opacity(0)`, causing high CPU and hover lag. The overlay now derives `visibleAudioPlayback` and passes `.idle` while collapsed, so hidden waveform animation is paused. Local CPU after restart dropped from roughly 90-100% to around 1%.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; `ps -o pid,stat,pcpu,pmem,command -p $(pgrep -x Island | head -n 1)`.
- Rollback: Revert the overlay change if hidden waveform animation should run while collapsed, but expect high CPU and hover lag to return.

### 2026-06-15 - add-core-audio-process-tap-waveform-backend
- Reason: User liked the Core Audio process tap approach for macOS and wanted a better way to read background music audio for real waveform rendering.
- Changed:
  - `Sources/Island/Support/AudioPlaybackDataSource.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Added `CoreAudioProcessTapAudioPlaybackDataSource`, selectable with `ISLAND_CORE_AUDIO_TAP_WAVEFORM=1`. It maps supported player PIDs to Core Audio process objects with `kAudioHardwarePropertyTranslatePIDToProcessObject`, creates a private process tap, reads audio through an aggregate-device IOProc, converts samples into waveform buckets, and falls back to the existing AppleScript/ECG path when unavailable. Default mode remains privacy-friendly and unchanged.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`.
- Rollback: Revert the files above to remove the Core Audio process tap backend and keep only AppleScript fallback plus ScreenCaptureKit opt-in.

### 2026-06-15 - keep-music-waveform-separate-while-refining-ecg
- Reason: User approved further heartbeat refinement but emphasized the waveform must still consider music playback.
- Changed:
  - `Sources/IslandCore/ECGWaveformModel.swift`
  - `Sources/Island/Views/AudioWaveformView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: ECG fallback now has subtle beat-to-beat cadence/amplitude variation so it feels less mechanical. `AudioWaveformView` now uses explicit `audioLevelsWaveform` and `ecgWaveform` branches: music playback keeps the audio-level waveform with shimmer, while ECG heartbeat uses the dedicated ECG model without music shimmer and with a subtle monitor-like glow.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`.
- Rollback: Revert the files above to restore the previous shared waveform branch and fixed ECG cycle.

### 2026-06-15 - rewrite-heartbeat-waveform-as-ecg-template
- Reason: User said the fallback waveform did not look like a real wave and clarified the heartbeat should look like a hospital monitor ECG trace, not just a generic moving wave.
- Changed:
  - `Sources/IslandCore/ECGWaveformModel.swift`
  - `Sources/Island/Views/AudioWaveformView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Added a testable ECG waveform model with explicit P wave, Q dip, R peak, S dip, and T wave structure. The heartbeat fallback now renders from this model through the existing continuous `TimelineView` path, while real audio levels still use the audio waveform branch.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`.
- Rollback: Revert the files above to restore the previous ad hoc heartbeat function inside `AudioWaveformView.swift`.

### 2026-06-15 - add-user-intent-interpretation-work-rule
- Reason: User asked to record that their future requirements may be non-technical, unclear, or emotional, and should be interpreted through product manager and senior software engineer judgment.
- Changed:
  - `AGENTS.md`
  - `MEMORY.md`
- Result: Added a project work rule requiring future agents to infer the real product goal, clarify key assumptions in product language, and break work into verifiable steps instead of mechanically following literal wording.
- Verify: Documentation-only change; no build required.
- Rollback: Remove the added work-rule bullet from `AGENTS.md` and this event if the collaboration style should return to literal requirement handling.

### 2026-06-15 - fix-cache-hit-label-and-ccswitch-rate-denominator
- Reason: User reported the cache hit label should be English and the displayed cache hit rate was not using the real cache rate.
- Changed:
  - `Sources/Island/Support/CCSwitchUsageDataSource.swift`
  - `Sources/Island/Views/DataPanelView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Overview cache card label changed from `命中缓存` to `CACHE HIT`. CC Switch ledger events now pass cache-inclusive input tokens (`freshInputTokens + cachedInputTokens`) into `CodexTokenUsage.inputTokens`, so `cachedInputHitRate` uses the real denominator instead of dividing cached tokens by fresh input only, which could incorrectly show 100%.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`.
- Rollback: Revert these files to restore the Chinese label and previous fresh-input denominator behavior.

### 2026-06-15 - align-right-waveform-and-cost-badge
- Reason: User reported the right-side waveform and balance/cost badge did not feel horizontally aligned.
- Changed:
  - `Sources/Island/Views/DataPanelView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Moved the top-right cost badge down by 4pt by changing `costBadgeVerticalOffset` from `-34` to `-30`, aligning its 24pt frame center with the 32pt top status band centerline used by the waveform. Tests now assert waveform and cost badge share the same horizontal centerline.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`.
- Rollback: Restore `costBadgeVerticalOffset` to `-34` if the badge should return to the previous higher position.

### 2026-06-15 - replace-overview-cost-card-with-cache-hit-rate
- Reason: User asked to rename the overview `EST COST` module to cache hit and change its data to cache hit rate before phase 3.
- Changed:
  - `Sources/IslandCore/CodexUsage.swift`
  - `Sources/Island/Views/DataPanelView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: `CodexUsageSummary` now exposes `cachedInputHitRate`, computed as cached input tokens divided by total input tokens. The overview metric card previously labeled `EST COST` now shows `命中缓存` with a percentage value, while the separate top-right cost badge remains unchanged.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`.
- Rollback: Revert these files to restore the overview cost card and remove the derived cache hit-rate metric.

### 2026-06-15 - move-audio-waveform-to-right-info-region
- Reason: User asked to move the audio waveform to the right before starting phase 3.
- Changed:
  - `Sources/IslandCore/IslandTopStatusBandLayout.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The expanded waveform now lives in the right info region, to the right of the physical camera housing and to the left of the top cost badge. The status dot remains in the left status region. Tests were updated so waveform placement is validated against the right info region and the cost badge gap instead of the previous left-lane position.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`.
- Rollback: Revert these files to place the waveform back in the left status region next to the status dot.

### 2026-06-15 - heartbeat-waveform-fallback-when-no-player-process
- Reason: User wanted the waveform to automatically play a real-looking heartbeat trace when no related player process is detected, instead of staying static.
- Changed:
  - `Sources/IslandCore/AudioPlaybackState.swift`
  - `Sources/Island/Support/AudioPlaybackDataSource.swift`
  - `Sources/Island/Views/AudioWaveformView.swift`
  - `Tests/IslandCoreChecks/main.swift`
- Result: Added an explicit `AudioWaveformPresentationMode` so waveform presentation is separated from detected audio content. `AudioPlaybackSnapshot.fallbackHeartbeat` now represents the no-player fallback, `AppleScriptAudioPlaybackDataSource` returns that fallback when no supported player is playing, and `AudioWaveformView` renders a continuous heartbeat-style trace with `TimelineView` instead of a static idle line. Real audio levels still use the previous active waveform path.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`.
- Rollback: Revert the files above to restore the previous idle/static fallback behavior.

### 2026-06-15 - phase2-top-status-band-layout-contract
- Reason: User approved phase 2 after phase 1, to formalize the expensive 32pt top band as left status region, physical camera housing exclusion zone, and right info region.
- Changed:
  - `Sources/IslandCore/IslandTopStatusBandLayout.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Added `IslandTopStatusBandLayout` in `IslandCore` so top-band regions and glanceable item frames are explicit and testable. The expanded status dot and audio waveform now derive their top-lane placement from this contract. Tests assert the left status region, centered camera housing region, and right info region do not overlap, and that status dot, waveform, and cost badge frames stay in their approved regions.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`.
- Rollback: Revert the files above to return top-lane placement to direct `NotchMetrics` center-point usage without a region contract.

### 2026-06-15 - phase1-unify-island-animation-profile
- Reason: User asked to apply senior macOS engineering feedback in phases, starting with animation consistency before layout and state layering.
- Changed:
  - `Sources/IslandCore/IslandAnimationProfile.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Added a shared `IslandAnimationProfile.default` for the island expand/collapse rhythm, attached element travel timing, content scale, waveform scale, and collapse canvas delay. Overlay and panel controller now reference the same profile instead of scattering hardcoded animation values, while existing status-dot Core Animation breathing and waveform TimelineView behavior remain unchanged.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`.
- Rollback: Revert the files above to restore direct hardcoded SwiftUI animation values in `IslandOverlayView` and `IslandPanelController`.

### 2026-06-15 - prevent-missing-player-choose-application-dialog
- Reason: User reported that launching/restarting Island showed a macOS `Choose Application` dialog asking `Where is Spotify?`.
- Changed:
  - `Sources/Island/Support/AudioPlaybackDataSource.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The default AppleScript playback detector now checks `NSWorkspace.shared.runningApplications` by player bundle identifier before executing any AppleScript for that player. Missing or not-running players such as Spotify are skipped, so AppleScript no longer asks the user to locate the app during startup. This dialog was separate from ScreenCaptureKit/system-audio permission.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`.
- Rollback: Revert these files if returning to name-only AppleScript player detection, but expect missing apps to trigger locate-application dialogs again.

### 2026-06-15 - default-audio-waveform-without-system-capture
- Reason: User did not want the macOS menu bar sharing/recording indicator to occupy limited taskbar space, and reported that the waveform looked like it refreshed once per second instead of moving continuously.
- Changed:
  - `Sources/Island/Support/AudioPlaybackDataSource.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Sources/Island/Views/AudioWaveformView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Default audio mode no longer starts ScreenCaptureKit, so Island does not trigger the screen/system audio sharing indicator by default. The default source uses cached AppleScript player-state detection and renders a smooth synthetic music waveform when playback is active. Real system-audio sampling remains available only by launching with `ISLAND_REAL_AUDIO_WAVEFORM=1`, which will require macOS recording permission and can show the sharing indicator. Active waveform rendering now uses a 30fps `TimelineView`, and audio state refresh is faster while player-state checks are cached.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; `/usr/bin/log show --last 30s --info --debug --style compact --predicate 'subsystem == "cx.island.mvp"'` shows no ScreenCaptureKit startup in default mode.
- Rollback: Change `IslandPanelController` back to `ScreenCaptureAudioPlaybackDataSource()` and remove the `TimelineView`/factory changes if real audio capture should again be the default.

### 2026-06-15 - stabilize-island-tcc-signing-for-audio-capture
- Reason: User showed that Island was already enabled in macOS Screen & System Audio privacy settings, but ScreenCaptureKit still reported TCC denial.
- Changed:
  - `script/build_and_run.sh`
  - `Sources/Island/Support/AudioPlaybackDataSource.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Found the generated app bundle was ad-hoc signed with a `cdhash`-only designated requirement and `Info.plist` was not bound, so TCC could treat rebuilt apps as a different identity. The build script now signs the full app bundle after writing `Info.plist`, preferring `ISLAND_CODESIGN_IDENTITY` or the first local codesigning identity before falling back to ad-hoc. Audio capture now explicitly runs `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess` and logs permission status before starting ScreenCaptureKit.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; `codesign -d -r- dist/Island.app` now reports `identifier "cx.island.mvp" and certificate leaf = ...`; logs show the current remaining blocker is `screen capture permission request result: false`.
- Rollback: Revert these files to return to ad-hoc bundle signing and direct ScreenCaptureKit startup; expect TCC authorization to become unstable again across rebuilds.

### 2026-06-15 - diagnose-audio-waveform-screen-capture-permission
- Reason: User showed Music playing while the top waveform still looked nearly static and asked what happened.
- Changed:
  - `Sources/Island/Support/AudioPlaybackDataSource.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Added audio capture diagnostics under `cx.island.mvp/audio` and changed ScreenCaptureKit sample parsing to read the actual PCM format from each sample buffer, supporting Float32/Float64 and signed 16/24/32-bit PCM instead of assuming Float32. Local logs showed the current machine denies ScreenCaptureKit with TCC error `Code=-3801`, so Island is falling back to player-state detection rather than receiving real audio samples.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh`; `/usr/bin/log show --last 60s --info --debug --style compact --predicate 'subsystem == "cx.island.mvp"'`.
- Rollback: Revert `AudioPlaybackDataSource.swift` and the new checks if removing ScreenCaptureKit diagnostics and multi-format PCM parsing.

### 2026-06-15 - drive-waveform-from-system-audio-samples
- Reason: User asked whether the waveform was accurate or virtual, then approved making it reflect real audio.
- Changed:
  - `Sources/IslandCore/AudioPlaybackState.swift`
  - `Sources/Island/Support/AudioPlaybackDataSource.swift`
  - `Sources/Island/Views/AudioWaveformView.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `script/build_and_run.sh`
- Result: Waveform state now carries real audio level samples. `ScreenCaptureAudioPlaybackDataSource` uses ScreenCaptureKit system audio output to compute normalized RMS buckets for the waveform, with the existing AppleScript playback detector as fallback if capture is unavailable. The app bundle declares screen/audio capture usage for permission prompts.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`.
- Rollback: Revert the files above to return to playback-state-only virtual waveform animation.

### 2026-06-15 - fix-audio-waveform-apple-events-permission
- Reason: User reported the waveform still did not react while Music was actually playing.
- Changed:
  - `Sources/Island/Support/AudioPlaybackDataSource.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `script/build_and_run.sh`
- Result: Confirmed the audio probe can see Music playing from the terminal, but the Island app bundle needed an Apple Events usage description to request/control Music reliably. The build script now writes `NSAppleEventsUsageDescription` so the bundled app can query common players, while idle playback still keeps the waveform static.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `osascript` probe returns `playing` for Music when a track is active.
- Rollback: Remove the Apple Events plist key if this permission path is later replaced with a different playback detector.

### 2026-06-15 - wire-audio-waveform-to-real-playback-state
- Reason: User confirmed the waveform should stay static when no music is playing and only animate with real playback.
- Changed:
  - `Sources/IslandCore/AudioPlaybackState.swift`
  - `Sources/Island/Support/AudioPlaybackDataSource.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Tests/IslandCoreChecks/main.swift`
- Result: Added a separate audio playback state source and connected it to the waveform. The waveform now defaults to static idle rendering and only animates when a real playback source reports `playing`. The current implementation checks common players via AppleScript and treats missing/idle playback as static.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `osascript` probe for `Music` returns `idle` when nothing is playing.
- Rollback: Revert the files above to return the waveform to the previous manual/static behavior.

### 2026-06-15 - add-first-stage-audio-waveform
- Reason: User wanted the first step of the dynamic audio waveform area before connecting real music/audio detection.
- Changed:
  - `Sources/IslandCore/NotchMetrics.swift`
  - `Sources/Island/Views/AudioWaveformView.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Tests/IslandCoreChecks/main.swift`
- Result: Added a simulated waveform in the marked expanded top-left lane, to the right of the breathing status dot and before the physical camera housing. The visual is now a thin continuous trace with a subtle center baseline, matching the user's waveform reference more closely than the earlier vertical bar visualizer. It is static by default when no real audio is detected, and the next step can wire a true active state for music playback. No real music app or system audio detection is connected yet.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`.
- Rollback: Revert the files above to remove the visual waveform area while keeping task status and usage stats unchanged.

### 2026-06-15 - fix-codex-task-activity-event-parsing
- Reason: User reported the breathing status dot still detects task activity incorrectly after multiple fixes.
- Changed:
  - `Sources/IslandCore/TaskActivityState.swift`
  - `Sources/Island/Support/TaskActivityDataSource.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `AGENTS.md`
- Result: Codex task activity now parses JSONL `payload.type` instead of the top-level `type`, so `task_started`, `task_complete`, `turn_aborted`, `function_call`, and `context_compacted` are visible to the heuristic. Stale `task_started` and stale manual state-file overrides no longer keep the dot breathing forever; fresh `idle` from `script/set_task_activity.sh idle` can still force-stop the dot for verification.
- Verify: `swift run IslandCoreChecks`.
- Rollback: Revert the files above if the app should return to file-only manual task state; keep the JSON parser fix if Codex automatic detection remains enabled.

### 2026-06-15 - align-usage-stats-with-cc-switch
- Reason: User compared Island usage stats with CC Switch and reported large gaps; CC Switch is considered more accurate.
- Changed:
  - `Sources/IslandCore/CodexUsage.swift`
  - `Sources/Island/Support/CodexUsageDataSource.swift`
  - `Sources/Island/Support/ClaudeUsageDataSource.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `AGENTS.md`
- Result: Codex stats now follow the CC Switch-style local session log approach more closely: prefer `total_token_usage` snapshots, compute per-file deltas, fall back to `last_token_usage` only when cumulative data is empty, skip zero events, invalidate old usage cache, and stop silently merging Claude session logs into Codex stats. Claude usage parsing was also corrected so cache hits count in real total tokens when used separately later.
- Verify: `swift run IslandCoreChecks`; `swift build --product Island`; `./script/build_and_run.sh --verify`.
- Rollback: Revert these files if the panel should return to the earlier combined Codex+Claude estimate. If exact CC Switch cost is required, add a separate integration with `~/.cc-switch/cc-switch.db` provider pricing rather than guessing from Codex logs.

### 2026-06-15 - stop-task-breathing-after-codex-idle
- Reason: User reported that the status dot breathes while Codex is working but keeps breathing after the task ends.
- Changed:
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Tests/IslandCoreChecks/main.swift`
- Result: `IslandPanelController` now defaults to `FileBackedTaskActivityDataSource()` instead of process-name based `ClaudeTaskActivityDataSource()`, so a persistent Codex or Claude desktop process is not treated as active task work.
- Verify: `swift run IslandCoreChecks`; `./script/build_and_run.sh --verify`.
- Rollback: Restore the controller default to `ClaudeTaskActivityDataSource()` only if a reliable real task detector replaces simple process-presence detection.

### 2026-06-14 - convert-memory-to-event-log
- Reason: User asked to make `MEMORY.md` event-based, similar to git history, so it is easier to understand what changed and how to roll back.
- Changed:
  - Recreated `MEMORY.md` as a compact event log instead of a long state summary.
  - Updated `AGENTS.md` so future assistants are not forced to prefix every user-facing reply with `cx`.
- Result: Project memory now records actions as dated events with changed files, verification, and rollback notes.
- Verify: Read `MEMORY.md` and `AGENTS.md`; run `git diff -- MEMORY.md AGENTS.md`.
- Rollback: Restore `.backup/memory/MEMORY.md.20260614-220518.bak` if the older long-form memory is needed, and revert the `AGENTS.md` project-memory bullet if the `cx` prefix rule should return.

### 2026-06-10 - establish-project-direction
- Reason: User clarified the product is not a Vibe Island clone. The project should learn the reference app's shell, layout, interaction, and visual framework, while new functionality must be chosen explicitly by the user.
- Changed:
  - `AGENTS.md`
  - `AGENTS-01-结构与外壳与UI.md`
  - `AGENTS-02-功能与架构.md`
  - `AGENTS-03-分阶段计划.md`
  - `.reference/vibe-island/`
- Result: Reference docs became navigation material, not a requirements backlog.
- Verify: Check `AGENTS.md` truth-priority and project-direction sections.
- Rollback: Re-read the current user request first; do not restore automatic feature inheritance unless the user explicitly asks for it.

### 2026-06-10 - build-native-swiftpm-mvp
- Reason: User approved starting a native macOS MVP after preview iterations around a 14-inch MacBook Pro notch-safe island shell.
- Changed:
  - `Package.swift`
  - `Sources/IslandCore/NotchMetrics.swift`
  - `Sources/Island/App/IslandMain.swift`
  - `Sources/Island/Controllers/AppDelegate.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - `Sources/Island/Views/IslandShape.swift`
  - `Sources/Island/Views/IslandTrackingHostingView.swift`
  - `Sources/Island/Views/StatusDotView.swift`
  - `Tests/IslandCoreChecks/main.swift`
  - `script/build_and_run.sh`
- Result: SwiftPM app can build and launch a top-center transparent `NSPanel` with a notch-aligned island shell and SwiftUI-rendered expansion.
- Verify: `swift run IslandCoreChecks`; `./script/build_and_run.sh --verify`.
- Rollback: Revert the SwiftPM app files above to return to the document/reference-only project state.

### 2026-06-10 - lock-notch-safe-shell-basics
- Reason: User required that the MacBook Pro camera housing be treated as a physical non-display area.
- Changed:
  - `Sources/IslandCore/NotchMetrics.swift`
  - `Sources/Island/Views/IslandShape.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
  - preview files under `.superpowers/brainstorm/`
- Result: Collapsed shell uses 14-inch MBP runtime metrics where available: camera housing gap about `185x32` logical points, closed shell `245x32`, side slots `30pt` each.
- Verify: `swift run IslandCoreChecks`.
- Rollback: Revert `NotchMetrics` sizing constants and related tests if a non-notch design is chosen.

### 2026-06-10 - stabilize-hover-and-window-resize
- Reason: User saw jitter when SwiftUI hover state changed the real `NSPanel` size repeatedly.
- Changed:
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `Sources/Island/Views/IslandTrackingHostingView.swift`
  - `Sources/Island/Views/IslandOverlayView.swift`
- Result: AppKit tracking became the single source for mouse enter/exit; collapse animation runs on the open canvas before shrinking the real window.
- Verify: Run app and move the pointer over/out of the island; check no repeated resize jitter.
- Rollback: Revert the tracking-hosting-view flow only if replacing it with another single-source event model.

### 2026-06-10 - add-real-usage-data-panel
- Reason: User wanted the data panel to become real rather than static mock data.
- Changed:
  - `Sources/IslandCore/CodexUsage.swift`
  - `Sources/IslandCore/CalendarHeatmap.swift`
  - `Sources/IslandCore/UsageTrendTimeline.swift`
  - `Sources/IslandCore/DataPanelMode.swift`
  - `Sources/IslandCore/DataPanelTooltipPolicy.swift`
  - `Sources/Island/Support/CodexUsageDataSource.swift`
  - `Sources/Island/Support/ClaudeUsageDataSource.swift`
  - `Sources/Island/Views/DataPanelView.swift`
  - `Tests/IslandCoreChecks/main.swift`
- Result: Stats panel reads local Codex session logs and Claude project logs, aggregates tokens, requests, estimated cost, trends, and calendar heatmap records.
- Verify: `swift run IslandCoreChecks`; run app and inspect `Stats`.
- Rollback: Revert these files to return to static or empty Stats UI. Remember `EST COST` is an estimate, not a bill.

### 2026-06-10 - add-task-activity-state-and-breathing-dot
- Reason: User wanted visible task activity through the status dot without changing shell layout.
- Changed:
  - `Sources/IslandCore/TaskActivityState.swift`
  - `Sources/Island/Support/TaskActivityDataSource.swift`
  - `Sources/Island/Support/ClaudeTaskActivityDataSource.swift`
  - `Sources/Island/Views/StatusDotView.swift`
  - `Sources/Island/Controllers/IslandPanelController.swift`
  - `script/set_task_activity.sh`
  - `Tests/IslandCoreChecks/main.swift`
- Result: `idle`, `thinking`, `running`, `compacting`, `warning`, and `error` states drive status-dot animation profiles. Debug state can be written through `script/set_task_activity.sh`.
- Verify: `swift run IslandCoreChecks`; run app, then use `./script/set_task_activity.sh running` and `./script/set_task_activity.sh idle`.
- Rollback: Revert task-activity files and remove polling if task state should disappear from the MVP.

### 2026-06-10 - refine-stats-header-and-time-ranges
- Reason: User wanted stable top controls, a separate `Status / Stats / Tools` feature switcher, and time ranges including `Today`.
- Changed:
  - `Sources/IslandCore/IslandFeature.swift`
  - `Sources/IslandCore/CalendarHeatmap.swift`
  - `Sources/IslandCore/UsageTrendTimeline.swift`
  - `Sources/IslandCore/CodexUsage.swift`
  - `Sources/Island/Views/DataPanelView.swift`
  - `Tests/IslandCoreChecks/main.swift`
- Result: Right header is fixed for `Status / Stats / Tools`; Stats has `Trends / Overview / All`, refresh badge, and `Today / 7d / 30d / All` ranges.
- Verify: `swift run IslandCoreChecks`; run app and switch between feature tabs and range tabs.
- Rollback: Revert these files if returning to the earlier single-level Stats controls.

### 2026-06-10 - preserve-reference-repo-facts
- Reason: User wanted the hidden Vibe Island reference source to be available for precise framework/layout lookup.
- Changed:
  - `.reference/vibe-island/`
  - `AGENTS.md`
- Result: Reference repo is recorded as separate git repo, branch `main`, version `1.0.29`; current source includes onboarding and bundled assets.
- Verify: Inspect `.reference/vibe-island/package.json`, `.reference/vibe-island/src/App.tsx`, and `.reference/vibe-island/src/assets/`.
- Rollback: Do not delete the reference directory unless user explicitly wants the project to stop using it.
