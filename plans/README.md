# Animation improvement plans

Audit target: working tree at commit `41b751d` on 2026-07-13. The working tree
already contained user changes in `MEMORY.md`, `IslandPanelController.swift`,
`IslandOverlayView.swift`, and `DynamicIslandCoreChecks/main.swift`; all plans
must preserve them.

## Vetted findings

| # | Severity | Category | Location | Finding | Fix summary |
| --- | --- | --- | --- | --- | --- |
| 1 | HIGH | Interruptibility | `IslandPanelController.swift:1068`, `IslandOverlayView.swift:430` | Every trackpad progress sample is spring-animated twice, so feedback cannot track 1:1. | Direct live progress; animate only arm/settle states. |
| 2 | HIGH | Physicality | `FileShelfOverlayView.swift:392`, `FilesPrimaryContentView.swift:569` | Drag proxies originate from the tile center instead of the actual pointer. | Build dragging frames from `currentLocation`. |
| 3 | HIGH | Easing | `IslandPanelController.swift:1181` | Committed skip feedback exits with `easeIn`. | Use immediate-start `easeOut`. |
| 4 | MEDIUM | Cohesion | `IslandPanelController.swift:289`, `IslandOverlayView.swift:432` | Runtime-scaled hide timing and fixed visual timing disagree. | One controller-owned profile duration. |
| 5 | MEDIUM | Purpose | `IslandAnimationProfile.swift:68` | Frequent feature selection uses an under-damped 0.75 spring. | Critically damp it at 1.0. |
| 6 | MEDIUM | Easing | `IslandOverlayView.swift:348`, `IslandPanelController.swift:1712` | Music accessory entry uses `easeInOut`; track info uses `linear`. | Use `easeOut` entry/exit tokens. |
| 7 | MEDIUM | Accessibility | `IslandOverlayView.swift`, `ClosedMusicWaveformView.swift`, `CodexStatusBarView.swift` | No Reduce Motion path exists for spatial, looping, or particle motion. | Add live system-policy branches with opacity/static equivalents. |
| 8 | MEDIUM | Physicality | Custom `.plain` buttons across Files/File Shelf/Tasks | Pressable controls lack pointer-down feedback; Files disagrees with peer primary controls. | Shared asymmetric press style. |
| 9 | LOW | Physicality | `IslandOverlayView.swift:355`, `CodexStatusBarView.swift:75` | Entry scale 0.72 is too close to appearing from nothing. | Raise entry scale to 0.94. |
| 10 | MEDIUM | Performance | `TopBandEnergyEffectView.swift:162` | Conditional mount synchronously compiles inline Metal source and a pipeline. | Reassess after first pass with mount-time evidence; cache if confirmed. |
| 11 | MEDIUM | Accessibility | `CodexStatusBarView.swift:22`, `IslandOverlayView.swift:162` | Hover-only delete and scroll-only skip lack semantic alternate actions. | Reassess after motion fixes; add scoped accessibility actions if still absent. |

## Second audit — 2026-07-13

The second `improve-animations` pass confirmed no remaining HIGH findings.
Plans 001–004 are implemented. Plan 005 is partially implemented: spatial and
continuous motion is removed under Reduce Motion, but two promised local fades
still have no animation transaction.

