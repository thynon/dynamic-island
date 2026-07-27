# Data 时间范围 Liquid Glass 浮层修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Data 时间范围控件改成“触发胶囊常驻、菜单从下方独立浮出”的单层 Liquid Glass 菜单，并消除首次启动、首次进入 Data、首次展开时的整块白闪。

**Architecture:** `IslandOverlayView` 继续拥有抽屉状态和统一动画事务；`DataPrimaryContentView` 只重组控件树，让时间胶囊和刷新按钮稳定挂载，把菜单作为条件 overlay 加入同一个 `GlassEffectContainer`。macOS 26 菜单使用独立 identity 和 `materialize`，macOS 14/15 与 Reduce Transparency 使用现有 fallback；不预热、不新增窗口或状态。

**Tech Stack:** Swift 6、SwiftUI、AppKit、macOS 14+、macOS 26 Liquid Glass、SwiftPM、现有 `DynamicIslandCoreChecks` 源码合同测试。

**Design:** [`docs/superpowers/specs/2026-07-27-data-time-range-liquid-glass-design.md`](../specs/2026-07-27-data-time-range-liquid-glass-design.md)

## Global Constraints

- 保持 SwiftPM、macOS 14+、Swift 6 和 AppKit + SwiftUI，不增加生产依赖或 framework。
- 原生 Liquid Glass 只在 `#if compiler(>=6.2)`、macOS 26+ 且 Reduce Transparency 关闭时使用。
- 时间胶囊、菜单和刷新按钮使用同一个 `GlassEffectContainer`，菜单只有一块 glass surface。
- 原生菜单容器和选项行不能添加显式 `Color`、Material、第二层 glass 或常驻白色行底；文字和图标前景色除外。
- 正常模式使用 `IslandAnimationProfile.default` 的现有 Data 抽屉参数；Reduce Motion 使用 parent-owned 淡入事务，不在视图中硬编码动画时间。
- 保持 Data 页面懒挂载、访问后保留、完整收起后释放，不增加隐藏预热、延迟任务、计时器或持续动画。
- 保持 Data 24、岛内关闭层 23、File Shelf 22 的层级，以及选择、刷新、Escape、切页、收起、隐藏关闭语义。
- 不改变顶部 32pt 状态带、camera housing 禁区、统计口径、刷新策略、权限或全局输入监听。
- 工作树已有 `MEMORY.md`、`CodexStatusBarView.swift`、`IslandOverlayView.swift` 和 `Tests/DynamicIslandCoreChecks/main.swift` 的未提交 hover 修复；不得 reset、checkout、覆盖或整文件暂存这些改动。

## File Map

