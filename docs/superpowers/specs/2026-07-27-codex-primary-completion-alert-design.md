# Codex 主会话完成三连提醒设计

## 背景

Dynamic Island 已能从本地 Codex state database 和 rollout JSONL 读取主会话、
子代理、活动状态与显式终态事件，但会话成功完成时没有独立的系统级提醒。
用户希望在主会话完成后得到一次明确、短促、低开销的三连反馈：

1. 收起且可见的灵动岛复用现有 hover 视觉，脉冲 3 次；
2. 每次视觉脉冲开始时同步播放一次 macOS 当前默认提示音，共 3 次。

本设计只新增完成反馈，不改变 Tasks 列表、会话保留时间、展开行为、隐藏行为、
审批流程或 Codex 数据读取方式。

## 已确认的产品决策

- 只对**主会话成功完成**提醒。
- 子代理成功完成不提醒。
- 取消、中止和失败不提醒。
- App 启动时已经完成的历史会话不提醒。
- 同一次状态刷新中多个主会话成功完成，合并为一组三连提醒。
- 三连正在播放时又观察到新的主会话完成，合并进当前提醒，不追加第二组三连。
- 灵动岛收起且可见时，hover 视觉和默认提示音同步 3 次。
- 灵动岛展开或隐藏时不强制改变状态，只播放 3 次提示音。
- 文件拖放或滑动手势正在占用视觉反馈时不抢占视觉，只播放提示音。
- 使用 macOS 当前默认提示音，不硬编码 `Glass` 等具体声音，不新增声音资源。

## 非目标

- 不提醒子代理完成。
- 不为取消、失败或中止设计另一套提示。
- 不发送通知中心横幅或角标。
- 不自动展开、收起、恢复或显示灵动岛。
- 不创建持久通知队列，不在下次启动补播错过的完成事件。
- 不增加 TCC 权限、系统音频捕获或第三方依赖。
- 不增加永久 Timer、`repeatForever` 或空闲持续动画。
- 不把完成反馈接入音乐、File Shelf、Data 查询或审批完成事件。

## 终态数据模型

### 明确区分终态结果

在 `DynamicIslandCore` 中新增：

```swift
public enum CodexTurnTerminalOutcome: String, Equatable, Sendable {
    case completed
    case aborted
    case cancelled
    case failed
}
```

`CodexTaskStatus` 增加可选的 `terminalOutcome`。现有 `completedAt`、`turnID`、
`activityState`、`progressEvents` 和 10 秒完成行保留规则继续存在。

`CodexStatusSignalSource.RolloutState` 同样保存可选的 `terminalOutcome`：

- `task_complete` 和 `turn/completed` → `.completed`
- `turn_aborted` 和 `turn/aborted` → `.aborted`
- `turn_cancelled` 和 `turn/cancelled` → `.cancelled`
- `turn_failed` 和 `turn/failed` → `.failed`

所有终态仍复用现有 `completeTurn` 流程，继续写入 `completedAt`、duration、
`.terminal` lifecycle、`.idle` activity 和 completion progress event。
`task_started` 必须清除上一轮的 `terminalOutcome`、`completedAt` 和其他终态字段，
避免旧终态污染新 turn。

### 完成身份

成功完成身份由以下字段组成：

1. thread ID；
2. 有值时使用 turn ID；
3. 缺少 turn ID 时使用毫秒精度的 `completedAt`。

普通 `.idle`、SQLite `updated_at`、rollout 文件修改时间和 60 秒 stale 隐藏都不是
成功完成身份，也不能触发提醒。

## 纯逻辑完成追踪器

在 `DynamicIslandCore` 增加一个小型可变状态机
`CodexPrimaryCompletionTracker`。它消费 `[CodexTaskStatus]`，返回本次新观察到的
主会话成功完成数量。

规则：

1. 第一次消费包含任务的有效 snapshot 只建立完成身份基线，返回 `0`；启动阶段的
   空任务或 unavailable snapshot 不提前完成基线。
2. 只检查 `parentThreadID == nil` 的主会话。
3. 只接受 `terminalOutcome == .completed`。
4. 同一完成身份只返回一次。
5. 同一批有多个新身份时返回其数量，由控制器合并成一组三连。
6. 同一 thread 的下一轮 turn 使用新身份，可以再次返回。

追踪器不依赖 AppKit、SwiftUI、文件系统或时间轮询，便于通过纯 Core 数值断言覆盖
基线、过滤、去重和批处理边界。

## 控制器调度

`IslandPanelController.startCodexStatusPolling()` 继续是唯一实时状态轮询入口。
每次得到新 snapshot 后：

1. 让 `CodexPrimaryCompletionTracker` 消费 `snapshot.tasks`；
2. 照常发布 `overlayState.codexStatusBarSnapshot`；
3. 若 tracker 返回的数量大于 `0`，启动一次完成反馈；
4. 若已有反馈任务运行，记录这些身份已观察，但不启动或排队第二组反馈。

控制器新增一个可取消的有限 `Task<Void, Never>`。任务只执行 3 个节拍：

```text
beat 1: 默认提示音 + hover pulse on -> pulse off
beat 2: 默认提示音 + hover pulse on -> pulse off
beat 3: 默认提示音 + hover pulse on -> pulse off
结束: completion pulse state = false
```

