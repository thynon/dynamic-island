# AGENTS.md

## 项目概述

为 **MacBook notch / 非 notch 显示器** 打造的 **Dynamic Island** 式桌面应用。纯黑药丸外壳与物理 camera housing 视觉融合，当前主线聚焦：

- 默认/音乐播放态的顶部灵动岛外壳
- 音乐播放信息、专辑图、条纹波形、左右滑切歌反馈
- 展开态临时 File Shelf overlay
- 显示器尺寸/刘海适配与交互日志

- **不是** Vibe Island 功能复刻——`.reference/vibe-island/` 仅用于学习外壳、布局和动效
- AI 会话监控、hook、socket、审批、终端跳转、SSH、更新等功能**不能自动纳入**，除非用户明确选择

**技术栈**: SwiftPM · macOS 14+ · Swift 6 · AppKit + SwiftUI
**参考栈**（仅查阅）: Tauri v2 · Rust · React 19 · TypeScript · Tailwind · Framer Motion · Zustand

---

## 构建与测试命令

```bash
# 核心检查（每次改动后必须跑）
swift run DynamicIslandCoreChecks

# 编译主程序
swift build --product DynamicIsland

# 构建 + 签名 + 打包 + 启动（唯一运行入口）
./script/build_and_run.sh

# 启动后检查进程健康
pid=$(pgrep -x DynamicIsland | head -n 1)
ps -o pid,stat,pcpu,pmem,etime,command -p "$pid"

# 调试音乐状态 / 左右滑反馈（显式 debug 模式）
./script/build_and_run.sh --debug-music-signal
ISLAND_DEBUG_MUSIC_SIGNAL_FILE=/tmp/dynamic-island-music-signal.json ./script/send_music_signal.sh playing

# 查看应用日志
./script/build_and_run.sh --telemetry
```

- 每次修改核心行为后至少运行 `swift run DynamicIslandCoreChecks`
- 涉及可执行 App 时追加 `swift build --product DynamicIsland` 和 `./script/build_and_run.sh`
- 不能跑的命令要明确说明原因，不要假装通过
- 修改动效或波形后建议检查 CPU；稳定空闲状态不应长期高占用

---

## 项目结构

```
Package.swift
Sources/
  DynamicIslandCore/            # 纯逻辑层，无 UI 依赖
    NotchMetrics.swift         #   刘海/外壳/安全边界尺寸真相源
    DisplayProfile.swift       #   显示器类型和缩放配置
    IslandTopStatusBandLayout.swift  #   展开态顶部 32pt 区域合同
    IslandAnimationProfile.swift     #   统一动画参数
    TemporaryFileShelf.swift   #   临时文件架纯模型、分类、筛选、选择
  DynamicIsland/               # AppKit + SwiftUI UI 层
    Controllers/
      IslandPanelController.swift  #   NSPanel + 展开/收起 + 手势 + 轮询
    Views/
      IslandOverlayView.swift        #   主视图（黑底 ZStack + 音乐态 + File Shelf overlay）
      ClosedMusicAvatarView.swift    #   收起音乐态专辑图
      ClosedMusicWaveformView.swift  #   收起音乐态条纹波形（Core Animation layer）
      TemporaryFileShelfView.swift   #   展开态临时文件架 overlay
      IslandTrackingHostingView.swift #  鼠标、滚动、拖放入口
    Support/
      MusicPlaybackDataSource.swift  #   Music/Spotify 播放状态和切歌命令
      TemporaryFileShelfStore.swift  #   内存 File Shelf store
      IslandInteractionLogger.swift  #   每次启动的 JSONL 交互日志
      ScreenMetricsProvider.swift    #   显示器/刘海尺寸派生
      DisplayProfileStore.swift      #   显示器配置缓存
      DebugMusicSignal.swift         #   显式 debug 音乐信号
Tests/DynamicIslandCoreChecks/main.swift  #   回归检查入口
script/build_and_run.sh             #   构建 + 签名 + 打包 + 启动
script/send_music_signal.sh         #   debug 音乐信号发送
```

---

## 必须遵守的硬约束

### 外壳与布局
- MacBook Pro camera housing 是**物理不可显示区域**——文字、图标、按钮、交互热点必须避开
- 收起态尺寸由 `NotchMetrics` 和当前显示器配置派生，不新增散落硬编码
- 展开态顶部 32pt 带分为 **左安全区 → camera 禁区 → 右安全区**（合同由 `IslandTopStatusBandLayout` 定义）
- 所有顶部元素通过 `IslandTopStatusBandLayout` 放置，不能随意移动
- 尺寸优先用 `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`，不要新增长期硬编码
- UI、文字、图标、拖放边界默认遵守 5pt 约束；圆角和 camera housing 附近需要使用现有 metrics/layout 合同

