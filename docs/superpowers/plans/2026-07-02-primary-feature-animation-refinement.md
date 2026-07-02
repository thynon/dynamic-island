# Primary Feature Animation Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 优化一级功能组（Tasks/Data/Tools/Settings）的入场、切换、退场动画，达到苹果原生级别的精致和流畅度

**Architecture:** 分阶段入场动画（按钮从左到右依次出现，错开 0.03 秒），matchedGeometryEffect 实现背景高亮流畅滑动，自定义 ButtonStyle 实现点击反馈，更柔和的弹簧参数（response 0.35, damping 0.88）

**Tech Stack:** Swift 6, SwiftUI, IslandAnimationProfile, matchedGeometryEffect

## Global Constraints

- macOS 14+
- Swift 6 strict concurrency
- 通过 `swift run DynamicIslandCoreChecks` 所有断言
- 不修改 NotchMetrics 系统（使用现有度量）
- 不修改 IslandPrimaryFeature 枚举定义
- 不添加屏幕录制权限
- 入场动画不得溢出外壳边界

---

## File Map

**Modified Files:**
1. `Sources/DynamicIslandCore/IslandAnimationProfile.swift` - 添加新动画参数，修改现有入场参数
2. `Sources/DynamicIsland/Views/IslandOverlayView.swift` - 重构 PrimaryFeatureSwitcher，添加分阶段入场、背景高亮滑动、点击反馈

**Verification:**
- `Tests/DynamicIslandCoreChecks/main.swift` - 现有断言应继续通过

---

### Task 1: 扩展动画配置参数

**Files:**
- Modify: `Sources/DynamicIslandCore/IslandAnimationProfile.swift`

**Interfaces:**
- Consumes: 现有 IslandAnimationProfile 结构体
- Produces: 
  - `primaryFeatureStaggerDelay: Double` - 按钮分阶段入场延迟
  - `primaryFeatureButtonSlideDistance: Double` - 按钮垂直滑动距离
  - `primaryFeatureSelectionResponse: Double` - 背景高亮切换响应时间
  - `primaryFeatureSelectionDamping: Double` - 背景高亮切换阻尼
  - `primaryFeatureButtonPressScale: Double` - 按钮点击缩放比例
  - `primaryFeatureButtonPressDuration: Double` - 按钮点击动画时长
  - Updated `primaryFeatureEntranceResponse: 0.35` (from 0.28)
  - Updated `primaryFeatureEntranceDampingFraction: 0.88` (from 0.74)

- [ ] **Step 1: 添加新动画参数字段到 IslandAnimationProfile**

在 `IslandAnimationProfile` 结构体中，在现有字段后添加：

```swift
public let primaryFeatureStaggerDelay: Double
public let primaryFeatureButtonSlideDistance: Double
public let primaryFeatureSelectionResponse: Double
public let primaryFeatureSelectionDamping: Double
public let primaryFeatureButtonPressScale: Double
public let primaryFeatureButtonPressDuration: Double
```

- [ ] **Step 2: 更新 init 方法签名**

在 `init` 方法中添加新参数：

