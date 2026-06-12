# Vibe Island — AGENTS 文档 ② 功能与技术架构

> 接文档①。本篇讲清楚"功能怎么实现的、数据怎么流的、有哪些设置"。所有内容核对自 `src-tauri/src/*` 与 `src/*` 真实源码。

---

## 1. 系统数据流（全局心智模型）

```
 AI 工具(Claude/Codex/…)
    │  触发生命周期事件
    ▼
 注入的 hook 脚本(Python/JS,hooks/mod.rs 内嵌为字符串)
    │  JSON 写入 Unix socket
    ▼
 ~/.vibe-island/run/vibe-island.sock   (回退 /tmp/vibe-island.sock)
 Windows: 命名管道 \\.\pipe\vibe-island
    │
    ▼
 SocketServer (socket/mod.rs)  ── 解析 HookEvent
    │
    ▼
 SessionStore.handle_event (sessions/mod.rs)  ── 更新会话状态机
    │
    ├─ handle.emit("session-update")  ─────────►  前端 Zustand
    ├─ handle.emit("permission-asked") ────────►  展开药丸 + 显审批卡
    └─ handle.emit("question-asked")  ─────────►  展开药丸 + 显问答卡
    │
    ▼ (权限/问答事件会"挂住"连接,最多 300s)
 用户点 Allow/Deny/选项
    │  invoke("approve_permission"/"answer_question")
    ▼
 SessionStore.respond_* → oneshot 把结果送回挂住的 socket 连接
    │
    ▼
 hook 脚本拿到响应,打印给 AI 工具 → 工具据此放行/拒绝
```

前端还有个 **2 秒轮询兜底**:`useStore.init()` 里 `setInterval(refreshSessions, 2000)`(`useStore.ts:135`),即使漏了事件也能刷新。

---

## 2. IPC:Socket 服务器（来源:`socket/mod.rs`）

- **Unix(macOS+Linux)**:`socket_path()` = `~/.vibe-island/run/vibe-island.sock`,启动前先 `remove_file` 清旧(`socket/mod.rs:18-51`)。
- **Windows**:命名管道 `\\.\pipe\vibe-island`,字节模式,64KB 缓冲(`socket/mod.rs:107-152`)。
- 读循环:不断 `read` 累积字节,直到能 `serde_json` 解析成完整 JSON 才停(`socket/mod.rs:82-89`)——简单的"读到合法 JSON 为止"分帧。
- 每个连接 `tokio::spawn` 独立处理。

### 事件处理与"挂连接"(`socket/mod.rs:156-231`)

`process_event` 调 `handle_event` 拿到 `needs_held: bool`:

- **不需挂**(普通事件):立即 `emit("session-update")` 返回,关连接。
- **需挂**(PermissionRequest):
  - 若 `tool_name == "AskUserQuestion"` → 问答路径:建 `oneshot`,存 `PendingQuestion`,emit `"question-asked"`,然后 `tokio::time::timeout(300s, rx)` 等用户作答;拿到后包成 `{hookSpecificOutput:{decision:{updatedInput:{answers}}}}` 写回 socket(`socket/mod.rs:174-202`)。
  - 否则 → 权限路径:存 `PendingPermission`,emit `"permission-asked"`,同样等 300s;拿到后包成 `{hookSpecificOutput:{decision:{behavior,reason}}}` 写回(`socket/mod.rs:203-228`)。

> 这是整个产品的精髓:**socket 连接被服务器"挂住"不关**,等 UI 上用户决策,再把决策从同一条连接回灌给 hook,从而原地放行/拒绝工具,无需切窗口。

---

## 3. 会话状态机（来源:`sessions/mod.rs`）

### 3.1 Session 数据模型(`sessions/mod.rs:8-32` / 前端镜像 `types/index.ts:1-24`)

关键字段(Agent 必须用一模一样的 snake_case 名,因为前后端靠 serde/JSON 对齐):

`id, source, status, cwd, last_user_text, last_assistant_message, tool_name, tool_input, title, env, tty, terminal_bundle_id, server_port, started_at, last_activity, codex_model, codex_permission_mode, codex_thread_id, codex_title, subagent_parent_id, subagent_nickname, subagent_role`

### 3.2 状态枚举 SessionStatus(`sessions/mod.rs:34-44`)

`active, idle, pending, in_progress, completed, waiting_for_approval, waiting_for_answer`(serde 序列化为 snake_case)。

> 注意:前端 `types/index.ts:26-33` 的联合类型与之一致。文档①的颜色映射就是按这套状态来的。

### 3.3 事件 → 状态转移(`sessions/mod.rs:157-257`,`handle_event`)

