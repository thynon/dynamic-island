# AGENTS.md

## 项目概述

为 **14 寸 MacBook Pro** 打造的灵动岛式桌面应用。纯黑药丸外壳与物理 camera housing 视觉融合，在顶部 32pt 空间提供任务状态、音频波形和本机使用量数据面板。

- **不是** Vibe Island 功能复刻——`.reference/vibe-island/` 仅用于学习外壳、布局和动效
- AI 会话监控、hook、socket、审批、终端跳转、SSH、更新等功能**不能自动纳入**，除非用户明确选择

**技术栈**: SwiftPM · macOS 14+ · Swift 6 · AppKit + SwiftUI
**参考栈**（仅查阅）: Tauri v2 · Rust · React 19 · TypeScript · Tailwind · Framer Motion · Zustand

---

## 构建与测试命令

```bash
# 核心检查（每次改动后必须跑）
swift run IslandCoreChecks

# 编译主程序
swift build --product Island

# 构建 + 签名 + 打包 + 启动（唯一运行入口）
./script/build_and_run.sh

# 启动后检查进程健康
pid=$(pgrep -x Island | head -n 1)
ps -o pid,stat,pcpu,pmem,etime,command -p "$pid"

# 调试任务状态（短时覆盖，约 5 分钟后过期）
./script/set_task_activity.sh idle|running|warning|error

# 查看应用日志
./script/build_and_run.sh --telemetry
```

- 每次修改核心行为后至少运行 `swift run IslandCoreChecks`
- 涉及可执行 App 时追加 `swift build --product Island` 和 `./script/build_and_run.sh`
- 不能跑的命令要明确说明原因，不要假装通过
- 修改动效或波形后建议检查 CPU；稳定空闲状态不应长期高占用

---

## 项目结构

```
Package.swift
Sources/
  IslandCore/                  # 纯逻辑层，无 UI 依赖
    NotchMetrics.swift         #   刘海尺寸真相源（收起 245×32，展开 700×230）
    IslandTopStatusBandLayout.swift  #   展开态顶部 32pt 区域合同
    IslandAnimationProfile.swift     #   统一动画参数
    TaskActivityState.swift    #   6 种任务状态 + 呼吸动效 + Codex 事件解析
    AudioPlaybackState.swift   #   波形状态（.idle / .audioLevels，无 ECG）
    CodexUsage.swift           #   Token 解析 + 成本估算 + Summary
    CalendarHeatmap.swift      #   热力图（Today/7d/30d/All）
    UsageTrendTimeline.swift   #   趋势时间线（小时/天分桶）
    DataPanelMode.swift        #   二级模式（Trends/Overview/All）
    ...
  Island/                      # AppKit + SwiftUI UI 层
    Controllers/
      IslandPanelController.swift  #   NSPanel + 展开/收起 + 轮询
    Views/
      IslandOverlayView.swift  #   主视图（黑底 ZStack + 展开内容）
      StatusDotView.swift      #   状态点（Core Animation 柔光呼吸）
      AudioWaveformView.swift  #   波形（Canvas + TimelineView）
      DataPanelView.swift      #   数据面板（趋势图 + 热力图 + 摘要）
    Support/
      CodexUsageDataSource.swift     #   用量（优先 CC Switch → 回退 JSONL）
      CCSwitchUsageDataSource.swift  #   CC Switch SQLite
      TaskActivityDataSource.swift   #   任务状态（JSONL 事件检测）
      AudioPlaybackDataSource.swift  #   音频源（AppleScript / SCK / Core Audio Tap）
Tests/IslandCoreChecks/main.swift  #   回归检查入口
script/build_and_run.sh             #   构建 + 签名 + 打包 + 启动
```

---

## 必须遵守的硬约束

### 外壳与布局
- MacBook Pro camera housing 是**物理不可显示区域**——文字、图标、按钮、交互热点必须避开
- 收起态：camera housing `185×32`，左右槽各 `30pt`，外壳 `245×32`
- 展开态：外壳 `700×230`，顶部 32pt 带分为 **左状态区 → camera 禁区 → 右信息区**（合同由 `IslandTopStatusBandLayout` 定义）
- 所有顶部元素通过 `IslandTopStatusBandLayout` 放置，不能随意移动
- Stats header 层级固定：右上角 `Status / Stats / Tools`（默认 Stats），左侧 `Trends / Overview / All`，下方 `30s` + `Today / 7d / 30d / All`
- 尺寸优先用 `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`，不要新增长期硬编码

### 状态点
- **只允许外层柔光呼吸**；中心点大小、位置、外壳尺寸不随呼吸变化
- `idle` → 不呼吸；`thinking/running/compacting` → 绿色呼吸；`warning` → 黄色慢呼吸；`error` → 红色快脉冲

### 音频波形
- **默认/无音乐 = 静态横线**，不能有任何自动动画
- 不恢复 ECG、heartbeat、scan head
- 折叠态暂停波形动画：`visibleAudioPlayback = isExpanded ? state.audioPlayback : .idle`
- 默认不启用 ScreenCaptureKit（避免菜单栏共享指示器）；`ISLAND_REAL_AUDIO_WAVEFORM=1` / `ISLAND_CORE_AUDIO_TAP_WAVEFORM=1` 是显式 opt-in

### 使用量数据
- 优先 `~/.cc-switch/cc-switch.db` → 回退 `~/.codex/sessions/**/*.jsonl`
- 不把 Claude session 日志合并进 Codex 统计
- `Today` = 本机时区当前自然日；`7d`/`30d` = 最近 N 个自然日；`All` = 最近约 6 个月

### 任务状态检测
- 默认 `CodexTaskActivityDataSource`（读 JSONL `payload.type`），不是进程名检测
- `task-activity-state.txt` 只是 `script/set_task_activity.sh` 的短时覆盖（5 分钟过期）

---

## 代码风格

- **匹配周围代码**：命名、注释密度、错误处理、测试风格
- **最小改动**：不顺手重构、重命名、格式化未触及代码
- **复用优先**：先用已有 helper/组件/模式
- **不推测性抽象**：不处理未出现的边界情况
- **IslandCore** = 纯逻辑层，无 AppKit/SwiftUI import
- **Island** = UI 层，通过 `@Published IslandOverlayState` 驱动
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

- [ ] 核心行为变更后，`swift run IslandCoreChecks` 通过
- [ ] 涉及可执行 App 时，`swift build --product Island` 通过
- [ ] UI/布局变更时，`./script/build_and_run.sh` 确认
- [ ] 修改动效、波形或轮询后，检查 Island 进程 CPU 没有长期高占用
- [ ] 未破坏顶部 32pt 布局合同
- [ ] 未引入默认自动动画
- [ ] 未合并 Claude 数据到 Codex 统计
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
| Claude 日志合并到 Codex 统计 | 数据污染 |
| 进程名检测任务状态 | 永远呼吸不停 |
| 硬编码刘海尺寸 | 多屏/外接显示异常 |
| 绝对时间当 beat index | 每帧亿次级运算 |
| 照搬 Vibe Island 功能 | 偏离项目定位 |
| 移动 Stats header 层级 | 布局已被多次调优 |

---

## 任务完成汇报格式

```
## 改动
- 文件: 变更内容

## 验证
- swift run IslandCoreChecks: 通过/失败
- swift build --product Island: 通过/失败
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
