# 011 — Restore primary-feature interaction ownership

- **Status**: DONE
- **Commit**: 41b751d
- **Severity**: MEDIUM
- **Category**: Interruptibility
- **Estimated scope**: 3 files, about 45 lines

## Problem

The right-side primary switcher writes the observed state directly:

```swift
// Sources/DynamicIsland/Views/IslandOverlayView.swift:303 — current
PrimaryFeatureSwitcher(
    selection: $state.selectedPrimaryFeature,
    isExpanded: isExpanded,
    animationProfile: animationProfile
)
```

When Files is in `.pinned` mode, switching directly to Tasks/Data/Tools/Settings
bypasses `closeFilesPrimaryFeature()`. `isFileShelfPinnedOpen` can remain true,
so `shouldCollapseOnMouseExit()` refuses to collapse a non-Files surface.

Tasks also has `zIndex(21)` while Files has `zIndex(2)`. During a crossfade the
outgoing Tasks container can remain above the incoming Files container and
intercept input.

## Target

- Route primary selection through an `IslandOverlayView` callback owned by
  `IslandPanelController`.
- Leaving Files clears its overlay, pin, and drop-target state before selecting
  the requested feature.
- Only the currently selected primary container accepts input during a
  transition, and the selected container has the higher z-index.

```swift
private var primaryFeatureSelection: Binding<IslandPrimaryFeature> {
    Binding(
        get: { state.selectedPrimaryFeature },
        set: { onPrimaryFeatureChange($0) }
    )
}

private func selectPrimaryFeature(_ feature: IslandPrimaryFeature) {
    guard feature != .files else {
        openFilesPrimaryFeature()
        return
    }
    guard overlayState.selectedPrimaryFeature != feature else { return }
    if overlayState.selectedPrimaryFeature == .files {
        closeFilesPrimaryFeature()
    }
    lastNonFilesPrimaryFeature = feature
    overlayState.selectedPrimaryFeature = feature
}
```

## Repo conventions to follow

- Controller methods own state transitions that affect more than one
  `IslandOverlayState` property.
- Preserve `closeFilesPrimaryFeature()` as the single cleanup path.
- Source-contract regression checks live in
  `Tests/DynamicIslandCoreChecks/main.swift`.

## Steps

1. Add failing checks that direct `$state.selectedPrimaryFeature` binding is
   gone, selection routes through the controller, Files cleanup is called, and
   outgoing content cannot hit-test above incoming content.
2. Run `swift run DynamicIslandCoreChecks`; expect those new checks to fail.
3. Add `onPrimaryFeatureChange` and the custom Binding in
   `IslandOverlayView.swift`; wire it in `IslandPanelController.swift`.
4. Add selected-state hit-testing and z-index modifiers to Tasks and Files
   containers.
5. Re-run `swift run DynamicIslandCoreChecks`; expect all checks to pass.

## Boundaries

- Do not change Files display-mode semantics.
- Do not change feature labels, layout frames, or content implementations.
- Do not add a second Files cleanup path.

## Verification

- **Mechanical**: `swift run DynamicIslandCoreChecks` exits 0.
- **Feel check**: open Files in pinned mode, click Tasks, move outside the shell;
  it collapses. Rapidly switch Tasks↔Files; the newly selected content receives
  input immediately.
- **Done when**: the controller owns every primary-feature state change and no
  outgoing container can intercept the selected container.