```swift
public init(
    expandResponse: Double,
    expandDampingFraction: Double,
    expandBlendDuration: Double,
    collapseDuration: Double,
    primaryFeatureEntranceResponse: Double,
    primaryFeatureEntranceDampingFraction: Double,
    primaryFeatureEntranceBlendDuration: Double,
    primaryFeatureEntranceStartDelay: Double,
    attachedElementExpandCurve: UnitBezier,
    attachedElementCollapseCurve: UnitBezier,
    attachedElementExpandDuration: Double,
    attachedElementCollapseDuration: Double,
    collapseCanvasDelay: Double,
    expandedContentScale: Double,
    audioWaveformCollapsedScale: Double,
    primaryFeatureStaggerDelay: Double,
    primaryFeatureButtonSlideDistance: Double,
    primaryFeatureSelectionResponse: Double,
    primaryFeatureSelectionDamping: Double,
    primaryFeatureButtonPressScale: Double,
    primaryFeatureButtonPressDuration: Double
) {
    self.expandResponse = expandResponse
    self.expandDampingFraction = expandDampingFraction
    self.expandBlendDuration = expandBlendDuration
    self.collapseDuration = collapseDuration
    self.primaryFeatureEntranceResponse = primaryFeatureEntranceResponse
    self.primaryFeatureEntranceDampingFraction = primaryFeatureEntranceDampingFraction
    self.primaryFeatureEntranceBlendDuration = primaryFeatureEntranceBlendDuration
    self.primaryFeatureEntranceStartDelay = primaryFeatureEntranceStartDelay
    self.attachedElementExpandCurve = attachedElementExpandCurve
    self.attachedElementCollapseCurve = attachedElementCollapseCurve
    self.attachedElementExpandDuration = attachedElementExpandDuration
    self.attachedElementCollapseDuration = attachedElementCollapseDuration
    self.collapseCanvasDelay = collapseCanvasDelay
    self.expandedContentScale = expandedContentScale
    self.audioWaveformCollapsedScale = audioWaveformCollapsedScale
    self.primaryFeatureStaggerDelay = primaryFeatureStaggerDelay
    self.primaryFeatureButtonSlideDistance = primaryFeatureButtonSlideDistance
    self.primaryFeatureSelectionResponse = primaryFeatureSelectionResponse
    self.primaryFeatureSelectionDamping = primaryFeatureSelectionDamping
    self.primaryFeatureButtonPressScale = primaryFeatureButtonPressScale
    self.primaryFeatureButtonPressDuration = primaryFeatureButtonPressDuration
}
```

- [ ] **Step 3: 更新 default 配置**

修改 `static let default` 的值：

```swift
public static let `default` = IslandAnimationProfile(
    expandResponse: 0.38,
    expandDampingFraction: 0.82,
    expandBlendDuration: 0,
    collapseDuration: 0.14,
    primaryFeatureEntranceResponse: 0.35,
    primaryFeatureEntranceDampingFraction: 0.88,
    primaryFeatureEntranceBlendDuration: 0,
    primaryFeatureEntranceStartDelay: 0.34,
    attachedElementExpandCurve: UnitBezier(0.18, 0.86, 0.22, 1.0),
    attachedElementCollapseCurve: UnitBezier(0.20, 0.82, 0.22, 1.0),
    attachedElementExpandDuration: 0.34,
    attachedElementCollapseDuration: 0.14,
    collapseCanvasDelay: 0.14,
    expandedContentScale: 0.88,
    audioWaveformCollapsedScale: 0.92,
    primaryFeatureStaggerDelay: 0.03,
    primaryFeatureButtonSlideDistance: 6.0,
    primaryFeatureSelectionResponse: 0.28,
    primaryFeatureSelectionDamping: 0.75,
    primaryFeatureButtonPressScale: 0.96,
    primaryFeatureButtonPressDuration: 0.12
)
```

- [ ] **Step 4: 编译验证**

Run: `swift build`
Expected: 编译成功，无错误

- [ ] **Step 5: Commit**

```bash
git add Sources/DynamicIslandCore/IslandAnimationProfile.swift
git commit -m "feat: add animation parameters for primary feature refinement"
```

---

### Task 2: 实现自定义按钮样式

**Files:**
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift`

**Interfaces:**
- Consumes: `IslandAnimationProfile` (from Task 1)
- Produces: `PrimaryFeatureButtonStyle: ButtonStyle` - 提供点击反馈的按钮样式

- [ ] **Step 1: 在 IslandOverlayView.swift 底部添加 PrimaryFeatureButtonStyle**

在文件末尾，`MusicSkipGlyph` 结构体之后添加：

```swift
private struct PrimaryFeatureButtonStyle: ButtonStyle {
    let animationProfile: IslandAnimationProfile
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? animationProfile.primaryFeatureButtonPressScale : 1.0)
            .animation(.easeOut(duration: animationProfile.primaryFeatureButtonPressDuration), value: configuration.isPressed)
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `swift build`
Expected: 编译成功，新的 ButtonStyle 可用

