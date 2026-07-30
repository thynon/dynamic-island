# Data 时间范围液态玻璃浮层与首次白闪修复设计

## 目标

修复以下稳定复现路径中的首次白色闪烁：

1. 第一次启动 Dynamic Island。
2. 第一次进入 Data 页面。
3. 第一次展开时间范围选择控件。

时间范围控件改为用户确认的截图式交互：当前范围胶囊保持在原位，选项菜单作为一块
独立的 Liquid Glass 浮层从胶囊下方出现。macOS 26 原生路径中，玻璃是菜单唯一的
可见背景，不叠加白色、黑色或其他 Material 底板。

本设计只替换
`docs/superpowers/specs/2026-07-19-data-token-usage-design.md`
中“触发胶囊直接变形成单块抽屉”的设计。Data 统计口径、刷新流程、页面懒加载、
顶部安全带和其他一级页面行为保持不变。

## 问题定位

当前 macOS 26 实现把时间胶囊和抽屉放在同一个条件分支中：关闭时只挂载胶囊，
打开时移除胶囊并首次挂载抽屉；两者再通过
`.glassEffectTransition(.matchedGeometry)` 进行形变。

Data 页面本身按需挂载，因此第一次启动后的首次展开同时触发：

- 第一次创建抽屉的原生玻璃表面；
- 第一次建立抽屉的玻璃 identity；
- 从小胶囊到大抽屉的 matched-geometry 形变。

这条冷路径会让尚未完成合成的玻璃表面短暂显示默认亮色，表现为整块菜单白闪。
代码中现有低透明白色值只覆盖统计卡或选中行，无法解释整块浮层的瞬时白色，
因此修复边界应是玻璃挂载与过渡方式，而不是调低普通背景透明度。

## 已确认的产品决策

1. 采用独立浮层方案，不再让时间胶囊变形成菜单。
2. 菜单打开后，时间胶囊和刷新按钮都保持原位且可见。
3. macOS 26 使用单块原生 Liquid Glass 作为菜单背景，不在其下方增加显式填充。
4. 菜单选项没有常驻行背景；当前选项只通过勾选、字重和克制的强调色表达。
5. 不预热隐藏玻璃表面，避免把首次开销转移到 Data 页 hover 或首次进入阶段。
6. 不改用系统 `Menu`、`Picker` 或 `NSPopover`，以保持外观、层级和关闭语义可控。
7. 保留现有进程内选择、范围刷新、关闭条件和辅助功能后备行为。

## 组件与布局

改动集中在 `DataPrimaryContentView`。父级
`IslandOverlayView` 继续持有 `isDataTimeRangeDrawerPresented`，并继续通过现有
回调控制展开、选择、刷新和关闭，不新增可观察状态或持久化。

控件区由两个稳定层组成：

1. 常驻控制行：时间胶囊和刷新圆钮始终挂载。
2. 条件浮层：菜单打开时，以时间胶囊为相对锚点，通过 top-trailing overlay 挂载。

菜单位于时间胶囊正下方，右边缘与时间胶囊右边缘对齐，与胶囊保持 5pt 间距。
它浮在统计卡上方，不参与统计卡布局，也不推动或裁剪内容。刷新按钮仍位于时间胶囊
右侧，菜单不能覆盖刷新按钮的点击区域。

现有 Data 页面 z-index 合同保持不变：

- Data 普通层为现有一级内容层；
- 菜单打开时 Data 升至 24；
- 岛内外部关闭点击层为 23；
- File Shelf 保持 22。

该布局不改变顶部 32pt 状态带、camera housing 禁区或 primary content frame。

## macOS 26 Liquid Glass

时间胶囊、菜单和刷新按钮继续放在一个 `GlassEffectContainer` 中，以复用原生玻璃
合成上下文。三个表面保留彼此独立的 `glassEffectID`，但不再共享形变来源。

- 时间胶囊始终使用 `.glassEffect(.regular.interactive())`，不因菜单开关而移除。
- 刷新按钮始终使用独立的圆形 interactive glass。
- 菜单使用一块连续圆角矩形 interactive glass。
- 菜单插入和移除使用
  `.glassEffectTransition(accessibilityReduceMotion ? .identity : .materialize)`。
- 菜单视图的普通 transition 在 Reduce Motion 下使用 `.opacity`，正常模式使用
  `.identity`，避免与玻璃 materialize 叠加第二套位移动画。
- 删除时间胶囊与菜单之间的 `.matchedGeometry` 过渡。
- 不使用 SwiftUI 的普通 `.matchedGeometryEffect`。
- 菜单和选项行都不添加 `Color.white`、`Color.black`、`.thinMaterial` 或第二层
  `.glassEffect` 作为背景。

`materialize` 让新菜单以自己的几何形状生成玻璃材质，不需要在首次创建时从另一块
玻璃推导大幅变化的几何形状。菜单关闭时执行相反的消隐；时间胶囊本身不重建，因此
不会出现标签或点击热点跳动。

## 视觉样式

菜单沿用项目的紧凑尺寸和连续圆角，整体外观参考用户提供的 macOS 颜色选择菜单：

- 背景只显示系统 Liquid Glass 的折射、亮边和环境融合效果；
- 不铺不透明或半透明的白色矩形底；
- 菜单作为单一玻璃容器，选项之间不分割成多块玻璃；
- 当前范围左侧显示勾选，文字使用现有蓝色强调和稍高字重；
- 未选范围使用正常前景色；
- 移除当前选项现有的常驻白色行底；
- 按下反馈继续使用 `IslandPressButtonStyle`，不加入循环动画。

玻璃边缘和阴影优先由原生效果表达，不额外叠加会导致发白的高透明填充。提高对比度
时只增强文字和系统允许的边界对比，不改变浮层结构。

