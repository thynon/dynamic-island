# Codex Approval Island Implementation Handoff

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Island 的 Tasks 中安全呈现 Codex 审批：检测到审批时自动展开并定位请求会话，从摘要卡右缘伸出协调的审批 attachment，并在 Island 确实持有 app-server 原始请求时支持“拒绝 / 同意 / 本次会话同意”。

**Architecture:** 保留现有 SQLite、rollout JSONL 和 global state 的只读观察链路，用它完成所有 Codex 会话的待审批检测与自动展开；另建严格隔离的 app-server 审批通道，只有该通道收到带 JSON-RPC `id` 的 server request 时才允许直接回复。基础 `850×200` Island、顶部 32pt 安全带和 `NotchMetrics` 不变；审批 attachment 只从 Tasks 摘要卡右缘向右伸出，并让 NSPanel 右侧画布按需增加。

**Tech Stack:** Swift 6、SwiftPM、macOS 14+、AppKit、SwiftUI、Foundation `Process`/`Pipe`、Codex app-server JSON-RPC 2.0（JSONL over stdio）。不添加第三方依赖。

## Global Constraints

- 当前工作区已有大量用户改动；不得 reset、revert、checkout、批量格式化或覆盖无关文件。
- 不修改 Codex SQLite、rollout JSONL、`.codex-global-state.json`，也不通过 Accessibility/UI automation 点击 Codex Desktop 的审批按钮。
- 没有原始 app-server JSON-RPC request id 时，不得显示成“可以直接审批”；必须显示“前往 Codex”。
- `acceptForSession` 只使用 Codex 返回的会话级语义，不由 Island 自行缓存、扩大或持久化权限。
- V1 直接回复只覆盖 command 和 file-change；permissions approval 先提醒并跳转 Codex，直到有独立的权限范围审阅 UI。
- 隐藏态优先级最高：用户已主动隐藏 Island 时，不得因为审批自动取消隐藏。
- 顶部 32pt 布局仍完全由 `IslandTopStatusBandLayout` 决定；审批 attachment 不得进入顶部带。
- 基础 `NotchMetrics.openWidth` 和 `openHeight` 不变；审批宽度不得写回显示器 profile。
- 所有新动画使用 `IslandAnimationProfile.default`，只做一次性可中断过渡；不得使用 `repeatForever`、`TimelineView`、持续 timer 或常驻 spinner。
- 原始命令、文件路径、diff 和审批原因只允许存在于瞬时内存和详情 popover；不得写入 Island JSONL 日志。
- 每个核心行为改动后运行 `swift run DynamicIslandCoreChecks`；最终追加主程序构建、真实启动和 CPU 检查。
- 当前 checkout 不自动 stage/commit。只有用户明确要求保存 Git 历史时才使用 `script/safe_git_save.sh`。

---

## 1. 当前交接快照

### 仓库状态

- 工作目录：`/Users/user/Documents/Codex/Island`
- 当前分支：`main`
- 当前 HEAD：`41b751d Update Island layout, interactions, and cleanup`
- 工作树不是干净状态。至少包括 Tasks companion、像素宠物、主会话/子代理层级、自适应向下展开、Files 和动效相关的未提交修改。
- 不要从 `HEAD` 新建空白 worktree 后重新实现本功能，否则会丢失当前 Tasks 布局基础。

开始工作前必须运行：

```bash
cd /Users/user/Documents/Codex/Island
git status --short
git diff --stat
```

把输出当作用户资产清单，不要清理。

### 已存在且必须复用的实现

- `Sources/DynamicIsland/Support/CodexStatusSignalSource.swift`
  - 只读查询 `~/.codex/state_5.sqlite`。
  - 只读解析 rollout JSONL。
  - 已识别：
    - `item/commandExecution/requestApproval`
    - `item/fileChange/requestApproval`
    - `item/permissions/requestApproval`
    - `serverRequest/resolved`
    - `.codex-global-state.json` 中的 `waitingOnApproval`
  - 当前只能得到审批类型和等待状态，不能得到可安全回复的 JSON-RPC request id。
- `Sources/DynamicIslandCore/CodexStatusBarSnapshot.swift`
  - `CodexTaskStatus.ApprovalState` 已有 `pendingCommand`、`pendingFileChange`、`pendingPermissions`、`autoReviewing`。
- `Sources/DynamicIsland/Views/CodexTasksContentView.swift`
  - 当前是 `252pt` 左侧主会话浏览器 + 分隔线 + 右侧详情。
  - 摘要卡高度 `54pt`。
  - `selectedTaskID` 目前是 View 私有状态，审批自动定位前需要提升到 controller-owned state。
- `Sources/DynamicIsland/Views/CodexStatusBarView.swift`
  - 已有像素宠物、Codex 图标、会话标题、运行状态、Token、待审批 badge。
  - 当前没有审批 callback；CoreChecks 还明确断言 Island 不执行 approve。
