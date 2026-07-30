# Tasks 展开顶端锚定与 Data 同宽下拉设计

## 背景

用户对当前运行版本进行真实鼠标验收后发现两个问题：

1. 在 Tasks 页面展开主会话下的子代理时，顶部文件按钮、一级导航、会话列表和详情区
   会作为整体先向下位移，再回到屏幕顶部。
2. Data 时间范围菜单虽然从“今日”下方出现，但菜单比触发框宽，额外宽度全部伸向
   左侧；选项文字也没有在用户红框所示的同一列中居中。

本设计在已经实现的闭合式时间范围入口与独立 Liquid Glass 菜单之上修订。首次展开
白闪修复、菜单材质、范围选择、Data 查询和 Tasks 数据模型都保持不变。

## 逐帧与代码证据

### Tasks 整岛位移

录屏 `录屏2026-07-27 下午8.08.38.mov` 的 `4.00s–4.45s` 显示：

- 展开前，整岛顶部稳定；
- 子代理出现的首帧，文件按钮、一级导航和所有内容同步向下移动；
- 随后整岛向上返回原位，子代理行完成展开。

一名子代理通过 `CodexTasksAdaptiveLayout` 请求 `10 + 26 = 36pt` 额外高度。
`IslandPanelController.setCodexTasksDetailExpansionHeight(_:)` 在增长路径中先把
`NSPanel` 扩到目标高度，再以 spring 更新
`overlayState.codexTasksDetailExpansionHeight`。这段时间内，HostingView 已经变高，
但 `IslandOverlayView` 根画布仍是旧的固定高度；根画布被 HostingView 暂时居中，
所以整体向下偏移约高度差的一半。随着 SwiftUI 画布追上目标高度，偏移消失。

面板 frame 的 `maxY` 始终固定在屏幕顶部，因此问题不是 AppKit 把窗口向下移动，也
不是子代理行自己的 `.move(edge: .top)` transition；根因是面板与根画布在动画早期的
尺寸错配缺少显式顶端锚定。

### Data 左侧多余区域

当前触发框宽 `72pt`，菜单宽 `104pt`。控件行为：

- HStack 宽度为 `72 + 6 + 24 = 102pt`；
- 菜单使用 `.topTrailing` overlay；
- 菜单向左偏移 `24 + 6 = 30pt`，使其右边缘与触发框右边缘对齐。

因此菜单左边缘比触发框左边缘多伸出 `104 - 72 = 32pt`；在 Retina 截图中约为
`64px`，与用户指出的空缺完全一致。

选项行同时使用 `9pt` 勾选占位、`5pt` 间距和 leading 对齐文字，所以文字从左侧
固定位置开始，而不是相对触发框中心排列。

## 目标

- Tasks 展开或收起子代理时，灵动岛顶部位置、顶部 32pt 状态带、文件按钮和一级导航
  在每一帧都保持固定。
- 壳体仍可以只向下扩展或收回，子代理行仍保留现有局部过渡。
- Data 菜单与时间范围触发框使用完全相同的宽度和左右边缘。
- 触发框与每个选项的文字都相对同一列几何居中。
- 当前选项的勾选只作为左侧叠加提示，不推挤文字，也不为未选项保留透明占位。
- 保留当前原生 Liquid Glass、首次 materialize、fallback 和所有关闭语义。

## 方案选择

### 采用：根画布填满 HostingView 并固定左上角

保留控制器“先扩面板、再动画壳体”的顺序，避免增长动画被旧窗口边界裁切。在
`IslandOverlayView.body` 的现有 `canvasWidth × canvasHeight` 画布外，再提供一个
填满 HostingView 可用空间、`.topLeading` 对齐的稳定根层。面板高度先变化时，旧尺寸
画布仍贴在顶部；画布随后向下增长，顶部内容不会移动。

这一修复不改变 `CodexTasksAdaptiveLayout`、展开高度、panel frame 计算、spring 参数、
子代理 transition 或 hit-testing 几何。

### 不采用：取消 Tasks 高度动画

这会消除尺寸插值，却让壳体和内容瞬间跳变，破坏当前展开质感。

### 不采用：永久预留最大 Tasks 高度

这能避免运行时 resize，但会让未展开状态长期保留最多 `140pt` 空白，不符合紧凑外壳
目标。

## Data 同宽下拉

Data 菜单采用用户红框确认的单列结构：

1. 触发框继续保持 `72 × 24pt`、`8pt` 连续圆角、居中文字和右侧固定双箭头。
2. 删除独立的 `104pt` 菜单宽度；原生和 fallback 菜单都直接使用
   `triggerWidth`，即 `72pt`。
3. 保留 `.topTrailing` overlay 与现有横向 offset。由于菜单和触发框同宽，二者左右
   边缘同时对齐，菜单不再向左或向右多出区域。
