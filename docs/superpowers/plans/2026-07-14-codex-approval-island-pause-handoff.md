# Codex Approval Island 暂停交接（2026-07-14）

## 恢复入口

- 工作目录：`/Users/user/Documents/Codex/Island`
- 执行计划：`docs/superpowers/plans/2026-07-14-codex-approval-island-handoff.md`
- 当前分支：`main`，dirty working tree；本计划明确不 stage、不 commit、不新建 worktree。
- 恢复时先读本文件，再读 `.superpowers/sdd/task-5-review.diff` 和 `.superpowers/sdd/task-5-report.md`。
- 保留所有既有未提交改动；不要清理、回退或格式化无关文件。

## 当前结论

Task 1–4 已完成并通过独立审查。Task 5 正在修复独立复审发现的竞态，已暂停在一个有意保留的 TDD 红灯；Task 6 尚未开始。

生产 `IslandPanelController` 仍默认 `codexApprovalCoordinator = nil`。没有证明 Island 自己持有产生 Desktop 审批的 app-server turn，因此当前生产行为必须保持 passive observation + `前往 Codex`，不得声称可直接审批任意 Codex Desktop 会话，也不得启动一个空 app-server 子进程。

## 已完成

1. Task 1：审批 Core 模型、routing identity、once-only inbox、attachment 几何合同；独立审查通过。
2. Task 2：passive 审批边沿、隐藏态与 Files pinned 优先级、自动展开和会话选择；独立审查通过。
3. Task 3：124×54 attachment、右侧额外画布、分裂按钮、union hit testing；独立审查通过。
4. Task 4：单连接 app-server client/coordinator、原始 JSON-RPC id 保真、command/file context gate、stale/double submit 防护；安全复审通过。
5. Task 5 已完成的部分：
   - Inbox 多请求排序、A/B submission state 隔离、targeted resolve。
   - typed privacy-safe audit event、安全摘要、Tasks nav 琥珀点、打开 Codex 公共 API。
   - 子代理 request 先到而 snapshot 后到时保留选择；snapshot 到达后展开所属 root。
   - `CodexApprovalPresentation.pendingThreadIDs` 驱动多个 managed pending 会话逐行琥珀标记。
   - Coordinator 已改为 `selectRequest(threadID:) -> Bool`、`onNewRequest` 单次边沿、`submit(_:for:)` 请求身份绑定；Coordinator 不再自行发 `.presented`。
   - 新增纯 Core `CodexApprovalApplicationOpenState`，行为测试覆盖失败持久、A→B 隔离和 attempt generation。

## 还剩 6 项

1. **混合来源仲裁**：managed A 与 passive B 同时存在时，按当前选中 thread 选择来源；B 没有 managed request 时允许 passive fallback。attachment 同步与异步挂载前都必须校验 `request.threadID == selectedCodexTaskID`。
2. **点击身份接线**：`CodexApprovalActionView` 的决定、前往 Codex、重试回调携带其渲染时的 `CodexApprovalRequest.ID`；Controller 调用 `submit(_:for:)`，不得在异步 Task 启动后读取可变 selection。
3. **单次展示边沿与审计**：`onPresentationChange` 只同步数据；只有 `onNewRequest` 可以自动定位/展开。`.presented` 仅在 attachment 实际首次可见时按 request identity 记录一次，hidden、Files pinned、metadata/submitting/failed 更新不得记录或抢回 Tasks。
4. **Codex 激活失败接线**：Controller 使用 `CodexApprovalApplicationOpenState` 绑定 request/attempt；同一 passive request 每秒刷新仍保留“无法打开 Codex”，A 的迟到 completion 不得污染 B，成功重试清除失败。
5. **Task 5 复审**：上述四项完成并跑绿后，重新生成 `.superpowers/sdd/task-5-review-fixed.diff`，交回独立 reviewer；只有 `APPROVED` 后才把 Task 5 标为完成。
6. **Task 6 集成验收**：运行完整构建与 `build_and_run`，检查无审批/passive/多 pending/长标题/Files pinned/hidden/Reduce Motion 视觉矩阵，采样 CPU，确认没有新增 app-server child，最后只追加一条项目 `MEMORY.md` 事件。

## 当前 TDD 状态

最后一次通过：

```text
./script/run_codex_approval_checks.sh
DynamicIslandApprovalChecks passed
```

当前有意保留的红灯：

```text
swift run DynamicIslandCoreChecks
FAIL: Codex activation uses request-bound attempt state. Expected true, got false
at Tests/DynamicIslandCoreChecks/main.swift:1200
```

原因：Core open-attempt 状态和行为测试已存在，但 Controller 尚未接线。不要删除或放宽该断言，应完成剩余四项接线使其转绿。

`git diff --check` 在暂停前通过。最近一次 `swift build --product DynamicIsland` 是在 Coordinator API 改为 `submit(_:for:)` 之前通过；当前 App 端尚未同步新签名，恢复后必须在接线完成再重新构建。

## 明天建议顺序

1. 运行 `./script/run_codex_approval_checks.sh`，确认 Core/coordinator 行为基线仍绿。
2. 从 `CodexApprovalActionView` → `IslandOverlayView` → `IslandPanelController` 接通 request ID 回调。
3. 在 Controller 完成 managed/passive 仲裁、严格 thread guard、`onNewRequest` 自动展示边沿和 actual-visible `.presented` 去重。
4. 把 `CodexApprovalApplicationOpenState` 接入 `openCodexApproval`、completion 和 passive presentation 重建。
5. 依次运行：

```bash
./script/run_codex_approval_checks.sh
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
git diff --check
```

6. 生成 Task 5 fixed review diff并复审；通过后才进入 Task 6。

## 关键文件

- `Sources/DynamicIsland/Support/CodexApprovalCoordinator.swift`
- `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
- `Sources/DynamicIsland/Views/CodexApprovalActionView.swift`
- `Sources/DynamicIsland/Views/IslandOverlayView.swift`
- `Sources/DynamicIsland/Views/CodexTasksContentView.swift`
- `Sources/DynamicIslandCore/CodexApprovalApplicationOpenState.swift`
- `Sources/DynamicIslandCore/CodexApprovalFlow.swift`
- `Tests/DynamicIslandApprovalChecks/main.swift`
- `Tests/DynamicIslandCoreChecks/main.swift`

## 审查证据与边界

- Task 5 初次实现报告：`.superpowers/sdd/task-5-report.md`
- Task 5 待修审查包：`.superpowers/sdd/task-5-review.diff`
- 审查结论：`CHANGES_REQUESTED`；无 Minor，包含 1 个 Critical、5 个 Important，其中 snapshot 滞后与 managed 行标记两项已实现。
- 不得写 Codex SQLite、rollout JSONL 或 global state。
- 不得使用 Accessibility、AppleScript、私有 deep link 模拟 Codex 审批。
- 不得杀掉 ChatGPT/Codex Desktop 已持有的 app-server；如需检查进程，必须重新核对当前 PID/PPID，不能依赖旧 PID。
- 不得在真实 round-trip 未证明前启用生产 managed coordinator。