- `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - 已有 `setExpanded(_:)`、自适应向下高度、1 秒循环和折叠态 5 秒后台快照刷新。
  - 当前 `windowSize` 和 hit testing 假设展开画布始终等于 `metrics.openWidth`。
- `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - 基础 shell 被 `IslandShape` 裁剪到 `shellWidth`。
  - 审批 attachment 必须作为 `islandShell` 的兄弟层渲染，不能把基础 shape 拉宽。

### 相关但不属于本交接范围的未完成设计

`docs/superpowers/specs/2026-07-14-hide-completed-session-progress-design.md` 描述“完成的会话进程立即不显示”。它是独立任务；除非用户明确要求，不要在本审批实现里顺手处理。

---

## 2. 已确认的产品与视觉合同

### 2.1 普通状态

- 没有审批时，Tasks 必须与当前截图和当前代码完全一致。
- 不预留空白按钮槽，不改变 Token 的常态位置，不扩大 Panel。

### 2.2 检测到审批

- 可见且折叠：自动选择 Tasks、定位请求会话、自动展开。
- 已展开且位于 Tasks：定位请求会话并显示审批状态。
- 已展开且位于 Data/Tools/Settings：自动切换到 Tasks。
- Files 未固定：关闭 Files 状态并切换到 Tasks。
- Files 处于 pinned 状态：不强行关闭；Tasks 顶部导航显示琥珀色待审批点，用户点击 Tasks 后再显示审批。
- Island 已主动隐藏：保持隐藏；不得破坏“隐藏态只允许下滑恢复”的既有合同。
- 同一个 pending 状态每次只触发一次展开；resolved 后再次出现的新请求可以重新触发。

### 2.3 审批 attachment 布局

基础 Tasks content 在默认指标下：

```text
open width                         850
horizontal content inset           21
Tasks content width               808
session browser                   252
HStack spacing + divider         8+1+8
summary detail minX               290
summary detail maxX               829
```

审批 attachment：

```text
attachment origin X               829  // 与摘要卡右缘相接
attachment width                  124
attachment height                  54
attachment maxX                   953
extra right canvas width          103  // 953 - 850
button height                      30
reject button width                42
button gap                          6
approve split button width         68
approve main segment width         50
approve menu segment width         18
```

布局含义：

- 基础 Island 左缘、camera housing、顶部导航、Tasks 左栏和摘要卡左缘完全不动。
- NSPanel 在显示 attachment 前先向右增加 `103pt` 画布；窗口左 X 仍以基础 `850pt` shell 居中位置计算，因此只有右缘向右移动。
- attachment 从摘要卡右缘向右揭开，左侧与摘要卡视觉连续；右侧保持 `8pt` 连续圆角。
- Token 区在 attachment 出现时只左移 `10pt`，避免文字和分隔线拥挤；会话标题继续单行尾部截断。
- attachment 内先放一条低对比度竖分隔线，再放 `拒绝` 和 `同意⌄`。
- `拒绝` 使用克制的红色描边/浅填充；`同意` 使用现有 mint 色系。不得使用大面积高饱和红绿。
- 动画使用现有 primary feature spring。Panel 先扩，attachment 再从 leading edge 揭开；收回时顺序相反。
- Reduce Motion 下取消水平几何 tween，只保留现有短淡入淡出，并直接更新 Panel frame。

### 2.4 三种审批动作

- `拒绝` -> app-server `{ "decision": "decline" }`
  - 只拒绝当前操作，Codex turn 继续。
  - V1 不把“拒绝”映射为 `cancel`。
- `同意` 主按钮 -> `{ "decision": "accept" }`
  - 只批准当前操作。
- `同意⌄` 菜单 -> `{ "decision": "acceptForSession" }`
  - 菜单文案：`同意，并在本次会话自动允许`
  - command 语义：使用 Codex 的 session-scoped approval cache；不要把它描述成永久规则。
  - file-change 语义：本次会话内对相同文件的后续变更不再重复询问。
  - 会话结束后由 Codex 清除；Island 不保存授权记录。

不在 V1 显示：

- `cancel`
- `acceptWithExecpolicyAmendment`
- `applyNetworkPolicyAmendment`
- 永久允许或跨会话允许

### 2.5 审阅上下文

- 真实可操作请求必须让用户看见自己在批准什么。
- 摘要卡第二行在 pending 时切换为：审批种类 + 一行安全摘要。
- command/file 原始详情只在临时 popover 中展示；详情不得进入 `CodexStatusBarSnapshot.progressEvents` 或日志。
- command 请求缺少 command/context，或 file-change 缺少可审阅 item 内容时，直接审批按钮保持禁用，并显示 `在 Codex 中查看`。
- passive observation 永远没有足够的 JSON-RPC 路由信息，只显示 `前往 Codex`，绝不能显示已连接状态下的三种动作。

### 2.6 多审批

- 会话列表的每个 pending 会话显示琥珀色标记。
- attachment 一次只绑定一个请求。
- 队列按 `startedAtMs` 从早到晚；相同时间以稳定 request id 排序。
- 摘要卡显示 `N 个待审批`，用户切换会话时 attachment 跟随当前选中的 pending request。
- 提交后锁定该请求，不能重复点击；其他请求仍可浏览但不得复用旧 request id。