- Modify: `Sources/DynamicIsland/Views/DataPrimaryContentView.swift`
  - 稳定挂载控制行、添加独立菜单 overlay、切换 glass transition、移除选中行白底。
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`
  - 把旧“matched morph”合同替换为独立浮层、materialize、无背景和 fallback 对称合同。
- Modify: `MEMORY.md`
  - 在验证成功后记录新视觉合同、验证结果和回退边界。
- No new production files.

---

### Task 1: 用失败检查锁定独立玻璃浮层并实现最小结构修复

**Files:**

- Modify: `Tests/DynamicIslandCoreChecks/main.swift:2379-2530`
- Modify: `Sources/DynamicIsland/Views/DataPrimaryContentView.swift:16-65`
- Modify: `Sources/DynamicIsland/Views/DataPrimaryContentView.swift:279-452`

**Interfaces:**

- Consumes:
  - `isTimeRangeDrawerPresented: Bool`
  - `onTimeRangeDrawerPresentationChange: @MainActor (Bool) -> Void`
  - `DataGlassEffectID.trigger`, `.drawer`, `.refresh`
  - `IslandPressButtonStyle`
  - parent-owned `setDataTimeRangeDrawerPresented(_:)` animation transaction
- Produces:
  - Stable time trigger and refresh controls that remain mounted while the menu is open.
  - A conditionally mounted drawer aligned below the trigger with no public API changes.
  - Native transition contract `accessibilityReduceMotion ? .identity : .materialize`.

- [ ] **Step 1: Add focused source slices and replace the old morph assertions**

In `testDataPrimaryContentViewContracts()`, add these slices beside the existing
`triggerSection` and `drawerContentSection`:

```swift
let nativeControlsSection = sourceSlice(
    dataView,
    from: "private var nativeLiquidGlassControls: some View",
    until: "    #endif"
)
let fallbackControlsSection = sourceSlice(
    dataView,
    from: "private var fallbackControls: some View",
    until: "    @ViewBuilder\n    private func fallbackBackground"
)
let optionSection = sourceSlice(
    dataView,
    from: "private func timeRangeOption",
    until: "    @MainActor\n    private func selectTimeRange"
)
```

Replace the old `.matchedGeometry` expectation and extend the glass assertions
with the following exact contracts:

```swift
expectEqual(dataView.contains("private let controlSpacing: CGFloat = 6"), true, "Data centralizes control spacing")
expectEqual(dataView.contains("private let drawerGap: CGFloat = 5"), true, "Data keeps the approved 5pt trigger-to-menu gap")
expectEqual(
    markersAppearInOrder(
        [
            "timeRangeTrigger",
            ".glassEffect(.regular.interactive(), in: Capsule",
            "if isTimeRangeDrawerPresented {",
            "timeRangeDrawerContent"
        ],
        in: nativeControlsSection
    ),
    true,
    "native trigger remains mounted before the conditional drawer"
)
expectEqual(
    nativeControlsSection.contains(
        ".glassEffectTransition(accessibilityReduceMotion ? .identity : .materialize)"
    ),
    true,
    "native drawer materializes independently and Reduce Motion disables the glass transition"
)
expectEqual(
    nativeControlsSection.contains(
        ".transition(accessibilityReduceMotion ? .opacity : .identity)"
    ),
    true,
    "Reduce Motion keeps only the parent-owned opacity transition"
)
expectEqual(nativeControlsSection.contains(".matchedGeometry"), false, "Data no longer morphs the trigger into the drawer")
expectEqual(nativeControlsSection.contains("matchedGeometryEffect"), false, "Data does not use traditional matched geometry")
expectEqual(nativeControlsSection.contains(".overlay(alignment: .topTrailing)"), true, "native drawer is a layout-neutral overlay")
expectEqual(nativeControlsSection.components(separatedBy: ".glassEffect(").count - 1, 3, "native controls own exactly trigger, refresh, and one drawer glass surface")
expectEqual(nativeControlsSection.contains(".background"), false, "native controls do not place a background beneath Liquid Glass")
expectEqual(nativeControlsSection.contains(".fill("), false, "native controls do not place a fill beneath Liquid Glass")
expectEqual(nativeControlsSection.contains(".thinMaterial"), false, "native controls do not stack fallback Material")
expectEqual(
    markersAppearInOrder(
        [
            ".offset(",
            "x: -(controlHeight + controlSpacing)",
            "y: controlHeight + drawerGap"
        ],
        in: nativeControlsSection
    ),
    true,
    "native drawer aligns below the trigger rather than replacing it"
)
expectEqual(
    markersAppearInOrder(
        ["timeRangeTrigger", "if isTimeRangeDrawerPresented {", "timeRangeDrawerContent"],
        in: fallbackControlsSection
    ),
    true,
    "fallback trigger also remains mounted before the conditional drawer"
)
expectEqual(fallbackControlsSection.contains(".overlay(alignment: .topTrailing)"), true, "fallback drawer is also a layout-neutral overlay")
expectEqual(
    markersAppearInOrder(
        [
            ".offset(",
            "x: -(controlHeight + controlSpacing)",
            "y: controlHeight + drawerGap"
        ],
        in: fallbackControlsSection
    ),
    true,
    "fallback drawer shares the approved independent alignment"
)
expectEqual(optionSection.contains("Color.white.opacity"), false, "selected range has no persistent white row background")
expectEqual(drawerContentSection.contains("glassEffect"), false, "drawer option rows do not stack a second glass layer")
```

Keep the existing availability, three unique IDs, `.thinMaterial` fallback,
accessibility, animation ownership, z-index and close-semantics assertions.

- [ ] **Step 2: Run the new contracts and confirm the expected failure**

Run:

```bash
swift run DynamicIslandCoreChecks
```

Expected: the new Data checks fail because the current implementation still
conditionally replaces the trigger, uses `.matchedGeometry`, lacks the 5pt
independent offset, and gives the selected row a white background. Existing
unrelated checks must not newly fail.

- [ ] **Step 3: Add the two layout constants**

In `DataPrimaryContentView`, place these beside the existing dimensions:

```swift
private let drawerWidth: CGFloat = 104
private let triggerWidth: CGFloat = 72
private let controlHeight: CGFloat = 24
private let controlSpacing: CGFloat = 6
private let drawerGap: CGFloat = 5
```

- [ ] **Step 4: Replace the native conditional replacement with stable controls plus a materializing overlay**

Replace `nativeLiquidGlassControls` with:

```swift
#if compiler(>=6.2)
@available(macOS 26.0, *)
private var nativeLiquidGlassControls: some View {
    GlassEffectContainer(spacing: 0) {
        HStack(alignment: .top, spacing: controlSpacing) {
            timeRangeTrigger
                .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
                .glassEffectID(DataGlassEffectID.trigger, in: glassNamespace)

            refreshButton
                .glassEffect(.regular.interactive(), in: Circle())
                .glassEffectID(DataGlassEffectID.refresh, in: glassNamespace)
        }
        .overlay(alignment: .topTrailing) {
            if isTimeRangeDrawerPresented {
                timeRangeDrawerContent
                    .padding(4)
                    .frame(width: drawerWidth)
                    .glassEffect(.regular.interactive(), in: drawerShape)
                    .glassEffectID(DataGlassEffectID.drawer, in: glassNamespace)
                    .glassEffectTransition(accessibilityReduceMotion ? .identity : .materialize)
                    .transition(accessibilityReduceMotion ? .opacity : .identity)
                    .offset(
                        x: -(controlHeight + controlSpacing),
                        y: controlHeight + drawerGap
                    )
            }
        }
    }
}
#endif
```

Do not add an explicit stroke, shadow, fill, `.background`, prewarm state or
child-owned `withAnimation` to this native path.

- [ ] **Step 5: Make the fallback use the same stable geometry**

Replace `fallbackControls` with:

```swift
private var fallbackControls: some View {
    HStack(alignment: .top, spacing: controlSpacing) {
        timeRangeTrigger
            .background {
                fallbackBackground(Capsule(style: .continuous))
            }
            .overlay(
                Capsule(style: .continuous)
                    .stroke(fallbackStrokeColor, lineWidth: colorSchemeContrast == .increased ? 1 : 0.7)
            )
            .shadow(color: .black.opacity(0.24), radius: 4, y: 2)

        refreshButton
            .background {
                fallbackBackground(Circle())
            }
            .overlay(
                Circle()
                    .stroke(fallbackStrokeColor, lineWidth: colorSchemeContrast == .increased ? 1 : 0.7)
            )
            .shadow(color: .black.opacity(0.24), radius: 4, y: 2)
    }
    .overlay(alignment: .topTrailing) {
        if isTimeRangeDrawerPresented {
            timeRangeDrawerContent
                .padding(4)
                .frame(width: drawerWidth)
                .background {
                    fallbackBackground(drawerShape)
                }
                .overlay(
                    drawerShape
                        .stroke(fallbackStrokeColor, lineWidth: colorSchemeContrast == .increased ? 1 : 0.7)
                )
                .shadow(color: .black.opacity(0.32), radius: 8, y: 4)
                .transition(drawerTransition)
                .offset(
                    x: -(controlHeight + controlSpacing),
                    y: controlHeight + drawerGap
                )
        }
    }
}
```

This retains the existing `.thinMaterial` and Reduce Transparency behavior in
`fallbackBackground(_:)`, while preventing the fallback trigger from
disappearing when the menu opens.

- [ ] **Step 6: Remove the persistent selected-row fill**

In `timeRangeOption(_:)`, keep the checkmark, blue foreground, padding, height
and `contentShape`, but remove this modifier:

```swift
.background(
    Color.white.opacity(range == selectedTimeRange ? 0.09 : 0),
    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
)
```

The end of the label must remain:

```swift
.padding(.horizontal, 5)
.frame(height: controlHeight)
.contentShape(Rectangle())
```

- [ ] **Step 7: Run the focused regression suite**

Run:

```bash
swift run DynamicIslandCoreChecks
```

Expected: `DynamicIslandCoreChecks passed`.

- [ ] **Step 8: Compile the executable target**

Run:

```bash
swift build --product DynamicIsland
```

Expected: build completes with exit code 0 and no Swift availability or opaque
return-type error in `DataPrimaryContentView`.

- [ ] **Step 9: Inspect the scoped patch and leave a safe checkpoint**

Run:

```bash
git diff --check -- Sources/DynamicIsland/Views/DataPrimaryContentView.swift Tests/DynamicIslandCoreChecks/main.swift
git diff -- Sources/DynamicIsland/Views/DataPrimaryContentView.swift Tests/DynamicIslandCoreChecks/main.swift
git status --short
```

Expected: no whitespace errors; the Data view diff contains only the stable
control tree, independent overlay, materialize transition and row-background
removal. The test file still includes the pre-existing hover checks.

Do not stage or commit `Tests/DynamicIslandCoreChecks/main.swift` while its prior
hover changes remain uncommitted. Keep this task as a verified working-tree
checkpoint so the existing patch is not split into an invalid commit.

---

### Task 2: Perform cold-path visual verification, sample CPU, and record the final contract

**Files:**

- Modify: `MEMORY.md:97`
- Verify: `Sources/DynamicIsland/Views/DataPrimaryContentView.swift`
- Verify: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**

- Consumes: Task 1's stable trigger, independent drawer, materialize transition
  and existing `IslandOverlayView` state/animation ownership.
- Produces: A runtime-verified Data menu contract and rollback record; no new
  runtime interface.

- [ ] **Step 1: Build, sign, package, and launch through the project entry point**

Run:

```bash
./script/build_and_run.sh
```

Expected: the script exits successfully and launches one healthy
`DynamicIsland` process.

Then run:

```bash
island_pid=$(pgrep -x DynamicIsland | head -n 1)
test -n "$island_pid"
ps -o pid,stat,pcpu,pmem,etime,command -p "$island_pid"
```

Expected: a nonempty PID and a live process state without a stuck or zombie
status.

- [ ] **Step 2: Verify the exact first-open path three times**

For each of three complete launches, use only `./script/build_and_run.sh` as the
launch entry, then perform:

1. First hover and expand after launch.
2. Select Data for the first time.
3. Open the current-range capsule for the first time.
4. Close and reopen the menu five times.
5. Select a different range once and confirm exactly one refresh.

All three launches must show:

- no full white or opaque frame during the first menu presentation;
- the current-range capsule remains visible with its up chevron;
- the menu appears 5pt below and right-aligned to the capsule;
- the menu does not cover the refresh button or move the statistics card;
- the selected row uses a checkmark and blue foreground without a white row
  panel;
- rapid toggle, island-internal outside click, Escape, page switch, collapse
  and hidden state still close the menu.

If any launch still shows an opaque flash or a hit-testing failure, stop this
task, preserve the evidence, and do not write a successful memory entry.

- [ ] **Step 3: Verify accessibility fallbacks**

With Reduce Motion enabled, confirm the drawer fades without materialize or
spring displacement. With Reduce Transparency enabled, confirm the near-black
fallback is readable and retains the same independent position. Restore the
user's original accessibility settings after each check.

No accessibility, screen-recording, microphone or Apple Events permission
should be requested.

- [ ] **Step 4: Sample settled CPU after closing the menu**

Leave Data visible with the menu closed and no interaction for five seconds,
then run:

```bash
island_pid=$(pgrep -x DynamicIsland | head -n 1)
for sample_index in {1..10}; do
    ps -o %cpu= -p "$island_pid"
    sleep 1