## 兼容与辅助功能

### macOS 14 和 15

继续使用现有 fallback 路径，以单块 `.thinMaterial` 圆角浮层近似菜单。触发胶囊
同样保持在原位，菜单从其下方独立出现。fallback 可以保留细描边与柔和阴影，但不能
退回“胶囊替换成菜单”的结构。

### Reduce Transparency

沿用现有近黑色高不透明 fallback，这是用户主动选择的辅助功能后备，不属于
macOS 26 原生玻璃路径的显式菜单底色。

### Reduce Motion

菜单不执行弹簧位移或玻璃材质形变，使用现有
`IslandAnimationProfile.default.reducedMotionFadeDuration` 淡入淡出。
正常模式继续使用 `IslandAnimationProfile.default` 中现有的 Data 抽屉响应与阻尼；
不在视图中新增动画时长硬编码。

## 交互与状态流

1. 点击时间胶囊只切换菜单的呈现状态，不发起统计查询。
2. 菜单出现时，胶囊保留并把箭头切换为向上。
3. 选择范围后先关闭菜单，再通过现有回调切换范围并刷新数据。
4. 点击刷新按钮时先关闭菜单，再刷新当前范围。
5. 点击岛内菜单以外区域、按 `Escape`、切换一级页面、收起或隐藏灵动岛时关闭菜单。
6. 快速重复点击胶囊可以中断并反向当前动画，不锁定输入。
7. 不安装全局鼠标或键盘监听，不新增辅助功能、录屏或 Apple Events 权限。
8. 隐藏态继续拥有最高交互优先级，不允许通过该控件展开菜单。

Data 页面继续按需挂载并在展开会话内保留访问过的页面。修复不能通过永久挂载、
隐藏预热、定时器或异步延迟来规避白闪，以免重新引入首次 hover、点击或空闲 CPU
问题。

## 错误处理

该改动不改变 Data 查询状态或错误展示。原生 Liquid Glass 只在编译器和运行系统均
支持且 Reduce Transparency 未开启时启用；其他情况进入现有 fallback。

菜单状态与查询状态相互独立。查询失败、无数据或 partial 数据都不能阻止菜单关闭，
也不能在菜单首次挂载时创建额外加载表面。

## 验证方案

### 源码回归检查

在 `DynamicIslandCoreChecks` 中更新 Data 控件合同：

- 时间胶囊在菜单开关条件之外始终挂载；
- 菜单和时间胶囊具有独立 glass identity；
- 菜单使用 `.glassEffectTransition(.materialize)`；
- Data 时间控件不再包含 `.matchedGeometry` 或 `.matchedGeometryEffect`；
- macOS 26 菜单容器和选项行的 background、fill、overlay 不含显式颜色或
  Material；文字和图标的既有前景强调色除外；
- 选中项没有常驻白色行底；
- 每个选项不创建独立玻璃表面；
- fallback 仍使用 `.thinMaterial` 或 Reduce Transparency 的高不透明表面；
- 现有 z-index、岛内点击、Escape、切页、刷新、收起和隐藏关闭合同继续成立；
- Data 页面懒挂载和访问后保留合同不变。

### 构建与运行

每次实现后运行：

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
./script/build_and_run.sh
```

### 冷启动验收

在 macOS 26 原生玻璃路径上至少执行三次完整冷启动：

1. 启动后第一次展开灵动岛。
2. 第一次进入 Data 页面。
3. 第一次点击时间胶囊。
4. 观察菜单完整出现，再重复打开和关闭至少五次。

每次首次打开都必须满足：

- 菜单没有整块白色或不透明表面闪现；
- 时间胶囊始终可见，没有先消失再重建；
- 菜单从胶囊下方出现，不覆盖刷新按钮；
- 统计卡和其他页面没有位置跳动；
- 选项可立即点击，选择后只触发一次范围刷新。

同时检查 Reduce Motion、Reduce Transparency、快速重复点击、切页关闭、收起关闭和
隐藏态。完成运行验证后检查 DynamicIsland 进程 CPU；菜单关闭且页面静止时不能因
本修复产生持续动画或长期高占用。

## 验收标准

- 首次启动、首次进入 Data、首次展开菜单不再出现白色闪烁。
- “今日”等当前范围胶囊在菜单打开期间保持原位。
- 菜单是胶囊下方独立的单块 Liquid Glass 浮层。
- macOS 26 原生路径没有菜单底板或选项行白底。
- 菜单视觉接近用户参考图的轻透玻璃、圆角和单层结构。
- 现有范围选择、刷新、关闭、辅助功能和多页面层级行为全部保留。
- 不通过预热、常驻隐藏视图、轮询或新权限换取视觉修复。
- 核心检查、主程序构建、实际冷启动和 CPU 检查通过。

## 范围外

- 修改 Token 统计口径、数据源、时间范围或刷新策略。
- 改造 Data 统计卡其他视觉元素。
- 改用系统弹出菜单、独立窗口或 `NSPopover`。
- 窗口外全局点击监听或全局 Escape。
- 修改顶部 32pt 安全带、camera housing 合同、File Shelf、Tasks 或音乐行为。
- 为其他页面建立通用下拉组件或进行无关重构。

## 回退

如果原生 `materialize` 在目标 macOS 26 版本仍出现首次合成异常，只回退本规格涉及的
Data 菜单结构和测试。隐藏预热不是默认回退方案；需要单独收集首次帧证据并重新评审，
不能直接引入长期挂载或延迟任务。

## 参考

- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Apple: GlassEffectTransition](https://developer.apple.com/documentation/swiftui/glasseffecttransition)
- [Apple: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
