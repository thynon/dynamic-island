# Data Token Usage Pause Handoff

Date: 2026-07-19
Completion update: 2026-07-22
Status: resumed and completed in the working tree; no stage or commit per plan
Branch: `codex/data-token-usage`
Plan: `docs/superpowers/plans/2026-07-19-data-token-usage.md`

## Resume Completion (2026-07-22)

- Tasks 5, 6, and 7 are complete. The final product contract below is implemented without adding a chart, source/model/client breakdown, polling loop, or new permissions.
- Fixture usage checks, `DynamicIslandCoreChecks`, app build, whitespace checks, final package/sign/launch, sanitized live reads, macOS 26 closed/open visual captures, and idle process sampling were completed.
- Today, 3-day, and 7-day live reads were complete. The 30-day live read was partial only for a rollout changing during the scan, insufficient 30-day CC Switch non-Codex coverage, and unpriced usage.
- The final app is running from `/Users/user/Documents/Codex/Island/dist/Dynamic Island.app`. The working tree remains intentionally dirty and uncommitted.

## Current State

The worktree is intentionally shared and dirty because this feature depends on earlier user changes. No existing changes were reset, stashed, staged, or committed. Task 5's implementation agent was stopped before it changed any Task 5 source or test file.

Completed tasks:

- Task 1: natural-day windows, half-open bounds, Token normalization, cumulative deltas, aggregation, formatting, and Core checks.
- Task 2: streaming Codex `token_count` parser, full-sequence diffing, baseline breaks, strict timestamps, structured marker scanning, and replayable parse results.
- Task 3: read-only SQLite runner, CC Switch non-Codex source, semantic mapping, request de-duplication, Decimal cost handling, cancellation-safe process lifecycle, and real temporary SQLite checks.
- Task 4: Codex actor source, state/canonical rollout selection, child-agent coverage, active/archive de-duplication, conflict ranking, 64 KiB streaming reads, signature retry/cache, partial-read handling, and root enumeration recovery.

Each completed task has an implementation report and an independent review package under `.superpowers/sdd/data-token-usage/`. The task ledger records all four as independently reviewed and approved.

## Remaining Work at Pause (historical)

1. Task 5: create `UsageAggregationService`, merge both sources concurrently, implement the failure matrix, and add generation/range/cancellation publication guards. Add the optional sanitized `--live` usage-check mode.
2. Task 6: create `DataPrimaryContentView` and the Liquid Glass time-range drawer. Keep Today as the default, use the four range choices plus manual refresh, preserve Reduce Motion/Transparency/increased contrast behavior, and keep the macOS 14/15 material fallback.
3. Task 7: integrate Data state, view mounting, drawer dismissal/z-index behavior, controller loading and stale-result guards, then update `MEMORY.md` with the final contract.
4. Final verification: run fixture checks, CoreChecks, app build, `./script/build_and_run.sh`, sanitized live checks, visual interaction checks for the drawer, and idle CPU/accessibility checks. Then perform a final independent review and decide whether to keep the branch or integrate it.

## Approved Product Contract

- Only total Token usage is shown; no source/model/client distinction and no chart.
- The range control defaults to Today and opens a downward drawer with Today, 3 days, 1 week, and 30 days; refresh is manual.
- Codex raw rollouts are aggregated with CC Switch non-Codex rows; CC Switch Codex rows are excluded to prevent double counting.
- Windows use captured local natural-day starts and a half-open `[start, end)` UTC interval. All sources share one captured `now` and time zone per refresh.
- Reads are local and read-only. No database writes, permissions, polling timer, or background refresh loop.
- macOS 26 uses native Liquid Glass with unique effect identities and matched geometry; older systems use the existing material fallback. Motion must remain interruptible and respect accessibility settings.

## Resume Procedure Used (historical)

1. Read this handoff and the implementation plan.
2. Confirm the current branch and preserve the existing dirty worktree; do not reset or bulk-format.
3. Re-run `./script/run_usage_checks.sh`, `swift run DynamicIslandCoreChecks`, and `swift build --product DynamicIsland` as the Task 4 baseline.
4. Start Task 5 with a fresh implementer and a separate reviewer, using the existing Task 5 brief and the same working-tree diff-package convention.
5. Continue sequentially through Tasks 6 and 7, updating `.superpowers/sdd/progress.md` after each approved task.

## Evidence Paths

- Design: `docs/superpowers/specs/2026-07-19-data-token-usage-design.md`
- Implementation plan: `docs/superpowers/plans/2026-07-19-data-token-usage.md`
- Task reports/reviews: `.superpowers/sdd/data-token-usage/task-{1,2,3,4}-report.md` and `task-{1,2,3,4}-review-fixed.diff`