---

## 3. 协议与安全事实

官方 app-server 是 rich client 处理 authentication、conversation history、approvals 和 streamed events 的接口。协议是双向 JSON-RPC；server request 带 `id`，客户端必须用同一个 `id` 回应。

本机 `codex-cli 0.144.2` 的稳定 schema 已验证：

- command request 必填：`threadId`、`turnId`、`itemId`、`startedAtMs`；可能有 `approvalId`、`command`、`cwd`、`reason`。
- file request 必填：`threadId`、`turnId`、`itemId`、`startedAtMs`。
- JSON-RPC `RequestId` 可能是 string 或 `Int64`，必须无损保留类型。
- command/file response 都支持 `accept`、`acceptForSession`、`decline`、`cancel`。
- `serverRequest/resolved` 带 `threadId` 和 `requestId`，它是 attachment 收回的主要确认信号。
- permissions response 不是普通 decision，而是 granted permissions subset + `scope: turn|session`，因此不能复用 command/file 的分裂按钮逻辑。

重新生成与当前 Codex 二进制匹配的 schema：

```bash
rm -rf /tmp/island-codex-app-server-schema
'/Applications/ChatGPT.app/Contents/Resources/codex' \
  app-server generate-json-schema \
  --out /tmp/island-codex-app-server-schema
```

官方参考：

- <https://learn.chatgpt.com/docs/app-server.md>
- <https://learn.chatgpt.com/docs/agent-approvals-security.md>
- <https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md#approvals>

当前 ChatGPT/Codex Desktop 的 app-server 是其父进程持有的私有 stdio/unix FD。Island 不得尝试注入、复用或写入该 FD。单独启动另一个 app-server 也不能批准 Desktop 现有 turn；只有通过 Island 所持连接发起的 turn 才能把审批 server request 安全路由回 Island。

---

## 4. 文件结构

### 新建

- `Sources/DynamicIslandCore/CodexApprovalFlow.swift`
  - JSON-RPC request id、request kind、decision、request、presentation/submission state、队列纯逻辑。
- `Sources/DynamicIslandCore/CodexTasksApprovalLayout.swift`
  - attachment 的唯一几何真相源。
- `Sources/DynamicIsland/Support/CodexApprovalCoordinator.swift`
  - 把 passive snapshot 和 managed app-server requests 合并为 UI presentation；处理去重、排序、提交锁和 resolved。
- `Sources/DynamicIsland/Support/CodexAppServerApprovalClient.swift`
  - app-server stdio 连接、initialize、JSONL 解码、server request 保留、response 写回。
- `Sources/DynamicIsland/Views/CodexApprovalActionView.swift`
  - attachment、拒绝按钮、同意 split button、菜单、提交/错误/跳转状态和详情 popover。

### 修改

- `Sources/DynamicIsland/Views/IslandOverlayState.swift`
  - controller-owned selected task id、approval presentation、attachment 可见状态。
- `Sources/DynamicIsland/Views/CodexTasksContentView.swift`
  - 选择状态改由外部传入；为 pending 会话增加标记。
- `Sources/DynamicIsland/Views/CodexStatusBarView.swift`
  - pending 时显示审阅摘要并为 Token 左移预留状态；不在这里直接写传输代码。
- `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - 把 attachment 作为 `islandShell` 兄弟层挂载，扩大 canvas 但不扩大基础 shell。
- `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
  - 审批边沿检测、自动展开/选择、Panel 右向扩缩、回调和 hit testing union。
- `Sources/DynamicIsland/Views/IslandOverlayView.swift`
  - 文件内私有 `PrimaryFeatureSwitcher` 为 Tasks 增加待审批琥珀色点。
- `Tests/DynamicIslandCoreChecks/main.swift`
  - 核心模型、布局、队列、动作映射、只读边界、UI source contract。
- `MEMORY.md`
  - 只在功能验证完成后追加事件；计划阶段不要提前宣称完成。

---

## 5. 实施任务

### Task 1: 核心审批模型与几何合同

**Files:**

- Create: `Sources/DynamicIslandCore/CodexApprovalFlow.swift`
- Create: `Sources/DynamicIslandCore/CodexTasksApprovalLayout.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**

- Produces: `CodexJSONRPCRequestID`, `CodexApprovalRequest`, `CodexApprovalDecision`, `CodexApprovalPresentation`, `CodexApprovalInbox`, `CodexTasksApprovalLayout`。
- Consumes: `NotchMetrics`, `IslandPrimaryContentLayout`。

- [ ] **Step 1: 先写失败的 CoreChecks**

在 `testCodexStatusBarContracts()` 附近增加数值和状态断言：

```swift
let approvalLayout = CodexTasksApprovalLayout(metrics: .preview14Inch)
expectEqual(approvalLayout.summaryFrame.minX, 290, "approval summary keeps the current detail origin")
expectEqual(approvalLayout.summaryFrame.maxX, 829, "approval attachment starts at the current summary edge")
expectEqual(approvalLayout.attachmentFrame.width, 124, "approval attachment has one centralized width")
expectEqual(approvalLayout.additionalCanvasWidth, 103, "approval grows only the right canvas")
expectEqual(approvalLayout.rejectButtonWidth, 42, "decline stays compact")
expectEqual(approvalLayout.approveSplitButtonWidth, 68, "accept split button fits the attachment")