- [ ] **Step 3: Commit**

```bash
git add Sources/DynamicIsland/Views/IslandOverlayView.swift
git commit -m "feat: add PrimaryFeatureButtonStyle for press feedback"
```

---

### Task 3: 重构 PrimaryFeatureSwitcher - 添加分阶段入场动画

**Files:**
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift:485-508` (PrimaryFeatureSwitcher)

**Interfaces:**
- Consumes: 
  - `IslandAnimationProfile` (from Task 1)
  - `PrimaryFeatureButtonStyle` (from Task 2)
  - `IslandPrimaryFeature.allCases`
- Produces: 重构后的 PrimaryFeatureSwitcher，支持分阶段入场

- [ ] **Step 1: 添加 featureEntranceAnimation 计算属性到 IslandOverlayView**

在 `IslandOverlayView` 中，在 `primaryFeatureEntranceAnimation` 属性之后添加：

```swift
private func featureEntranceAnimation(index: Int) -> Animation {
    guard isExpanded else {
        return .easeOut(duration: animationProfile.attachedElementCollapseDuration)
    }
    
    let baseAnimation = Animation.spring(
        response: animationProfile.primaryFeatureEntranceResponse,
        dampingFraction: animationProfile.primaryFeatureEntranceDampingFraction,
        blendDuration: animationProfile.primaryFeatureEntranceBlendDuration
    )
    
    let staggerDelay = animationProfile.primaryFeatureEntranceStartDelay + (Double(index) * animationProfile.primaryFeatureStaggerDelay)
    
    return baseAnimation.delay(staggerDelay)
}
```

- [ ] **Step 2: 重构 PrimaryFeatureSwitcher - 修改 ForEach 以支持索引**

找到 `PrimaryFeatureSwitcher` 结构体（约第 485 行），将：

```swift
ForEach(IslandPrimaryFeature.allCases) { feature in
```

替换为：

```swift
ForEach(Array(IslandPrimaryFeature.allCases.enumerated()), id: \.element) { index, feature in
```

- [ ] **Step 3: 为每个按钮添加独立的偏移和动画**

在 Button 的 label 闭包后，修改 `.buttonStyle(.plain)` 行为：

找到：
```swift
}
.buttonStyle(.plain)
```

替换为：

```swift
}
.buttonStyle(PrimaryFeatureButtonStyle(animationProfile: IslandOverlayView.defaultAnimationProfile))
.offset(y: -IslandOverlayView.defaultAnimationProfile.primaryFeatureButtonSlideDistance)
.opacity(0)
.modifier(FeatureEntranceModifier(isExpanded: false, index: index, animationProfile: IslandOverlayView.defaultAnimationProfile))
```

等等，这里有问题。PrimaryFeatureSwitcher 是独立的 View，它没有访问 `isExpanded` 状态的权限。让我重新设计。

- [ ] **Step 3 (修正): 为 PrimaryFeatureSwitcher 添加 isExpanded 和 animationProfile 参数**

修改 `PrimaryFeatureSwitcher` 的定义：

```swift
private struct PrimaryFeatureSwitcher: View {
    @Binding var selection: IslandPrimaryFeature
    let isExpanded: Bool
    let animationProfile: IslandAnimationProfile
    
    @Namespace private var selectionNamespace
    
