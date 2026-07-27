# MEMORY.md

Project-local memory for `/Users/user/Documents/Codex/Island`.

This file is a compact working memory, not a full changelog. It keeps the
current project truth, recent rollback-relevant events, and consolidated older
history. Use git history for the pre-consolidation line-by-line event log.

## Current Memory Rules

- Project truth priority: `AGENTS.md`, project docs, source files, then this file.
- Do not use global memory as project truth.
- Keep entries fact-based, newest first, and easy to use for rollback.
- Record decisions, changed files, verification, and rollback notes.
- Do not re-expand this file into a complete historical dump.
- When a change is important but only supersedes an older experiment, record the
  final state and the rollback boundary, not every intermediate tweak.

## Current Snapshot

- Date: 2026-07-14.
- Branch observed during consolidation: `main`.
- Product: native macOS Dynamic Island-style desktop app for notched and
  non-notched displays.
- Stack: SwiftPM, macOS 14+, Swift 6, AppKit + SwiftUI.
- Current focus:
  - black notch-blended island shell
  - music playback state with album art, low-cost waveform, and cancellable
    horizontal skip gestures
  - expanded Tasks list backed by local Codex state and rollout metadata
  - retained Data, Tools, and Settings primary navigation controls
  - temporary File Shelf overlay with filtering, selection, and drag-out
  - runtime settings, calibration/debug modes, display adaptation, and sanitized
    interaction logs
- Explicit non-goals unless user reselects them:
  - Vibe Island feature cloning
  - ECG/heartbeat fallback waveform
  - default ScreenCaptureKit/system-audio capture
  - legacy Claude-only usage/task data sources
  - persistent File Shelf storage or copied files

## Important Current Contracts

- `DynamicIslandCore` is pure logic: no AppKit or SwiftUI imports.
- `NotchMetrics` and `DisplayProfile` are the sizing truth for notch/display
  adaptation. Avoid scattered hardcoded display dimensions.
- `IslandTopStatusBandLayout` owns expanded top-band placement around the
  physical camera housing.
- `IslandAnimationProfile.default` owns shared island animation timing.
- `MusicSkipDirection` is the single canonical skip-direction enum and lives in
  `DynamicIslandCore/MusicSkipGestureStateMachine.swift`.
- Horizontal music skip gestures must arm first, allow rollback cancellation,
  and commit on phase end when phase data is available.
- Hidden shell state has priority over hover, click, and horizontal skip.
- File Shelf stores only temporary file URL references in memory. Logs must not
  include raw paths or file names.
- Data diffs each canonical Codex rollout's full cumulative Token sequence before
  applying a local natural-day window, then combines it with request-deduplicated
  non-Codex CC Switch rows. Both sources stay read-only; there is no local usage
  mirror and no background usage polling.

## Verification Baseline

Use these commands for most implementation changes:

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
./script/build_and_run.sh
```

Additional useful checks:

```bash
./script/build_and_run.sh --debug-data
./script/build_and_run.sh --debug-calibration
./script/build_and_run.sh --debug-music-signal
git diff --check
```

For UI, animation, waveform, polling, or gesture work, also sample the running
`DynamicIsland` process and make sure CPU does not stay high at idle.

## Event Format

New events should use this shape:

```md
### YYYY-MM-DD - short-title
- Reason:
- Changed:
- Result:
- Verify:
- Rollback:
```

### 2026-07-19 - read-only-data-token-usage-integration
- Reason: The retained Data primary page needed an accurate local Token summary
  without double-counting Codex, guessing cache semantics, writing source data,
  or adding a background refresh loop.
- Changed:
  - `Sources/DynamicIslandCore/UsageTimeRange.swift`
  - `Sources/DynamicIslandCore/UsageSnapshot.swift`
  - `Sources/DynamicIslandCore/CodexRolloutUsageParser.swift`
  - `Sources/DynamicIslandCore/IslandAnimationProfile.swift`
  - `Sources/DynamicIsland/Support/UsageSQLiteQueryRunner.swift`
  - `Sources/DynamicIsland/Support/CodexUsageSource.swift`
  - `Sources/DynamicIsland/Support/CCSwitchUsageSource.swift`
  - `Sources/DynamicIsland/Support/UsageAggregationService.swift`
  - `Sources/DynamicIsland/Views/DataPrimaryContentView.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayState.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - usage fixture/Core checks, the read-only check script, and this memory
- Result: Codex usage is derived by per-field cumulative deltas across each
  canonical thread's complete rollout sequence before `[startUTC, endUTC)`
  filtering; active/archive moved copies count once and conflicting candidates
  remain partial. CC Switch permanently excludes Codex and deduplicates only by
  validated request ID. The four ranges are captured local natural days ending
  at one refresh `now`, default to Today, and refresh only on first Data entry or
  an explicit range/refresh action. The controller rejects cancelled, stale
  generation, and stale-range results. The Data card and local Liquid Glass or
  fallback drawer expose partial/failed states without a trusted zero, while
  logs contain only aggregate counts, timing, completeness, and warning
  categories.
- Verify: `./script/run_usage_checks.sh`, `swift run
  DynamicIslandCoreChecks`, `swift build --product DynamicIsland`, and the
  Task 7 scoped `git diff --check` passed. Real `--live` comparison, packaged
  app launch, visual/accessibility review, and settled CPU sampling remain the
  final runtime verification boundary.
- Rollback: Remove the three new usage Core files, four usage support files,
  Data primary view, and usage check entry/script; restore the animation profile,
  overlay state/view, controller, CoreChecks, and this current-contract entry to
  their Task 7 before snapshots. Preserve unrelated Tasks, approval, Files,
  music, shell, and historical memory changes.

### 2026-07-16 - centered-shell-expansion-and-collapse-anchor
- Reason: Frame-level visual diagnosis found that normal expansion moved the
  closed shell `277.5pt` left before growing right, while collapse shrank toward
  that left origin and then snapped back to center.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
- Result: The base shell wrapper now always uses centered `.top` alignment
  inside its fixed 850pt base canvas. Normal, approval-backed, and Reduce Motion
  expansion therefore share one screen-space center; the approval attachment
  still extends only the outer canvas to the right. A scoped source contract
  prevents the shell frame from inheriting `.topLeading` again without being
  confused by the separate primary-feature mask alignment.
- Verify: The scoped CoreCheck failed first for both the original
  `usesOpenCanvas` condition and an incomplete approval-only condition, then
  `swift run DynamicIslandCoreChecks`, `swift build --product DynamicIsland`,
  `./script/run_codex_approval_checks.sh`, `./script/build_and_run.sh`, and
  `git diff --check` passed. A 25-frame main-app expansion capture measured
  `-0.25pt...0pt` center error; an 11-frame current-source diagnostic collapse
  measured `-0.5pt...+0.25pt`, replacing the former `-277.5pt` jump with normal
  half-pixel rounding. Ten settled collapsed CPU samples had a `1.30%` median;
  the isolated peak did not persist.
- Rollback: Restore a conditional `.topLeading` shell alignment only if
  left-origin growth is deliberately selected again. Keep the approval
  attachment's separate right-side canvas and primary-feature mask contracts.

### 2026-07-15 - bounded-codex-approval-island-handoff
- Reason: Surface pending Codex approvals inside Tasks without pretending that
  an arbitrary Codex Desktop session can be approved from another process.
- Changed:
  - `Sources/DynamicIslandCore/CodexApprovalFlow.swift`
  - `Sources/DynamicIslandCore/CodexApprovalApplicationOpenState.swift`
  - `Sources/DynamicIslandCore/CodexTasksApprovalLayout.swift`
  - `Sources/DynamicIsland/Support/CodexAppServerApprovalClient.swift`
  - `Sources/DynamicIsland/Support/CodexApprovalCoordinator.swift`
  - `Sources/DynamicIsland/Views/CodexApprovalActionView.swift`
  - approval wiring in the existing Tasks views and `IslandPanelController`
  - approval behavior runners and Core source-contract checks