let managedApproval = CodexApprovalRequest(
    requestID: .integer(61),
    threadID: "thread",
    turnID: "turn",
    itemID: "item",
    approvalID: nil,
    kind: .command,
    startedAtMilliseconds: 1,
    source: .managedAppServer,
    availableDecisions: [.decline, .accept, .acceptForSession],
    reviewSummary: "请求运行命令"
)
expectEqual(managedApproval.canRespondInline, true, "managed app-server approvals are actionable")
expectEqual(CodexApprovalDecision.acceptForSession.rawValue, "acceptForSession", "session approval preserves the app-server wire value")

let passiveApproval = CodexApprovalRequest.passive(
    threadID: "thread",
    turnID: "turn",
    kind: .command,
    startedAtMilliseconds: 1
)
expectEqual(passiveApproval.canRespondInline, false, "passive rollout detection never becomes an approval transport")
```

- [ ] **Step 2: 运行并确认红灯**

```bash
swift run DynamicIslandCoreChecks
```

Expected: 编译失败，提示上述审批类型尚未定义。

- [ ] **Step 3: 实现最小模型**

实现 request id 的类型保持：

```swift
public enum CodexJSONRPCRequestID: Equatable, Hashable, Sendable {
    case string(String)
    case integer(Int64)
}

public enum CodexApprovalDecision: String, Equatable, Hashable, Sendable {
    case decline
    case accept
    case acceptForSession
}

public enum CodexApprovalKind: String, Equatable, Sendable {
    case command
    case fileChange
    case permissions
}

public enum CodexApprovalSource: Equatable, Sendable {
    case passiveObservation
    case managedAppServer
}
```

`CodexApprovalRequest.canRespondInline` 必须同时满足：source 是 managed、request id 非空、kind 是 command/fileChange、available decisions 包含 accept 和 decline。Permissions 在 V1 返回 false。

`CodexApprovalInbox` 至少提供：

```swift
public mutating func upsert(_ request: CodexApprovalRequest)
public mutating func beginSubmitting(id: CodexApprovalRequest.ID, decision: CodexApprovalDecision) -> Bool
public mutating func resolve(requestID: CodexJSONRPCRequestID, threadID: String)
public mutating func markFailed(id: CodexApprovalRequest.ID, message: String)
public var orderedRequests: [CodexApprovalRequest] { get }
```

同一个 request 只能从 ready 进入 submitting 一次。

- [ ] **Step 4: 实现唯一布局真相源**

`CodexTasksApprovalLayout` 必须从 `IslandPrimaryContentLayout` 推导 frame，不改 `NotchMetrics`：

```swift
public struct CodexTasksApprovalLayout: Equatable, Sendable {
    public static let sessionBrowserWidth: CGFloat = 252
    public static let detailSpacing: CGFloat = 8
    public static let dividerWidth: CGFloat = 1
    public static let summaryHeight: CGFloat = 54
    public static let attachmentWidth: CGFloat = 124

    public let summaryFrame: CGRect
    public let attachmentFrame: CGRect
    public let additionalCanvasWidth: CGFloat
    public let rejectButtonWidth: CGFloat = 42
    public let approveSplitButtonWidth: CGFloat = 68

    public init(metrics: NotchMetrics, shellHeight: CGFloat? = nil) {
        let content = IslandPrimaryContentLayout(metrics: metrics, shellHeight: shellHeight).tasksContentFrame
        let detailMinX = content.minX
            + Self.sessionBrowserWidth
            + Self.detailSpacing
            + Self.dividerWidth
            + Self.detailSpacing
        summaryFrame = CGRect(
            x: detailMinX,
            y: content.minY,
            width: content.maxX - detailMinX,
            height: Self.summaryHeight
        )
        attachmentFrame = CGRect(
            x: summaryFrame.maxX,
            y: summaryFrame.minY,
            width: Self.attachmentWidth,
            height: Self.summaryHeight
        )
        additionalCanvasWidth = max(0, attachmentFrame.maxX - metrics.openWidth)
    }
}
```

- [ ] **Step 5: 运行并确认绿灯**

```bash
swift run DynamicIslandCoreChecks
```

Expected: `All DynamicIslandCore checks passed.`

### Task 2: Passive 审批边沿检测、自动展开和会话定位

**Files:**

- Modify: `Sources/DynamicIsland/Views/IslandOverlayState.swift`
- Modify: `Sources/DynamicIsland/Views/CodexTasksContentView.swift`
- Modify: `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**

- Consumes: `CodexApprovalRequest.passive(...)`, `CodexApprovalCoordinator` 的 passive update 入口。
- Produces: controller-owned `selectedCodexTaskID` 和一次性自动展开行为。

