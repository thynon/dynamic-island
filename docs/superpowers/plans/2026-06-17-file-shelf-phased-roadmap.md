# File Shelf Phased Roadmap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:writing-plans before implementing a phase, then use superpowers:executing-plans task-by-task. This document is the feature roadmap, not the execution plan for every code line.

**Goal:** Make Island File Shelf feel like a small system-level temporary file tray with grouped files, clear drop bounds, selection, and reliable drag-out removal.

**Architecture:** Keep file classification and shelf state in `IslandCore`, keep drag/drop and external drag completion in AppKit-facing Island files, and keep shelf visuals inside focused SwiftUI views. Each phase should be independently testable and should not turn `Files` into a fourth first-level feature.

**Tech Stack:** Swift 6, SwiftPM, AppKit drag/drop APIs, SwiftUI, `IslandCoreChecks`, existing Island top-band layout contracts.

---

## Current Baseline

Already implemented:

- File drag enters the Island target and opens File Shelf immediately.
- Drag recognition reuses the existing completion-style bottom-edge bounce and Glass sound.
- Shelf data is in-memory only.
- App restart clears the shelf.
- Items expire after `24h` during one app run.
- `Files` button appears only when shelf has items.
- `Files` button sits in the expanded top-left safe band near the camera housing.
- Shelf supports `Open`, `Remove`, `Clear`, and basic drag-out item providers.

Known next gaps:

- Images, documents, spreadsheets, and other files are currently displayed together.
- Shelf content needs a persistent dashed boundary so the usable shelf area is visually clear.
- Multi-select and rectangle selection are not implemented.
- Dragging files out does not yet reliably remove them only after a successful external drop.
- Drag-out cancel zones are not implemented; cancelling currently depends on the normal system drag cancellation flow.
- Accessibility, multi-display cancel behavior, and 20+ item performance have not been validated yet.

---

## Phase 1: File Categories And Dashed Shelf Bounds

**Goal:** Group files by type and make the shelf range visually obvious.

**Files:**

- Create or modify: `Sources/IslandCore/TemporaryFileShelf.swift`
- Modify: `Sources/Island/Views/TemporaryFileShelfView.swift`
- Modify: `Tests/IslandCoreChecks/main.swift`

**Scope:**

- Add a file category model:
  - `images`: `png`, `jpg`, `jpeg`, `heic`, `gif`, `webp`, `svg`
  - `documents`: `pdf`, `doc`, `docx`, `txt`, `md`, `pages`, `rtf`
  - `spreadsheets`: `xls`, `xlsx`, `csv`, `numbers`, `tsv`
  - `presentations`: `ppt`, `pptx`, `key`
  - `other`: everything else
- Render only non-empty categories.
- Show category title and count.
- Add a dashed rounded boundary around the whole shelf content area.
- Keep drag-active state brighter than normal state.
- Keep filename truncation stable for long names.

**Acceptance Criteria:**

- Dropping an image and spreadsheet shows two separate category sections.
- Dropping a `.pptx` or `.key` file shows it under `Presentations`, not `Other`.
- Empty categories are hidden.
- A dashed boundary is visible around the shelf area even when files exist.
- Top `Files` button position and right `Status / Stats / Tools` switcher do not move.

**Verification:**

```bash
swift run IslandCoreChecks
swift build --product Island
./script/build_and_run.sh
```

Manual check:

- Drag one `.png`, one `.xlsx`, and one `.pdf` into Island.
- Confirm they appear under separate sections.
- Confirm the dashed shelf bounds are visible and do not overlap the top 32pt camera band.
- On a non-notched or external display profile, confirm the dashed shelf bounds still fit the adapted Island panel and do not assume a physical camera housing exists.

---

## Phase 2: Selection State And Rectangle Selection

**Goal:** Allow users to select one or more shelf items before dragging them out.

**Files:**

- Create or modify: `Sources/IslandCore/TemporaryFileShelf.swift`
- Modify: `Sources/Island/Views/TemporaryFileShelfView.swift`
- Optional create: `Sources/Island/Views/TemporaryFileShelfSelectionOverlay.swift`
- Modify: `Tests/IslandCoreChecks/main.swift`

**Scope:**

- Add selected item IDs to overlay/store state.
- Click an item to select it.
- Click empty shelf space to clear selection.
- Drag across the shelf content to show a translucent selection rectangle.
- Do not start rectangle selection until pointer travel exceeds a small threshold, initially `5pt`.
- Select all item tiles intersecting the rectangle.
- Highlight selected tiles without changing tile size.
- Define scroll behavior for the first version: rectangle selection does not auto-scroll; auto-scroll can be added later if large shelves need it.
- Keep first version simple: no keyboard modifiers required.

