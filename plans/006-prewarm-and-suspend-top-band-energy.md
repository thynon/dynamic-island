# 006 — Prewarm and suspend top-band energy rendering

- **Status**: DONE
- **Commit**: 41b751d
- **Severity**: MEDIUM
- **Category**: Performance
- **Estimated scope**: 3 files, about 100 lines

## Problem

The top-band energy view is mounted only after expansion settles:

```swift
// Sources/DynamicIsland/Views/IslandOverlayView.swift:279 — current
if isExpanded && state.isTopBandEnergyEffectEnabled && isTopBandEnergyActive && !accessibilityReduceMotion {
    TopBandEnergyEffectView()
}
```

Every mount constructs a renderer and synchronously compiles inline Metal source
and a render pipeline on the UI creation path:

```swift
// Sources/DynamicIsland/Views/TopBandEnergyEffectView.swift:162 — current
init?(device: MTLDevice) {
    self.device = device
    guard
        let commandQueue = device.makeCommandQueue(),
        let library = try? device.makeLibrary(source: Self.metalSource, options: nil),
        let vertexFunction = library.makeFunction(name: "energy_vertex"),
        let fragmentFunction = library.makeFunction(name: "energy_fragment")
    else {
        return nil
    }
    // ...
    let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
}
```

The render timer also stops only when the view leaves its window:

```swift
// Sources/DynamicIsland/Views/TopBandEnergyEffectView.swift:43 — current
override func viewDidMoveToWindow() {
    // ...
    if window == nil {
        stopRenderTimer()
    } else {
        startRenderTimer()
    }
}
```

`IslandPanelController.hide()` uses `panel.orderOut(nil)`. Ordering a window off
screen does not detach its content view, so `window` remains non-nil and the
12Hz timer can continue drawing while the panel is invisible.

## Target

Compile immutable Metal resources once per `MTLDevice.registryID`, prewarm that
cache on a utility queue during controller startup, and give each renderer only
its per-instance command queue and animation state. The UI path must never
compile or wait for compilation.

```swift
// target shape
private struct TopBandEnergyPipelineResources {
    let pipelineState: MTLRenderPipelineState
    let vertexBuffer: MTLBuffer
}

private final class TopBandEnergyPipelineCache: @unchecked Sendable {
    static let shared = TopBandEnergyPipelineCache()
    // NSLock protects ready resources and in-flight device IDs.
    func prepareResources(for device: MTLDevice) { ... } // background only
    func readyResources(for device: MTLDevice) -> TopBandEnergyPipelineResources? { ... } // quick lookup only
}

enum TopBandEnergyEffectResources {
    static func prewarm() {
        DispatchQueue.global(qos: .utility).async {
            guard let device = MTLCreateSystemDefaultDevice() else { return }
            TopBandEnergyPipelineCache.shared.prepareResources(for: device)
        }
    }
}
```

Call `TopBandEnergyEffectResources.prewarm()` once from
`IslandPanelController.init`. `TopBandEnergyRenderer.init` must only request
`readyResources(for:)`; it must return immediately when the background prepare
has not completed.

Post a main-queue `didPrepareNotification` after storing ready resources.
`TopBandEnergyEffectNSView` keeps its base gradient, observes that notification,
and attaches the `MTKView`/renderer only when `readyResources(for:)` succeeds.
If `start()` arrived before resources were ready, start the renderer and timer
after attachment. No UI call may acquire a lock held across shader compilation.

Observe the public `NSWindow.didChangeOcclusionStateNotification` for the owning
window. Run the timer only when all are true: the effect has started,
`window?.isVisible == true`, and the Metal view exists. Stop it when the panel
is ordered off or the view detaches; restart it when the panel becomes visible.

## Repo conventions to follow

- Keep the existing 12fps budget and `MTKView` rendering path.
- Keep the effect conditionally mounted and disabled by Reduce Motion.
- `IslandPanelController` already performs startup-only setup in `init`; the
  prewarm call belongs there and must not change product state.
- Tests use source-contract checks in
  `Tests/DynamicIslandCoreChecks/main.swift`.

## Steps

1. Add failing source checks for a device-keyed pipeline cache, startup prewarm,
   and an owning-window occlusion-state observer.
2. Add failing checks that `TopBandEnergyRenderer.init` no longer contains
   `makeLibrary(source:)` or `makeRenderPipelineState`.
3. Run `swift run DynamicIslandCoreChecks` and confirm the new assertions fail.
4. Add the immutable pipeline-resource cache with separate background
   `prepareResources` and non-blocking `readyResources` APIs.
5. Call the prewarm entry once from `IslandPanelController.init`.
6. Refactor the renderer initializer to consume only ready cached resources.
7. Add a main-queue ready notification so an already-mounted gradient-only
   view attaches Metal after background preparation completes.
8. Add window-occlusion observation and a single
   `syncRenderTimerWithWindowVisibility()` gate to the AppKit view.
9. Re-run checks, build, launch, and verify both first reveal and Hide/Show.

## Boundaries

- Do NOT change the shader source, colors, burst timing, or 12fps rate.
- Do NOT keep the effect view mounted while collapsed.
- Do NOT add a dependency or change SwiftPM resources.
- Do NOT change panel Show/Hide semantics.

## Verification

- **Mechanical**: `swift run DynamicIslandCoreChecks`,
  `swift build --product DynamicIsland`, and `git diff --check`.
- **Feel check**: launch fresh, trigger xhigh/max energy, and expand for the
  first time. The shell/content animation must stay responsive when the energy
  tail appears. Collapse/re-expand repeatedly; no later mount may compile a new
  pipeline.
- **Lifecycle check**: while energy is visible, choose “Hide Dynamic Island”,
  wait, then sample the process. The 12Hz draw path must stop; “Show Dynamic
  Island” must restart it only if the effect is still mounted.
- **Done when**: shader/pipeline construction is cached and prewarmed, and no
  render timer runs for an ordered-out panel.