- Result: Production remains passive by default: local Codex state can surface a
  pending command, file, or permissions request, select Tasks, and offer
  `前往 Codex`, while hidden and pinned Files keep priority. Managed command/file
  decisions are implemented behind an injected coordinator with type-preserving
  JSON-RPC request IDs, once-only responses, targeted resolution, and
  privacy-safe audit events, but the production coordinator remains `nil` until
  the Island owns the app-server connection and the turn that produced the
  request. Permissions remain non-actionable. No Codex database, rollout, or
  global state is written, and no private Desktop connection or UI automation is
  used. When more than one request is pending, the summary badge shows the
  privacy-safe queue count while a single request keeps its approval-kind badge.
- Verify: `./script/run_codex_approval_checks.sh`, `swift run
  DynamicIslandCoreChecks`, `swift build --product DynamicIsland`,
  `git diff --check`, and `./script/build_and_run.sh` passed. A 25-frame capture
  verified the live no-approval Tasks shell, long-title truncation, large token
  summary, camera-safe navigation, and the Files count without an approval
  attachment. Ten expanded CPU samples had a `2.05%` median and ten normally
  collapsed samples had a `1.05%` median; isolated polling/render peaks did not
  persist, and the app had no child process. A real decline/accept/
  acceptForSession round-trip was not run because the current product has no
  Island-managed `turn/start`; this is the plan's explicit stop condition, not
  evidence that arbitrary Desktop approvals are supported.
- Rollback: Remove the approval Core models, client/coordinator/action view,
  controller and Tasks approval wiring, and approval checks. Preserve the
  pre-existing Tasks hierarchy, adaptive height, Files, music, and shell work.

### 2026-07-14 - grouped-codex-sessions-and-adaptive-tasks-shell
- Reason: The flat four-row Codex query allowed recently updated subagents to
  displace primary sessions, while Tasks always focused the first row and had
  no way to reveal a large agent group without compressing unrelated sessions.
- Changed:
  - `Sources/DynamicIslandCore/CodexStatusBarSnapshot.swift`
  - `Sources/DynamicIslandCore/CodexTasksAdaptiveLayout.swift`
  - `Sources/DynamicIslandCore/IslandPrimaryContentLayout.swift`
  - `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift`
  - `Sources/DynamicIsland/Views/CodexTasksContentView.swift`
  - `Sources/DynamicIsland/Views/CodexStatusBarView.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayState.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - the 2026-07-14 Tasks hierarchy design and implementation plan
- Result: The local Codex reader now selects eight primary sessions before a
  bounded recursive tree of 24 descendants and preserves parent, root, depth,
  and agent nickname metadata. Tasks uses a stable master-detail selection:
  primary sessions stay in the left list, exactly one chevron group can expose
  recursively indented agents, and hidden or overflowing rows remain reachable
  by local scrolling. Opening a group adds `10pt + 26pt` per visible agent,
  capped at five rows and `140pt`; the same height drives the SwiftUI shell,
  content layout, transparent `NSPanel`, and precise `IslandShape` hit test.
  Switching features or collapsing resets the contribution. The height spring
  is critically damped, and Reduce Motion applies geometry immediately.
- Verify: The new hierarchy, selection, SQL, and height source contracts were
  each observed failing before implementation. `swift run
  DynamicIslandCoreChecks`, `swift build --product DynamicIsland`,
  `./script/build_and_run.sh`, and `git diff --check` passed. The recursive CTE
  ran read-only against the live `state_5.sqlite` and returned eight roots
  before 24 descendants with correct root/parent/depth/nickname columns. A
  final main-repository frame capture showed the 850x200 base Tasks layout.
  Ten collapsed CPU samples had a `0.6%` median after launch; an expanded debug
  capture while the existing xhigh/max energy effect and active rollout were
  running had a `6.7%` median with periodic polling/render peaks, but no new
  continuous animation or timer was added by Tasks.
- Rollback: Restore the flat thread query and former single-column
  `CodexTasksContentView`, remove the hierarchy/adaptive Core models and the
  controller height callback, and return open canvas and hit testing to
  `metrics.openHeight`. Keep the pre-existing Codex progress, dismissal, Files,
  music, and motion work intact.

### 2026-07-14 - screen-space-vertical-primary-entrance
- Reason: Frame-level review confirmed that the locally vertical Files and
  Tasks/Data/Tools/Settings entrance still inherited up to `4.5px` of the
  centered shell-width spring, making the composed path read diagonally. The
  user requested a strictly top-to-bottom entrance with no left/right motion.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - the expanded-content motion spec and synchronized-primary implementation
    plan
  - `plans/README.md`
  - `MEMORY.md`
- Result: Files and the right-side primary controls retain their canonical
  `IslandTopStatusBandLayout` frames but now mount in one stable open-canvas
  top-band layer. Their X coordinate no longer inherits shell expansion; the
  only entrance transform remains the shared `6pt` top-to-bottom offset plus
  opacity over `0.18s linear`, with no stagger. A shell-width mask preserves
  clipping during expansion and collapse. Controller-routed selection,
  Files cleanup, hit testing, keyboard ownership, and accessibility hiding are
  unchanged. Frame QA rejected and removed two intermediate approaches that
  produced visible left-to-right motion; no animated X compensation remains.
- Verify: The new CoreChecks contract first failed because the stable canvas
  layer was absent, then `swift run DynamicIslandCoreChecks`, `swift build
  --product DynamicIsland`, `git diff --check`, and
  `./script/build_and_run.sh` passed. The final 25-frame capture measured `0px`
  X travel for all five controls and a shared Retina-pixel Y sequence of
  `-12,-10,-8,-5,-2,0` over about `175ms`. Computer Use opened Files and
  switched back to Tasks. Ten expanded samples had a `1.95%` CPU median and
  ten collapsed samples had a `0.95%` median; isolated peaks remained tied to
  existing Codex polling. The final run used only the main repository app.
- Rollback: Move the two primary mounts back into `islandShell` and remove the
  canvas layer, mask, and matching CoreChecks only if the small inherited X
  drift is acceptable again. Do not restore the rejected animated X
  compensation, which caused a pronounced left-to-right entrance.

### 2026-07-14 - synchronized-linear-primary-entrance
- Reason: Runtime review found the separately delayed Files icon and the
  staggered Tasks/Data/Tools/Settings entrance visually inconsistent. The user
  requested one linear entrance with no sequential reveal.
- Changed:
  - `Sources/DynamicIslandCore/IslandAnimationProfile.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - the 2026-07-14 expanded-content motion spec and implementation plan
  - `plans/012-animate-expanded-primary-content.md` and `plans/README.md`
  - `MEMORY.md`
- Result: Files and the entire right-side primary switcher now start after the
  same `0.34s` settled-shell delay and move together from the existing `6pt`
  top source using one `0.18s` linear entrance. The switcher animates as one
  `HStack`; indexed timing and the shared stagger/spring entrance tokens were
  removed. Selection, press feedback, `0.14s` collapse, `0.20s` Reduce Motion
  fade, and the delayed Tasks/Files content transition are unchanged.
- Verify: The new CoreChecks contract first failed because the switcher still
  used `enumerated()` for stagger timing, then `swift run
  DynamicIslandCoreChecks`, `swift build --product DynamicIsland`, and
  `git diff --check`, and `./script/build_and_run.sh` passed. A 25-frame main-app capture showed all five entry
  points absent in frame 009, appearing together in frame 010, brightening
  together in frame 011, and settling together in frame 012. Computer Use
  successfully switched Files to Tasks. Ten expanded samples had a `0.75%`
  CPU median, and the final collapsed run had a `0.40%` median. The isolated
  peaks remained tied to existing Codex polling. The final launch had one main
  repository process, and its log recorded hover enter, expand, collapse, and
  hover exit.
- Rollback: Restore the per-button index and spring/stagger profile tokens only
  if a sequential navigation reveal is deliberately selected again. Do not
  change the independent primary-content entrance when rolling this back.

