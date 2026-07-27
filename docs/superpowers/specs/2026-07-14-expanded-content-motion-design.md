# Expanded Content Motion Design

## Goal

Restore reliable primary-feature interaction and give the expanded island a
clear Apple-style content entrance without animating individual task rows or
file tiles.

## Decision

Use a layered, container-level entrance:

1. The existing shell expansion remains the geometry owner.
2. Top-band feature controls and the Files icon appear only after the shell has
   enough horizontal room. They share the same `0.34s` safety delay and `0.18s`
   linear entrance, with no per-control stagger. They keep their canonical
   top-band frames in a stable open-canvas layer, so their screen X does not
   inherit the shell-width spring and the composed path stays vertical.
3. The selected Tasks or Files container starts `0.40s` after expansion, moves
   `6pt` down from the top-band source while fading in, and settles with a
   critically damped spring (`response: 0.30`, `damping: 1.0`).
4. Switching Tasks/Files while already expanded has no additional delay. The
   old container returns toward the top-band source while the new container
   enters from it.
5. Collapse uses the existing `0.14s` ease-out attached-element timing.
6. Reduce Motion removes offset and spring movement, removes the entrance
   delay, and keeps a `0.20s` opacity transition before the open canvas snaps
   closed without spatial tweening.

The top controls and Files icon enter as one visual tier. A shared linear fade
and `6pt` vertical source path removes the previous rhythm mismatch: all five
entry points become readable together instead of asking the eye to follow an
unnecessary sequence. Collapse keeps its existing `0.14s` ease-out because the
user requested a linear entrance, not a constant-speed exit.

## Alternatives considered

- **Per-control, per-row, or per-file stagger**: rejected. The top controls are
  one navigation tier, while polling and file mutations would repeatedly replay
  decorative motion and add work to high-frequency updates.
- **Opacity only**: rejected. It does not explain that the active content comes
  from the selected top-band function.
- **Full-content bounce**: rejected. The content is not released from a drag or
  flick, so visible overshoot would violate physical causality.

## Interaction contract

- Primary navigation changes must pass through `IslandPanelController`; the
  view must not mutate `selectedPrimaryFeature` directly.
- Leaving Files for another primary feature clears Files overlay, pinned, and
  drop-target state so mouse-exit collapse remains predictable.
- During a cross-transition only the newly selected container accepts input,
  and it is layered above the outgoing container. Tasks and Files share the
  transition lifetime; hidden content is disabled, ignores pointer input, and
  is removed from the accessibility tree.
- Reopening during the active exit window reverses from the current visual
  state; the `0.40s` first-entrance delay is paid again only after exit has
  completed.
- Collapsed top controls are disabled and absent from the accessibility tree.
- Hover, precise `IslandShape` hit testing, click-to-expand, File Shelf display
  modes, and the top 32pt safe-band layout remain unchanged.

## Performance contract

- Only opacity and SwiftUI transform offsets animate.
- The stable top-band layer is masked by the animated shell width, preserving
  expansion/collapse clipping without adding a second horizontal animation.
- Canonical `IslandTopStatusBandLayout` frames remain unchanged.
- TopBand energy rendering stops when its window is ordered out or occluded.
- Drag validation decodes pasteboard URLs once per drag session rather than on
  every `draggingUpdated` callback.
- The hidden Files drop target unregisters its AppKit drag types, Files icons
  use a view-lifetime cache, and multi-file drag startup resolves one
  representative icon.

## Verification

- Add source-contract checks before production edits and observe the expected
  red result.
- Run `swift run DynamicIslandCoreChecks` after each focused implementation.
- Run `swift build --product DynamicIsland`, `git diff --check`, and
  `./script/build_and_run.sh` after integration.
- In the running app verify hover, click expansion, layered content entrance,
  Tasks/Files switching, Files-to-Tasks mouse-exit collapse, and reduced motion.
- Confirm only `/Users/user/Documents/Codex/Island/dist/Dynamic Island.app`
  remains running and sample CPU after the UI settles.

## Scope boundaries

- No task-row or file-tile entrance animation.
- No new framework or dependency.
- No layout, camera-safe-zone, feature content, persistence, or permission
  changes.
- No staging or commit while the existing dirty working tree is being
  preserved.
