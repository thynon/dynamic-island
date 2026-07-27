# 007 — Publish rectangle selection only when it changes

- **Status**: DONE
- **Commit**: 41b751d
- **Severity**: MEDIUM
- **Category**: Performance
- **Estimated scope**: 2 files, about 20 lines

## Problem

The File Shelf rectangle gesture calls `onSelectItems` for every drag sample
after crossing the threshold:

```swift
// Sources/DynamicIsland/Views/FileShelfOverlayView.swift:225 — current
let selectedIDs = visibleItems.compactMap { item -> TemporaryShelfItem.ID? in
    guard let frame = tileFrames[item.id], frame.intersects(selectionRect) else { return nil }
    return item.id
}
onSelectItems(selectedIDs, NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift))
```

The controller republishes state and synchronously serializes/writes a JSONL
record even when the selected set is identical to the prior sample:

```swift
// Sources/DynamicIsland/Controllers/IslandPanelController.swift:551 — current
private func selectTemporaryFiles(ids: [TemporaryShelfItem.ID], extendingSelection: Bool) {
    let itemIDs = Set(ids)
    if extendingSelection {
        temporaryFileShelfSelection.select(temporaryFileShelfSelection.selectedItemIDs.union(itemIDs))
    } else {
        temporaryFileShelfSelection.select(itemIDs)
    }
    syncTemporaryFileShelfSelectionState()
    interactionLogger.log("file.shelf.select", metadata: [ ... ])
}
```

This disk I/O is on the MainActor and competes with 1:1 selection feedback.

## Target

Compute the next selected set first and return immediately when it equals the
current set. Publish and log only real selection transitions.

```swift
// target
let itemIDs = Set(ids)
let currentSelectedItemIDs = temporaryFileShelfSelection.selectedItemIDs
let nextSelectedItemIDs = extendingSelection
    ? currentSelectedItemIDs.union(itemIDs)
    : itemIDs
guard nextSelectedItemIDs != currentSelectedItemIDs else { return }

temporaryFileShelfSelection.select(nextSelectedItemIDs)
syncTemporaryFileShelfSelectionState()
interactionLogger.log("file.shelf.select", metadata: [ ... ])
```

## Repo conventions to follow

- Keep selection truth in `TemporaryFileShelfSelection`.
- Keep the existing privacy-safe event and metadata fields.
- Source-contract tests belong in `DynamicIslandCoreChecks`.

## Steps

1. Add a failing source-section check that rectangle selection computes
   `nextSelectedItemIDs` and guards equality before state sync or logging.
2. Run `swift run DynamicIslandCoreChecks` and confirm the check fails.
3. Add the equality guard in `selectTemporaryFiles` only.
4. Re-run the checks and build.

## Boundaries

- Do NOT throttle pointer events or add timers.
- Do NOT change rectangle geometry, the 5pt threshold, modifier-key semantics,
  or selection visuals.
- Do NOT make logging asynchronous in this plan.

## Verification

- **Mechanical**: `swift run DynamicIslandCoreChecks` and
  `swift build --product DynamicIsland`.
- **Feel check**: drag a rectangle slowly inside the same set of tiles, then
  cross tile boundaries and drag back. The rectangle must remain 1:1; selection
  must update exactly when the intersected set changes.
- **Log check**: the session JSONL should contain selection events for set
  changes, not one record per pointer sample.
- **Done when**: identical rectangle-selection samples cause no published state
  change and no disk write.