    private func featureEntranceAnimation(index: Int) -> Animation {
        guard isExpanded else {
            return .easeOut(duration: animationProfile.attachedElementCollapseDuration)
        }
        
        let baseAnimation = Animation.spring(
            response: animationProfile.primaryFeatureEntranceResponse,
            dampingFraction: animationProfile.primaryFeatureEntranceDampingFraction,
            blendDuration: animationProfile.primaryFeatureEntranceBlendDuration
        )
        
        let staggerDelay = animationProfile.primaryFeatureEntranceStartDelay + (Double(index) * animationProfile.primaryFeatureStaggerDelay)
        
        return baseAnimation.delay(staggerDelay)
    }
```

- [ ] **Step 4: 修改 ForEach 并添加动画修饰符**

在 PrimaryFeatureSwitcher 的 body 中，修改为：

```swift
var body: some View {
    HStack(spacing: 2) {
        ForEach(Array(IslandPrimaryFeature.allCases.enumerated()), id: \.element.id) { index, feature in
            Button {
                selection = feature
            } label: {
                Text(feature.title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selection == feature ? .white.opacity(0.16) : .white.opacity(0.05))
                    )
            }
            .buttonStyle(PrimaryFeatureButtonStyle(animationProfile: animationProfile))
            .offset(y: isExpanded ? 0 : -animationProfile.primaryFeatureButtonSlideDistance)
            .opacity(isExpanded ? 1 : 0)
            .animation(featureEntranceAnimation(index: index), value: isExpanded)
        }
    }
    .foregroundStyle(.white)
}
```

- [ ] **Step 5: 更新 IslandOverlayView 中的 PrimaryFeatureSwitcher 调用**

找到 IslandOverlayView 中调用 PrimaryFeatureSwitcher 的地方（约第 245 行）：

```swift
PrimaryFeatureSwitcher(selection: $state.selectedPrimaryFeature)
```

替换为：

```swift
PrimaryFeatureSwitcher(
    selection: $state.selectedPrimaryFeature,
    isExpanded: isExpanded,
    animationProfile: animationProfile
)
```

- [ ] **Step 6: 移除旧的整体动画**

在 IslandOverlayView 中，找到对 PrimaryFeatureSwitcher 应用的旧动画修饰符（约第 248-251 行）：

```swift
.offset(y: isExpanded ? 0 : -primaryFeatureEntranceOffsetY)
.opacity(isExpanded ? 1 : 0)
.allowsHitTesting(isExpanded)
.animation(primaryFeatureEntranceAnimation, value: isExpanded)
```

替换为：

```swift
.allowsHitTesting(isExpanded)
```

- [ ] **Step 7: 编译验证**

Run: `swift build`
Expected: 编译成功

- [ ] **Step 8: Commit**

```bash
git add Sources/DynamicIsland/Views/IslandOverlayView.swift
git commit -m "feat: implement staggered entrance animation for primary features"
```

---

### Task 4: 实现背景高亮滑动动画

**Files:**
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift:485-508` (PrimaryFeatureSwitcher)

**Interfaces:**
- Consumes: 
  - `IslandAnimationProfile.primaryFeatureSelectionResponse`
  - `IslandAnimationProfile.primaryFeatureSelectionDamping`
  - `@Namespace` for matchedGeometryEffect
- Produces: 流畅滑动的背景高亮效果

- [ ] **Step 1: 修改 PrimaryFeatureSwitcher 的背景实现**

在 PrimaryFeatureSwitcher 的 body 中，找到按钮的 background 修饰符：

```swift
.background(
    RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(selection == feature ? .white.opacity(0.16) : .white.opacity(0.05))
)
```

替换为：

```swift
.background(
    ZStack {
        if selection == feature {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.16))
                .matchedGeometryEffect(id: "selection", in: selectionNamespace)
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.05))
        }
    }
)
```

- [ ] **Step 2: 为 HStack 添加选择动画**

在 PrimaryFeatureSwitcher 的 HStack 后添加动画修饰符：

找到：
```swift
}
.foregroundStyle(.white)
```

替换为：

```swift
}
.foregroundStyle(.white)
.animation(
    .spring(
        response: animationProfile.primaryFeatureSelectionResponse,
        dampingFraction: animationProfile.primaryFeatureSelectionDamping
    ),
    value: selection
)
```