### 2026-07-14 - apple-motion-audit-and-expanded-content-entrance
- Reason: The user requested an `improve-animations` audit followed by an
  Apple-style implementation and repeat audit. Runtime QA also found that a
  second app built from an old worktree could overlap the main transparent
  panel, making hover and clicks appear missing.
- Changed:
  - `Sources/DynamicIslandCore/IslandAnimationProfile.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Views/IslandPressButtonStyle.swift`
  - Files, File Shelf, waveform, Codex status, tracking, and top-band energy
    views touched by the selected motion/performance plans
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `docs/superpowers/specs/2026-07-14-expanded-content-motion-design.md`
  - `plans/001` through `plans/014` and `plans/README.md`
- Result: Shell geometry remains the transition owner. Top controls enter after
  `0.34s`; selected Tasks/Files content enters after `0.40s` with a restrained
  `6pt` source offset and a critically damped `0.30s` spring. Expanded feature
  switches are immediate and reversible; collapse uses `0.14s` ease-out.
  Reduce Motion removes spatial/continuous movement and uses a local `0.20s`
  fade. Primary-feature writes now pass through the controller, leaving Files
  clears its overlay/pin/drop state, and hidden layers release pointer,
  keyboard, accessibility, and AppKit drag ownership. Hover publication,
  selection logging, native icon work, drag validation, and Metal rendering
  were removed from their pointer/frame hot paths. Only the app under this
  repository remains running.
- Verify: Every selected source contract was first observed failing, then
  `swift run DynamicIslandCoreChecks`, `swift build --product DynamicIsland`,
  `./script/build_and_run.sh`, and `git diff --check` passed. A 25-frame main-app
  capture showed shell, controls, and content entering in order. Computer Use
  clicked Files and Tasks successfully; the sanitized log recorded both open
  and close events. The final three-domain motion audit and an independent diff
  review reported no HIGH or MEDIUM findings. Twelve settled CPU samples had a
  `0.55%` collapsed median and a `3.35%` expanded median; isolated peaks tracked
  existing Codex status polling rather than continuous animation.
- Rollback: Remove the expanded-content timing/state and controller-routed
  primary selection to restore the prior immediate content appearance. Revert
  the hot-path lifecycle/cache changes only with their matching source-contract
  checks. If hover or clicks disappear again, first terminate every
  `DynamicIsland` process and relaunch only this repository's `dist` app.

### 2026-07-10 - precise-shell-actions-and-settled-content-entrance
- Reason: Visual and interaction QA found transparent panel corners retaining
  input, completed Tasks actions unreachable, and Files/primary content
  appearing while the shell was still expanding.
- Changed:
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: An on-demand pointer monitor now uses the existing `IslandShape` hit
  test to pass transparent regions through and collapse a visible shell only
  when the current Files display policy permits it. The monitor exists only
  while a visible, non-hidden panel is passing mouse events through; returning
  to the shell, menu hiding, and gesture hiding remove it, and queued callbacks
  recheck lifecycle state. Raw mouse events feed a main-queue user-data dispatch
  source, which coalesces bursts instead of creating one MainActor task per
  event. Completed Tasks retain their
  existing completion/approval guards while hover, delete, shatter, and Undo
  are reachable. Files and initial Tasks/Files content wait for the shared
  primary-feature entrance delay; File Shelf draws above the Tasks layer.
- Verify: Each new CoreChecks contract failed before its production change, then
  `swift run DynamicIslandCoreChecks`, `swift build --product DynamicIsland`,
  and `./script/build_and_run.sh` passed. A 25-frame debug capture kept the
  early shell frames free of Files/Tasks content and showed the settled UI by
  frame 014. After the launch refresh, five settled post-optimization samples
  measured 0.2-1.2% CPU and 0.2% memory.
- Rollback: Remove the pointer monitor helpers, restore the Tasks hit-test
  blocker, remove delayed primary-content state and Files entrance animation,
  and return File Shelf to its former z-index only if these interaction and
  visual contracts are intentionally retired.

### 2026-07-10 - codex-completed-task-dismissal
- Reason: User requested manual removal for completed Tasks rows with a hover
  corner close control and a short shatter effect.
- Changed:
  - `Sources/DynamicIsland/Views/CodexTasksContentView.swift`
  - `Sources/DynamicIsland/Views/CodexStatusBarView.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIsland/Support/CodexTaskDismissalStore.swift`
  - `Sources/DynamicIslandCore/CodexStatusBarSnapshot.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Only non-working, non-approval rows expose a delayed-fade `xmark`
  corner button while hovered. Clicking starts an 8-particle shatter animation;
  the row is removed after the animation and the source Codex database/rollout
  remains untouched. Each task uses `threadID + turnID` identity; dismissal
  keys are stored locally for seven days and can be undone for five seconds.
  Logs contain only sanitized ID/title/turn lengths.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `./script/build_and_run.sh`; `./script/build_and_run.sh
  --debug-calibration`; `git diff --check`. The expanded debug screenshot
  showed the Tasks/Data/Tools/Settings switcher and active Tasks row; no
  completed row was available in the live fixture for destructive click testing.
- Rollback: Remove the dismissal callback and local dismissal store to restore
  read-only task rows; leave Codex source data untouched.

### 2026-07-10 - codex-terminal-state-reconciliation
- Reason: Tasks kept showing a completed Codex tool session as `Running tool`
  because the rollout ended with `turn_aborted`, while the parser only treated
  `task_complete` as terminal.
- Changed:
  - `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Rollout parsing now has an explicit unknown/running/terminal lifecycle;
  task completion, app-server turn completion/abort/failure/cancel events all
  close the current turn and compute a fallback duration. Terminal turns ignore
  stale global approval flags, completed rows retain the existing 10-second
  display window, and active-looking sessions with no rollout file update for
  60 seconds are hidden as stale. Rollout file modification time supplies the
  stale check without parsing a timestamp for every JSONL event.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `./script/build_and_run.sh`; `git diff --check`. After
  relaunch, the previous stale session stopped contributing to
  `runningTasks`; the current live Codex turn remained the only running task.
  Process samples settled around 0.4–1.3% CPU and 0.2% memory.
- Rollback: Restore the previous timestamp comparison and terminal-event
  handling only if a future Codex event schema requires a different lifecycle
  mapping; keep the regression assertions with whichever mapping is selected.

### 2026-07-10 - remove-unused-reference-and-qa-artifacts
- Reason: User requested removal of unused reference files and images.
- Changed:
  - deleted ignored `.reference/vibe-island/` local reference clone
  - deleted historical design images, planning/specification documents, archived
    handoff/log documents, and visual QA screenshots
  - `AGENTS.md`
  - `.gitignore`
  - `MEMORY.md`
- Result: The project no longer carries external reference source, stale design
  artifacts, or committed capture output. Production source, tests, and scripts
  have no dependency on the removed paths; debug frame capture still writes
  only to an explicitly supplied output directory.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `git diff --check`.
- Rollback: Restore tracked artifacts from Git if historical design material is
  required again; re-clone Vibe Island separately only if the user explicitly
  requests fresh external research.

### 2026-07-10 - layout-and-background-activity-optimization
- Reason: Improve compact Files layout and reduce inactive Codex status work
  without changing the requested `Data`, `Tools`, and `Settings` navigation.