| 收到事件 | 动作 |
|----------|------|
| 任意非 SessionEnd 且会话不存在 | **自动建会话**(因 Claude Code 不发 SessionStart)`:162-166` |
| `SessionStart` | upsert,刷新 cwd/env/tty/port,不挂连接 |
| `SessionEnd` | 删除会话 |
| `UserPromptSubmit` | 存 `last_user_text`,状态→`in_progress` |
| `PreToolUse` | 存 `tool_name/tool_input`,状态→`in_progress` |
| `PostToolUse` | 清 tool_name/tool_input |
| `PermissionRequest` | 若 `AskUserQuestion`→`waiting_for_answer`,否则→`waiting_for_approval`;**返回 true(需挂连接)** |
| `Stop` | 状态→`idle`,存 last_assistant_message / codex_title |
| `Notification` | 仅刷新 last_activity |

### 3.4 待决连接与回灌(`sessions/mod.rs:259-298`)

`SessionStore` 用三个 `Arc<Mutex<HashMap>>` 分开存:`sessions`、`pending_permissions`、`pending_questions`。`respond_permission/respond_question` 从 map 取出 `oneshot::Sender` 发送决策,并把会话状态改回 `in_progress`。

### 3.5 空闲清理(`sessions/mod.rs:300-319` + `lib.rs:256-274`)

后台每 60s 跑一次 `cleanup_idle(timeout)`:删掉 `last_activity` 超过 `session_idle_cleanup_secs`(默认 300s)且非待审批/问答的会话;删到了就 emit 一次 `session-update`。`timeout==0` 表示永不清理。

---

## 4. Hook 机制:如何让 16 个工具上报（来源:`hooks/mod.rs`,1076 行）

### 4.1 协议常量

所有 hook 脚本都带 `_proto_rev = "vi-e7c4"`、`_compat = 0x3A7F`(`hooks/mod.rs:540-541` 等)。事件用下划线前缀字段传带外数据:`_source`(哪个工具)、`_ppid`、`_tty`、`_env`、`_server_port`、`_opencode_request_id`(对应 `HookEvent` 的 serde rename,`sessions/mod.rs:85-96`)。

### 4.2 安装方式按工具分四类(`install_all` 逐个调,`hooks/mod.rs:28-114`)

| 类型 | 工具 | 落地位置 / 方式 |
|------|------|------|
| **Python hook** | Claude Code | 写 `~/.claude/vibe-island-hook.py` + 改 `~/.claude/settings.json` 注册 6 个事件(`:201-241`) |
| | Codex | `~/.codex/vibe-island-hook.py` + `hooks.json`,事件名 `session.start/end`,`tool.start/end`(`:243-271`) |
| | Gemini | `~/.gemini/...` + `settings.json`(`:273-301`) |
| | Cursor | `~/.cursor/...`(仅当目录存在)(`:303-333`) |
| | Copilot / Windsurf / CodeBuddy / Qoder / Droid / Cline / Pi-CLI | 各自配置文件注入 `python3 <hook>` 命令 |
| **JS plugin** | OpenCode | `~/.config/opencode/plugins/vibe-island.js`(ESM,**双向**:能回灌权限决策到本地 server,`:847-905`) |
| | Amp | `~/.amp/plugins/vibe-island.js`(监听 session/agent/tool 事件,`:908-936`) |
| | Hermes | `~/.hermes/plugins/vibe-island`(`:938-966`) |
| **TOML 注入** | Kimi | 往 `~/.kimi/config.toml` 注入 `# --- vibe-island Kimi hooks START/END` 受管块(`:353-373`) |
| **JSON agent** | Kiro | 写 `~/.kiro/agents/vibe-island.json` 声明 on_tool_call/session_start/end(`:375-394`) |

凡"目录不存在就跳过"(Cursor/Windsurf/CodeBuddy/Qoder/Kiro/Droid)——只给已安装的工具装 hook。

### 4.3 Claude hook 脚本的关键逻辑(`CLAUDE_HOOK_PY`,`hooks/mod.rs:536-694`)

- `get_tty()`:`os.ttyname(0)`,失败退回 `ps -o tty=`,用于后续终端跳转。
- `write_osc2()`:把 `项目名: prompt前30字` 写到 `~/.vibe-island/cache/osc2-titles/<sid前16位>`,供跳转时做标题匹配。
- **核心重映射**(`:653-665`):`PreToolUse` 且 `tool_name==AskUserQuestion` → 标记 held;`PreToolUse` 且有 tool_name 且非 bypass → 标记 perm。两者都把上报事件名 **改写成 `PermissionRequest`**,这样 Rust 端才会挂连接走审批 UI。否则 socket 立即关闭,点按钮就成了静默无效操作(脚本注释原话)。
- `bypass`:环境变量 `CLAUDE_BYPASS_PERMISSIONS=1` 时跳过审批(对应 §6 的 Auto Mode)。
- held 模式下脚本会阻塞读 socket 响应,把 `hookSpecificOutput` 打印给 Claude。