- [ ] **Step 1: 写失败检查**

检查以下 source contracts：

```swift
expectEqual(overlay.contains("@Published var selectedCodexTaskID"), true, "controller owns approval-driven task selection")
expectEqual(controller.contains("handleCodexApprovalTransition"), true, "controller centralizes approval edge behavior")
expectEqual(controller.contains("guard !overlayState.isShellHidden"), true, "approval cannot override explicit hidden state")
expectEqual(controller.contains("setExpanded(true)"), true, "visible collapsed Island expands for a new approval")
expectEqual(tasksContentView.contains("selectedTaskID: Binding<String?>"), true, "Tasks accepts controller-owned selection")
```

- [ ] **Step 2: 确认红灯**

```bash
swift run DynamicIslandCoreChecks
```

- [ ] **Step 3: 提升选择状态**

在 `IslandOverlayState` 增加：

```swift
@Published var selectedCodexTaskID: String?
@Published var codexApprovalPresentation: CodexApprovalPresentation = .hidden
@Published var isCodexApprovalAttachmentPresented = false
```

`CodexTasksContentView` 删除私有 `@State selectedTaskID`，改收 `Binding<String?>`。用户手动选择仍写回同一 binding，因此审批定位后用户可以继续切换会话。

- [ ] **Step 4: 实现 pending edge**

Controller 保存当前 pending identity 集合，不用单个全局布尔值：

```swift
private var lastObservedPassiveApprovalKeys: Set<String> = []

private func handleCodexApprovalTransition(_ snapshot: CodexStatusBarSnapshot) {
    let pendingTasks = snapshot.tasks.filter {
        $0.approvalState != .none && $0.approvalState != .autoReviewing
    }
    let keys = Set(pendingTasks.map {
        [$0.id, $0.turnID ?? "", $0.approvalState.rawValue].joined(separator: "|")
    })
    let newKeys = keys.subtracting(lastObservedPassiveApprovalKeys)
    lastObservedPassiveApprovalKeys = keys

    guard !newKeys.isEmpty,
          let task = pendingTasks.first(where: {
              newKeys.contains([$0.id, $0.turnID ?? "", $0.approvalState.rawValue].joined(separator: "|"))
          }),
          !overlayState.isShellHidden
    else { return }

    overlayState.selectedCodexTaskID = task.id

    if overlayState.selectedPrimaryFeature == .files,
       overlayState.isFileShelfPinnedOpen {
        return
    }

    selectPrimaryFeature(.tasks)
    if !isExpanded {
        setExpanded(true)
    }
}
```

调用顺序必须是：snapshot 写入 state -> coordinator/passive state 更新 -> `handleCodexApprovalTransition`。不要在 rollout parser 内操作 UI。

- [ ] **Step 5: 将折叠态审批检测延迟降到约 1 秒**

Controller 可以每秒调用 `currentSnapshot()`，因为 source 内部的 thread SQLite 查询仍有 5 秒缓存，global approval state 有 1 秒缓存。不得把 `threadRefreshInterval` 改成 1 秒。

修改后采样 CPU；如果折叠空闲态持续明显升高，停止并改用文件事件唤醒，而不是继续缩短轮询。

