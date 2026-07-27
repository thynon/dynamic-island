# 005 — Honor reduced motion across the island

- **Status**: DONE
- **Commit**: 41b751d
- **Severity**: MEDIUM
- **Category**: Accessibility
- **Estimated scope**: 6 files, about 130 lines

## Problem

The project has no `accessibilityReduceMotion` or AppKit reduced-motion branch.
Large shell morphs, move/scale transitions, gesture edge expansion, an infinite
waveform, a 12fps energy effect, and task shatter all remain active when macOS
Reduce Motion is enabled.

```swift
// Sources/DynamicIsland/Views/IslandOverlayView.swift:344 — current
.transition(.opacity.combined(with: .move(edge: .bottom)))

// Sources/DynamicIsland/Views/IslandOverlayView.swift:355 — current
.transition(.opacity.combined(with: .scale(scale: 0.72)))

// Sources/DynamicIsland/Views/IslandOverlayView.swift:426 — current
.animation(isExpanded ? expandAnimation : collapseAnimation, value: isExpanded)
```

```swift
// Sources/DynamicIsland/Views/ClosedMusicWaveformView.swift:76 — current
let animation = CABasicAnimation(keyPath: "transform.scale.y")
// ...
animation.autoreverses = true
animation.repeatCount = .infinity
```

```swift
// Sources/DynamicIsland/Views/TopBandEnergyEffectView.swift:119 — current
let timer = Timer(timeInterval: 1.0 / 12.0, target: self, selector: #selector(renderFrame(_:)), userInfo: nil, repeats: true)
```

```swift
// Sources/DynamicIsland/Views/CodexStatusBarView.swift:58 — current
if isShattering {
    TaskShatterEffectView()
}
```

## Target

Add `reducedMotionFadeDuration: 0.20` to `IslandAnimationProfile.default` and
provide a non-vestibular equivalent rather than removing all feedback.

- `IslandOverlayView` reads `@Environment(\.accessibilityReduceMotion)`.
- Reduced motion uses opacity-only transitions for File Shelf, music
  accessories, track info, and task delete; it removes offset/scale entrance
  motion and entrance delays.
- Hover keeps shadow/contrast feedback but scale stays 1.0.
- Hidden state keeps horizontal scale 1.0 and cross-fades opacity.
- Music-skip edge expansion becomes 0 while glyph opacity still communicates
  tracking/armed state.
- Top-band energy effect is not mounted while reduced motion is enabled.
- Controller checks
  `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`; shell
  expand/collapse becomes immediate, while hide/show uses the 0.20s opacity
  fade so the existing pointer-passthrough schedule remains synchronized.
- `ClosedMusicWaveformView` removes `waveform-scale` animations and sets static
  bar transforms derived from the current snapshot; turning Reduce Motion off
  can restart the existing CA animation.
- `CodexStatusBarView` skips particle shatter under reduced motion and uses a
  0.20s row opacity exit before the existing delete callback.
- `IslandPressButtonStyle` from plan 004 uses opacity feedback instead of scale
  when reduced motion is enabled.

The opacity-only transition must have a local animation transaction without
re-enabling shell width/height motion. Keep the root animation and the
controller's track-info transaction disabled under Reduce Motion, then apply a
scoped fade to the conditional content. The modifier itself must exist only in
the Reduce Motion branch; `.animation(nil, value:)` in normal mode would block
the content from inheriting the existing parent/controller transaction:

```swift
// target shape in IslandOverlayView
@ViewBuilder
private func reducedMotionFade<Value: Equatable, Content: View>(
    value: Value,
    @ViewBuilder content: () -> Content
) -> some View {
    if accessibilityReduceMotion {
        content()
            .animation(
                .easeOut(duration: animationProfile.reducedMotionFadeDuration),
                value: value
            )
    } else {
        content()
    }
}

reducedMotionFade(value: showsMusicAccessories) {
    Group { /* artwork + waveform */ }
}

reducedMotionFade(value: showsTrackInfo) {
    Group { /* title + artist */ }
}
```

This local scope is required: animating the root `showsMusicAccessories` or the
controller's `isTrackInfoPresented` transaction under Reduce Motion would also
tween shell width/height, which is the spatial movement being removed.

## Repo conventions to follow

- SwiftUI accessibility state uses the environment; AppKit-only controller
  timing uses `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
- Default behavior remains unchanged when Reduce Motion is off.
- The waveform remains mounted only while music is playing, and the energy
  effect remains conditional on xhigh/max and expansion.
- Keep feedback that aids comprehension: opacity, color, glyph state, and
  selection remain visible.

## Steps

1. Add failing checks for `@Environment(\.accessibilityReduceMotion)`,
   `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, the 0.20s
   profile token, opacity-only transition branches, energy-effect gating, and
   waveform animation removal.
2. Add a failing check that task shatter is not mounted under reduced motion.
3. Run `swift run DynamicIslandCoreChecks` and confirm the new checks fail.
4. Extend `IslandAnimationProfile` with `reducedMotionFadeDuration`.
5. Add reduced-motion computed transitions/geometry branches to
   `IslandOverlayView`, `PrimaryFeatureSwitcher`, and
   `FilesPrimaryFeatureButton`. Use zero entrance delay under reduced motion.
6. Add controller helpers for reduced-motion expand/collapse, hide timing, and
   collapse-canvas delay.
7. Pass the SwiftUI environment value into `ClosedMusicWaveformView`'s AppKit
   update method. Under reduced motion remove infinite animations in a disabled
   `CATransaction` and set static bar transforms.
8. Gate task shatter and delete-button transition in
   `CodexStatusBarView.swift`.
9. Update `IslandPressButtonStyle` so reduced motion substitutes opacity for
   press scale.
10. Add failing checks, then scoped reduced-motion fades for music accessory
    insertion/removal and track-info insertion/removal. Keep the root and
    controller transactions `nil` in Reduce Motion so geometry still changes
    without spatial tweening.
11. Ensure the local fade modifier is conditionally absent in normal mode; do
    not use an optional animation whose `nil` branch suppresses inherited
    normal-mode transitions.

## Boundaries

- Do NOT remove normal-mode springs, shatter, waveform, or energy effects.
- Do NOT change music skip commit/cancel semantics.
- Do NOT change layout contracts or camera-safe coordinates.
- Do NOT persist an accessibility preference; read the live system setting.
- Do NOT treat reduced motion as zero feedback.

## Verification

- **Mechanical**: red/green `swift run DynamicIslandCoreChecks`, then
  `swift build --product DynamicIsland` and `git diff --check`.
- **Feel check**: in System Settings → Accessibility → Display, turn Reduce
  Motion on. Relaunch and confirm shell expansion/collapse does not spring,
  hide/show cross-fades without squeezing, File Shelf/track info/music
  accessories do not move or scale, the skip glyph still communicates progress,
  waveform bars stay static, xhigh energy does not mount, and task deletion
  fades without particles. Turn the setting off and confirm all normal motion
  returns.
- **Performance**: sample CPU in normal idle, playing, and reduced-motion
  playing states; reduced motion must not leave waveform or energy timers active.
- **Done when**: every major motion surface has a live reduced-motion branch,
  comprehension feedback remains, and normal mode is visually unchanged.
