# 004 — Add consistent press physicality

- **Status**: DONE
- **Commit**: 41b751d
- **Severity**: MEDIUM
- **Category**: Physicality & origin
- **Estimated scope**: 7 files, about 70 lines

## Problem

The right-side primary feature buttons have pressed-state scale feedback, but
the peer Files button and every other custom `.plain` button do not.

```swift
// Sources/DynamicIsland/Views/IslandOverlayView.swift:628 — current
.buttonStyle(PrimaryFeatureButtonStyle(animationProfile: animationProfile))

// Sources/DynamicIsland/Views/IslandOverlayView.swift:704 — current
.buttonStyle(.plain)
```

Files toolbar, File Shelf, task delete, and Undo controls also use
`.buttonStyle(.plain)` without a replacement pressed state. Press and release
for the one existing custom style use the same 0.12s duration, although the
system response should snap back faster than the deliberate press-in.

Two entry transitions also start from an implausibly small 72% scale:

```swift
// Sources/DynamicIsland/Views/IslandOverlayView.swift:355 — current
.transition(.opacity.combined(with: .scale(scale: 0.72)))

// Sources/DynamicIsland/Views/CodexStatusBarView.swift:75 — current
.transition(.opacity.combined(with: .scale(scale: 0.72, anchor: .topTrailing)))
```

The audit target for appearing UI is scale 0.90–0.97, not near-zero growth.

## Target

Create one internal `IslandPressButtonStyle` in
`Sources/DynamicIsland/Views/IslandPressButtonStyle.swift` and use it for all
custom buttons that currently opt into `.plain`.

```swift
// target
struct IslandPressButtonStyle: ButtonStyle {
    private let animationProfile = IslandAnimationProfile.default

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? animationProfile.primaryFeatureButtonPressScale : 1)
            .animation(
                .easeOut(
                    duration: configuration.isPressed
                        ? animationProfile.primaryFeatureButtonPressDuration
                        : animationProfile.primaryFeatureButtonReleaseDuration
                ),
                value: configuration.isPressed
            )
    }
}
```

Keep press-in at 0.12s and add a faster 0.08s release token. Reuse the existing
0.96 scale, which is inside the accepted 0.95–0.98 range. Replace the music
accessory and task-delete entry scales with `0.94`; preserve the delete
button's correct `.topTrailing` origin.

## Repo conventions to follow

- Motion values come from `IslandAnimationProfile.default`.
- Custom button visuals keep `.plain` chrome semantics; the new style adds only
  pressed-state transform feedback.
- Match existing SwiftUI file organization under `Sources/DynamicIsland/Views`.

## Steps

1. Add failing source checks that custom interactive views no longer contain
   `.buttonStyle(.plain)` and that an `IslandPressButtonStyle` file exists.
2. Add failing numeric/source checks for 0.12s press-in, 0.08s release, and 0.96
   scale.
3. Add failing checks that music accessories and task delete use 0.94 entry
   scale rather than 0.72.
4. Run `swift run DynamicIslandCoreChecks` and confirm expected failures.
5. Extend `IslandAnimationProfile` with
   `primaryFeatureButtonReleaseDuration: 0.08`.
6. Add `IslandPressButtonStyle.swift`; remove the private duplicate style from
   `IslandOverlayView.swift`.
7. Replace `.buttonStyle(.plain)` in `IslandOverlayView.swift`,
   `FilesPrimaryContentView.swift`, `FileShelfOverlayView.swift`,
   `CodexStatusBarView.swift`, and `CodexTasksContentView.swift`.
8. Change the two 0.72 entry transitions to 0.94.

## Boundaries

- Do NOT change button labels, hit targets, enabled states, actions, or layout.
- Do NOT add hover enlargement to toolbar buttons.
- Do NOT change the task shatter particle animation in normal motion mode.
- Do NOT add a dependency or public API.

## Verification

- **Mechanical**: red/green `swift run DynamicIslandCoreChecks`, then
  `swift build --product DynamicIsland`.
- **Feel check**: press and hold every top-level feature control, Files toolbar
  action, File Shelf action, task delete, and Undo. Feedback must start on
  mouse-down, remain subtle, cancel cleanly if the pointer leaves, and return
  faster on release. Music accessories and the delete control should
  materialize from a nearby scale rather than pop from a tiny point.
- **Done when**: no custom `.plain` button lacks pressed feedback, peer primary
  controls feel identical, and all appearing controls stay in the 0.90–0.97
  physical scale range.
