# 002 — Anchor file drag proxies to the pointer

- **Status**: DONE
- **Commit**: 41b751d
- **Severity**: HIGH
- **Category**: Physicality & origin
- **Estimated scope**: 3 files, about 30 lines

## Problem

Both file-drag implementations measure the real pointer position but place the
dragging image at the center of the source view.

```swift
// Sources/DynamicIsland/Views/FileShelfOverlayView.swift:374 — current
let currentLocation = convert(event.locationInWindow, from: nil)
let distance = hypot(currentLocation.x - mouseDownLocation.x, currentLocation.y - mouseDownLocation.y)
// ...
draggingItem.setDraggingFrame(
    NSRect(
        x: bounds.midX - 16 + offset,
        y: bounds.midY - 16 - offset,
        width: 32,
        height: 32
    ),
    contents: icon
)
```

```swift
// Sources/DynamicIsland/Views/FilesPrimaryContentView.swift:551 — current
let currentLocation = convert(event.locationInWindow, from: nil)
// ...
draggingItem.setDraggingFrame(
    NSRect(
        x: bounds.midX - 14 + offset,
        y: bounds.midY - 14 - offset,
        width: 28,
        height: 28
    ),
    contents: dragIcon
)
```

After the 4pt threshold is crossed, the proxy can visibly jump from the actual
grab point to the tile center. That breaks the direct-manipulation illusion in a
high-frequency File Shelf workflow.

## Target

Center the first drag proxy on the current pointer location at the instant the
dragging session begins. Preserve the existing 3pt stack offset for additional
items.

```swift
// target for the 32pt proxy
let dragImageSize = NSSize(width: 32, height: 32)
let dragImageOrigin = NSPoint(
    x: currentLocation.x - (dragImageSize.width / 2),
    y: currentLocation.y - (dragImageSize.height / 2)
)

let offset = CGFloat(index) * 3
draggingItem.setDraggingFrame(
    NSRect(
        x: dragImageOrigin.x + offset,
        y: dragImageOrigin.y - offset,
        width: dragImageSize.width,
        height: dragImageSize.height
    ),
    contents: icon
)
```

Use the same structure with a 28pt size in `FilesPrimaryContentView.swift`.

## Repo conventions to follow

- Keep the existing AppKit `NSDraggingItem` and `NSDraggingSession` approach.
- Keep the 4pt hysteresis and current multi-selection semantics.
- Keep external-success detection and removal callbacks unchanged.

## Steps

1. Add failing source checks in `Tests/DynamicIslandCoreChecks/main.swift` for
   both drag-source sections: they must not use `bounds.midX`/`bounds.midY` in
   `setDraggingFrame`, and must derive the origin from `currentLocation`.
2. Run `swift run DynamicIslandCoreChecks` and confirm the checks fail on the
   centered frames.
3. In `FileShelfOverlayView.swift`, introduce a named 32pt drag image size and
   pointer-derived origin immediately before creating the dragging items.
4. In `FilesPrimaryContentView.swift`, do the same with the existing 28pt drag
   image.
5. Keep the per-item stack offset and all drag completion logic unchanged.

## Boundaries

- Do NOT change selection behavior, the 4pt drag threshold, allowed operations,
  or whether successful external drags remove items.
- Do NOT replace the file icon with a snapshot of the full tile.
- Do NOT add momentum or animation to the drag proxy.
- Preserve all privacy rules around file paths and names.

## Verification

- **Mechanical**: `swift run DynamicIslandCoreChecks`; then
  `swift build --product DynamicIsland`.
- **Feel check**: run `./script/build_and_run.sh`, add several files, then start
  drags from the top-left, center, and bottom-right of tiles in both Files and
  the independent File Shelf overlay. The proxy must appear under the pointer,
  without jumping to the tile center. Multi-file stacks must retain their 3pt
  diagonal offset.
- **Done when**: both drag sources use `currentLocation`, all existing drag-out
  behaviors remain intact, and off-center grabs have no visible origin jump.