- [ ] **Step 6: 运行绿灯**

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
```

### Task 3: 右向 attachment、分裂按钮和命中区域

**Files:**

- Create: `Sources/DynamicIsland/Views/CodexApprovalActionView.swift`
- Modify: `Sources/DynamicIsland/Views/CodexStatusBarView.swift`
- Modify: `Sources/DynamicIsland/Views/CodexTasksContentView.swift`
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift`
- Modify: `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**

- Consumes: `CodexTasksApprovalLayout`, `CodexApprovalPresentation`。
- Produces: `onApprovalDecision(CodexApprovalDecision)`、`onOpenCodexApproval()`。

- [ ] **Step 1: 写布局和安全 source checks**

```swift
expectEqual(approvalView.contains("Button(\"拒绝\""), true, "approval attachment exposes decline")
expectEqual(approvalView.contains("CodexApprovalDecision.acceptForSession"), true, "approve menu exposes session-scoped acceptance")
expectEqual(approvalView.contains("ProgressView"), false, "approval submission does not add a continuous spinner")
expectEqual(overlay.contains("CodexApprovalActionView"), true, "approval attachment is mounted beside the clipped base shell")
expectEqual(controller.contains("pointInsideApprovalAttachment"), true, "approval attachment participates in pointer hit testing")
```

把旧断言：

```swift
expectEqual(statusBarView.contains("Button(action: approve"), false, ...)
```

替换成“`CodexStatusBarView` 不直接持有 transport；action view 通过 callback 发送决策”的断言。

- [ ] **Step 2: 确认红灯**

```bash
swift run DynamicIslandCoreChecks
```

- [ ] **Step 3: 实现 action view**

视觉结构：

```swift
HStack(spacing: 6) {
    Rectangle()
        .fill(.white.opacity(0.10))
        .frame(width: 1, height: 30)

    Button("拒绝") {
        onDecision(.decline)
    }
    .frame(width: 42, height: 30)

    HStack(spacing: 0) {
        Button("同意") {
            onDecision(.accept)
        }
        .frame(width: 50, height: 30)

        Menu {
            Button("同意，并在本次会话自动允许") {
                onDecision(.acceptForSession)
            }
        } label: {
            Image(systemName: "chevron.down")
                .frame(width: 18, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
    .frame(width: 68, height: 30)
}
```

要求：

- action view 只收 presentation 和 callbacks，不 import/创建 transport。
- submitting 时按钮全部 disabled，并用静态 `提交中…` 替换按钮文字。
- failed 时显示短错误文案和 `重试`，不得假装 resolved。
- passive/permission 状态用一个 `前往 Codex` 按钮替代分裂按钮。
- `acceptForSession` 不可用时隐藏 menu segment，并让普通同意按钮保持 `68pt` 总宽。
- 详情 popover 只持有瞬时内容；dismiss 或 resolved 立即清空。

- [ ] **Step 4: 作为 shell 兄弟层挂载**

`IslandOverlayView.body` 的顶层 `ZStack` 中：

```swift
islandShell
    .frame(width: metrics.openWidth, height: canvasHeight, alignment: .topLeading)

if state.isCodexApprovalAttachmentPresented {
    CodexApprovalActionView(...)
        .frame(
            width: approvalLayout.attachmentFrame.width,
            height: approvalLayout.attachmentFrame.height
        )
        .position(
            x: approvalLayout.attachmentFrame.midX,
            y: approvalLayout.attachmentFrame.midY
        )
}
```

基础 `shellWidth`、`IslandShape` 和 top-band frames 不变。`canvasWidth` 仅在 attachment 预备/显示期间增加 `approvalLayout.additionalCanvasWidth`。

- [ ] **Step 5: Panel 右向扩缩**

新增 expanded frame helper，保持基础 shell 左缘：

```swift
private static func expandedWindowFrame(
    metrics: NotchMetrics,
    shellHeight: CGFloat,
    additionalRightWidth: CGFloat,
    on screen: NSScreen?
) -> NSRect? {
    guard let screen else { return nil }
    let baseX = screen.frame.midX - (metrics.openWidth / 2)
    let width = metrics.openWidth + max(0, additionalRightWidth)
    return NSRect(
        x: baseX,
        y: screen.frame.maxY - shellHeight - NotchMetrics.defaultClosedCanvasBottomSlack,
        width: width,
        height: shellHeight + NotchMetrics.defaultClosedCanvasBottomSlack
    )
}
```

展示顺序：扩大 Panel -> SwiftUI 揭开 attachment。收回顺序：SwiftUI 隐藏 -> 等现有 spring/fade 结束 -> 缩小 Panel。

- [ ] **Step 6: 合并命中区域**

不要把 `IslandShape` 横向拉到 attachment maxX。改为 union：

```swift
private func pointInsideInteractiveShell(_ mouseLocation: NSPoint) -> Bool {
    if pointInsideBaseShell(mouseLocation) {
        return true
    }
    return pointInsideApprovalAttachment(mouseLocation)
}
```

展开且有 attachment 时，基础 shell 的 screen X 是 `panel.frame.minX`，不再用 `panel.frame.midX - metrics.openWidth / 2`。attachment screen rect 使用 Core layout frame offset 到 `panel.frame.minX/panel.frame.maxY`。

- [ ] **Step 7: 验证**

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
./script/build_and_run.sh
```

人工确认：顶部导航/camera 区不动，左侧会话不动，Token 左移 10pt，右缘单向增加，鼠标移到按钮不会触发 collapse。

### Task 4: app-server 审批通道与严格能力门控

**Files:**

- Create: `Sources/DynamicIsland/Support/CodexAppServerApprovalClient.swift`
- Create: `Sources/DynamicIsland/Support/CodexApprovalCoordinator.swift`
- Modify: `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**

- Produces: `CodexApprovalResponding`, `CodexAppServerApprovalClient.events`, `CodexApprovalCoordinator.submit(_:)`。
- Consumes: Task 1 的 request/decision/inbox。

- [ ] **Step 1: 先做受控协议探针，不碰 Desktop 私有连接**

用单独 `codex app-server --listen stdio://` 验证：initialize -> initialized -> thread/start -> turn/start -> requestApproval -> decline -> serverRequest/resolved。探针使用临时目录和 read-only/需要审批的无害操作；最终选择 decline，确保没有外部写入。

若没有收到带 `id` 的 server request，停止真实按钮接入，只保留 passive 自动展开 + 前往 Codex。不得用 rollout 中的 event 伪造 request id。

- [ ] **Step 2: 定义传输接口并写 fake transport 测试**

```swift
protocol CodexApprovalResponding: Sendable {
    func respond(
        to requestID: CodexJSONRPCRequestID,
        decision: CodexApprovalDecision
    ) async throws
}
```

Fake transport 记录写入的 id/decision，验证：

- `.integer(61)` 回应仍是 JSON number `61`。
- `.string("abc")` 回应仍是 JSON string `"abc"`。
- double-click 只产生一次 response。
- passive request 调用 submit 返回 capability error，传输没有写入。

- [ ] **Step 3: 启动与 initialize**

生产 client 只启动 Island 自己拥有的 app-server：

```text
/Applications/ChatGPT.app/Contents/Resources/codex app-server --listen stdio://
```

实际实现要有 executable resolver，不得只硬编码该路径。顺序：

1. ChatGPT/Codex bundle 内 Resources/codex。
2. `/opt/homebrew/bin/codex`。
3. `/usr/local/bin/codex`。
4. 找不到时返回 unavailable，不弹出真假审批按钮。

发送：

```json
{"method":"initialize","id":0,"params":{"clientInfo":{"name":"dynamic_island","title":"Dynamic Island","version":"<bundle version>"}}}
{"method":"initialized","params":{}}
```

不要默认开启 `experimentalApi`。稳定 schema 已足够支持 command/file 的 `acceptForSession`。

- [ ] **Step 4: 解析 server request**

只把下列 methods 转成 managed request：

```text
item/commandExecution/requestApproval
item/fileChange/requestApproval
item/permissions/requestApproval
```

必须保存 JSON-RPC envelope 的顶层 `id`，不能只保存 params。

request stable identity：

```text
source + JSON-RPC id + threadId + turnId + itemId + approvalId(if present)
```

command/file 默认 available decisions：decline、accept、acceptForSession。Permissions 记录为不可内联回复。

- [ ] **Step 5: 写回 response**

对 command/file：

```json
{"id":61,"result":{"decision":"accept"}}
{"id":61,"result":{"decision":"acceptForSession"}}
{"id":61,"result":{"decision":"decline"}}
```

写入必须在同一个 app-server connection 上完成，并用单一串行 writer，避免 JSONL 交错。

- [ ] **Step 6: resolved 和断线**

- 收到 `serverRequest/resolved`：按 threadId + requestId 清除。
- 收到 turn completed/aborted/cancelled/failed：清除该 turn 的 pending requests。
- child process 退出或 stdout EOF：所有 managed request 变为 failed/unavailable，按钮恢复为 `前往 Codex`；不得自动重发旧决定。
- 提交后 15 秒仍未 resolved：显示 `未确认，请在 Codex 中检查`；不得再次自动发送。

- [ ] **Step 7: 明确 turn ownership**

只有通过这个 client connection 启动的 turn 才能使用真实动作。当前 Codex Desktop 已在运行的 turn 仍由 passive observation 表示。

如果当前产品没有 Island-managed `turn/start` 入口，保留 client/coordinator 的注入接口和测试，但生产默认不得启动一个“看似连接、实际收不到 Desktop 审批”的空 app-server。必须在 UI 上诚实显示 `前往 Codex`。

- [ ] **Step 8: 验证 Core 和 build**

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
```

### Task 5: 多审批、详情、错误状态和导航提醒

**Files:**

- Modify: `Sources/DynamicIsland/Support/CodexApprovalCoordinator.swift`
- Modify: `Sources/DynamicIsland/Views/CodexTasksContentView.swift`
- Modify: `Sources/DynamicIsland/Views/CodexStatusBarView.swift`
- Modify: `Sources/DynamicIsland/Views/CodexApprovalActionView.swift`
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift`（文件内私有 `PrimaryFeatureSwitcher`）
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Interfaces:**

- Consumes: `CodexApprovalInbox.orderedRequests`。
- Produces: selected task presentation、pending count、review detail、nav badge。

- [ ] **Step 1: 写场景测试**

覆盖：

1. 两个主会话同时 pending，按 startedAt 排序。
2. 子代理 pending 时选中该子代理，并展开它所属主会话组。
3. 正在提交 A 时切到 B，A 仍保持 submitting，B 显示自己的 request。
4. A resolved 不会清除 B。
5. autoReviewing 只显示“审查中”，不显示 manual buttons。
6. Files pinned 时不抢占，但 Tasks nav 有待审批点。
7. hidden 时不自动出现。

- [ ] **Step 2: 实现 privacy-safe 日志**

允许记录：

```text
codex.approval.detected: kind, source, pendingCount, threadIDLength
codex.approval.presented: kind, inlineCapable
codex.approval.decision.sent: decision, kind
codex.approval.resolved: kind, latencyMilliseconds
codex.approval.failed: kind, errorCategory
```

禁止记录：command、cwd、reason、diff、path、itemId、approvalId、request id 原值。

- [ ] **Step 3: 实现打开 Codex**

`前往 Codex` 只负责激活 Codex/ChatGPT app 或使用项目已有的安全跳转能力；没有已验证 deep link 时不要构造私有 URL scheme。激活失败时显示静态错误，不做 UI automation。

- [ ] **Step 4: 运行验证**

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
```

### Task 6: 集成、真实视觉检查、CPU 和项目记忆

**Files:**

- Modify: `MEMORY.md`（验证全部通过后）
- No other file unless verification exposes an approval-specific defect.

- [ ] **Step 1: 静态检查**

```bash
git diff --check
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
```

Expected: 全部通过。

- [ ] **Step 2: 启动唯一产物**

```bash
./script/build_and_run.sh
```

Expected: 只运行 `/Users/user/Documents/Codex/Island/dist/Dynamic Island.app`。

- [ ] **Step 3: 视觉矩阵**

逐项检查：

- 无审批：850×200 和现有 Tasks 完全一致。
- command passive：约 1 秒内自动展开；显示前往 Codex，不显示假同意。
- command managed：右缘增加 103pt；拒绝 + 同意 split 可用。
- file managed：菜单 `同意，并在本次会话自动允许` 可用。
- permissions：显示请求类型和前往 Codex，不复用 command decision。
- 两个 pending：列表有两个标记，attachment 只显示一个。
- 长标题/大 Token：无覆盖，标题尾部截断。
- Files pinned：不抢占。
- hidden：不自动恢复。
- Reduce Motion：无水平 tween，仍可完成审批。

- [ ] **Step 4: 真实协议矩阵**

至少验证一次 decline、一次 accept、一次 acceptForSession。每次确认：

```text
request id 与 response id 完全一致
只发送一次 response
收到 serverRequest/resolved 后才收回 attachment
item/completed 是最终状态来源
```

若 acceptForSession 之后仍出现完全相同的 file/command 提示，记录为 Codex server semantics/配置问题，不要在 Island 本地建立“自动同意”缓存补偿。

- [ ] **Step 5: CPU**

```bash
pid=$(pgrep -x DynamicIsland | head -n 1)
ps -o pid,stat,pcpu,pmem,etime,command -p "$pid"
```

无审批且 UI 稳定后重复采样。若折叠空闲态长期明显高于改动前，回查一秒 passive polling、attachment 动画和 app-server child process，不接受持续高占用。

- [ ] **Step 6: 更新项目 MEMORY**

只追加一个事件，包含：设计原因、协议边界、实际支持范围、验证命令和回退方式。不得把“Desktop 任意会话可直接审批”写成已支持，除非实际证明。

---

## 6. 验收标准

- 新审批在可见状态下能自动展开并定位正确主会话/子代理。
- 无审批时布局零变化；审批时只从摘要卡右缘向右扩展。
- 左侧会话列表、顶部导航、camera housing 和基础 shell 左缘不移动。
- Token 与按钮无覆盖，长标题可预测截断。
- `拒绝`、`同意`、`同意并在本次会话自动允许` 映射到准确 wire value。
- `acceptForSession` 不跨会话持久化，也不被 Island 模拟。
- passive observation 永远不能触发真实审批 response。
- request id 数字/字符串类型无损，response 只发送一次。
- attachment 只在 `serverRequest/resolved`、turn terminal 或明确失败后改变状态。
- permissions approval 不被错误映射为 command/file decision。
- 多审批不叠 UI、不串 request id、不误清其他会话。
- Codex 原始数据保持只读；日志不包含敏感命令/路径/diff。
- CoreChecks、build、真实启动、视觉矩阵和 CPU 检查通过。

---

## 7. 明确停止条件

出现以下任一情况，停止真实审批实现并向用户报告，不要绕过：

- 只有 rollout/global `waitingOnApproval`，没有 app-server 顶层 request `id`。
- 尝试连接的是 ChatGPT/Codex Desktop 的私有 stdio FD。
- 另起 app-server 后无法证明该连接拥有产生审批的 turn。
- approval context 不足，用户看不到自己将批准什么。
- permissions request 需要的 granted subset/scope 尚未建模。
- 需要 Accessibility、Apple Events、ScreenCaptureKit 或其他 TCC 权限。
- 需要写入 Codex DB、rollout 或 global state。
- 现有脏工作树与本功能修改发生无法安全区分的冲突。

---

## 8. 回退

1. 移除 attachment sibling layer、approval extra canvas 和 union hit testing。
2. 恢复 controller 的固定 `metrics.openWidth` expanded window frame。
3. 恢复 `CodexTasksContentView` 的私有选中状态（如果没有其他功能依赖 controller-owned selection）。
4. 移除 app-server approval client/coordinator 和 Core approval flow/layout 文件。
5. 保留现有 `CodexStatusSignalSource` 的只读 approval badge 检测。
6. 不改动 Codex 数据，也不影响 Tasks companion、层级、动态向下展开、Files 和音乐功能。

---

## 9. 给下一会话的启动指令

```text
请先完整阅读：
1. /Users/user/Documents/Codex/Island/AGENTS.md
2. /Users/user/Documents/Codex/Island/docs/superpowers/plans/2026-07-14-codex-approval-island-handoff.md

严格按文档 Task 1 开始，先运行 git status --short 和 git diff --stat，保留当前所有未提交改动。使用 TDD，每个任务结束运行 swift run DynamicIslandCoreChecks。不要修改 Codex SQLite/rollout/global state，不要做 UI automation；没有原始 app-server request id 时只允许“前往 Codex”，禁止伪造同意/拒绝。
```