4. 保留触发框与菜单之间 `5pt` 间距，菜单仍是独立玻璃表面。
5. 每个选项行改为叠放布局：
   - 范围文字占据整行并使用 center 对齐；
   - 当前项勾选叠在左侧；
   - 未选项不创建 `Color.clear` 占位；
   - 勾选隐藏于独立辅助功能元素，Button 现有“已选择”标签继续表达状态。
6. 菜单的 `12pt` 连续圆角、行高、字体、颜色、按压反馈与 materialize 路径保持不变。

`72pt` 足以显示当前四个范围：“今日”“3天”“一周”“30天”。本次不为不存在的更长
本地化文本增加自适应宽度，以免重新产生左右溢出。

## 交互与状态

- Tasks disclosure 仍一次只展开一个主会话，并继续上报受限高度。
- Data 入口仍只切换菜单状态，不触发查询。
- 选择范围后仍先关闭菜单，再刷新一次对应范围。
- 刷新、岛内外部点击、`Escape`、切页、收起和隐藏关闭菜单的行为不变。
- 不新增 hover 状态、计时器、预热、持续动画、全局监听或权限。

## 辅助功能与兼容

- Reduce Motion 下仍使用现有无 spring 路径；顶端锚定同样生效。
- Reduce Transparency、macOS 14/15 fallback 只改变材质，不改变同宽几何。
- 时间范围文字与 Button 标签保持现有可访问性；双箭头和勾选图形是装饰性元素。
- 根视图填满透明 panel 后，实际交互区域仍由现有 `IslandShape` 精确 hit test 控制，
  不能扩大透明区域的点击所有权。

## 验证方案

### TDD 源码合同

先更新 `DynamicIslandCoreChecks` 并观察失败：

- `IslandOverlayView` 的显式 canvas 外存在填满 HostingView、`.topLeading` 对齐的根
  frame；
- Tasks 高度仍通过现有 controller 路径增长，不能改成永久预留或取消自适应高度；
- Data 不再声明或使用 `drawerWidth: 104`；
- 原生和 fallback 菜单都使用 `triggerWidth`；
- 选项行使用叠放布局与居中文字；
- 勾选使用 leading overlay 且隐藏于辅助功能；
- 未选项没有 `Color.clear` 勾选占位；
- materialize、独立 drawer identity、5pt 间距和无显式原生背景合同继续成立。

### 构建与静态验证

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
git diff --check
./script/build_and_run.sh
```

### 运行验收

使用真实鼠标完成：

1. 冷启动后首次展开灵动岛。
2. 在 Tasks 中展开和收起一名子代理至少五次。
3. 确认顶部文件按钮、一级导航和整个壳体顶边逐帧固定，只有底边及内部子代理行变化。
4. 切换到 Data，首次打开时间范围菜单。
5. 确认菜单没有白闪，宽度与触发框完全一致，左右边缘在同一竖线上。
6. 确认四个选项文字居中，勾选不推挤“今日”，菜单可立即选择并正常关闭。
7. 重复打开和关闭菜单至少五次，测试刷新、外部点击、`Escape`、切页与收起。
8. 静止后采样进程 CPU，确认没有新增持续高占用。

由于透明 nonactivating panel 对 Computer Use 点击返回 `AXError.notImplemented`，构建
输出不能替代上述真实鼠标验收。若自动化仍受限，必须由用户录屏确认后才能记录成功
项目记忆。

## 验收标准

- Tasks 子代理展开/收起全过程不再让整岛先下移再回顶。
- 顶部 32pt 状态带和 camera housing 合同未变化。
- Data 菜单与 `72pt` 触发框同宽、同左右边缘，左侧 `32pt` 多余区域消失。
- 触发框和每个范围文字处于同一列中心；勾选不影响文字位置。
- 原生 Liquid Glass 首次打开无白闪，fallback 和 Reduce Motion/Transparency 可用。
- 现有 Tasks、Data、刷新、关闭和选择行为全部保留。
- 核心检查、主程序构建、打包启动、真实运行视觉和 CPU 检查通过。

## 范围外

- 改变 Tasks 数据、子代理层级、展开数量或高度预算。
- 重做整个灵动岛 resize 架构或动画参数。
- 改变 Data 查询、统计口径、时间范围或刷新策略。
- 改用系统 `Menu`、`Picker`、`NSPopover` 或新窗口。
- 修改其他页面布局或抽取通用下拉组件。

## 回退

- Tasks：只回退根画布的 HostingView 顶端锚定；保留既有 adaptive height 数据流。
- Data：只回退同宽菜单和居中选项布局；保留闭合触发框、独立 drawer 与首次白闪修复。
