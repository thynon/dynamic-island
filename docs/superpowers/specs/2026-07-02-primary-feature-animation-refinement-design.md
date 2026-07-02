# Primary Feature Animation Refinement Design

**Date**: 2026-07-02  
**Status**: Approved  
**Objective**: 优化一级功能组（Tasks/Data/Tools/Settings）的入场、切换、退场动画，达到苹果原生级别的精致和流畅度

---

## 设计目标

将当前机械、统一的动画升级为：
- **更流畅自然**：使用更柔和的弹簧参数
- **有层次感**：分阶段入场营造深度
- **节奏适中**：压缩时序，避免拖沓
- **精致反馈**：切换和点击有微妙的视觉响应
- **苹果原生感**：克制、物理、可预测

---

## 动画场景

### 场景 1：入场动画（灵动岛展开时）

**当前行为**：
- 四个按钮作为整体从上方滑入（垂直偏移 `primaryNavigationFrame.height + metrics.openTopCornerRadius`）
- 统一的淡入（opacity 0→1）
- 单一的弹簧动画（response 0.28, damping 0.74）
- 延迟 0.34 秒启动

**问题**：
- 所有按钮同时出现，缺少层次
- 弹簧参数略显急促，damping 偏低导致轻微过冲
- 视觉上较为生硬

**新设计**：
- **分阶段入场**：按钮从左到右依次出现（Tasks → Data → Tools → Settings）
- 每个按钮错开 **0.03 秒**
- 每个按钮有独立的垂直偏移动画：从 `-6pt` 滑入到最终位置
- 配合淡入效果（opacity 0→1）
- 使用更柔和的弹簧：**response 0.35, damping 0.88**
- 整体延迟保持 **0.34 秒**（等待外壳展开稳定）

**时序**：
```
t=0.00s:  外壳开始横向展开
t=0.34s:  Tasks 按钮开始入场（-6pt → 0pt, opacity 0→1）
t=0.37s:  Data 按钮开始入场
t=0.40s:  Tools 按钮开始入场  
t=0.43s:  Settings 按钮开始入场
t=0.70s:  所有动画基本完成
```

**安全保障**：
- 6pt 的滑动距离完全在外壳顶部圆角内部
- 总错开时长 0.09 秒，紧凑但有层次
- 配合 clipShape 确保不溢出

---

### 场景 2：切换动画（点击不同功能标签时）

**当前行为**：
- 背景高亮颜色变化（`.white.opacity(0.16)` ↔ `.white.opacity(0.05)`）
- 无平滑过渡，直接切换

**问题**：
- 高亮位置跳变，缺少连贯性
- 没有触觉反馈
- 视觉上不够精致

**新设计**：
- 使用 **matchedGeometryEffect** 让背景高亮从旧位置滑动到新位置
- 滑动动画使用弹性曲线：**response 0.28, damping 0.75**
- 点击时按钮有微妙的缩放反馈：
  - 按下：scale 1.0 → 0.96（duration 0.12s, easeOut）
  - 松开：scale 0.96 → 1.0（spring response 0.22, damping 0.68）
- 高亮背景在滑动过程中保持圆角连续性

**视觉效果**：
- 高亮背景像"流体"一样从 Tasks 流向 Data
- 按钮点击有轻微"下沉"感
- 整体感觉像 iOS 的 Segmented Control

---

### 场景 3：退场动画（灵动岛收起时）

**当前行为**：
- 按钮随外壳整体淡出和偏移
- 使用统一的 collapse 动画（easeOut 0.14s）

**问题**：
- 与入场不对称（入场有延迟和弹性，退场很平淡）
- 但这其实是**合理的**：用户注意力在外壳收起上

**新设计**：
- **保持现有退场逻辑**（统一淡出，不分阶段）
- 原因：退场时用户关注点是整体收缩，分阶段反而干扰
- 微调：退场时 opacity 曲线改为 **easeIn**（而非 easeOut），让淡出更快速利落

---

## 动画参数详细定义

### IslandAnimationProfile 新增字段

```swift
// 一级功能组分阶段入场
public let primaryFeatureStaggerDelay: Double = 0.03
public let primaryFeatureButtonSlideDistance: Double = 6.0

// 背景高亮切换
public let primaryFeatureSelectionResponse: Double = 0.28
public let primaryFeatureSelectionDamping: Double = 0.75

// 按钮点击反馈
public let primaryFeatureButtonPressScale: Double = 0.96
public let primaryFeatureButtonPressDuration: Double = 0.12
public let primaryFeatureButtonReleaseResponse: Double = 0.22
public let primaryFeatureButtonReleaseDamping: Double = 0.68
```

### IslandAnimationProfile 修改字段

```swift
// 原值：0.28, 0.74
primaryFeatureEntranceResponse: 0.35
primaryFeatureEntranceDampingFraction: 0.88
```

---

## 实现架构

### 1. PrimaryFeatureSwitcher 重构

**当前结构**：
```swift
HStack {
    ForEach(IslandPrimaryFeature.allCases) { feature in
        Button { ... } label: { ... }
    }
}
```

