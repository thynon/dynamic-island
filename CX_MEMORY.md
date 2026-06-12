# CX_MEMORY.md

这是 `/Users/jayu/Documents/Codex/Island` 项目的独立记忆文件。只用于本项目，避免和其他 Codex 线程或全局记忆混淆。

## 身份标记

- 助手名字：`cx`
- 规则：每次面向用户回复都必须带上 `cx`。
- 用途：用户通过是否出现 `cx` 判断当前对话是否使用了本项目记忆。

## 项目定位

- 本目录当前是面向 14 寸 MacBook Pro 的灵动岛体验项目资料库。
- `.reference/vibe-island/` 是隐藏参考源码目录，也是单独 git 仓库；已确认分支 `main`、提交短哈希 `4c68977`、版本 `1.0.29`。
- 现有三份 `AGENTS-*` 文档和 `.reference/vibe-island/` 只用于学习框架、窗口、布局、动效、组件组织和视觉外壳。
- 不要把三份阶段文档当成功能需求或开发路线；功能添加必须由用户逐项选择。
- 目标产品是补足 MacBook Pro 14 寸没有灵动岛的体验缺口，不是复刻 Vibe Island 的 AI 会话工具。

## 读取顺序

1. 先读 `AGENTS.md`。
2. UI、外壳、窗口、布局问题读 `AGENTS-01-结构与外壳与UI.md`，再用 `.reference/vibe-island/` 源码校验。
3. 组件组织和 Tauri 框架问题查 `.reference/vibe-island/`。
4. `AGENTS-02-功能与架构.md` 只在用户选择相关功能后读取对应章节。
5. `AGENTS-03-分阶段计划.md` 只参考“分阶段验收方法”，不要继承其中功能阶段。

## 稳定约束