### 4.4 卸载(`uninstall_all`,`hooks/mod.rs:469-532`)

删各 hook 文件;对 Claude settings.json 精准移除含 "vibe-island" 的 hook 项;对 Kimi 移除受管 TOML 块;并调 `code/cursor/windsurf --uninstall-extension vibe-island.terminal-focus` 卸 VS Code 扩展。

---

## 5. 终端跳转 jump_to_terminal（来源:`platform/mod.rs:192-342`）

核心思路:**TTY → 终端进程 PID / 标题 → 用平台手段聚焦那个窗口**。

### macOS 顺序(`:199-271`)

1. **iTerm2**:AppleScript 遍历 windows/tabs/sessions,`tty contains` 匹配则选中并激活,返回 "ok" 即结束。
2. **Terminal.app**:同样 AppleScript by TTY。
3. **Ghostty**:写 sentinel 文件 `/tmp/vibe-island-ghostty-title-<sid前8>` = 标题,由 Ghostty 侧读取聚焦。
4. **Kitty**:若有 `KITTY_LISTEN_ON` 环境变量 → `kitty @ --to <listen> focus-window`。
5. **WezTerm**:若有 `WEZTERM_PANE` → `wezterm cli activate-pane --pane-id`。
6. **Warp**:兜底 `osascript` activate bundle id `dev.warp.Warp-Stable`。

标题提示 `title_hint` 来源优先级:OSC2 缓存文件 → `session.title` → `last_user_text[:20]`(`:195-197`)。

### Linux 顺序(`:274-328`)

tmux(`TMUX` 存在 → 按 pane_tty 选 pane)→ WezTerm → **TTY→PID**(扫 `/proc/*/fd/0` readlink 匹配 tty,`tty_owner_pid`,`:94-113`)→ 按合成器聚焦:Hyprland `hyprctl dispatch focuswindow pid:` / Sway `swaymsg [pid=] focus` / KDE `wmctrl` / X11 `xdotool search --pid`。兜底按标题 `xdotool --name` 或 `swaymsg [title=]`。

### Windows(`:330-341`)

PowerShell `SetForegroundWindow`,按 `MainWindowTitle -like *标题*` 匹配。

> VS Code / Cursor 的精确跳转靠 `src-tauri/resources/terminal-focus/` 里的 URI handler 扩展(卸载逻辑印证其存在)。

---

## 6. 设置项全集（来源:`config/mod.rs` 结构 + `SettingsPanel.tsx` 实际暴露的控件）

配置文件:`~/.config/vibe-island/config.json`(`config/mod.rs:126-132`),原子写(临时文件 + rename,`:146-154`)。

### 6.1 配置结构与默认值(`config/mod.rs:5-123`)

```jsonc
{
  "auto_install_hooks": true,        // 启动自动装 hook
  "launch_at_login": false,          // 开机自启(走 autostart 插件)
  "display": { "monitor": "auto", "position": "top-center", "opacity": 0.95, "scale": 1.0 },
  "layout": {
    "style": "clean",
    "show_tool_names": true,
    "show_session_time": true,
    "show_cwd": false,
    "max_visible_sessions": 8,
    "dwell_time_secs": 4.0,                // 任务完成后展开停留秒数
    "expand_on_hover": true,
    "hide_when_empty": false,
    "expand_on_subagent_done": false,
    "click_outside_dismisses": false,
    "notch_follows_active_window": false,
    "auto_configure_terminal_titles": false, // Ghostty/Warp 精确跳转需要
    "session_idle_cleanup_secs": 300          // 0 = 永不清理
  },
  "shortcuts": {                       // ⚠️ 结构存在,但未实际绑定(见下)
    "toggle_panel": "CmdOrCtrl+Shift+V",
    "approve_all":  "CmdOrCtrl+Shift+A",
    "deny_all":     "CmdOrCtrl+Shift+D",
    "bypass_permissions": "CmdOrCtrl+Shift+B"
  },
  "sound": {
    "enabled": true, "volume": 0.5, "pack": "default",
    "events": { "session_start": true, "session_end": false,
                "permission_request": true, "approval": true, "error": true }
  },
  "monitored_tools": ["claude","codex","gemini","cursor","windsurf",
                      "copilot","opencode","codebuddy","qoder"]
}
```

### 6.2 设置窗实际暴露的控件(`SettingsPanel.tsx`)