| # | Severity | Category | Location | Finding | Plan |
| --- | --- | --- | --- | --- | --- |
| 12 | MEDIUM | Performance | `TopBandEnergyEffectView.swift:162` | Conditional mounts still compile inline Metal source and a render pipeline on the UI creation path. | 006 |
| 13 | MEDIUM | Performance | `TopBandEnergyEffectView.swift:43`, `IslandPanelController.swift:195` | `orderOut` leaves the effect attached to its window, so the 12Hz timer can continue while the panel is hidden. | 006 |
| 14 | MEDIUM | Performance | `FileShelfOverlayView.swift:210`, `IslandPanelController.swift:551` | Every rectangle-drag sample republishes selection and synchronously writes JSONL even when the selected set is unchanged. | 007 |
| 15 | MEDIUM | Performance | `IslandPanelController.swift:1336` | Every mouse-move sample republishes the same `@Published isHovered` value. | 008 |
| 16 | MEDIUM | Interruptibility | `IslandOverlayView.swift:448`, `IslandPanelController.swift:1095` | Skip rollback/dismiss has both a controller transaction and a view-level direction tween. | 009 |
| 17 | MEDIUM | Accessibility | `IslandOverlayView.swift:262`, `IslandOverlayView.swift:447` | Music accessories declare an opacity-only reduced-motion transition but disable the transaction, so they snap. | 005 |
| 18 | MEDIUM | Accessibility | `IslandOverlayView.swift:266`, `IslandPanelController.swift:1718` | Track info likewise snaps under Reduce Motion because its transition receives a nil transaction. | 005 |

## Third audit — 2026-07-13

The next pass closed findings 12–18 but found three implementation-level
follow-ups. There are still no HIGH findings.

| # | Severity | Category | Location | Finding | Plan |
| --- | --- | --- | --- | --- | --- |
| 19 | MEDIUM | Cohesion | `IslandOverlayView.swift:270`, `IslandOverlayView.swift:410` | A local `.animation(nil, value:)` in normal mode suppresses inherited accessory/track-info transitions. | 005 |
| 20 | MEDIUM | Performance | `TopBandEnergyEffectView.swift:186`, `TopBandEnergyEffectView.swift:253` | Renderer lookup can wait on the cache lock while background shader compilation holds it. | 006 |
| 21 | MEDIUM | Performance | `FileShelfOverlayView.swift:210`, `FileShelfOverlayView.swift:253` | Rectangle-drag body updates repeat synchronous `NSWorkspace.icon(forFile:)` work for every visible tile. | 010 |

Finding 11 is outside this motion-only execution pass: it concerns alternate
semantic commands rather than animation behavior and would broaden controller
APIs. It remains a documented accessibility follow-up, not a motion blocker.

## Fourth audit — 2026-07-14

The resumed `improve-animations` pass found no HIGH findings. It confirmed four
MEDIUM issues relevant to the user's reported interaction loss and the new
expanded-content motion request:

| # | Severity | Category | Location | Finding | Plan |
| --- | --- | --- | --- | --- | --- |
| 22 | MEDIUM | Interruptibility | `IslandOverlayView.swift:303`, `IslandPanelController.swift:660` | Direct primary-feature binding bypasses Files cleanup, so pinned state can survive a Files→Tasks switch and block mouse-exit collapse. | 011 |
| 23 | MEDIUM | Physicality | `IslandOverlayView.swift:326`, `IslandOverlayView.swift:506` | Tasks/Files content has a pure fade at the same start time as navigation and has no spatial origin. | 012 |
| 24 | MEDIUM | Performance | `TopBandEnergyEffectView.swift:157` | The 12Hz renderer checks ordered visibility but not occlusion state. | 013 |
| 25 | MEDIUM | Performance | `IslandTrackingHostingView.swift:58`, `FilesPrimaryContentView.swift:455` | Pointer-frequency drag updates repeatedly decode and match pasteboard URLs. | 014 |

The prior hover publication, precise-shell hit testing, 1:1 music gesture,
reduced-motion, icon-cache, and non-blocking Metal pipeline fixes remain intact.

Implementation review then tightened the transition lifecycle: Tasks and Files
remain available to the same transition transaction, outgoing content loses all
input ownership immediately, Reduce Motion gets a visible `0.20s` fade before
the canvas snaps closed, and reopening during an active exit reverses from the
current presentation state.

## Fifth audit — 2026-07-14

The final `improve-animations` pass found no HIGH issues and closed five MEDIUM
runtime/accessibility follow-ups before a clean three-domain re-audit:

| # | Severity | Category | Finding | Resolution |
| --- | --- | --- | --- | --- |
| 26 | MEDIUM | Accessibility | Collapsed top controls could retain keyboard or accessibility ownership. | Disable them and remove them from the accessibility tree while collapsed. |
| 27 | MEDIUM | Accessibility | Reduce Motion still tweened hover shadow radius and vertical offset. | Keep shadow geometry fixed and animate opacity only. |
| 28 | MEDIUM | Performance | The hidden Files AppKit drop target stayed registered. | Explicit active-state registration and callback guards. |
| 29 | MEDIUM | Performance | Persistent hidden Files content repeated native icon lookups. | Add a view-lifetime Files icon cache. |
| 30 | MEDIUM | Performance | Multi-file File Shelf drag start looked up one icon per selected item. | Reuse one representative drag icon for the session. |

The post-fix motion, runtime, and integration reviews all reported no remaining
HIGH or MEDIUM findings.

## User-directed timing refinement — 2026-07-14

Runtime review found the separately delayed Files icon and the `30ms`
right-navigation cascade visually inconsistent. Files plus
Tasks/Data/Tools/Settings now retain the settled-shell `0.34s` start point but
share one `0.18s` linear entrance with no per-control stagger. Primary content,
selection, press, collapse, and Reduce Motion timing remain unchanged. A
25-frame capture confirmed all five controls begin and settle together before
primary content enters.

A subsequent screen-space review measured up to `4.5px` of horizontal drift
while the shell spring was still settling, which made the shared vertical
entrance read diagonally. The five controls now keep their existing top-band
frames in one stable open-canvas layer and use the animated shell width only as
a clip mask. A final 25-frame capture measured `0px` X travel with the expected
top-to-bottom Y sequence and preserved Files/Tasks interaction.

## Selected plans

| Plan | Title | Severity | Status | Dependencies |
| --- | --- | --- | --- | --- |
| 001 | Make music-skip tracking direct | HIGH | DONE | None |
| 002 | Anchor file drag proxies to the pointer | HIGH | DONE | None |
| 003 | Correct motion curves and timing contracts | HIGH | DONE | 001 |
| 004 | Add consistent press physicality | MEDIUM | DONE | 003 |
| 005 | Honor reduced motion across the island | MEDIUM | DONE | 003, 004 |
| 006 | Prewarm and suspend top-band energy rendering | MEDIUM | DONE | None |
| 007 | Publish rectangle selection only when it changes | MEDIUM | DONE | None |
| 008 | Publish hover only on boundary changes | MEDIUM | DONE | None |
| 009 | Give music-skip settling one animation owner | MEDIUM | DONE | 001, 003 |
| 010 | Cache File Shelf icons outside the drag hot path | MEDIUM | DONE | 007 |
| 011 | Restore primary-feature interaction ownership | MEDIUM | DONE | None |
| 012 | Animate expanded primary content from its source | MEDIUM | DONE | 011 |
| 013 | Suspend occluded top-band energy rendering | MEDIUM | DONE | 006 |
| 014 | Cache drag-session validation | MEDIUM | DONE | None |

All selected plans are implemented. The source-level final audit is clean, and
the full build, main-app launch, 25-frame entrance capture, Files/Tasks
interaction check, and settled CPU sampling are complete.

## Missed opportunities

- `ClosedMusicAvatarView.swift`: artwork swaps while playback remains active are
  abrupt; a short keyed cross-fade may help, but it is additive and not selected.
- `CodexTasksContentView.swift`: polling can change row count, row height, and
  spacing in one frame; a restrained collection transition may reduce jumps.
- `FilesPrimaryContentView.swift`: file insertion/removal reflows the grid
  instantly; animate only if real use shows the jump is distracting.

These additive items are intentionally deferred. The product is a compact,
frequently used utility; motion must explain state or interaction, not decorate
routine updates.