- [ ] **Step 3: 编译验证**

Run: `swift build`
Expected: 编译成功

- [ ] **Step 4: 运行项目并测试背景高亮滑动**

Run: 
```bash
swift run DynamicIsland
```

操作：
1. 展开灵动岛
2. 点击不同的功能标签（Tasks → Data → Tools → Settings）

Expected: 背景高亮从旧位置平滑滑动到新位置，有弹性效果

- [ ] **Step 5: Commit**

```bash
git add Sources/DynamicIsland/Views/IslandOverlayView.swift
git commit -m "feat: implement fluid background highlight transition with matchedGeometryEffect"
```

---

### Task 5: 运行验证检查

**Files:**
- Verify: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**
- Consumes: 所有前面任务的修改
- Produces: 验证所有断言通过

- [ ] **Step 1: 运行 DynamicIslandCoreChecks**

Run:
```bash
swift run DynamicIslandCoreChecks
```

Expected: 所有检查通过，特别是：
- `expectEqual(overlay.contains(".animation(primaryFeatureEntranceAnimation, value: isExpanded)"), true, "primary feature group uses one whole-group entrance animation")`

注意：这个断言可能需要更新，因为我们现在使用的是每个按钮独立的动画。

- [ ] **Step 2: 如果断言失败，更新检查逻辑**

如果上述断言失败，在 `Tests/DynamicIslandCoreChecks/main.swift` 中找到相关断言（约第 411 行）：

```swift
expectEqual(overlay.contains(".animation(primaryFeatureEntranceAnimation, value: isExpanded)"), true, "primary feature group uses one whole-group entrance animation")
```

替换为：

```swift
expectEqual(overlay.contains("featureEntranceAnimation(index: index)"), true, "primary feature buttons use per-button staggered entrance animation")
```

- [ ] **Step 3: 再次运行检查**

Run:
```bash
swift run DynamicIslandCoreChecks
```

Expected: 所有检查通过

- [ ] **Step 4: 编译发布版本验证**

Run:
```bash
swift build -c release
```

Expected: 编译成功，无警告

- [ ] **Step 5: Commit 检查更新（如果有）**

如果修改了检查文件：

```bash
git add Tests/DynamicIslandCoreChecks/main.swift
git commit -m "test: update primary feature animation assertion for staggered entrance"
```

---

### Task 6: 手动视觉测试和最终验证

**Files:**
- Test: All modified files

**Interfaces:**
- Consumes: 完整实现的所有功能
- Produces: 视觉和功能验证报告

- [ ] **Step 1: 启动应用进行完整测试**

Run:
```bash
swift run DynamicIsland
```

- [ ] **Step 2: 测试入场动画**

操作：
1. 将鼠标悬停在药丸上
2. 观察展开动画

验证点：
- ✅ 外壳先横向展开
- ✅ 0.34 秒后，Tasks 按钮开始从上方滑入（6pt）
- ✅ Data 按钮延迟 0.03 秒出现
- ✅ Tools 按钮再延迟 0.03 秒出现
- ✅ Settings 按钮最后出现
- ✅ 所有按钮在外壳内部，无溢出
- ✅ 动画流畅，有层次感但不拖沓

- [ ] **Step 3: 测试背景高亮滑动**

操作：
1. 在展开状态下，点击 Data 标签
2. 点击 Tools 标签
3. 点击 Settings 标签
4. 点击 Tasks 标签

验证点：
- ✅ 背景高亮从当前位置平滑滑动到新位置
- ✅ 滑动有轻微的弹性效果（不过冲）
- ✅ 圆角在滑动过程中保持连续
- ✅ 没有跳变或闪烁

- [ ] **Step 4: 测试点击反馈**

操作：
1. 快速点击不同的标签
2. 观察按钮的缩放反馈

