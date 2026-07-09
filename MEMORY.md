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

- Date: 2026-06-27.
- Branch observed during consolidation: `optimization-comprehensive`.
- Product: native macOS Dynamic Island-style desktop app for notched and
  non-notched displays.
- Stack: SwiftPM, macOS 14+, Swift 6, AppKit + SwiftUI.
- Current focus:
  - black notch-blended island shell
  - music playback state with album art, low-cost waveform, and cancellable
    horizontal skip gestures
  - expanded Data panel backed by cc-switch usage and a local usage mirror
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
- Data reads `~/.cc-switch/cc-switch.db` read-only and mirrors successful
  snapshots to local app support so the panel can show the last known usage
  when cc-switch is unavailable.

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