每个节拍约间隔 0.6 秒。脉冲激活时间和节拍间隔必须集中在
`IslandAnimationProfile.default`，不能在 View、Controller 和测试中散落不同数值。

声音通过 `NSSound.beep()` 播放，遵循用户当前的 macOS 默认提醒音和系统音量。
系统静音或提醒音不可用时不绕过系统设置；视觉序列仍正常结束。

有限任务使用统一清理路径把视觉状态恢复为 `false`；控制器析构时取消任务。
Controller 生命周期结束后 UI 同步销毁，不留下 Timer、轮询或动画源。

## 视觉状态与优先级

`IslandOverlayState` 新增独立的完成脉冲布尔状态。它不复用、不覆盖
`isHovered`，因此真实鼠标进入、离开和精确 shell path 命中逻辑保持不变。

`IslandOverlayView` 将完成脉冲并入现有 hover 视觉：

- 正常动态效果：复用 1.035 scale、轻阴影和顶部锚点；
- Reduce Motion：scale 保持 1，仅让现有 hover 阴影淡入淡出；
- 展开或隐藏：View 的现有状态门禁阻止完成脉冲可见；
- 文件拖放或滑动手势占用反馈：该组三连从开始时就标记为 sound-only；
- 用户本来已经 hover：不强制把真实 hover 闪灭；提示音仍准确播放 3 次。

视觉资格在一组三连开始时捕获：

```text
closed
AND visible
AND no file-drop visual
AND no active/armed music-skip gesture
```

若开始时不满足，整组三连只播放声音。反馈不会在状态恢复后补播陈旧动画。
若开始时满足但用户中途展开或隐藏，现有 View 门禁立即抑制后续视觉，声音继续完成
3 次。

## 并发与合并

- 同一 snapshot 内多个主会话完成：一组三连。
- 三连运行期间的新完成：合并进当前组，不重启、不延长、不排队。
- 三连结束后的新完成：新的三连。
- 子代理无论单独或与主会话同时完成，都不增加提醒次数。
- 重复轮询同一完成行不触发。
- App 首次 snapshot 中的完成行只进入基线。

## 日志与隐私

新增脱敏事件：

- `codex.completion.feedback.started`
  - `primaryCompletionCount`
  - `visualEnabled`
- `codex.completion.feedback.coalesced`
  - `primaryCompletionCount`
- `codex.completion.feedback.finished`
  - `beatCount`

不得记录 thread ID、turn ID、标题、路径、提示内容或 agent 名称。

## 测试策略

### TDD / Core

为 `CodexPrimaryCompletionTracker` 覆盖：

1. 首个 terminal snapshot 只建基线；
2. running → successful completion 只返回一次；
3. 重复 terminal snapshot 返回 0；
4. aborted / cancelled / failed 返回 0；
5. 子代理 successful completion 返回 0；
6. 两个主会话同批完成返回 2，但控制器只启动一组反馈；
7. 同一主会话不同 turn ID 可分别完成；
8. 无 turn ID 时使用 completedAt 去重；
9. stale/idle 且无明确 successful outcome 不触发。

### 源码合同

`DynamicIslandCoreChecks` 同时锁定：

- parser 对四种 terminal outcome 的映射；
- `task_started` 清除旧终态；
- Controller 首帧基线与有限 3 次循环；
- `NSSound.beep()` 是唯一声音调用；
- 运行中反馈执行合并而非排队；
- Overlay 使用独立脉冲状态并保留展开、隐藏、拖放和手势门禁；
- 动画时长来自 `IslandAnimationProfile.default`；
- deinit 取消任务；
- 日志字段保持脱敏。

### 构建与运行

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
./script/build_and_run.sh
git diff --check
```

真实运行验收：

1. 冷启动不对已有完成会话提醒；
2. 一个主会话成功完成后出现 3 次 hover 脉冲和 3 次默认提示音；
3. 子代理完成没有任何提醒；
4. 主会话取消或失败没有提醒；
5. 展开或隐藏时主会话完成只响 3 次，不改变 shell 状态；
6. 同批多个主会话完成只有一组三连；
7. 提醒结束后无残留视觉状态；
8. 静置 CPU 回到项目正常低占用范围。

## 风险与缓解

- **轮询期间启动并立即完成的短 turn**：首次基线之后，新的 completion identity
  仍可被识别；App 休眠超过 10 秒导致错过完成行时不补播，符合实时提醒而非 inbox
  的定位。
- **终态混淆**：显式 outcome 透传，禁止用 `.idle` 猜测成功。
- **轮询重复**：Core tracker 以完成身份去重。
- **声音重叠**：统一节拍间隔约 0.6 秒，并在运行中合并新完成。
- **抢占用户交互**：展开、隐藏、拖放和滑动手势不被改变。
- **持续 CPU**：只使用一次性 3 节拍 Task，无永久动画或额外轮询。

## 回退

回退时删除 terminal outcome 的新增透传、Core 完成追踪器、Controller 三连任务、
Overlay 完成脉冲状态与相关动画 profile 字段，并恢复对应 CoreChecks。保留现有
Codex 解析、Tasks 完成行、真实 hover、隐藏优先级、音乐手势和交互日志。