**新结构**：
```swift
HStack {
    ForEach(Array(IslandPrimaryFeature.allCases.enumerated()), id: \.element) { index, feature in
        Button { ... } label: { ... }
            .buttonStyle(PrimaryFeatureButtonStyle(animationProfile: animationProfile))
            .offset(y: isExpanded ? 0 : -animationProfile.primaryFeatureButtonSlideDistance)
            .opacity(isExpanded ? 1 : 0)
            .animation(
                featureEntranceAnimation(index: index),
                value: isExpanded
            )
    }
}
.background(
    // matchedGeometryEffect 背景高亮
)
```

### 2. 背景高亮实现

使用 `@Namespace` 和 `matchedGeometryEffect`：

```swift
@Namespace private var selectionNamespace

// 在每个按钮的 background 中：
if selection == feature {
    RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(.white.opacity(0.16))
        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
}
```

### 3. 点击反馈状态管理

使用自定义 ButtonStyle 实现点击缩放反馈：

```swift
struct PrimaryFeatureButtonStyle: ButtonStyle {
    let animationProfile: IslandAnimationProfile
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? animationProfile.primaryFeatureButtonPressScale : 1.0)
            .animation(.easeOut(duration: animationProfile.primaryFeatureButtonPressDuration), value: configuration.isPressed)
    }
}
```

在按钮上应用：`.buttonStyle(PrimaryFeatureButtonStyle(animationProfile: animationProfile))`

---

## 时序协调验证

### 外壳展开 vs 功能入场

**外壳展开**：
- 动画：spring(response: 0.38, damping: 0.82)
- 在 t≈0.6s 达到 95% 稳定
- 在 t≈0.34s 时已经达到 60% 稳定宽度

**功能入场**：
- 延迟：0.34s
- 最后一个按钮在 t=0.43s 开始
- 滑动距离仅 6pt，完全在内部

**结论**：安全，不会溢出。

### 防御措施

在 `IslandOverlayView` 的 shell 层级添加：
```swift
.clipShape(
    IslandShape(
        topCornerRadius: isExpanded ? metrics.openTopCornerRadius : metrics.closedTopCornerRadius,
        concaveTopRadius: isExpanded ? metrics.openTopCornerRadius : metrics.closedConcaveTopRadius,
        bottomCornerRadius: isExpanded ? metrics.openBottomCornerRadius : metrics.closedBottomCornerRadius,
        baseHeight: shellHeight
    )
)
```

已有此 clipShape，因此即使偏移计算有误，也不会视觉溢出。

---

## 代码影响范围

### 修改文件

1. **DynamicIslandCore/IslandAnimationProfile.swift**
   - 添加新动画参数字段
   - 修改 primaryFeatureEntranceResponse 和 DampingFraction

2. **DynamicIsland/Views/IslandOverlayView.swift**
   - 重构 `PrimaryFeatureSwitcher` 实现
   - 添加 matchedGeometryEffect 背景高亮
   - 添加分阶段入场动画
   - 添加点击反馈逻辑

### 不修改的文件

- `IslandPanelController.swift`：控制器逻辑不变
- `IslandPrimaryFeature.swift`：枚举定义不变
- 其他 View 文件：不受影响

---

## 测试验证点

### 功能测试

1. 展开灵动岛，观察四个按钮是否从左到右依次出现
2. 点击不同标签，观察背景高亮是否平滑滑动
3. 快速点击不同标签，确认动画不卡顿、不跳跃
4. 收起灵动岛，确认退场流畅

### 视觉测试

1. 入场时按钮不应该溢出外壳顶部边界
2. 分阶段入场应该"一气呵成"，不应该感觉"拖沓"
3. 背景高亮滑动应该连贯，不应该出现"跳变"
4. 点击反馈应该微妙，不应该过于夸张

### 性能测试

1. 在低端设备上测试（如 2018 MacBook Air）
2. 快速多次展开/收起，确认无掉帧
3. 使用 Instruments 的 Core Animation 工具验证图层合成

---

## 边界情况

### 快速展开/收起

如果用户在入场动画未完成时就收起：
- SwiftUI 会自动中断并反向动画
- 需确保中间状态视觉合理

### 切换到已选中的标签

点击当前选中的标签时：
- 不触发动画
- 可添加轻微"弹跳"反馈表示"已在此页"

### 无障碍访问

- VoiceOver 不应该朗读动画中间状态
- 键盘导航应该在动画完成前就可用
- 减少动画设置（Reduce Motion）应该关闭分阶段效果，改为统一淡入

---

## 成功标准

完成后应达到：
1. ✅ 入场动画有明显的从左到右的层次感
2. ✅ 切换时背景高亮像"流体"一样滑动
3. ✅ 点击有细微但可感知的反馈
4. ✅ 整体节奏接近 iOS Segmented Control 的精致度
5. ✅ 通过 `swift run DynamicIslandCoreChecks` 所有断言

---

## 后续可能的优化方向（本次不实现）

- 添加轻微的模糊效果淡入（入场时）
- 切换时内容区域的过渡动画（目前只做标签动画）
- 减少动画（Reduce Motion）的适配
- 深色模式下的视觉微调

---

**设计完成。准备进入实施计划阶段。**
