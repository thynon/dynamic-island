# Dynamic Island Rename and Mainline Cleanup

> **For agentic workers:** This record is complete. The rename work has already been implemented and verified.

**Goal:** Rename the project to Dynamic Island across code, scripts, docs, and branch structure.

**Status:** complete

**Summary:** The SwiftPM package, executable, module names, app display strings, bundle identifier, support directory, and user-facing status menu now use Dynamic Island / DynamicIsland naming. The local branch layout has been collapsed so `main` is the active branch, and the renamed app builds and runs successfully.

**Files touched:**
- `Package.swift`
- `Sources/DynamicIsland/`
- `Sources/DynamicIslandCore/`
- `Tests/DynamicIslandCoreChecks/`
- `script/build_and_run.sh`
- `script/set_task_activity.sh`
- `docs/CODEX_GIT_WORKFLOW.md`
- `docs/HANDOFF-2026-06-15.md`
- `AGENTS.md`
- `MEMORY.md`

**Verification:**
- `swift run DynamicIslandCoreChecks`
- `swift build --product DynamicIsland`
- `./script/build_and_run.sh --verify`
- `git branch -vv`
- `gh repo view thynon/dynamic-island --json nameWithOwner,visibility,defaultBranchRef,url`

**Branch:** `main`
**Commit:** `7227244 rename project to dynamic island`