- Changed:
  - `Sources/DynamicIslandCore/IslandAnimationProfile.swift`
  - `Sources/DynamicIslandCore/TemporaryFileShelf.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIsland/Views/FilesPrimaryContentView.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: `Tasks`, `Data`, `Tools`, and `Settings` remain in the right safe-zone
  switcher, and Files returns to the previously selected primary feature.
  Only unused animation-profile values, the unused status-stop path, and an
  unused file grouping API were removed. Files keeps its 220pt AirDrop zone on
  wide layouts but reduces it to 30% of available content width, never below
  150pt, on compact layouts. Music event logs now retain only title and artist
  lengths. Codex status reads stay at 1-second cadence only while Tasks is
  visible; collapsed, Files, and File Shelf states refresh their background
  snapshot at most every 5 seconds.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `./script/build_and_run.sh`; `git diff --check`. With two
  active Codex tasks, the normal collapsed app settled at 1.1% CPU and 0.2%
  memory after 39 seconds.
- Rollback: Restore the removed unused animation-profile values or status-stop
  path only if a future caller needs them. Restore the fixed AirDrop width if a
  future layout has a guaranteed wide content frame.

### 2026-07-09 - codex-tasks-normal-mode-polling
- Reason: User reported the expanded `Tasks` feature was not showing Codex
  session processes in the normal app launch, then clarified calibration mode
  is only a layout-locking aid and must not gate feature visibility.
- Changed:
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIsland/Support/CodexReasoningEffortSignalSource.swift`
  - `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Codex Tasks status polling now starts during normal app launch instead
  of being tied to calibration/debug mode. The expanded `Tasks` primary feature
  renders the Codex task list in normal mode; toggling calibration only shows or
  hides the calibration overlay and no longer controls Tasks visibility or
  clears the Tasks Codex snapshot. Follow-up performance tuning keeps realtime
  reasoning polling responsive while throttling slower fallback sqlite/config
  reads to 2 seconds, and caches global approval state by file signature plus
  visible thread IDs so unchanged `.codex-global-state.json` is not rescanned on
  each status tick.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `./script/build_and_run.sh --verify`. Latest normal-mode log
  had `calibrationOverlay:false` and `codex.status.changed` with
  `runningTasks:2`. Before tuning, a 60-second sample averaged 2.62% CPU with a
  6.10% max and `sample` showed frequent reasoning fallback sqlite/global state
  scanning. After tuning, `/tmp/dynamic-island-perf-20260709-175908.tsv`
  averaged 1.03% CPU over 30 samples with a 7.10% transient max and 67.8 MB RSS;
  `/tmp/dynamic-island-sample-20260709-180018.txt` showed the remaining cost
  mainly in active rollout tail reads and the 5-second status thread sqlite
  refresh.
- Rollback: Gate `startCodexStatusPolling()` behind
  `runtimeSettings.isCalibrationModeEnabled` again in `IslandPanelController`,
  restore the `state.isCalibrationOverlayVisible` condition around
  `CodexTasksContentView`, remove the reasoning fallback throttle and global
  state signature cache, and restore the old core-check expectations if Tasks
  should return to debug-only status polling and rendering.

### 2026-07-09 - files-manual-multi-selection
- Reason: User clarified that batch delete should let the user choose specific
  files, not automatically select every staged file.
- Changed:
  - `Sources/DynamicIsland/Views/FilesPrimaryContentView.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The toolbar button left of trash now toggles multi-selection mode
  only. While enabled, clicking file tiles toggles individual file selection
  with a small check indicator; the trash button still deletes only the
  selected temporary shelf URL references. The Files primary toolbar no longer
  exposes a select-all batch action.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `git diff --check`; verified `checklist.checked` exists via
  AppKit; `./script/build_and_run.sh` with debug staged files; CPU settled to
  1.0% after launch.
- Rollback: Restore `FilesSelectAllButton`, `toggleAllFileSelection()`, and the
  `FilesPrimaryContentView` `onSelectItems` toolbar binding if select-all is
  desired again.

### 2026-07-09 - files-content-fade
- Reason: User clarified that the `Files` open/close animation should apply to
  the feature content area, not just the left icon.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: `FilesPrimaryContentView` now uses an opacity transition, and primary
  feature selection changes animate against `selectedPrimaryFeature`, so the
  AirDrop and file preview content fades in and out when `Files` opens or
  closes.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `git diff --check`; `./script/build_and_run.sh` with debug
  staged files; CPU settled to 2.1% after launch.
- Rollback: Remove the `FilesPrimaryContentView` opacity transition and the
  `selectedPrimaryFeature` animation binding from `IslandOverlayView`.

### 2026-07-09 - files-select-all-and-icon-fade
- Reason: User wanted the left `Files` icon open/close state to fade instead
  of swapping abruptly, and wanted an explicit multi-select entry beside the
  trash button for batch deletion.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Views/FilesPrimaryContentView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The `Files` primary icon now cross-fades between outline and filled
  tray symbols. The Files preview toolbar now has a select-all button to the
  left of the trash button; it selects all staged files, toggles back to an
  empty selection when all are selected, and keeps trash deletion scoped to
  selected temporary shelf URL references only.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `git diff --check`; `./script/build_and_run.sh` with debug
  staged files; CPU settled to 0.6% after launch.
- Rollback: Restore the single conditional tray icon and remove
  `FilesSelectAllButton` plus the `FilesPrimaryContentView` batch selection
  binding.

### 2026-07-09 - files-primary-feature-airdrop-preview
- Reason: User wanted file staging to live in a separate left-safe-region
  `Files` primary feature instead of inside `Tasks`, with the left content
  region for AirDrop and the right region for file preview.
- Changed:
  - `Sources/DynamicIsland/Views/IslandPrimaryFeature.swift`
  - `Sources/DynamicIsland/Views/FileShelfActions.swift`
  - `Sources/DynamicIsland/Views/FilesPrimaryContentView.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: `Files` is now a real primary feature selected from the expanded
  left safe band, while `Tasks/Data/Tools/Settings` stay in the right safe band.
  Dropping files only stages in-memory URL references and does not expand or
  switch the island to `Files`; clicking the left `Files` button opens that
  feature and pins the island open. The content area shows a full-height gray
  dashed AirDrop zone on the left and a full-height gray dashed file preview
  zone on the right. AirDrop uses `NSSharingService(.sendViaAirDrop)` from the
  app layer and sends selected/dragged staged files, or all staged files when
  nothing is selected. Dragging files from the preview zone to external apps
  exports real file URL pasteboard items. Files sent via AirDrop or successful
  external drag are removed from the island. File Shelf storage remains
  in-memory URL references only.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `git diff --check`; `./script/build_and_run.sh`; CPU settled
  to 2.0% after launch.
- Rollback: Remove the `files` primary feature case and
  `FilesPrimaryContentView`, restore the old conditional `FileShelfButton`
  overlay opener, and route file drops back to the independent overlay.

### 2026-07-09 - files-balanced-dashed-frame
- Reason: User reported the Files dashed regions did not look equally spaced
  from the top and bottom content boundaries.
- Changed:
  - `Sources/DynamicIslandCore/IslandPrimaryContentLayout.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: `Files` now uses a dedicated `filesContentFrame` with a shared 8pt
  vertical inset after the top status band and before the bottom edge, while
  `Tasks` keeps its existing content frame.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `git diff --check`; `./script/build_and_run.sh`; CPU settled
  to 1.4% after launch.
- Rollback: Point `FilesPrimaryContentView` back to `tasksContentFrame` and
  remove `filesContentFrame`.

### 2026-07-09 - files-compact-button-and-airdrop-completion
- Reason: User wanted the `Files` primary button to remove its text, show the
  count as a badge, reduce drag lag, make the file name less intrusive, and
  keep staged files when AirDrop is cancelled.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Views/FilesPrimaryContentView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The `Files` button is now icon-only with a compact numeric badge.
  The Files preview uses a smaller bottom-left caption for the name. Drag start
  work is reduced by dragging only the current preview item unless a selection
  is active and by reusing one drag icon. AirDrop now keeps files staged when
  the share panel is opened or cancelled, and removes them only from the
  successful `NSSharingServiceDelegate.didShareItems` callback.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `git diff --check`; `./script/build_and_run.sh`; CPU settled
  to 1.6% after launch.
- Rollback: Restore the previous `FilesPrimaryFeatureButton` label, previous
  `filePreview` layout, previous multi-item default drag behavior, and direct
  removal after `NSSharingService.perform`.

