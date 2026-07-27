# Codex Tasks Hierarchy and Adaptive Expansion Design

## Goal

Prevent Codex subagent threads from displacing or mixing with primary sessions,
and let one primary session reveal its subagents by smoothly extending the
expanded Island downward.

## Data hierarchy

`CodexStatusSignalSource` continues to read Codex state and rollout files
read-only. Primary sessions are queried separately from subagents so a burst of
agents cannot consume the primary-session limit. The source reads at most eight
recent primary sessions and at most 24 recent descendants of those sessions.

Subagents are identified by `thread_source = 'subagent'`. Their immediate
parent, root session, depth, and display nickname come from the existing Codex
thread metadata (`source.subagent.thread_spawn`, `agent_nickname`). Nested
agents retain their depth and root-session identity. Raw prompts, agent task
instructions, paths, and tool payloads are not added to the UI model.

## Tasks layout

The base expanded shell remains 850×200 points. Tasks uses a master-detail
layout: primary sessions appear in the left column and the selected primary
session or subagent appears in the right detail column. New sessions do not
replace a still-visible manual selection.

Each primary row has a fixed height and shows a subagent count when applicable.
A trailing disclosure button opens only that primary session. Subagents render
indented below their parent and never appear as peer primary sessions. Only one
primary group may be open at a time. Selecting an agent shows that agent's
identity, token total, state, and sanitized rollout progress on the right.

## Adaptive height

Opening a group adds 10 points of section spacing and 26 points per visible
agent row. Five rows contribute to height; additional rows remain reachable by
local scrolling. The additional height is therefore capped at 140 points and
the shell at 340 points. Closing the group restores the 200-point base height.

The top edge stays fixed at the screen top. One controller-owned height value
drives the SwiftUI shell, its primary-content frame, the NSPanel canvas, and the
precise `IslandShape` hit-test path. Switching away from Tasks or collapsing
the Island resets the extra height to zero.

## Motion and accessibility

Expansion uses the existing shared animation profile with a critically damped,
interruptible spring. The panel canvas grows before the visible shell and
shrinks only after the shell settles, so content is never clipped. The
disclosure indicator and child content follow the same state transition.

Reduce Motion disables geometric tweening and uses the existing short opacity
feedback. There is no continuous animation, timer, display link, or new polling
loop.

## Existing behavior retained

- The physical camera region and 32-point top-band contract remain unchanged.
- Codex SQLite and rollout JSONL remain read-only.
- Approval display, 10-second completed retention, 60-second stale cutoff,
  local-only dismissal, shatter feedback, and five-second Undo remain intact.
- Files, music, gestures, permissions, dependencies, and primary navigation do
  not change.

## Verification

- Core checks cover hierarchy metadata, root selection, height calculation,
  dynamic primary-content height, and synchronized controller/view hit testing.
- Source contracts prove primary and subagent limits are separate and reject
  the former flat `LIMIT 4` query.
- `swift run DynamicIslandCoreChecks`, `swift build --product DynamicIsland`,
  `git diff --check`, and `./script/build_and_run.sh` must pass.
- The live app is checked with multiple real sessions/subagents and settled CPU
  is sampled after expansion and collapse.

## Rollback

Restore the flat recent-thread query and fixed 200-point Tasks shell, remove the
hierarchy metadata and disclosure state, and keep the existing companion,
timeline, dismissal, polling, rollout caching, and camera-safe contracts.