**Acceptance Criteria:**

- Single click selects one item.
- Moving the pointer less than `5pt` while clicking does not start rectangle selection.
- Dragging a rectangle across multiple visible tiles selects those tiles.
- When the shelf content is scrollable, rectangle selection stays within the visible shelf viewport and does not auto-scroll in this phase.
- Clicking empty shelf space clears selection.
- Selection highlight does not shift layout.
- Clearing/removing an item also removes it from selection.

**Verification:**

```bash
swift run IslandCoreChecks
swift build --product Island
./script/build_and_run.sh
```

Manual check:

- Drop at least four files.
- Drag a selection rectangle over two files.
- Confirm only those files are highlighted.
- Slightly move the pointer while clicking a tile and confirm it is treated as a click, not a rectangle selection.
- Remove one selected file and confirm selection state updates cleanly.

---

## Phase 3a: Reliable Drag-Out With Remove-On-Success

**Goal:** When files are dragged out to Finder, Desktop, or another app and the external drop succeeds, remove those files from Island Shelf. Cancelled or rejected drags must keep the files.

**Files:**

- Create: `Sources/Island/Views/TemporaryFileShelfDragSourceView.swift`
- Modify: `Sources/Island/Views/TemporaryFileShelfView.swift`
- Modify: `Sources/Island/Controllers/IslandPanelController.swift`
- Modify: `Sources/Island/Support/TemporaryFileShelfStore.swift`
- Modify: `Tests/IslandCoreChecks/main.swift`

**Scope:**

- Replace or wrap simple SwiftUI `.onDrag` with an AppKit drag source when needed.
- Start dragging selected files when one selected tile is dragged.
- If no selection exists, dragging one tile drags only that item.
- Provide file URLs to the pasteboard.
- Detect drag session completion.
- Use `NSDraggingSource.draggingSession(_:endedAt:operation:)` as the first technical path for detecting completion.
- Treat `operation == []` / `.none` as cancelled or rejected.
- Treat non-empty operations such as `.copy`, `.move`, or `.generic` as external drop success only after manual verification against Finder/Desktop and at least one non-Finder app.
- Remove dragged items only when external drag operation succeeds.
- If the drag is cancelled or rejected, keep the items.

**Acceptance Criteria:**

- Drag one file from shelf to Finder/Desktop: item disappears from shelf after successful drop.
- Drag multiple selected files out: all successfully dropped selected items disappear.
- Start a drag and cancel it: items remain.
- Drag to an app that rejects the pasteboard contents: items remain.
- If shelf becomes empty, `Files` button disappears and Island returns to normal collapse behavior.

**Verification:**

```bash
swift run IslandCoreChecks
swift build --product Island
./script/build_and_run.sh
```

Manual check:

- Drop files into Island.
- Select two files.
- Drag them to Desktop or Finder.
- Confirm they are no longer shown inside Island.
- Repeat with a cancelled drag and confirm they remain.
- Repeat with at least one non-Finder drop target and record whether `operation` reliably reports success.

---

## Phase 3b: Drag-Out Cancel Zones

**Goal:** Give users a convenient cancel target while dragging shelf files out, without requiring them to return the pointer to Island.

**Files:**

- Create: `Sources/Island/Controllers/FileShelfCancelDropWindowController.swift`
- Create: `Sources/Island/Views/FileShelfCancelDropView.swift`
- Modify: `Sources/Island/Views/TemporaryFileShelfDragSourceView.swift`
- Modify: `Sources/Island/Controllers/IslandPanelController.swift`
- Modify: `Tests/IslandCoreChecks/main.swift`

**Scope:**

- While dragging shelf files out, show temporary left and right screen-edge cancel zones.
- Start with `48pt` wide cancel zones for usability. Narrow only if manual testing shows accidental hits.
- Dropping on a cancel zone cancels the drag-out operation and keeps the files in the shelf.
- Cancel zones are visible only during File Shelf drag-out and disappear immediately after drag end.
- Cancel zones should be visually quiet: faint dashed boundary, dark translucent fill, concise `Cancel` label.
- The cancel overlay must ignore normal interactions when no shelf drag-out is active.
- Avoid top menu bar and Dock conflict by keeping cancel zones inside the active screen's visible frame where possible.
- Do not cover all displays by default. In multi-display setups, first show cancel zones on the display that owns the Island panel; evaluate cross-display drag behavior manually.
- Keep standard macOS drag cancellation behavior available. If technically feasible, also support Escape as a secondary cancel path, but do not depend on it for the first pass.

**Acceptance Criteria:**

