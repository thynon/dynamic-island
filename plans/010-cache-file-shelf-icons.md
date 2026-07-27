# 010 — Cache File Shelf icons outside the drag hot path

- **Status**: DONE
- **Commit**: 41b751d
- **Severity**: MEDIUM
- **Category**: Performance
- **Estimated scope**: 2 files, about 35 lines

## Problem

Rectangle selection updates local `@State` for every pointer sample:

```swift
// Sources/DynamicIsland/Views/FileShelfOverlayView.swift:210 — current
.onChanged { value in
    // ...
    selectionCurrentPoint = value.location
}
```

That recomputes the same view body and every visible tile synchronously asks
Launch Services for its file icon again:

```swift
// Sources/DynamicIsland/Views/FileShelfOverlayView.swift:253 — current
Image(nsImage: NSWorkspace.shared.icon(forFile: item.fileURL.path))
```

File icon lookup is main-thread AppKit work inside a gesture that must remain
1:1 with the pointer.

## Target

Preserve an internal reference cache for the lifetime of the SwiftUI view and
make tile rendering read through it:

```swift
// target shape
@State private var iconCache = TemporaryFileIconCache()

Image(nsImage: iconCache.icon(for: item))

@MainActor
private final class TemporaryFileIconCache {
    private var imagesByItemID: [TemporaryShelfItem.ID: NSImage] = [:]

    func icon(for item: TemporaryShelfItem) -> NSImage {
        if let image = imagesByItemID[item.id] { return image }
        let image = NSWorkspace.shared.icon(forFile: item.fileURL.path)
        imagesByItemID[item.id] = image
        return image
    }
}
```

The cache mutates internally without publishing SwiftUI state, so rectangle
movement can redraw the overlay without repeating Launch Services work.

## Repo conventions to follow

- Keep AppKit icon loading in the app target, never `DynamicIslandCore`.
- Keep the current file tile, drag source, selection model, and privacy rules.
- The shelf is temporary and small; a view-lifetime dictionary is sufficient.

## Steps

1. Add failing source checks that `fileTile` reads `iconCache.icon(for: item)`
   and does not call `NSWorkspace.shared.icon` directly.
2. Add a failing check for a view-lifetime `TemporaryFileIconCache` state value.
3. Run `swift run DynamicIslandCoreChecks` and confirm failure.
4. Add the small MainActor cache and route tile rendering through it.
5. Re-run checks and build.

## Boundaries

- Do NOT load icons asynchronously or add placeholders in this plan.
- Do NOT cache file names, paths, or file contents in logs/persistence.
- Do NOT change tile identity, layout, selection, or drag behavior.

## Verification

- **Mechanical**: `swift run DynamicIslandCoreChecks` and
  `swift build --product DynamicIsland`.
- **Feel check**: stage several mixed file types and drag a selection rectangle
  slowly and quickly. The rectangle and selection highlights must track without
  hitching; icons must remain correct.
- **Done when**: each visible item resolves its AppKit icon once per view
  lifetime rather than once per pointer sample.
