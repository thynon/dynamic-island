# Dynamic Island Rename and Mainline Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the project to Dynamic Island across code, scripts, docs, and branch structure so the repository reads like a clean mainline project.

**Architecture:** Keep SwiftPM module names, executable names, app bundle naming, and user-facing strings aligned on `DynamicIsland` for code and `Dynamic Island` for display. Update the small set of runtime support paths that currently hard-code `Island` so the renamed app writes to its new support directory. Finish by collapsing the local branch layout so `main` is the active branch and the stale local branch ref is removed.

**Tech Stack:** SwiftPM, AppKit, Bash scripts, Git.

---

### Task 1: Rename SwiftPM targets and source roots

**Files:**
- Modify: `Package.swift`
- Move: `Sources/Island` -> `Sources/DynamicIsland`
- Move: `Sources/IslandCore` -> `Sources/DynamicIslandCore`
- Move: `Tests/IslandCoreChecks` -> `Tests/DynamicIslandCoreChecks`

- [ ] **Step 1: Update the package manifest to use `DynamicIsland`, `DynamicIslandCore`, and `DynamicIslandCoreChecks` product and target names.**

```swift
let package = Package(
    name: "DynamicIsland",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DynamicIslandCore", targets: ["DynamicIslandCore"]),
        .executable(name: "DynamicIsland", targets: ["DynamicIsland"]),
        .executable(name: "DynamicIslandCoreChecks", targets: ["DynamicIslandCoreChecks"])
    ],
    targets: [
        .target(name: "DynamicIslandCore"),
        .executableTarget(
            name: "DynamicIsland",
            dependencies: ["DynamicIslandCore"]
        ),
        .executableTarget(
            name: "DynamicIslandCoreChecks",
            dependencies: ["DynamicIslandCore"],
            path: "Tests/DynamicIslandCoreChecks"
        )
    ]
)
```

- [ ] **Step 2: Move the source and test directories to the new module names.**

```bash
git mv Sources/Island Sources/DynamicIsland
git mv Sources/IslandCore Sources/DynamicIslandCore
git mv Tests/IslandCoreChecks Tests/DynamicIslandCoreChecks
```

- [ ] **Step 3: Run `swift run DynamicIslandCoreChecks` and confirm the build fails until import statements and file paths are updated.**

Expected: SwiftPM reports missing module references such as `import IslandCore`.

- [ ] **Step 4: Update all source imports and test path lookups to the renamed modules and directories.**

```swift
import DynamicIslandCore
```

```swift
let overlay = source("Sources/DynamicIsland/Views/IslandOverlayView.swift")
```

- [ ] **Step 5: Run `swift run DynamicIslandCoreChecks` again and confirm it passes.**

Expected: `DynamicIslandCoreChecks passed`.

- [ ] **Step 6: Commit the rename once the manifest, module imports, and test references all align.**

```bash
git add Package.swift Sources/DynamicIsland Sources/DynamicIslandCore Tests/DynamicIslandCoreChecks
git commit -m "rename project to dynamic island"
```

### Task 2: Rename app packaging, display strings, and support paths

**Files:**
- Modify: `script/build_and_run.sh`
- Modify: `script/set_task_activity.sh`
- Modify: `Sources/DynamicIsland/Controllers/AppDelegate.swift`
- Modify: `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
- Modify: `Sources/DynamicIsland/Support/DisplayProfileStore.swift`
- Modify: `Sources/DynamicIsland/Support/ScreenMetricsProvider.swift`

- [ ] **Step 1: Switch the packaged app identity to `DynamicIsland` while keeping the visible title as `Dynamic Island`.**

```bash
APP_EXECUTABLE_NAME="DynamicIsland"
APP_DISPLAY_NAME="Dynamic Island"
BUNDLE_ID="cx.dynamicisland.mvp"
```

- [ ] **Step 2: Update UI strings so the status menu, tooltips, and panel title read `Dynamic Island`.**

```swift
item.button?.toolTip = "Dynamic Island MVP"
menu.addItem(NSMenuItem(title: "Show Dynamic Island", action: #selector(showIsland), keyEquivalent: ""))
menu.addItem(NSMenuItem(title: "Hide Dynamic Island", action: #selector(hideIsland), keyEquivalent: ""))
menu.addItem(NSMenuItem(title: "Quit Dynamic Island", action: #selector(quit), keyEquivalent: "q"))
panel.title = "Dynamic Island"
```

- [ ] **Step 3: Move Application Support reads and writes from `Library/Application Support/Island` to `Library/Application Support/Dynamic Island`.**

```swift
.appendingPathComponent("Library/Application Support/Dynamic Island", isDirectory: true)
```

- [ ] **Step 4: Update the task activity helper to write the renamed support path and print the renamed project label.**

```bash
STATE_FILE="${HOME}/Library/Application Support/Dynamic Island/task-activity-state.txt"
echo "Dynamic Island task activity: $STATE"
```

- [ ] **Step 5: Run `swift build --product DynamicIsland` and `./script/build_and_run.sh --verify`.**

Expected: the app bundle is produced under `dist/Dynamic Island.app` and launches successfully.

### Task 3: Clean up docs and local branch layout

**Files:**
- Modify: `MEMORY.md`
- Modify: `docs/CODEX_GIT_WORKFLOW.md`
- Modify: `docs/HANDOFF-2026-06-15.md`
- Modify: `docs/superpowers/specs/2026-06-17-file-shelf-overlay-design.md`
- Modify: `docs/superpowers/plans/2026-06-10-island-mvp-app.md`
- Modify: `docs/superpowers/plans/2026-06-17-file-shelf-overlay.md`
- Modify: `docs/superpowers/plans/2026-06-17-file-shelf-phase-1.md`
- Modify: `docs/superpowers/plans/2026-06-17-file-shelf-phase-2.md`
- Modify: `docs/superpowers/plans/2026-06-17-file-shelf-phased-roadmap.md`

- [ ] **Step 1: Update the project memory with the rename decision and the branch cleanup result.**

```markdown
### 2026-06-17 - rename-project-to-dynamic-island
- Reason: User requested the project name change and a cleaner main branch layout.
- Result: Project code, app identity, support paths, and local branch structure now use Dynamic Island / DynamicIsland naming.
```

- [ ] **Step 2: Rewrite the active docs that describe the project as Island so they use the new project name where they are not historical notes.**

```markdown
Dynamic Island
```

- [ ] **Step 3: Rename the current local branch to `main` after moving the stale local `main` ref out of the way.**

```bash
git branch -m main main-old
git branch -m codex/file-shelf-overlay main
```

- [ ] **Step 4: Verify the final branch layout and working tree status.**

```bash
git branch -vv
git status -sb
```

Expected: `main` tracks `origin/main` and there is no active feature branch left behind.