done
```

Expected: samples return to the app's existing idle range without a sustained
high-CPU plateau. A transient refresh or polling spike is acceptable only if
subsequent samples settle immediately.

- [ ] **Step 5: Add the verified project-memory event**

Only after Steps 1–4 succeed, insert this event above
`2026-07-27 - cold-first-hover-click-hitch-removal` in `MEMORY.md`:

```md
### 2026-07-27 - data-time-range-independent-liquid-glass-menu
- Reason: The first Data time-range expansion after a cold app launch briefly
  exposed an opaque white glass frame, and the menu needed to match the
  independent macOS Liquid Glass popup style.
- Changed:
  - `Sources/DynamicIsland/Views/DataPrimaryContentView.swift`
  - `Tests/DynamicIslandCoreChecks/main.swift`
  - `MEMORY.md`
- Result: The time-range capsule and refresh button remain mounted while one
  independent menu surface materializes 5pt below the capsule. The native path
  has no explicit menu or row background, the selected option uses only its
  checkmark and foreground emphasis, and fallback/accessibility behavior keeps
  the same geometry without prewarming or continuous work.
- Verify: `swift run DynamicIslandCoreChecks`, `swift build --product
  DynamicIsland`, `./script/build_and_run.sh`, three cold first-open visual
  checks, Reduce Motion/Transparency checks, and settled CPU sampling passed.
- Rollback: Restore the conditional trigger/drawer replacement and matched
  glass transition only if the independent popup interaction is deliberately
  abandoned; do not add hidden prewarming as an implicit rollback.
```

- [ ] **Step 6: Run the complete final verification**

Run:

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
git diff --check -- Sources/DynamicIsland/Views/DataPrimaryContentView.swift Tests/DynamicIslandCoreChecks/main.swift MEMORY.md
```

Expected: core checks and build pass; `git diff --check` has no output.

- [ ] **Step 7: Review the final working tree without disturbing prior changes**

Run:

```bash
git status --short --branch
git diff --stat
git diff -- Sources/DynamicIsland/Views/DataPrimaryContentView.swift Tests/DynamicIslandCoreChecks/main.swift MEMORY.md
```

Expected: the original hover/click changes remain present; the new Data change
is limited to the three planned files; no secrets, generated app bundles,
temporary screenshots or unrelated formatting are included.

Because `MEMORY.md` and the CoreChecks file were dirty before this plan, do not
stage or commit them automatically. Report the verified working-tree result and
let the root agent or user decide how to group the completed hover and Data
fixes into a later commit.