验证点：
- ✅ 按下时按钮轻微缩小到 96%
- ✅ 松开时恢复到 100%
- ✅ 反馈微妙但可感知
- ✅ 不会过于夸张或干扰

- [ ] **Step 5: 测试退场动画**

操作：
1. 将鼠标移出药丸区域
2. 观察收起动画

验证点：
- ✅ 按钮整体淡出
- ✅ 配合外壳收缩
- ✅ 淡出快速利落（easeIn）

- [ ] **Step 6: 边界情况测试**

操作：
1. 快速展开然后立即收起（在入场动画完成前）
2. 快速连续点击不同标签
3. 点击当前已选中的标签

验证点：
- ✅ 中断动画视觉合理，无异常
- ✅ 快速切换无卡顿
- ✅ 重复点击不触发异常

- [ ] **Step 7: 记录测试结果**

创建测试记录文件：

```bash
cat > /tmp/animation-test-report.txt << 'EOF'
# Primary Feature Animation Refinement - Test Report

Date: $(date +%Y-%m-%d)

## 入场动画
- [ ] 分阶段入场清晰可见
- [ ] 按钮不溢出外壳
- [ ] 时序协调良好
- [ ] 视觉流畅自然

## 背景高亮滑动
- [ ] 平滑滑动无跳变
- [ ] 弹性效果适中
- [ ] 圆角连续

## 点击反馈
- [ ] 缩放反馈可感知
- [ ] 不过于夸张

## 退场动画
- [ ] 快速利落

## 边界情况
- [ ] 快速展开/收起正常
- [ ] 快速切换无卡顿

## 整体评价
[填写测试总结]
EOF

open /tmp/animation-test-report.txt
```

- [ ] **Step 8: 最终提交**

```bash
git add -A
git commit -m "feat: complete primary feature animation refinement

- Staggered entrance animation (0.03s delay between buttons)
- Fluid background highlight transition with matchedGeometryEffect
- Press feedback with scale animation (0.96)
- Softer spring parameters (response 0.35, damping 0.88)
- All visual tests passing"
```

---

## Spec Coverage Self-Review

### 场景 1: 入场动画
- ✅ Task 1: 动画参数（stagger delay, slide distance）
- ✅ Task 3: 分阶段入场实现
- ✅ Task 1: 更柔和的弹簧参数（0.35, 0.88）

### 场景 2: 切换动画
- ✅ Task 4: matchedGeometryEffect 背景高亮
- ✅ Task 2: 点击反馈 ButtonStyle
- ✅ Task 1: 背景滑动动画参数

### 场景 3: 退场动画
- ✅ 保持现有退场逻辑（无需修改，在 Task 3 中确认）

### 时序协调
- ✅ Task 1: 延迟参数 (0.34s)
- ✅ Task 3: 安全的滑动距离 (6pt)

### 测试验证
- ✅ Task 5: DynamicIslandCoreChecks
- ✅ Task 6: 手动视觉测试

### 无遗漏，所有规格点已覆盖。

---

## Type Consistency Check

- `IslandAnimationProfile.primaryFeatureStaggerDelay: Double` - 一致使用于 Task 1, 3
- `IslandAnimationProfile.primaryFeatureButtonSlideDistance: Double` - 一致使用于 Task 1, 3
- `IslandAnimationProfile.primaryFeatureSelectionResponse: Double` - 一致使用于 Task 1, 4
- `IslandAnimationProfile.primaryFeatureSelectionDamping: Double` - 一致使用于 Task 1, 4
- `IslandAnimationProfile.primaryFeatureButtonPressScale: Double` - 一致使用于 Task 1, 2
- `PrimaryFeatureButtonStyle` - 一致定义于 Task 2，使用于 Task 3
- `featureEntranceAnimation(index: Int)` - 一致定义和使用于 Task 3
- `@Namespace selectionNamespace` - 一致定义和使用于 Task 4

### 无类型不一致，所有签名匹配。