- 用户当前方向优先级最高：框架和布局可以深度学习，功能和项目路线不要参考三份阶段 md 自动继承。
- 实施顺序优先级高：先完成适配 14 寸 MacBook Pro 的窗口壳子、位置、尺寸、视觉和 mock 交互，再按用户选择逐个添加功能。
- 刘海/camera housing 是不可显示内容的区域；灵动岛可以用黑色外壳与刘海融合，但任何文字、图标、按钮、交互热点都必须避开中心摄像头区域。
- 14 寸 MBP 的官方显示规格可作为视觉参考：14.2 英寸、3024×1964、254 ppi；真实实现不要长期硬编码刘海尺寸，优先用 macOS 安全区 API 运行时读取。
- 当前本机读取到的内建屏幕数据：逻辑尺寸 `1512×982`，Retina `2x`，物理分辨率 `3024×1964`，`NSScreen.safeAreaInsets.top = 32`，`auxiliaryTopLeftArea = x0 y950 w663 h32`，`auxiliaryTopRightArea = x848 y950 w664 h32`，中间 camera housing gap 约 `185×32` 逻辑点。预览可用外壳宽 `245` = 左空槽 `30` + camera `185` + 右状态槽 `30`。
- 刘海/收起态方案已敲定：连续黑色外壳，尺寸参考本机安全区 `245×32`；中间 `185×32` camera housing 不放内容；左侧 `30px` 状态槽显示绿/黄/红状态点；右侧 `30px` 暂空；不在刘海下方放尺寸文字或解释标签。
- 状态点当前规则：默认态和展开态都使用 `10pt` 可见安全圈，默认中心 `(23,16)`，展开中心 `(25,16)`；展开/收回主移动必须跟随外壳展开/收回同步。因为展开窗口会从中心放大，屏幕空间动画方向为默认态到展开态向左移动，展开态到默认态向右收回；不做左-右-左回弹，不使用额外 offset，不越过最终安全点位。视觉为上一版柔光状态点，不使用玻璃晶体效果；保留绿/黄/红语义，使用多层柔光、ring、core shadow 和低透明高光，所有光效裁在 `10pt` 安全圈内。
- 任务呼吸当前规则：只让状态点外层柔光圈呼吸，中心点不缩放；`idle` 为绿色静态低透明柔光，`running` 为绿色轻呼吸，`warning` 为黄色更慢且略亮呼吸，`error` 为红色小幅高亮轻脉冲。外层呼吸光源必须进入可见 halo 边缘区域，不能小到被中心点盖住；当前 `outerSourceDiameter` 为 halo 的约 `0.82`，仍裁在 `10pt` 安全圈内。当前真实任务检测还未接入，`FileBackedTaskActivityDataSource` 默认读取 `~/Library/Application Support/Island/task-activity-state.txt`，缺失或无效时返回 `idle`，不要把 Codex App 存在当作任务进行中。控制器每秒轮询一次，状态变化后无需重启 App。用 `./script/set_task_activity.sh running` 进入呼吸状态，用 `./script/set_task_activity.sh idle` 停止呼吸。
- 展开态数据面板当前层级：右上角一级功能是固定 header 层 `Status / Stats / Tools`，默认选中 `Stats`；切换到 `Status` 或 `Tools` 时一级切换的 x/y、宽高和内边距不能跳动。`DataPanelView.header` 必须固定高度并顶端对齐，不能使用默认居中 frame，否则 `Status/Tools` 少一行二级控件时会整体下移。`Stats` 内部二级是左侧 `Data` 旁边的 `Trends / Overview / All`；二级控件下方左对齐放置小型 `30s` 刷新状态 + `Today / 7d / 30d / All` 时间范围。不要把 `30s / Today / 7d / 30d / All` 放回右上角。
- `Trends` 当前规则：曲线使用真实事件级 `UsageTrendRecord`，按 `Today / 7d / 30d / All` 生成 `UsageTrendTimeline`；当天范围按小时聚合，跨天范围按自然日聚合，但 x 轴统一显示 `MM/dd HH:mm`，保留时间信息。视觉参考用户给的使用统计页：紫色 tokens 面积线、红色 cost 虚线、蓝色 requests 线，左侧 tokens 轴、右侧 cost 轴。
- `Overview` 当前时间范围语义：`Today` 表示用户本机时区的当前自然日 00:00 到当前时间；`7d` 是最近 7 个自然日，`30d` 是最近 30 个自然日，`All` 表示最近约 6 个月的真实自然日 calendar heatmap，不表示全部历史；补齐周首/周末的空白格只用于网格对齐，不代表数据。
- Calendar 下方四个摘要卡片是紧凑 dashboard metric tile：当前卡片高度约 `23pt`，label 约 `5.8pt`，value 约 `9.4pt`，水平 padding 约 `5pt`，Calendar 标题行约 `13pt`，网格间距约 `4pt`，外层 padding 约 `6pt`。目标是给 heatmap 和后续细节预留更多空间；不要删除 `TOKENS / EST COST / REQ / MODEL`，也不要让文字贴边或溢出。
- 展开态底部内容当前规则：不要把底部状态 chip 大幅上移；三枚 chip 的下边缘应贴近外壳底部内边缘，视觉间距约 `2pt`，同时左右底部圆角附近也按外壳曲线保持约 `2pt` 内距，不碰到或被外壳裁切。当前模型用内容槽高度 `86pt`、chip 高度 `24pt`、底部 inset `2pt`、横向内容 padding `22pt` 达成。
- Session 字段、SessionStatus、HookEvent、Config 字段、hook 协议、socket 审批闭环等只属于参考项目功能；除非用户明确选择相关功能，否则不要纳入本项目。
- 本项目根目录不是 git 仓库；`.reference/vibe-island/` 是参考源码 git 仓库。
- 当前参考源码里 `App.tsx` 会渲染 `OnboardingScreen`，并会根据 onboarding 状态调整 notch 窗口尺寸。
- 当前参考源码里存在 `src/assets/brand`、`src/assets/sounds` 和 `src-tauri/resources/Sounds`，不要沿用旧文档里“无 src/assets / onboarding 未渲染 / 无打包音效”的说法，除非任务明确要求按旧版本复刻。
- 如果后续新增源码，先更新 `AGENTS.md` 的目录说明，再更新本文件的记忆摘要。

## 记忆更新记录