### 音乐态与手势
- 默认/无音乐不显示音乐附件，不跑持续动画
- 音乐态专辑图是静态圆角图；条纹波形使用低开销 Core Animation layer
- 左右滑切歌必须先进入 armed 状态，支持回滑取消；真实触控板 phase 手势等 `.ended` 后才提交
- 隐藏态优先级最高，只允许下滑恢复，不允许 hover、点击、左右切歌

### File Shelf
- 只是临时文件架：保存文件 URL 引用，不复制、不持久化、不上传、不申请额外权限
- 支持拖入、分类筛选、选择、多文件拖出；重启后为空
- File Shelf 是独立 overlay，不作为一级 tab；Done 关闭 overlay，Clear 才清空文件

### 日志
- 每次启动创建 `~/Library/Logs/DynamicIsland/session-*.jsonl`
- 日志可以记录启动、显示器指标、展开/隐藏、手势、音乐、File Shelf 事件
- 文件日志只能写脱敏信息：扩展名、类别、名称长度、路径指纹；不能写原始路径/文件名

---

## 代码风格

- **匹配周围代码**：命名、注释密度、错误处理、测试风格
- **最小改动**：不顺手重构、重命名、格式化未触及代码
- **复用优先**：先用已有 helper/组件/模式
- **不推测性抽象**：不处理未出现的边界情况
- **DynamicIslandCore** = 纯逻辑层，无 AppKit/SwiftUI import
- **DynamicIsland** = UI 层，通过 `@Published IslandOverlayState` 驱动
- **动画参数**统一走 `IslandAnimationProfile.default`，不硬编码
- **测试**用 `expectEqual()` + 字符串源码检查 + 数值断言
- 用中文沟通

---

## 安全
- 不提交 secrets / tokens / keys / credentials
- `.env*` 视为敏感文件
- codesigning 优先 `ISLAND_CODESIGN_IDENTITY` 环境变量，回退本地 identity，最后 ad-hoc
- 不默认请求 ScreenCaptureKit / 系统音频权限

---

## 完成前检查清单

- [ ] 核心行为变更后，`swift run DynamicIslandCoreChecks` 通过
- [ ] 涉及可执行 App 时，`swift build --product DynamicIsland` 通过
- [ ] UI/布局变更时，`./script/build_and_run.sh` 确认
- [ ] 修改动效、波形或轮询后，检查 DynamicIsland 进程 CPU 没有长期高占用
- [ ] 未破坏顶部 32pt 布局合同
- [ ] 未引入默认自动动画
- [ ] 核心约束变更已记入 `MEMORY.md`

---

## 何时停下来问

- 新增功能（本项目功能由用户逐项选择）
- 添加生产依赖或新 framework
- 涉及 TCC 权限（ScreenCaptureKit / Apple Events / Microphone）
- 修改数据库、持久化数据、公共 API、CI/构建管道
- 多个方案难判优劣

---

## 常见陷阱

| 陷阱 | 后果 |
|------|------|
| 恢复 ECG/心跳波形 | 已明确移除 |
| 折叠态跑持续动画 | CPU 飙高 + hover 卡顿 |
| 默认启用屏幕采集 | 菜单栏共享指示器 |
| 硬编码刘海尺寸 | 多屏/外接显示异常 |
| 绝对时间当 beat index | 每帧亿次级运算 |
| 照搬 Vibe Island 功能 | 偏离项目定位 |
| 把 File Shelf 做成文件管理器 | 偏离临时文件架范围 |
| 隐藏态仍允许 hover/点击/切歌 | 用户无法预测交互状态 |

---

## 任务完成汇报格式

```
## 改动
- 文件: 变更内容

## 验证
- swift run DynamicIslandCoreChecks: 通过/失败
- swift build --product DynamicIsland: 通过/失败
- CPU: x%

## 未运行
- 无法运行的检查及原因

## 风险/后续
- 需要注意的点
```

---

## 项目记忆

- 项目记忆文件：`MEMORY.md`，事件日志格式，类似 git log
- 记录决策/变更时更新 `MEMORY.md`，保留日期、原因、验证和回退说明
- 不把全局记忆当成本项目事实

---

## 相关文件

| 文件 | 用途 |
|------|------|
| `AGENTS.md` | 本文件——项目指令 |
| `MEMORY.md` | 项目事件记忆 |
| `AGENTS-01-结构与外壳与UI.md` | 参考项目外壳/UI 分析 |
| `AGENTS-02-功能与架构.md` | 参考项目功能/架构分析 |
| `AGENTS-03-分阶段计划.md` | 参考分阶段方法 |
| `docs/HANDOFF-2026-06-15.md` | 项目交接文档 |
| `docs/CODEX_GIT_WORKFLOW.md` | Codex + Git 协作流程 |
| `script/safe_git_save.sh` | 安全提交指定文件脚本 |
| `.reference/vibe-island/` | 参考源码（独立 git 仓库，v1.0.29） |
