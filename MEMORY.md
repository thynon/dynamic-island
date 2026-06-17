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