分区:**Environment**(只读:平台/桌面/Wayland)、**Behavior**(expand on hover / hide when empty / expand on subagent done / click outside dismiss / dwell time 滑杆 0-30s / session dismissal 滑杆 0-1800s)、**Display**(notch follows active window / auto-configure terminal titles / show tool names / show session time / opacity 滑杆 0.5-1)、**Sound**(enable / volume / permission_request / session_start)、**Integrations**(Install / Reinstall Hooks 按钮)、**Advanced**(auto-install on startup / launch at login / Uninstall All Hooks 红色按钮)。底部 Save Settings。

> 改设置是"本地副本 → 点 Save 才 `update_config` 落盘"(`SettingsPanel.tsx:8-18`)。

---

## 7. 快捷键真相（来源:`App.tsx:26-51`、`NotchPanel.tsx:19-32`）

实际生效的只有键盘事件监听,**不是** config.shortcuts 里那套全局快捷键(那套在 1.0.0 里没接 `tauri_plugin_global_shortcut` 注册逻辑):

- **⌘/Ctrl + Y**:批准当前 `waiting_for_approval` 会话(`App.tsx:32-33`)。
- **⌘/Ctrl + N**:拒绝(`App.tsx:34-35`)。
- **⌘/Ctrl + 1..9**:回答当前 `waiting_for_answer` 会话的第 N 个选项(`App.tsx:37-46`)。
- **⌥(Alt) + G**:展开药丸并循环切换到下一个会话(heartbeat,`NotchPanel.tsx:19-32`)。

审批卡里按钮也直接对应这些:`approve("allow"/"always"/"deny")`(`ApprovalCard.tsx:86-88`)。

---

## 8. 审批/问答卡 ApprovalCard（来源:`ApprovalCard.tsx`）

- **问答卡**(`waiting_for_answer`,青色调):标题"{source} asks",显示问题文本;有选项→渲染带 `⌘N` 序号徽章的按钮(`:127-172`);无选项→自由文本输入框 + Send(`:174-203`);答完显示 ✓ 确认。回答经 `answerQuestion(id, {header:[序号或文本]})`。
- **权限卡**(`waiting_for_approval`,橙色调):脉冲橙点 + "Permission Request",⚠ + 工具名 + 文件名;对 `Edit/Write/MultiEdit` 调 `parseDiff` 渲染 **行内 diff**(绿增红删,最多 12 行)+ `+N -N` 统计(`:251-301`);其他工具显示 command/detail 代码块(最多 3 行);底部 Deny ⌘N / Allow ⌘Y 两按钮 + Always Allow(青色小字)。批准后显示 ✓ Allowed。

---

## 9. SSH 远程会话监控（来源:`ssh_remote/mod.rs`）

被文档①前两版完全漏掉的真实功能。`SshRemoteManager` 为每个远程主机起一条 SSH 隧道:`ssh -N -o StrictHostKeyChecking=accept-new -o ExitOnForwardFailure=yes [-i key] -p port -L <本地sock>:<远程sock> user@host`(`:67-75`),把远程 `~/.vibe-island/run/vibe-island.sock` 转发到本地 `~/.vibe-island/run/remote-<host>.sock`。命令:`ssh_connect / ssh_disconnect / ssh_list_remotes`(`lib.rs:138-161`)。`list` 用 `try_wait` 判断隧道存活(`:108-127`)。前端目前未见对应 UI,属后端先行能力。

---

## 10. 自动更新（来源:`updater.rs` + `tauri.conf.json:72-79`）

- 用 `tauri-plugin-updater`,pubkey + endpoint = GitHub releases 的 `latest.json`(`tauri.conf.json:73-76`)。
- 启动后延时 5s 静默检查,有更新 emit `"update-available"`,前端 `App.tsx:68-125` 在药丸下方弹一条 "vX available [Install & Restart] [×]" 提示条。
- 命令:`check_for_update`(右键菜单手动触发)、`install_update`(`download_and_install` 后 `app.restart()`)。

---

## 11. Tauri 命令总表（前后端桥,来源:`lib.rs:206-224`）

`get_sessions, approve_permission, answer_question, get_config, update_config, install_hooks, play_sound, get_platform_info, jump_to_terminal, uninstall_hooks, set_bypass_mode, cleanup_sessions, ssh_connect, ssh_disconnect, ssh_list_remotes, check_for_update, install_update`(共 17 个)。

后端启用的插件(`lib.rs:194-203`):shell、notification、global-shortcut、positioner、updater、process、autostart(macOS 用 LaunchAgent)。

启动时 `run()` 还会:建 `~/.vibe-island/run` 与 `cache/osc2-titles` 目录、加载 config、起 socket server、(若开)装 hook、平台窗口设置、启动更新检查与清理循环(`lib.rs:174-276`)。