### 2026-07-09 - files-grid-retained-airdrop-display-mode
- Reason: User wanted the Files preview area to avoid horizontal piling, use a
  two-dimensional arrangement with clearer spacing, keep staged files when
  AirDrop is cancelled, and finish the long-lived display control idea.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayState.swift`
  - `Sources/DynamicIsland/Views/FileShelfActions.swift`
  - `Sources/DynamicIsland/Views/FilesPrimaryContentView.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The right Files area now uses a horizontal `LazyHGrid` with explicit
  horizontal inset and tile spacing, so staged files distribute across multiple
  rows while the shelf scrolls left and right instead of vertically. AirDrop
  marks staged files as pending so the drag-completion path cannot remove them
  early.
  The drag-completion path ignores pending AirDrop files so they are not
  removed before the share flow resolves. AirDrop completion automatically
  removes the staged files and shows a short undo affordance, avoiding a
  manual confirmation step while still letting the user restore files if macOS
  reports completion for a cancelled AirDrop flow. Files now has display modes:
  auto close on mouse exit, pinned open, or keep open until the shelf is empty.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `git diff --check`; `./script/build_and_run.sh` with six
  debug staged files; CPU settled to 3.0% after launch.
- Rollback: Restore the single-preview Files layout, remove
  `FilesDisplayMode`, route mouse exit back to `isFileShelfPinnedOpen`, remove
  `pendingAirDropItemIDs`, and return AirDrop deletion to the previous strategy.

### 2026-07-09 - files-selected-delete-toolbar
- Reason: User wanted a delete function for the Files staging area without
  crowding each file tile or interfering with drag gestures.
- Changed:
  - `Sources/DynamicIsland/Views/FileShelfActions.swift`
  - `Sources/DynamicIsland/Views/FilesPrimaryContentView.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The Files preview toolbar now has a trash icon beside the display
  mode control. It is disabled until at least one file is selected, shows a
  count badge for multi-selection, and removes only selected temporary shelf
  URL references through a batch removal action. It does not delete real files
  from disk and does not add per-tile delete controls.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `git diff --check`; `./script/build_and_run.sh` with six
  debug staged files; CPU settled to 2.9% after launch.
- Rollback: Remove `onRemoveItems`, `FilesDeleteSelectionButton`, and the
  controller batch removal binding.

### 2026-07-09 - files-icon-toggle
- Reason: User wanted the left `Files` icon to open and close the Files
  primary feature directly instead of needing to click a right-side primary
  feature to switch away.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Clicking the `Files` icon now opens Files when closed and closes it
  back to the last non-`Files` primary feature when already open, releasing the
  pinned state. The icon also changes between outline and filled tray states to
  make on/off visible.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `git diff --check`; `./script/build_and_run.sh` with six
  debug staged files; CPU settled to 2.1% after launch.
- Rollback: Remove `closeFilesPrimaryFeature()` and always route the icon click
  through the previous open-only behavior.

### 2026-07-06 - Codex approval status badge
- Reason: User wanted the reserved right side of each Tasks row hooked to Codex
  approval state.
- Changed:
  - `Sources/DynamicIslandCore/CodexStatusBarSnapshot.swift`
  - `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift`
  - `Sources/DynamicIsland/Views/CodexStatusBarView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
- Result: Codex task rows now carry an approval state. The status source
  recognizes command, file-change, and permission approval request method names,
  plus persisted `waitingOnApproval` active flags when Codex exposes them. The
  right-side reserved slot renders a compact display-only badge and does not
  approve or reject from the island.
- Verification:
  - `swift run DynamicIslandCoreChecks`: passed.
  - `swift build --product DynamicIsland`: passed.
  - `./script/build_and_run.sh --debug-calibration`: launched.
  - `ISLAND_DEBUG_PRIMARY_FEATURE_FRAME_CAPTURE_DIR=/tmp/dynamic-island-approval-capture ./script/build_and_run.sh --debug-calibration`: captured 25 frames.
  - CPU after launch settled around 1.1%-2.3% in short samples.
- Rollback: Remove `ApprovalState` from `CodexTaskStatus`, delete approval
  parsing and global-state approval fallback from `CodexStatusSignalSource`,
  and restore the clear right-side slot in `CodexStatusBarView`.

### 2026-07-06 - codex-tasks-long-rollout-read
- Reason: User reported one active Codex session was not appearing in the
  `Tasks` list.
- Changed:
  - `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The Tasks status reader still performs a small 128KB rollout tail read
  first. When that tail contains activity but no `task_started` or
  `task_complete` boundary, it expands to an 8MB read and caches parsed rollout
  state by file size and modification time. Long sessions with large reasoning
  JSONL lines now remain visible without repeatedly reparsing unchanged files.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `./script/build_and_run.sh --debug-calibration`; `git diff
  --check`. Latest debug log showed `runningTasks: 2`; CPU sampled at 2.3%
  after launch.
- Rollback: Remove the expanded-tail fallback and rollout cache, and restore the
  previous single `rolloutTailMaximumBytes` read if Codex rollout files become
  small and boundary events are always in the fast tail.

### 2026-07-06 - codex-effort-state-source
- Reason: User clarified that the top-band energy effect must read Codex's real
  effort state, with config treated only as the last fallback.
- Changed:
  - `Sources/DynamicIsland/Support/CodexReasoningEffortSignalSource.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The reasoning effort signal source now reads
  `~/.codex/state_5.sqlite` and uses the latest non-archived
  `threads.reasoning_effort` value before falling back to CcSwitch provider
  config and finally `~/.codex/config.toml`. `xhigh` and `max` still gate the
  top-band energy effect.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `./script/build_and_run.sh`; `git diff --check`; CPU sampled
  at 0.8% shortly after launch.
- Rollback: Remove the `codexState` source and
  `readLatestCodexThreadEffort()` from `CodexReasoningEffortSignalSource`, then
  restore the previous CcSwitch/config-only ordering.

## Recent Events

### 2026-07-06 - tasks-status-text-priority
- Reason: User asked whether only `Running tool` was fixed; the underlying
  issue was that activity state text was placed after elapsed time and token
  counts, so any long row could truncate the activity first.
- Changed:
  - `Sources/DynamicIsland/Views/CodexStatusBarView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Task status text now starts with the activity label, then elapsed
  time and token count. This prioritizes visible states such as `Running tool`,
  `Compacting conversation`, `Retrying`, `Responding`, and `Thinking`; if a
  row still runs out of space, trailing metrics are truncated before the
  activity label.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `./script/build_and_run.sh --debug-calibration`; CPU sampled
  at 2.9% after launch.
- Rollback: Restore `CodexStatusBarView.statusText` to the previous
  `elapsed · tokens · activity` ordering and remove the ordering assertion.

### 2026-07-06 - tasks-status-column-width-fix
- Reason: User noticed the middle task status text such as `Running tool` was
  truncated in the Tasks list.
- Changed:
  - `Sources/DynamicIsland/Views/CodexTasksContentView.swift`
  - `Sources/DynamicIsland/Views/CodexStatusBarView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The status column widened from 190pt to 260pt, the future approval
  placeholder narrowed from 84pt to 68pt, and status text now uses compact
  9.5pt type. Task names remain the flexible/truncated column, so status text
  gets priority and `Running tool` has enough room.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; debug calibration frame capture attempted after launch, but
  no active task row was visible because completed tasks had already expired.
- Rollback: Restore `statusColumnWidth` to 190, `approvalSlotWidth` to 84, and
  the previous dynamic status font size in `CodexStatusBarView`.

### 2026-07-06 - completed-codex-task-expiry
- Reason: User wanted completed Codex task rows in the `Tasks` primary content
  list to close automatically after a short grace period instead of lingering.