- Drag selected files to either screen-edge cancel zone and release: items remain.
- Cancel zones do not appear during normal mouse movement, normal Island hover, or dragging unrelated files into Island.
- Cancel zones do not obscure the menu bar, Dock, or the Island panel itself.
- In multi-display setups, cancel zones appear only on the Island panel's current display in the first version.

**Verification:**

```bash
swift run IslandCoreChecks
swift build --product Island
./script/build_and_run.sh
```

Manual check:

- Drop files into Island.
- Select two files.
- Repeat by dragging to the left and right screen-edge cancel zones and confirm they remain.
- Test with Dock at bottom and at left/right if available.
- Test with at least one external display if available.

---

## Phase 4: File Metadata And Stale File Cleanup

**Goal:** Make file cards more informative and remove stale entries safely.

**Files:**

- Modify: `Sources/IslandCore/TemporaryFileShelf.swift`
- Modify: `Sources/Island/Support/TemporaryFileShelfStore.swift`
- Modify: `Sources/Island/Views/TemporaryFileShelfView.swift`
- Modify: `Tests/IslandCoreChecks/main.swift`

**Scope:**

- Display lightweight metadata:
  - extension/category
  - size
  - remaining retention time
- Detect missing source files during prune/open/render refresh.
- Mark missing files visually first, using a muted state and warning indicator. Do not silently delete missing files in the first version.
- Prune expired items when the shelf opens and on the existing periodic shelf prune loop. Do not run heavy metadata reads every frame.
- Keep all metadata collection local and synchronous only when cheap.
- For larger shelves, cap synchronous metadata refresh per cycle so 50+ files do not block interaction.

**Acceptance Criteria:**

- Cards show useful metadata without becoming crowded.
- Missing files no longer create broken open actions.
- Missing files are visibly marked and remain removable by the user.
- Expired items are removed without leaving stale selection.
- UI still fits inside the current Island panel size.

**Verification:**

```bash
swift run IslandCoreChecks
swift build --product Island
./script/build_and_run.sh
```

Manual check:

- Drop files of different sizes and types.
- Delete one source file in Finder.
- Reopen shelf and confirm the item is handled cleanly.

---

## Phase 5: Visual Polish And Interaction Refinement

**Goal:** Make File Shelf feel integrated with the rest of Island.

**Files:**

- Modify: `Sources/Island/Views/TemporaryFileShelfView.swift`
- Modify: `Sources/Island/Views/IslandOverlayView.swift`
- Modify: `Sources/Island/Controllers/IslandPanelController.swift`
- Modify: `Tests/IslandCoreChecks/main.swift`

**Scope:**

- Tune dashed boundary opacity for normal, drag-active, and selected states.
- Add subtle transitions for category appearance and item removal.
- Keep all tile dimensions stable.
- Ensure long filenames do not overlap action buttons.
- Ensure grouped sections scroll without affecting the top safe band.
- Add basic accessibility labels for category headers, file tiles, and `Open` / `Remove` / `Clear` actions.
- Verify VoiceOver can identify the shelf, category groups, file names, and destructive actions.
- Re-check CPU after animations and drag interactions.

**Acceptance Criteria:**

- No text overlap in long filenames.
- No card or button layout jump during selection or removal.
- Drag-active boundary is clearly visible but not visually loud.
- VoiceOver labels are understandable for file tiles and actions.
- With 20 shelf items, scrolling and selection remain responsive.
- Idle CPU remains low after interactions.

**Verification:**

```bash
swift run IslandCoreChecks
swift build --product Island
./script/build_and_run.sh
pid=$(pgrep -x Island | head -n 1)
ps -o pid,stat,pcpu,pmem,etime,command -p "$pid"
```

Manual check:

- Drag in a mix of images, PDFs, tables, and long filenames.
- Select, drag out, cancel drag, remove, clear, and wait for collapse.
- Drag in at least 20 files and confirm scrolling remains usable.
- Run a basic VoiceOver pass on file tiles and action buttons.
- Confirm the Island returns to the default state when shelf is empty.

---

## Recommended Execution Order

1. Phase 1: categories and dashed shelf bounds.
2. Phase 2: selection and rectangle selection.
3. Phase 3a: drag-out remove-on-success.
4. Phase 3b: drag-out cancel zones.
5. Phase 4: metadata and stale file cleanup.
6. Phase 5: visual polish, accessibility, and CPU verification.

Do not start Phase 3a before Phase 2, because drag-out behavior depends on a clear selected-item model.

Do not start Phase 3b before Phase 3a, because cancel zones depend on the drag source/session model.

Do not add persistence across restarts unless the user explicitly changes the product decision.
