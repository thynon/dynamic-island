# AGENTS.md

本目录是面向 14 寸 MacBook Pro 的灵动岛体验项目资料库。目标不是照搬 Vibe Island 的功能，而是深度学习它的窗口外壳、顶部布局、展开交互和整体框架，用来完善一款适配 MacBook Pro 14 寸无灵动岛缺口的软件。

## 项目记忆

- 项目内独立记忆文件是 `CX_MEMORY.md`。
- 本项目里的助手名字是 `cx`。每次面向用户回复都必须带上 `cx`，用于确认没有串记忆。
- 不要把全局记忆当成本项目事实；只有 `CX_MEMORY.md` 和本目录文档里的内容可作为本项目记忆来源。
- 需要更新项目记忆时，只更新 `CX_MEMORY.md`，并保留日期和原因。

## 项目方向

- 用户看重这个创意：用软件补足 MacBook Pro 14 寸没有灵动岛的体验缺口。
- `AGENTS-01/02/03` 是软件制作阶段资料和参考实现拆解，不是本项目的功能需求清单。
- 不要默认实现 AI 会话监控、hook、审批、socket、终端跳转、SSH、更新等功能。
- 功能添加必须由用户逐项选择；agent 只能主动参考框架、窗口、布局、动效、组件组织和视觉外壳。
- 讨论新功能时，先把它作为独立功能设计，不要从三份阶段文档里自动继承路线。

## 现有文件

- `Package.swift`：当前 MVP App 的 SwiftPM 入口，包含 `IslandCore`、`Island` 和 `IslandCoreChecks`。
- `Sources/IslandCore/`：可测试的刘海尺寸、展开尺寸、Stats 时间范围、真实日期热力图、Codex token 日志解析、usage 聚合模型和任务活动状态模型。
- `Sources/IslandCore/IslandFeature.swift`：展开态一级功能状态，当前为 `Status / Stats / Tools`，默认 `Stats`。
- `Sources/IslandCore/UsageTrendTimeline.swift`：把真实 usage 事件按 `Today / 7d / 30d / All` 聚合成小时或自然日趋势点，并输出带时间的 x 轴标签。
- `Sources/Island/`：原生 macOS SwiftUI/AppKit MVP；AppKit 控制顶部透明面板，SwiftUI 控制灵动岛外壳、动画和数据面板。
- `Sources/Island/Support/CodexUsageDataSource.swift`：读取本机 `~/.codex/sessions/**/*.jsonl`，解析 `token_count` 的 `last_token_usage`，为数据面板提供真实本机 usage 汇总。
- `Sources/Island/Support/TaskActivityDataSource.swift`：当前任务活动状态的可替换文件数据源；默认读取 `~/Library/Application Support/Island/task-activity-state.txt`，缺失或无效时返回 `idle`，不要把 Codex App 存在误判为 `running`。
- `script/set_task_activity.sh`：本地任务状态调试入口，可写入 `idle / running / warning / error`，用于验证状态点呼吸。
- `Tests/IslandCoreChecks/`：当前环境可运行的核心检查器；用 `swift run IslandCoreChecks` 验证关键尺寸逻辑。
- `script/build_and_run.sh`：构建、打包并启动 `dist/Island.app` 的唯一运行入口。
- `.reference/vibe-island/`：隐藏参考源码目录，当前可直接查实现细节。该目录是单独的 git 仓库，当前分支 `main`，已确认提交短哈希 `4c68977`，`package.json` / `Cargo.toml` 版本为 `1.0.29`。
- `AGENTS-01-结构与外壳与UI.md`：可重点参考项目结构、Tauri 窗口、药丸 UI、设计令牌、资源清单。
- `AGENTS-02-功能与架构.md`：只在需要理解参考项目架构时读取；其中功能不要默认纳入本项目。
- `AGENTS-03-分阶段计划.md`：只作为“制作阶段拆分方式”的参考；不要把里面的阶段当成本项目路线。

## 真相优先级

1. 本项目需求以用户当前明确选择为准。
2. 框架、布局、交互外壳可参考 `.reference/vibe-island/` 源码。
3. 三份 `AGENTS-*` 文档是整理版导航，适合快速理解，但功能与路线不能自动继承。
4. 若文档和用户方向冲突，用户方向优先。
5. 本目录根不是 git 仓库；`.reference/vibe-island/` 才是参考源码 git 仓库。

## 阅读路径

- 查精确代码：先到 `.reference/vibe-island/`。
- 做 UI/外壳/窗口：读 `AGENTS-01-结构与外壳与UI.md`，再查 `.reference/vibe-island/src/components/notch/` 和 `src-tauri/tauri.conf.json`。
- 做布局或组件组织：参考 `.reference/vibe-island/src/App.tsx`、`src/store/useStore.ts`、`src/components/`。
- 做新功能：先确认用户选择了该功能，再设计本项目自己的实现；不要直接照搬 `AGENTS-02` 或 `AGENTS-03` 的功能路线。
- 做任务拆分：可参考 `AGENTS-03-分阶段计划.md` 的“分阶段验收方法”，但阶段内容必须按用户选定功能重写。

## 核心事实