- Changed:
  - `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift`
  - `Sources/DynamicIsland/Views/CodexTasksContentView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Running Codex tasks remain visible. Completed tasks remain visible
  for `10` seconds after `task_complete`, then are filtered out of
  `snapshot.tasks`. The Tasks content view now renders only visible tasks and
  does not synthesize a fake fallback row after completed sessions expire.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `./script/build_and_run.sh --debug-calibration`; CPU sampled
  at 2.4% after settling.
- Rollback: Remove `completedTaskRetentionDuration` and `isTaskVisible` from
  `CodexStatusSignalSource`, restore direct mapping from recent threads to
  tasks, and restore the previous fallback row in `CodexTasksContentView` if a
  persistent idle row is desired.

### 2026-07-05 - tasks-codex-status-content-layout
- Reason: User clarified the Codex status display should live in the expanded
  `Tasks` primary feature's main white-box content area, not in the top green
  calibration safe region. Task rows need a stable `task name | status |
  reserved approval slot` structure that adapts for one, two, and several
  concurrent Codex tasks without clipping or overlap.
- Changed:
  - `Sources/DynamicIslandCore/IslandPrimaryContentLayout.swift`
  - `Sources/DynamicIslandCore/CodexStatusBarSnapshot.swift`
  - `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift`
  - `Sources/DynamicIsland/Views/CodexTasksContentView.swift`
  - `Sources/DynamicIsland/Views/CodexStatusBarView.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIslandCore/IslandTopStatusBandLayout.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: `Tasks` now renders a compact Codex task list in the expanded primary
  content area below the top status band. The list reads up to 4 recent
  unarchived Codex threads, uses dynamic row heights for 1, 2, and 3+ tasks,
  truncates long task names/status text, and reserves a fixed empty right-side
  slot for future approval controls. The old top-band `codexStatusFrame`
  placement was removed so the green calibration region remains only a debug
  safe-region marker.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; debug calibration launch with frame capture at
  `/tmp/dynamic-island-codex-tasks-capture/frame-024.png`; CPU sampled at 2.5%
  after settling.
- Rollback: Remove `IslandPrimaryContentLayout` and `CodexTasksContentView`,
  restore the old top-band `CodexStatusBarView` placement if desired, revert
  `CodexStatusSignalSource` to one latest thread, and delete the matching
  CoreChecks assertions.

### 2026-07-05 - debug-codex-status-bar-hook
- Reason: User wanted the extracted Claude-style status bar shown in the
  expanded calibration debug green left-safe top-band region, hooked to local
  Codex session/time/token/status data.
- Changed:
  - `Sources/DynamicIslandCore/CodexStatusBarSnapshot.swift`
  - `Sources/DynamicIslandCore/IslandTopStatusBandLayout.swift`
  - `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift`
  - `Sources/DynamicIsland/Views/CodexStatusBarView.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayState.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `docs/superpowers/plans/2026-07-05-codex-status-bar.md`
  - `MEMORY.md`
- Result: Calibration debug mode now starts a Codex status poller that reads
  `~/.codex/state_5.sqlite` for the latest thread metadata and the latest
  rollout JSONL tail for active turn timing/token/status events. The status
  bar is rendered only while expanded calibration overlay is visible, uses
  `IslandTopStatusBandLayout.codexStatusFrame` inside the left safe region,
  avoids the camera housing, and leaves room for the File Shelf button. The
  source caches sqlite thread lookups for 5 seconds and polls at 1 second so
  it does not continuously spawn sqlite. Logs record only activity, counts,
  token totals, ID length, and title length; raw Codex titles, prompts, paths,
  and transcript text are not logged.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `./script/build_and_run.sh --debug-calibration`; process CPU
  sampled at 2.9% after the debug overlay settled.
- Rollback: Remove `CodexStatusBarSnapshot`, `CodexStatusSignalSource`,
  `CodexStatusBarView`, the `codexStatusFrame` layout helper, controller
  polling task, and `codexStatusBarSnapshot` overlay state, then delete the
  matching CoreChecks assertions and plan document.

### 2026-07-05 - codex-xhigh-energy-trigger
- Reason: User wanted the top-band `璀璨流光拖尾` effect to trigger from the
  local Codex reasoning effort, preferring CcSwitch when installed and falling
  back to the Codex config file when it is not available.
- Changed:
  - `Sources/DynamicIslandCore/CodexReasoningEffort.swift`
  - `Sources/DynamicIsland/Support/CodexReasoningEffortSignalSource.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayState.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The app first reads the realtime request signal at
  `~/.cc-switch/codex-reasoning-signal.json` (or `/tmp/codex-reasoning-signal.json`
  for debug), then falls back to CcSwitch's current Codex provider config from
  `~/.cc-switch/cc-switch.db` using only the embedded `config` field, then
  falls back to `~/.codex/config.toml`. Only `xhigh` and `max` enable the
  top-band energy effect; lower efforts or `active:false` leave it unmounted.
  Realtime signal files older than 60 seconds are ignored so stale debug or
  proxy output cannot permanently override the config fallback.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `./script/build_and_run.sh --debug-calibration`; manual
  realtime signal writes for `high`, `xhigh`, and `active:false`; CPU sampled
  at 0.8% after launch.
- Rollback: Remove `CodexReasoningEffort`, `CodexReasoningEffortSignalSource`,
  the controller polling task, and the `isTopBandEnergyEffectEnabled` overlay
  gate, then restore the top-band energy condition to its previous debug-only
  behavior.

### 2026-07-05 - expanded-top-band-energy-effect
- Reason: User requested the Claude-style pixel energy effect be moved into the
  expanded island's debug blue right-safe top-band region while leaving the
  `Tasks/Data/Tools/Settings` primary feature controls unchanged.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Views/TopBandEnergyEffectView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The effect is a bottom background layer mounted only when expanded,
  starts at `IslandTopStatusBandLayout.rightInfoRegion.minX`, extends to the
  island's right edge, refuses hit testing, removes its own rounded ends,
  clips to that rectangular right-side region, starts after the expand animation
  settles to avoid a left-side opening trail, defers the initial burst until the
  Metal view has its real layout size so particles do not start from the
  default 1x1 left edge, keeps the highest energy on the right side with a
  right-to-left pixel shimmer tail, and uses a low-frequency manual Metal draw
  timer instead of an always-on display link.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `./script/build_and_run.sh`; debug expanded launch with
  `./script/build_and_run.sh --debug-calibration`; CPU sampled at 0.2% after
  launch settled in calibration mode.
- Rollback: Remove `TopBandEnergyEffectView` and the `topBandEnergyFrame`
  branch from `IslandOverlayView`, then delete the matching CoreChecks
  assertions.

### 2026-07-02 - primary-feature-top-to-bottom-spring-fade
- Reason: User clarified the expanded top-level feature controls
  `Tasks/Data/Tools/Settings` should open as one whole group from top to
  bottom, with a small rebound, rather than entering from left to right or
  fading in button by button. A later attempt to move the group into a stable
  open-canvas layer shifted the perceived position and was rolled back.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIslandCore/IslandAnimationProfile.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: `PrimaryFeatureSwitcher` still renders as a pure button group inside
  `islandShell`, so it keeps the shell's original positioning and clipping
  behavior. The group fades in while dropping vertically from above the top
  status band, with spring timing from `IslandAnimationProfile.default`. The
  CoreChecks contract forbids the previous horizontal group entrance, the
  reverted external stable layer, and any internal per-button stagger.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `./script/build_and_run.sh`;
  `ISLAND_DEBUG_PRIMARY_FEATURE_FRAME_CAPTURE_DIR=... open -n dist/Dynamic Island.app`.
- Rollback: Restore the horizontal parent `.offset(x:)` entrance and
  duration-only profile field only if left-to-right group opening is desired
  again.

### 2026-07-02 - primary-feature-left-to-right-fade
- Reason: User requested the expanded top-level feature controls
  `Tasks/Data/Tools/Settings` open with a left-to-right fade-in animation.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIslandCore/IslandAnimationProfile.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: `PrimaryFeatureSwitcher` now animates as one whole control group,
  not as four internally staggered buttons. The group fades in while moving
  from a full-width left-side path to its final right-safe-region position.
  Entrance duration and start delay are defined on
  `IslandAnimationProfile.default` instead of scattered in the view. An
  explicit debug frame capture path can export ordered PNG frames from the
  actual hosting view for visual QA.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `./script/build_and_run.sh`;
  `ISLAND_DEBUG_PRIMARY_FEATURE_FRAME_CAPTURE_DIR=... open -n dist/Dynamic Island.app`.
- Rollback: Restore the switcher to a single parent opacity/offset animation
  and remove the primary feature fade profile fields if grouped opening is
  preferred again.