- 2026-06-10：创建项目独立记忆；确认本项目助手名为 `cx`，且每次用户回复都要带上该名字。
- 2026-06-10：补查隐藏目录 `.reference/vibe-island/`，确认它是当前可查的参考源码，版本为 `1.0.29`，提交短哈希 `4c68977`。
- 2026-06-10：用户明确项目方向：三份阶段 md 和参考源码只学习框架、布局和灵动岛外壳；功能添加由用户自己选择，不自动参考或继承其中功能路线。
- 2026-06-10：用户指出第一版预览没有处理 MBP 刘海不可显示区域；已记录 MVP 必须基于刘海安全区设计，中心 camera housing 不放内容。
- 2026-06-10：按用户要求调用本机数据验证刘海区域；本机 `safeAreaInsets.top` 为 32，camera housing gap 约 185×32 逻辑点，预览 v7 改为 245×32 并去掉外层高对比边框。
- 2026-06-10：用户确认“刘海的灵动岛方案可以敲定”；后续优先完善展开区域，不再改变收起态连续黑色刘海外壳基础方案，除非用户明确重新调整。
- 2026-06-10：用户指定 Boring Notch 作为刘海位置、展开动画和展开大小参考；已查其公开源码，提取为本项目外壳参考：默认展开区域约 `640×190`，关闭尺寸用真实刘海宽高推导，打开动画可参考 `spring(response: 0.42, dampingFraction: 0.8)` / `interactiveSpring(response: 0.38, dampingFraction: 0.8)`。只参考外壳、位置和动效，不继承其音乐、日历、相机等功能。
- 2026-06-10：用户确认 v13 预览效果不错并要求开始制作；第一阶段 MVP 已选择原生 macOS SwiftPM App，先完成 `Island` 应用和效果展示。核心文件：`Package.swift`、`Sources/IslandCore/NotchMetrics.swift`、`Sources/Island/Controllers/IslandPanelController.swift`、`Sources/Island/Views/IslandOverlayView.swift`、`script/build_and_run.sh`。验证优先用 `swift run IslandCoreChecks` 和 `./script/build_and_run.sh --verify`。
- 2026-06-10：用户要求收回时不要 q 弹，避免看到摄像头本体；同时去掉黑色转白色的渐变背景。后续视觉规则：展开可保留 Boring Notch 风格 q 弹，收回必须快速无弹性且不能压缩小于 `245×32`；默认态和展开态都不绘制 camera housing 内部高光，也不使用黑到白渐变或大阴影。当前预览版本为 v14，展示默认态和展开态两张静态效果图。
- 2026-06-10：用户要求默认态上边直角与展开态上边圆角统一，并明确 App 不可拖动、固定在刘海位置。当前实现：`NotchMetrics.topCornerRadius = 16`，默认态和展开态共用上边圆角；`IslandPanelController` 设置 `panel.isMovable = false` 和 `panel.isMovableByWindowBackground = false`，没有添加任何拖动手势。当前预览版本为 v15。
- 2026-06-10：用户反馈顶部灵动岛出现“鬼畜”抖动，并担心收起态挡住下方应用点击。已确认根因是 SwiftUI `onHover` 在改变真实 `NSPanel` 尺寸时反复触发进出事件。修复规则：展开/收回事件由 AppKit `IslandTrackingHostingView` 的 `mouseEntered/mouseExited` 单源控制；`IslandPanelController` 持有 `IslandOverlayState`，SwiftUI 只渲染状态和动画；收起真实窗口保持 `245×32`，展开真实窗口保持 `640×190`；展开内容保留，状态点仍在摄像头右侧。二次修正：关闭时不能先把真实窗口缩到 `245×32`，否则 SwiftUI 内容会被裁切导致错位；必须先在 `640×190` 大画布里快速直收，约 `0.13s` 后再缩回真实窗口。当前预览版本为 v16。
- 2026-06-10：展开态内容必须在 `640×190` 内完整可见；当前 SwiftUI 内容已压缩内部间距和卡片高度，确保 `Island MVP` 标题、左右内容槽、`Running / Attention / Error` 三个状态 chip 都显示，不通过删除内容解决高度问题。
- 2026-06-10：用户要求默认态小圆点完整显示，同时保持之前认可的刘海圆角，不能把外壳改成胶囊。修复方式：恢复 `IslandShape` 原刘海肩部路径；默认态只把状态点移动到右侧可见肩部中心并略收外圈描边，外壳仍保持左 `30px` / camera `185px` / 右 `30px` 的等宽结构。以后遇到状态点裁切，优先调整点位和描边，不改外壳形状。
- 2026-06-10：用户明确不希望预览模式反复创建多个 localhost / 多个版本页，认为浪费资源。后续预览规则：只复用一个固定预览入口，优先覆盖同一个文件或直接用原生 App 截图验证；除非用户明确要求，不再新开 preview server、不再新建一堆 `vXX` 页面、不再让浏览器本地列表积累多个 localhost。旧预览进程已检查并停止，相关端口 `15721/7073/55149/7070/23333/49503` 当前无监听。
- 2026-06-10：用户要求展开态内容卡片和状态 chip 的边框内侧增加安全空白，并强制所有内部内容锁在安全区内，不只是文字，后续图标、图片、按钮等 UI 内容也不能碰到或越过边缘。用户指出 `1px` 效果不明显；当前实现改为 `contentGuardInset = 4pt`、`innerGuardInset = 4pt`。外层展开内容区域也按 `metrics.openTopCornerRadius + contentGuardInset` 缩进，避免标题、右上 capsule、内容卡、状态 chip 贴到外壳曲线边缘；`demoSlot` / `statusChip` 使用组件级 `guardedRoundedPanel`，内部 content 统一 padding + clip，再绘制 `strokeBorder`；右上角 capsule 使用 `GuardedCapsule`，保持内容自适应宽度并约束内部内容。
- 2026-06-10：用户要求状态点边缘有自然散发的模糊光，running/warning/error 三色都适用；展开时小圆点要随展开动画从默认右侧位置沿用户标记方向向右移动，不能瞬移或死板。当前实现：`StatusDotView` 使用多层圆形 blur halo，不使用 `drawingGroup()`，避免矩形暗块；状态点颜色来自 `IslandStatus.color`，三色共用同一光效；`IslandOverlayView` 中展开态目标为 `expandedStatusDotX`，位置变化绑定 `interactiveSpring(response: 0.44, dampingFraction: 0.76)`，随展开状态同步移动。
- 2026-06-10：用户用实拍指出默认态状态点仍会被物理刘海吃掉，并要求任何布局修改都要先调取本机原始数据验证。当前本机数据仍为 `1512×982`、`2x`、`safeAreaInsets.top=32`、camera gap `x=663...848`、默认窗口 `245×32`。修复规则：默认态和展开态状态点大小必须一致，均使用 `10pt` 可见光晕；默认中心锁定在本地 `(222,16)`，外圈本地 `x=217...227`，屏幕 `x=850.5...860.5`，离物理刘海右边界 `x=848` 留约 `2.5pt`；展开态目标本地 `(575,16)`，窗口为 `640×190`。`StatusDotView` 的 blur/shadow 必须裁在自己的 halo 边界内，不能让默认态光效越过模型给出的安全圈。
- 2026-06-10：用户重新定义底部圆角区域修复：不是把底部 chip 大幅上移，而是让底部内容和外壳内边缘保持约 `2pt` 安全贴合距离。当前修复规则：不要改外壳圆角，不删展开内容；把展开内容高度做成 `NotchMetrics` 的可测试模型，顶部占位 `30pt`、区块间距 `6pt`、header `30pt`、内容卡 `86pt`、状态 chip `24pt`、底部 inset `2pt`、横向内容 padding `22pt`。状态 chip 下边缘为 `y=188`，展开外壳底部为 `y=190`，左右底部圆角附近也按曲线计算保持约 `2pt` 内距。
- 2026-06-10：用户要求展开态小圆点移动到截图红色箭头指向的红圈位置，并且展开/默认小圆点大小和垂直位置一致；收回默认态时允许小回弹，但不能被刘海遮挡。该阶段曾采用只向右的安全回弹；后续已更新为当前单方向目标点位动画规则。
- 2026-06-10：用户要求只把小圆点样式回退到上一版柔光状态点，位置、大小、安全区和展开动画全部保持当前方案。当前实现改为 `StatusDotSoftGlowStyle` 可测参数；`StatusDotView` 恢复多层柔光、ring、core shadow 和低透明高光；小圆点位移规则以后续惯性记录为准。
- 2026-06-10：用户重新调整小圆点位移动画：不要“左-右-左”往返回弹，要方向明确的目标点位动画。当前实现：移除 `statusDotInertiaOffset`、惯性 work item 和所有 left/right offset；`NotchMetrics.statusDotDirectionalOvershootOffset = 0` 用于测试无反向 overshoot；`IslandOverlayView` 的小圆点使用单方向 timing curve，展开只向右到 `(615,16)`，收回只向左到 `(222,16)`，外壳尺寸、内容布局、小圆点大小和最终安全点位不变。
- 2026-06-10：用户选择先做“数据功能”静态 MVP，只看效果和 UI，不做实时数据采集或后台刷新。该阶段新增 `DataPanelMode` 和 `DataPanelView`，三种英文模式为 `Trends` / `Overview` / `All`，默认 `All`；曾使用静态 mock 数据。后续用户要求真实有效后，数据面板已改为读取本机 Codex 会话日志。
- 2026-06-10：用户要求把数据面板右上角的 `Trends / Overview / All` 切换控件移动到左侧 `Data` 标题旁边，并整体缩小一点。当前实现：`DataPanelView.header` 中 `Data` 后直接放 `modeControl`，三段按钮宽度分别为 `43/55/34pt`，高度 `18pt`，不再放在右上角；主体趋势图、统计卡片、热力图和外壳规则不变。
- 2026-06-10：用户要求 `Overview` 模式里的布局不要靠左，能铺平就铺平，不能铺平再居中。该阶段曾短暂把 `Overview` 热力图按宽高分别拉伸为长方形，但后续用户明确认为不美观；此规则已被后续真实日期日历热力图取代。
- 2026-06-10：用户进一步要求 `All` 和 `Overview` 的热力图保持同样布局，不要一个矩形拉伸、一个正方形；并允许展开态稍微放大以适配数据。该阶段曾固定为参考图风格的 `26×7` 正方形格子；后续用户明确要求不要固定 mock 格子，此规则已被后续真实日期日历热力图取代。展开态尺寸仍为 `700×230`，该阶段状态点仍在右侧；后续已被左侧状态点规则取代。
- 2026-06-10：用户要求热力图改为真实日期日历热力图，不要固定 mock 格子。当前实现新增 `CalendarHeatmap`、`UsageHeatmapRecord`，并已升级为 `StatsTimeRange`：每个可见格子代表用户时区内的真实自然日，列为 week、行为 weekday；`Today / 7d / 30d / All` 是 Stats 统一时间范围；周首和周末 padding 会补齐但 `date == nil`，不代表数据；真实日期无数据显示低亮灰色，有数据时按 tokens/cost/requests 三者归一化最大强度变蓝；格子永远按正方形渲染，不再拉伸成长方形。后续已接入本机 Codex 会话日志作为真实数据源。
- 2026-06-10：用户要求把小圆点放到左边同样的位置，展开状态也一样，并把动画方向反过来。当前实现：`NotchMetrics.closedStatusDotCenterX = 23`，`expandedStatusDotCenterX = 25`，状态点保持 `10pt` 和 `y=16`；局部坐标只小幅变化，但由于展开窗口从中心放大，屏幕空间会从默认左槽向展开外壳左侧移动，收回时反向回到默认左槽。`IslandOverlayView` 沿用单方向 timing curve，不增加回弹、不改热力图和数据面板布局。
- 2026-06-10：用户要求完善 `Trends / Overview / All`，让功能真实有效。当前实现新增 `CodexUsage.swift` 和 `CodexUsageDataSource.swift`：App 每 30 秒后台读取 `~/.codex/sessions/**/*.jsonl`，解析 `event_msg.payload.type == token_count` 的 `info.last_token_usage` 作为请求级增量，聚合 tokens、requests、active days、每日 trend points 和真实日期 heatmap records。`Trends` 使用真实 tokens / estimated cost / requests 曲线；`Overview` 使用真实汇总卡片和真实日期热力图；`All` 叠加两层真实数据。日志没有账单金额字段，`EST COST` 使用本地估算公式，不等同于真实账单。
- 2026-06-10：用户要求实现任务呼吸动效，只改状态点动效和任务活动状态，不改外壳尺寸、刘海安全区、点位或数据面板。当前实现新增 `TaskActivityState` / `StatusDotBreathingProfile` 和占位 `TaskActivityDataSource`；`StatusDotView` 仍是单个视图，展开/收回只改变 position，呼吸相位不会因展开/收回重新创建；默认 `idle` 静止，`running/warning/error` 只驱动外层柔光圈。
- 2026-06-10：用户要求 `Trends` 曲线参考使用统计截图，包含 tokens/cost/requests 和时间显示，并让 `All / 30d / 7d` 的功能区参考截图布局。当前实现新增 `UsageTrendTimeline.swift`，`CodexUsageSummary` 增加 `trendRecords`；`Trends` 画真实时间序列曲线、双 y 轴和 `MM/dd HH:mm` x 轴标签，`Overview` 热力图也复用同一范围状态。
- 2026-06-10：用户要求调整展开态顶部控制区层级，只改数据面板顶部控制区。当前实现新增 `IslandFeature`，右上角一级切换为 `Status / Stats / Tools`，默认 `Stats`；时间范围 `All / 30d / 7d` 和 `30s` 刷新状态移动到左侧 `Trends / Overview / All` 下方；`Status` 和 `Tools` 目前是占位内容。`Overview > All` 改为最近约 6 个月 heatmap，不再表示全部历史。
- 2026-06-10：用户要求继续完成任务活动状态接入，不能让占位数据源永远 `idle`。当前实现：`TaskActivityState(debugValue:)` 只接受显式 `idle/running/warning/error`；`FileBackedTaskActivityDataSource` 读取本地状态文件；`IslandPanelController` 每秒轮询数据源并只在状态变化时更新 overlay；新增 `script/set_task_activity.sh` 作为本地可测试入口。已验证真实 App 运行中可从 `idle` 切到 `running`，再切回 `idle`。
- 2026-06-10：用户要求微调 Stats 顶部时间范围/刷新控件和一级功能切换稳定性。当前实现：`DataPanelView.header` 抽出固定的 `FeatureSwitcher(selection:)`，始终位于右上角固定 header 层；`Stats` 左侧控制区使用同一个垂直控制栈，上排 `Trends / Overview / All`，下排左对齐为 `30s` + `Today / 7d / 30d / All`，不再用硬编码大缩进。
- 2026-06-10：用户要求 Stats 时间范围新增 `Today` 并让 Calendar 下方摘要卡片随范围同步。当前实现：新增 `StatsTimeRange`，顺序 `Today / 7d / 30d / All`；`Today` 按用户本机时区当前自然日计算，`All` 仍是最近约 6 个月；`CodexUsageSummary` 保留事件级数据并提供 `filtered(range:today:calendar:)`，摘要卡片、趋势图和 heatmap 共用同一个 `statsTimeRange`；Calendar 下方 metric tile 已缩小高度、字体和 padding。
- 2026-06-10：用户再次要求缩小 Calendar 下方卡片。当前实现进一步压缩 `DataPanelView.statCard`：卡片高度 `28pt -> 23pt`，label `6.6pt -> 5.8pt`，value `10.5pt -> 9.4pt`，水平 padding `6pt -> 5pt`；`overviewLayer` 间距 `6pt -> 4pt`，Calendar 标题行 `16pt -> 13pt`，grid spacing `5pt -> 4pt`，外层 padding `7pt -> 6pt`。真实 App 已验证 All 和 Today 下文字完整显示，无贴边或溢出。
- 2026-06-10：用户指出一级功能切换在不同类别间仍上下移动。已确认根因是 `DataPanelView.header` 的 `.frame(height: 50)` 默认居中：`Stats` 有两行左侧控件，高度接近 50；`Status/Tools` 只有一行，内容被居中后下移约 9pt。当前修复为 `.frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .top)`；真实 App AX 坐标验证三页均为 `Status x=943 y=34`、`Stats x=994 y=34`、`Tools x=1039 y=34`。
- 2026-06-10：用户反馈看不到小圆点呼吸。已确认两点：本地状态文件默认是 `idle`，按规则不会呼吸；同时旧 running 外层光源只有 halo 的约 `0.58`，几乎被中心点盖住。当前修复：核心检查新增“breathing glow reaches visible halo edge”，`StatusDotSoftGlowStyle.previousSoftGlow` 的 `outerSourceDiameter` 提升到 halo 的约 `0.82`，中心点大小、状态点位置和 `10pt` 安全裁剪不变。真实 App 已切到 `running` 方便直接观察。