- 目标产品是适配 MacBook Pro 14 寸顶部区域的灵动岛式桌面软件。
- 当前第一阶段 MVP 选型为原生 macOS SwiftPM App，原因是先验证真实刘海安全区、无边框顶层面板和展开动画；Tauri 参考栈仍可作为后续产品化参考。
- 技术参考栈：Tauri v2、Rust、React 19、TypeScript、Tailwind v3、Framer Motion v11、Zustand v5。
- 现阶段最值得学习的是顶部悬浮窗口、纯黑药丸外壳、展开/收起动效、设置窗口和组件布局。
- MacBook Pro 刘海/camera housing 是不可显示内容的物理区域；黑色外壳可以与其视觉融合，但文字、图标、按钮和交互热点必须避开。
- 14 寸显示可用 Apple 官方规格作参考：14.2 英寸、3024×1964、254 ppi；真实避让不要长期硬编码，优先用 macOS `NSScreen.safeAreaInsets`、`auxiliaryTopLeftArea`、`auxiliaryTopRightArea` 等运行时信息。
- `snake_case`、SessionStatus、hook 协议、socket 审批闭环等只属于参考项目功能；除非用户选择相关功能，否则不要纳入本项目。
- 数据面板当前真实数据源是本机 Codex 会话日志 `~/.codex/sessions/**/*.jsonl`；tokens、requests、active days、趋势和热力图来自 `token_count.last_token_usage`。`Trends` 使用事件级趋势记录按 `Today / 7d / 30d / All` 生成时间轴曲线；日志没有真实账单金额字段，`EST COST` 是本地估算，不等同于账单。
- 展开态数据面板当前层级：右上角一级功能为固定 header 层 `Status / Stats / Tools`，默认 `Stats`，切换到 `Status` 或 `Tools` 时位置不能跳动；`DataPanelView.header` 必须使用固定高度且顶端对齐，不能用默认居中 frame；左侧 `Data` 旁边是 `Stats` 内部二级 `Trends / Overview / All`；二级控件下方左对齐放置 `30s` 刷新状态 + `Today / 7d / 30d / All` 时间范围。不要把时间范围/刷新控件放回右上角。
- `Overview` 的时间范围语义：`Today` 表示用户本机时区的当前自然日 00:00 到当前时间；`7d` 表示最近 7 个自然日；`30d` 表示最近 30 个自然日；`All` 表示最近约 6 个月的真实日期 calendar heatmap，不表示全部历史。周首/周末 padding 不代表数据。
- Calendar 下方四个摘要卡片是紧凑 dashboard metric tile：当前卡片高度约 `23pt`，label 约 `5.8pt`，value 约 `9.4pt`，水平 padding 约 `5pt`，用于给 heatmap 和后续细节预留更多空间；不要删除卡片内容，也不要让文字贴边或溢出。
- 任务呼吸动效当前只作用于状态点外层柔光圈；中心点大小、颜色、最终位置、外壳尺寸、刘海安全区和数据面板布局都不能随呼吸变化。`idle` 静止，`running/warning/error` 才按 `TaskActivityState` 的参数呼吸或轻脉冲。外层呼吸光源必须进入可见 halo 边缘区域，不能小到被中心点盖住；当前 `outerSourceDiameter` 为 halo 的约 `0.82`。
- 当前真实 Codex 任务检测尚未接入；App 通过 `FileBackedTaskActivityDataSource` 每秒轮询本地状态文件来支持可验证 demo。用 `./script/set_task_activity.sh running` 进入呼吸状态，用 `./script/set_task_activity.sh idle` 停止呼吸。
- 推荐实施顺序：先完成 14 寸 MacBook Pro 的窗口外壳、位置、尺寸、视觉和 mock 交互，再按用户选择逐个添加功能。
- `.reference/vibe-island/src/App.tsx` 当前会渲染 `OnboardingScreen`，并会根据 onboarding 状态调整 notch 窗口尺寸。
- `.reference/vibe-island/src/assets/` 当前存在品牌资源和声音资源；不要沿用旧文档里“无 src/assets / onboarding 未渲染 / 无打包音效”的说法，除非任务明确要求按旧版本复刻。

## 关键源码入口

- `.reference/vibe-island/src/App.tsx`：前端根组件、窗口 label 分流、onboarding、更新提示、审批快捷键、声音触发。
- `.reference/vibe-island/src/store/useStore.ts`：Zustand 状态源、Tauri invoke/listen、2 秒轮询兜底；只参考状态组织方式。
- `.reference/vibe-island/src/components/notch/NotchPanel.tsx`：药丸主 UI、展开/收起、右键菜单、会话列表。
- `.reference/vibe-island/src/components/approval/ApprovalCard.tsx`：权限审批与问答卡；仅在用户选择类似功能时参考。
- `.reference/vibe-island/src/components/settings/SettingsPanel.tsx`：设置窗口。
- `.reference/vibe-island/src-tauri/src/lib.rs`：Tauri command 注册、插件、窗口 setup、后台任务组织。
- `.reference/vibe-island/src-tauri/src/sessions/mod.rs`：参考状态机写法；不要默认采用 AI 会话模型。
- `.reference/vibe-island/src-tauri/src/socket/mod.rs`：仅在用户选择本地 IPC 功能时参考。
- `.reference/vibe-island/src-tauri/src/hooks/mod.rs`：仅在用户选择 AI 工具集成功能时参考。
- `.reference/vibe-island/src-tauri/src/platform/mod.rs`：平台信息与终端跳转。

## 工作规则

- 改文件前先确认当前目录内容，不要假设存在源码、git 仓库或依赖。
- 保持改动小而明确；若新增实现项目，先按“外壳/布局优先，功能由用户选择”的原则重写阶段计划。
- 不要问“严格复刻还是修复参考项目”；本项目默认不是复刻，只有框架和布局可深度学习。
- 遇到刘海尺寸、屏幕安全区、窗口定位问题时，先查 Apple 官方规格/API，再做视觉或代码判断。
- 验收时按阶段给出可执行证据：UI 截图、运行命令、窗口位置/尺寸检查、交互录屏或日志。socket/hook 等只在用户选择对应功能后验证。