### 2026-07-02 - package-launch-contract-repair
- Reason: Packaging and launch were blocked because `DynamicIslandCoreChecks`
  referenced stale file locations, stale skip-direction names, and a pure File
  Shelf selection type that lived only in the App target.
- Changed:
  - `Sources/DynamicIslandCore/TemporaryFileShelfSelection.swift`
  - `Sources/DynamicIsland/Support/TemporaryFileShelfSelection.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Temporary File Shelf selection is now a public Core model shared by
  the App and Core checks. Source-contract checks now scan the split overlay
  files, renamed File Shelf overlay, canonical `MusicSkipDirection`, Core-owned
  window slack constants, and `ScreenMetricsProvider.metrics(for:)`.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product
  DynamicIsland`; `./script/build_and_run.sh`; process sample showed
  `DynamicIsland` running from `dist/Dynamic Island.app` at idle `0.0%` CPU.
- Rollback: Move the selection type back to the App target only if Core checks
  no longer exercise File Shelf selection; restore old source-contract strings
  only if the split overlay files and canonical skip direction are reverted.

### 2026-06-28 - notched-open-size-850x200
- Reason: User requested the expanded Dynamic Island size be `850pt` wide and
  `200pt` tall.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Sources/DynamicIsland/Support/ScreenMetricsProvider.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Notched displays now derive a fixed expanded shell size of
  `850 x 200pt`. Cached display profiles are refreshed automatically when the
  sizing policy changes. Standard non-notch displays keep their existing compact
  adaptation.
- Verify: `swift run DynamicIslandCoreChecks`.
- Rollback: Restore the previous dynamic `recommendedOpenSize` notch formula,
  old width/height expectations, and cache-only profile lookup if
  display-scaled sizing is needed again.

### 2026-06-28 - closed-only-vertical-hide-show
- Reason: User wanted default-state upward scroll to hide the island with a
  horizontal sides-to-center transition, hidden-state downward scroll to restore
  from center outward, and expanded state to ignore vertical hide/show gestures.
- Changed:
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Visible vertical hide/show now has a dedicated gate that only allows
  the closed, non-hidden shell to hide. Hidden state still has first priority
  and restores on downward scroll. Expanded state no longer locks or executes
  vertical hide/show gestures.
- Verify: `swift run DynamicIslandCoreChecks`.
- Rollback: Remove `canHandleVerticalHideShow` and the added source-contract
  checks to restore previous expanded-state vertical scroll behavior.

### 2026-06-27 - consolidate-memory-log
- Reason: `MEMORY.md` had grown to more than 1600 lines of detailed historical
  events, making current project context harder to read.
- Changed:
  - `MEMORY.md`
- Result: Replaced the full historical dump with a compact current snapshot,
  current contracts, recent rollback-relevant events, and consolidated older
  history. Older committed detail remains recoverable from git history; the
  latest uncommitted details were summarized in the recent events above.
- Verify: Documentation-only change; `git diff --check -- MEMORY.md`.
- Rollback: Restore a previous `MEMORY.md` version from git if full historical
  granularity is needed again.

### 2026-06-27 - data-panel-redesign-visualization
- Reason: User requested a Data panel redesign focused on visualization for
  today plus seven-day history; the previous layout had too many stacked text
  blocks and mixed Chinese/English labels.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `MEMORY.md`
- Result: Data panel now uses four compact components: header, four metric
  cards, seven-day bar chart, and token ledger. It shows Total Tokens, Cost,
  Cache Hit, Requests, recent bars, peak label, and token breakdown.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`;
  `./script/build_and_run.sh`.
- Rollback: Restore the previous Data subviews from git history if the new
  visualization direction should be backed out.

### 2026-06-27 - naming-normalization-and-macbook-size-adaptation
- Reason: Review found duplicate skip-direction enums, bridge conversion,
  silent save errors, and missing named preview constants for supported MacBook
  sizes.
- Changed:
  - `Sources/DynamicIslandCore/MusicSkipGestureStateMachine.swift`
  - `Sources/DynamicIsland/Support/MusicPlaybackDataSource.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIsland/Support/DisplayProfileStore.swift`
  - `Sources/DynamicIsland/Support/IslandInteractionLogger.swift`
  - `Sources/DynamicIslandCore/CCSwitchUsageSnapshot.swift`
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `AGENTS.md`
  - `MEMORY.md`
- Result: `MusicSkipDirection` is canonical in Core; bridge conversion was
  removed; `currentDirection` became a computed property; save failures assert
  in debug; date/cost formatters were normalized; `preview16Inch` and device
  matrix checks were added.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`;
  `./script/build_and_run.sh`.
- Rollback: Restore the old Core/UI split enums and bridge only if a separate UI
  direction type becomes necessary again.

### 2026-06-21 - data-reveal-delay-shell-first-animation
- Reason: Expanded Data animation still felt like it grew down and right because
  final-width Data content appeared before the shell spring had widened enough.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Data reveal delay now waits until
  `animationProfile.expandResponse * 0.72`, letting shell expansion lead before
  Data content fades in.
- Verify: A regression check failed on the old `0.42` multiplier; then
  `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`;
  `./script/build_and_run.sh --debug-data`; screenshot and CPU sampling.
- Rollback: Restore the `0.42` delay only if Data content stops occupying final
  open width during the shell spring.

### 2026-06-20 - data-local-usage-mirror
- Reason: Data should not go empty when cc-switch is unavailable after a
  successful read.
- Changed:
  - `Sources/DynamicIslandCore/CCSwitchUsageSnapshot.swift`
  - `Sources/DynamicIsland/Support/CCSwitchUsageDataSource.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: cc-switch snapshots became `Codable`; successful reads are mirrored to
  `~/Library/Application Support/Dynamic Island/cc-switch-usage-snapshot.json`;
  missing/unreadable cc-switch falls back to the mirrored snapshot before
  `.empty`.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`;
  `./script/build_and_run.sh --debug-data`; mirror file was created with real
  usage data.
- Rollback: Remove `LocalCCSwitchUsageSnapshotStore`, remove `Codable` from
  snapshot models, and return directly to `.empty` on missing cc-switch.

### 2026-06-20 - data-animation-and-debug-interaction-cleanup
- Reason: Data panel animation and debug launch behavior were causing the
  expanded shell to feel asymmetric and changed normal mouse-exit behavior.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Data content no longer applies its own horizontal scale/corner morph on
  top of the shell morph; Data uses shell-owned spatial animation plus opacity
  reveal. `--debug-data` still starts expanded on Data but no longer disables
  normal mouse-exit collapse when File Shelf is not pinned.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`;
  `./script/build_and_run.sh --debug-data`; screenshots and CPU sampling.
- Rollback: Remove the Data reveal modifier/state for static mounting, or add a
  separate screenshot-only hold flag if visual QA needs one.

### 2026-06-20 - data-command-deck-and-boundary-qa
- Reason: User selected a visual Data direction and later QA showed the panel
  needed better fidelity and safer calibration boundaries.
- Changed:
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIslandCore/IslandCalibrationLayout.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `docs/superpowers/plans/2026-06-20-data-command-deck-phase-1.md`
  - `design-qa.md`
  - `MEMORY.md`
- Result: Data gained a staged Command Deck implementation, design QA notes,
  header/ledger/ribbon refinements, and later boundary fixes so content stays
  inside the visible 5pt calibration boundary and rounded shell constraints.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`;
  `git diff --check`; `./script/build_and_run.sh --debug-data`; comparison and
  calibration screenshots.
- Rollback: Restore the previous `DataUsagePanelView` internals and remove the
  Command Deck checks if this design direction is abandoned. Keep later 5pt
  boundary rules unless the shell shape contract changes.

### 2026-06-20 - cc-switch-data-feature-panel
- Reason: User wanted the new `Data` primary feature to use current cc-switch
  usage without restoring removed old Stats/task monitoring surfaces.
