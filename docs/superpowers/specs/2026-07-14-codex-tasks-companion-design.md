# Codex Tasks Companion Design

## Goal

Replace the current row-only Tasks surface with the approved high-fidelity
Codex companion layout: a 32pt pixel pet, Codex identity, current-conversation
token total, and a compact realtime session-progress timeline.

## Visual decision

The expanded island keeps its existing `850×200` logical-point shell, black
material, 32pt camera-safe top band, left Files control, and right
`Tasks / Data / Tools / Settings` navigation. Only the content inside
`IslandPrimaryContentLayout.tasksContentFrame` changes.

The Tasks content has two fixed tiers:

1. A 54pt summary card contains a 32pt code-native pixel cat, the installed
   Codex app icon, `Codex`, a live indicator, the focused thread title and
   activity, the approval badge when needed, and the focused conversation's
   cumulative token count.
2. The remaining height contains `会话进程` and the three most recent distinct
   progress events. Each event shows local `HH:mm` time, a concise sanitized
   phase label, and a state badge such as `完成`, `进行中`, `待审`, or `重试`.

The focused thread is the newest visible, non-dismissed task. If more than one
task is visible, the identity line adds a compact session-count label without
changing the single-session layout.

## Pixel pet

The production pet is a 32pt SwiftUI `Canvas` rendered from a 16×16 logical
pixel grid at an exact 2pt integer scale. It uses an off-white/cool-gray body,
graphite shadow pixels, and mint-cyan eyes. Four discrete poses map to current
Codex state:

- `idle`: no visible task or Codex unavailable.
- `thinking`: thinking, writing, compacting, retrying, or waiting for approval.
- `tool`: a tool call is running; the pet includes a tiny terminal panel.
- `done`: a retained completed turn; the pet includes a restrained mint
  completion sparkle.

The pet does not blink, bob, pulse, or run a default loop. State changes may
redraw the static pixel pattern, but they do not start continuous animation.
The 16×16 design remains a future compact-state option and is not added until a
real collapsed-state placement is selected.

## Codex identity and tokens

The identity mark resolves the installed app with bundle identifier
`com.openai.codex` and asks `NSWorkspace` for its icon. When the app icon cannot
be resolved, the view falls back to the existing system terminal symbol.

`TOTAL TOKENS` uses the focused task's `totalTokens` value. That value continues
to come from Codex's read-only `threads.tokens_used` value and newer rollout
`token_count.total_token_usage.total_tokens` events. It is the cumulative total
for the current Codex conversation, not an estimate and not a sum across every
visible thread.

## Realtime progress data

`CodexStatusSignalSource` continues to read `~/.codex/state_5.sqlite` and rollout
JSONL tails read-only. During the existing rollout pass it derives a bounded
list of progress events from lifecycle, reasoning, response, tool, approval,
retry, compaction, and completion records. Consecutive duplicates collapse to
one event and only a small recent buffer is retained in the snapshot.

Tool names are never rendered raw. A small allowlist maps known categories to
labels such as `运行命令`, `修改文件`, `查看图像`, `生成图像`, and `等待工具`;
everything else becomes `运行工具`. The parser never copies prompt text,
assistant text, command arguments, tool output, raw paths, or filenames into a
progress event.

If a rollout has no usable progress events, the timeline shows
`暂无会话进程` rather than synthesizing fake history.

## Existing behavior retained

- Normal-mode polling remains 1 second while Tasks is visible and at most every
  5 seconds in the background.
- The source query remains bounded to four recent unarchived Codex threads.
- Approval is display-only; the island does not approve commands or file
  changes.
- A focused completed task keeps the existing hover close control, shatter
  effect, local-only seven-day dismissal, and five-second Undo.
- The 10-second completed-row retention and 60-second stale-task cutoff remain
  unchanged.
- Tasks stays inside the existing content frame and never enters the physical
  camera-housing region.
- Primary-feature entrance, Files behavior, shell geometry, music behavior,
  permissions, and dependencies remain unchanged.

## Accessibility and performance

- The pet exposes a state-specific accessibility label and is otherwise one
  accessibility element, not hundreds of pixel elements.
- Timeline rows provide combined time, phase, and status labels.
- Text remains single-line with truncation for long thread titles.
- No `ProgressView`, `TimelineView`, timer, `repeatForever`, or per-frame state
  is introduced.
- The existing rollout cache remains keyed by file size and modification date;
  progress extraction happens only when that cached rollout state is rebuilt.
- Reduce Motion keeps the existing content fade and removes the shatter motion
  through the current deletion path.

## Verification

- Add Core checks for progress-event modeling, state-to-pet mapping, privacy
  boundaries, exact 32pt pixel-pet rendering, token presentation, timeline
  capping, and retained dismissal/approval behavior.
- Run `swift run DynamicIslandCoreChecks` after each focused change.
- Run `swift build --product DynamicIsland`, `git diff --check`, and
  `./script/build_and_run.sh` after integration.
- Capture the expanded Tasks frame and compare it with the approved concept:
  identity/pet left, total tokens right, and three progress rows below.
- Verify live timeline and tokens against the current Codex rollout without
  exposing raw conversation or tool payloads.
- Sample settled expanded and collapsed CPU; no continuous pet animation should
  appear in the profile.

## Rollback

Restore the former row-only `CodexTasksContentView` and `CodexStatusBarView`,
remove the pixel-pet view and progress-event snapshot field, and stop deriving
progress events in `CodexStatusSignalSource`. Keep the existing Codex database,
rollout parsing, approval detection, dismissal store, polling cadence, and
camera-safe layout contracts.
