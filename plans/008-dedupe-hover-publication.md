# 008 — Publish hover only on boundary changes

- **Status**: DONE
- **Commit**: 41b751d
- **Severity**: MEDIUM
- **Category**: Performance
- **Estimated scope**: 2 files, about 15 lines

## Problem

The tracking view forwards every mouse-move sample:

```swift
// Sources/DynamicIsland/Views/IslandTrackingHostingView.swift:42 — current
override func mouseMoved(with event: NSEvent) {
    onMouseMoved?()
}
```

Every sample rebuilds the precise shell path and assigns the same published
hover value again:

```swift
// Sources/DynamicIsland/Controllers/IslandPanelController.swift:1336 — current
private func syncHoverWithPointer() {
    let pointerInsideIsland = pointerInsideInteractiveShell()
    overlayState.isHovered = pointerInsideIsland && !overlayState.isShellHidden
    // ...
}
```

`@Published` emits on assignment even when the Boolean did not change, so the
entire observed SwiftUI root is invalidated throughout ordinary pointer motion.

## Target

Keep the precise hit test and pass-through synchronization on every necessary
sample, but assign `isHovered` only when the boundary state changes.

```swift
// target
let pointerInsideIsland = pointerInsideInteractiveShell()
let shouldHover = pointerInsideIsland && !overlayState.isShellHidden
if overlayState.isHovered != shouldHover {
    overlayState.isHovered = shouldHover
}

guard !overlayState.isShellHidden else { return }
collapseExpandedShellIfPointerLeavesInteractiveShell(pointerInsideIsland)
syncMouseEventPassthroughWithPointer(isPointerInside: pointerInsideIsland)
```

## Repo conventions to follow

- `pointerInsideInteractiveShell()` remains the hit-test source of truth.
- Hidden state still outranks hover/click/skip.
- Do not remove the global pointer monitor or transparent-area pass-through.

## Steps

1. Add a failing source-section check for a named `shouldHover` value and an
   equality guard around the published assignment.
2. Run `swift run DynamicIslandCoreChecks` and confirm it fails.
3. Add the guard without changing collapse or pass-through ordering.
4. Re-run checks, build, launch, and replay hover/click.

## Boundaries

- Do NOT debounce or throttle mouse movement.
- Do NOT widen/narrow the interactive shell path.
- Do NOT change hover scale, shadow, timing, or click behavior.

## Verification

- **Mechanical**: `swift run DynamicIslandCoreChecks` and
  `swift build --product DynamicIsland`.
- **Interaction check**: move into the visible right safe slot, move around
  within it, click to expand, and move out. Logs must still show entered,
  expanded, and exited; the visual hover must remain visible.
- **Performance check**: move the pointer continuously over the island and
  confirm CPU settles immediately when movement stops, with no interaction lag.
- **Done when**: mouse moves inside one hover state do not republish the same
  value, while boundary crossing remains exact.