- Changed:
  - `Sources/DynamicIslandCore/CCSwitchUsageSnapshot.swift`
  - `Sources/DynamicIsland/Support/CCSwitchUsageDataSource.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `script/build_and_run.sh`
  - `MEMORY.md`
- Result: Expanded `Data` reads `~/.cc-switch/cc-switch.db` read-only, publishes
  today's usage, seven-day token trend, peak token/s estimate, and sanitized
  `data.ccswitch.snapshot` logs. `--debug-data` opens a cursor-free visual QA
  state.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`;
  `./script/build_and_run.sh --debug-data`; screenshot and logs.
- Rollback: Remove the cc-switch snapshot/data source/polling and Data usage
  panel if `Data` should return to a placeholder.

### 2026-06-18 - release-display-adaptation-and-core-trim
- Reason: User requested release readiness across MacBook notch sizes and
  non-notch displays, plus code trimming and verification.
- Changed:
  - `Sources/DynamicIslandCore/NotchMetrics.swift`
  - `Sources/DynamicIslandCore/CalendarHeatmap.swift`
  - `Sources/DynamicIslandCore/CalendarHeatmapVisualPolicy.swift`
  - `Sources/DynamicIslandCore/CodexUsage.swift`
  - `Sources/DynamicIslandCore/DataPanelMode.swift`
  - `Sources/DynamicIslandCore/DataPanelTooltipPolicy.swift`
  - `Sources/DynamicIslandCore/IslandFeature.swift`
  - `Sources/DynamicIslandCore/TaskActivityState.swift`
  - `Sources/DynamicIslandCore/UsageTrendTimeline.swift`
  - `Sources/DynamicIsland/Support/ScreenMetricsProvider.swift`
  - `Sources/DynamicIsland/Support/DisplayProfileStore.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Added display-matrix coverage for compact notched, large notched, and
  non-notch displays; launch diagnostics log sanitized display metrics; unused
  old Stats/Usage/TaskActivity Core modules were removed from the active release
  path.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`;
  `swift build -c release --product DynamicIsland`; `git diff --check`;
  `./script/build_and_run.sh --verify`; visual audit screenshot and launch logs.
- Rollback: Restore deleted Core files only if Stats/Usage/TaskActivity is
  explicitly reselected.

### 2026-06-18 - music-gesture-state-machine-and-debug-signal
- Reason: Horizontal music skip needed reliable direction locking, rollback
  cancellation, phase-ended commit, and screenshot/debug support.
- Changed:
  - `Sources/DynamicIslandCore/MusicSkipGestureStateMachine.swift`
  - `Sources/DynamicIsland/Support/DebugMusicSignal.swift`
  - `Sources/DynamicIsland/Support/MusicPlaybackDataSource.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `script/send_music_signal.sh`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Horizontal skip is handled by a Core state machine; direction locks per
  gesture, rollback can cancel, phase-aware gestures commit only on end, and
  debug signal files can preview playing/idle/next/previous states.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`;
  `./script/build_and_run.sh --debug-music-signal`; CGEvent/debug screenshots.
- Rollback: Remove `MusicSkipGestureStateMachine` and debug-signal polling only
  if horizontal skip is removed or replaced.

### 2026-06-18 - file-shelf-independent-overlay-current-contract
- Reason: User required File Shelf to behave as an independent temporary-file
  module rather than patched expanded content.
- Changed:
  - `Sources/DynamicIslandCore/TemporaryFileShelf.swift`
  - `Sources/DynamicIsland/Support/TemporaryFileShelfStore.swift`
  - `Sources/DynamicIsland/Views/TemporaryFileShelfView.swift`
  - `Sources/DynamicIsland/Views/IslandTrackingHostingView.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: File Shelf is an in-memory overlay with file URL dedupe, expiry
  pruning, filtering, selection, rectangle selection, multi-file drag-out,
  pinned open behavior, cancel-safe drag removal, compact density, and sanitized
  logs.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`;
  `./script/build_and_run.sh`; debug visual QA screenshots and process sampling.
- Rollback: Remove the store/view/controller/overlay shelf wiring to return to a
  music-only expanded shell.

### 2026-06-18 - runtime-settings-calibration-and-primary-navigation
- Reason: User wanted runtime settings, calibration overlay visibility, and
  first-level expanded navigation in camera-safe regions.
- Changed:
  - `Sources/DynamicIsland/Support/IslandRuntimeSettings.swift`
  - `Sources/DynamicIsland/Views/IslandSettingsView.swift`
  - `Sources/DynamicIsland/Controllers/AppDelegate.swift`
  - `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - `Sources/DynamicIslandCore/IslandCalibrationLayout.swift`
  - `Sources/DynamicIslandCore/IslandTopStatusBandLayout.swift`
  - `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: Menu bar settings are Chinese and transient; runtime toggles/sliders
  drive controller state; `--debug-calibration` and settings toggle show the same
  calibration overlay; expanded shell has `Tasks / Data / Tools / Settings`
  navigation in the top safe region.
- Verify: `swift run DynamicIslandCoreChecks`; `swift build --product DynamicIsland`;
  `./script/build_and_run.sh --verify`; `./script/build_and_run.sh --debug-calibration`.
- Rollback: Remove runtime settings/calibration toggle/navigation if the product
  returns to a fixed expanded shell.

## Consolidated Older History

### 2026-06-17 to 2026-06-18 - shell, music, file shelf, and mainline stabilization
- Scope: Rename to Dynamic Island, set black theme, tune compact shell sizing and
  corner radii, add hidden scroll behavior, add track info reveal, stabilize
  hover/window resizing, rebuild File Shelf, add interaction JSONL logging, and
  clean mainline naming/docs.
- Final state: Current app is a black Dynamic Island shell with music-aware
  closed state, hidden-state priority, low-cost waveform, independent File Shelf,
  display adaptation, and sanitized logs.
- Superseded details: Multiple intermediate shell-radius, width, music skip, and
  File Shelf approaches were tried then refined or rolled back. Use git history
  before this consolidation for exact intermediate commits/events.
- Rollback anchor: Commit history around `9c47b80` records the horizontal-swipe
  rollback boundary; later events reintroduced skip through a stricter state
  machine.

### 2026-06-16 - display profile cache and completion feedback
- Scope: Added display calibration/profile cache, display profile kinds, Tools
  debug panel, selected feature persistence, and Codex completion feedback.
- Final state: Display metrics can be cached and classified as compact notched,
  large notched, or standard display. The old full-width completion sweep was
  replaced by closed-island bottom-edge bounce feedback.
- Rollback: Remove display profile model/store/cache if runtime measurement
  should be direct-only. Remove completion bounce trigger and shape
  `bottomEdgeDrop` if completion feedback should be disabled.

### 2026-06-15 - usage, waveform, audio experiments, and cleanup
- Scope: Added/adjusted Codex usage parsing, cc-switch alignment, audio waveform
  detection experiments, ScreenCaptureKit diagnostics, Apple Events usage
  description, Core Audio tap opt-in, ECG experiments, and CPU fixes.
- Final state: Default mode avoids ScreenCaptureKit/system-audio capture and
  avoids ECG/heartbeat fallback. Music waveform is separated from idle/default
  state and must not run hidden continuous animation.
- Important rejected paths: ECG/heartbeat fallback was explicitly removed;
  default screen/system audio capture was rejected because of privacy indicator
  and permission friction.
- Rollback: Do not restore ECG or default ScreenCaptureKit unless the user
  explicitly reselects those behaviors.

### 2026-06-14 - memory converted to event log
- Scope: Converted `MEMORY.md` from long-form state summary to event-log style.
- Final state: Future updates should be concise event records, not a complete
  rule dump.
- Rollback: Restore older backup only if long-form memory is wanted again.

### 2026-06-10 - initial direction and SwiftPM MVP
- Scope: Established that the project learns from Vibe Island without cloning
  features, created native SwiftPM MVP, locked notch-safe shell basics, added
  real usage/status prototypes, and preserved `.reference/vibe-island/`.
- Final state: Native macOS app owns the product direction; reference repo is
  navigation material only.
- Rollback: Do not delete `.reference/vibe-island/` unless user explicitly asks.
