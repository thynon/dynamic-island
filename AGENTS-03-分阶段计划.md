# Vibe Island — AGENTS 文档 ③ 分阶段开发计划

> 接文档①②。本篇是给 Codex / AI Agent 的 **施工路线图**,核心原则:**先做壳子(窗口/尺寸/UI 外观与交互),再用 mock 数据填 UI,最后接真实后端功能。**
> 每阶段都给出"做什么、验收标准、对应源码"。功能优先级由用户决定,这里给出推荐顺序与依赖关系。

---

## 阶段总览

| 阶段 | 主题 | 一句话目标 | 可独立验收 |
|------|------|-----------|-----------|
| **0** | 工程脚手架 | Tauri v2 + React 19 + TS + Tailwind 跑起来 | `npx tauri dev` 出空窗口 |
| **1** | 外壳 | 两窗口 + 纯黑药丸 + 两态动画 | 肉眼看到正确的药丸,能展开/收起 |
| **2** | UI 骨架(mock) | 用假数据把所有组件画全 | 截图与真品一致,纯前端 |
| **3** | 后端骨架 + 打通 | socket → 状态机 → 前端事件流 | 一条真实会话能显示 |
| **4** | Hook 接入 | 至少 Claude Code 上报成功 | 真跑 Claude,药丸有反应 |
| **5** | 权限审批闭环 | Allow/Deny 能原地放行工具 | 挂连接回灌成功 |
| **6** | 终端跳转 | 点会话跳到对应终端 | iTerm2/Terminal 跳转成功 |
| **7** | 设置 + 配置持久化 | 设置窗可改并落盘 | 改完重启仍生效 |
| **8** | 音效 / 更新 / 多工具 / SSH | 周边能力 | 按需逐项 |

> 建议每个阶段结束都跑一次"验证步骤"(见各阶段末尾),不要攒到最后。

---

## 阶段 0 — 工程脚手架

**做什么**
- `npm create tauri-app` 选 React+TS,或手搭。对齐真实依赖(`package.json` / `Cargo.toml`):
  - 前端:`@tauri-apps/api ^2`、`framer-motion ^11`、`lucide-react ^0.460`、`react ^19`、`zustand ^5`、Tailwind `^3`、Vite `^6`。
  - Tauri 插件:shell、notification、global-shortcut、positioner、updater、process、autostart。
  - Rust:`tauri 2`(features `tray-icon,image-png`)、`tokio full`、`serde/serde_json`、`chrono`、`dirs 6`、`rodio 0.20`、`toml`、`tracing`、macOS 下 `cocoa/objc`。
- `tsconfig.json`、`tailwind.config.js`、`vite.config.ts`(devUrl `http://localhost:5173`)。

**验收**:`npx tauri dev` 起一个空 Tauri 窗口,无报错。

---

## 阶段 1 — 外壳(壳子)⭐ 用户要的"先完成位置/大小/UI"

**做什么**(对应文档① §3-§5)
1. `tauri.conf.json` 定义 **两个窗口**,参数逐字照抄文档① §3:
   - `notch`:420×48,y=0,center,decorations=false,transparent=true,alwaysOnTop=true,skipTaskbar=true,shadow=false,resizable=false。
   - `settings`:560×640,decorations=true,transparent=false,visible=false,resizable=true。
2. 落地 `src/styles/index.css` 的设计令牌(文档① §5.1 整段),引 JetBrains Mono CDN。
3. `.notch-shell`:纯黑 `#000`、`border-radius:0 0 14px 14px`、三层 box-shadow(文档① §5.2)。
4. `NotchPanel.tsx`:Framer Motion `animate={{width: isExpanded?380:240}}`,spring `stiffness:500,damping:35`;点击切换 `toggleExpanded`;`expand_on_hover` 悬停展开;dwell-time 自动收起(先写死 4s)。
5. 收起态 `.compact-pill`(36px):像素宠物占位 + 标题文字 + 会话数小标 + ▼/▲ 按钮(文档① §5.3)。
6. `data-tauri-drag-region` 让药丸可拖;`[data-no-drag]` 给按钮(`index.css:43-48`)。
7. 右键药丸的自绘上下文菜单(4 项;Quit 接 `plugin:process|exit`,Settings 接 `WebviewWindow.getByLabel("settings").show()`)。
8. macOS `platform::setup_window` 做 `set_always_on_top(true)`;`on_window_event` 拦截 notch 关闭 → `hide()`。

**验收**
- 屏幕顶部正中出现一个纯黑、底部圆角、从顶部"垂下来"的药丸。
- 点一下从 240→380px 平滑展开,再点收起;鼠标移上去自动展开。
- 右键出菜单,Quit 能退,Settings 能开出 560×640 的空窗。
- 此阶段 **不接任何数据**。

---

## 阶段 2 — UI 骨架(mock 数据驱动)

**做什么**:在 store 里放一组假 `Session[]`,把所有展示组件画全。
- `types/index.ts`:照抄 Session / SessionStatus / PlatformInfo / AppConfig 类型 + `TOOL_COLORS` / `TOOL_LABELS` 表(文档② §3.1、文档① 工具色)。
- `SessionRow.tsx`:hero/mini 两态、像素宠物/圆点、工具+终端+bypass 标签、时长、第二行(You:/工具/Done)、右键菜单、点击调 `jumpToTerminal`(先 console.log)。
- `PixelPet.tsx`:SVG rect 8×8 与 13×8 两版,状态色 + 感叹号 + drop-shadow 辉光。
- `ApprovalCard.tsx`:权限卡(橙)+ 问答卡(青),含 `parseDiff` 行内 diff、序号选项按钮、自由文本输入、✓ 确认态(文档② §8)。
- 展开态列表:父会话 + 子代理缩进嵌套 + 待审批时插卡 + 底栏。

**验收**:用假数据切换不同 status,UI 颜色/布局/动画与真品截图一致。仍是纯前端,无 Rust 交互。

---

## 阶段 3 — 后端骨架 + 事件打通

**做什么**(对应文档② §1-§3)
- Rust:`SessionStore`(三个 `Arc<Mutex<HashMap>>`)+ `handle_event` 状态机 + `HookEvent` 模型(serde 字段名/rename 必须与文档② §3.1、§4.1 完全一致)。
- `SocketServer`:Unix socket(`~/.vibe-island/run/vibe-island.sock`,先不做 Windows)、"读到合法 JSON 为止"分帧、`process_event` emit `session-update`。
- `lib.rs`:注册 `get_sessions`、建目录、起 socket server、`setup_window`、清理循环。
- 前端 `useStore.ts`:`init()` 里 `listen("session-update")` + 2s 轮询;`refreshSessions` 调 `get_sessions`。
- **联调**:用 `nc -U` 或一个小 Python 脚本手动往 socket 发一条 `SessionStart` JSON,看药丸是否冒出会话。

**验收**:手动喂一条事件 JSON,前端列表实时出现该会话并能展开看到它。

---

## 阶段 4 — Hook 接入(先 Claude Code 一个)

**做什么**(对应文档② §4)
- 实现 `HookInstaller::install_claude_hook`:写 `CLAUDE_HOOK_PY` 到 `~/.claude/vibe-island-hook.py`,改 `~/.claude/settings.json` 注册 6 事件。
- 实现 `install_hooks` 命令 + 启动时按 `auto_install_hooks` 自动装。
- hook 脚本务必含 §4.3 的 **PreToolUse→PermissionRequest 重映射** 与 `get_tty()`、`write_osc2()`。

**验收**:真实跑一次 `claude`,在终端里发个 prompt、让它调工具,药丸里出现该会话、状态随事件变化(in_progress / idle)。

---

## 阶段 5 — 权限审批闭环 ⭐ 产品核心价值

**做什么**(对应文档② §2、§3.4、§8)
- `process_event` 的"挂连接"逻辑:权限/问答事件建 `oneshot`,存 pending,emit `permission-asked`/`question-asked`,`timeout(300s, rx)` 等决策,拿到后包 `hookSpecificOutput` 写回 socket。
- 命令 `approve_permission` / `answer_question` → `respond_*` 发 oneshot。
- 前端:`permission-asked` 事件展开药丸 + 渲染 ApprovalCard;⌘Y/⌘N/数字键(`App.tsx`)。

**验收**:Claude 要权限时药丸弹审批卡,点 Allow → 终端里工具立刻放行;点 Deny → 被拒。问答同理。

---

## 阶段 6 — 终端跳转

**做什么**(对应文档② §5):实现 `jump_to_terminal`,macOS 先做 iTerm2 + Terminal.app 的 AppleScript by TTY,再加 Ghostty sentinel / Kitty / WezTerm / Warp。前端点行/右键 Jump 调用。

**验收**:在 iTerm2 里跑 Claude,点药丸里的会话行,iTerm2 对应标签被激活到前台。

---

## 阶段 7 — 设置 + 配置持久化

**做什么**(对应文档② §6):`AppConfig` 结构 + `load/save`(原子写)+ `get_config`/`update_config` 命令;`SettingsPanel.tsx` 各分区控件;dwell-time、cleanup、opacity 等读 config 生效。

**验收**:设置窗改 dwell time / hide when empty 等,Save 后写入 `~/.config/vibe-island/config.json`,重启 app 仍生效。

---

## 阶段 8 — 周边能力(按用户优先级挑)

- **音效**(文档② §6.1、`sound/mod.rs`):rodio 播放,从用户 sound-pack 目录加载;`play_sound` 命令 + 事件触发。**注:需自备音效文件,1.0.0 不打包。**
- **自动更新**(文档② §10):updater 插件 + endpoint + 前端提示条。
- **多工具 hook**:逐个补 Codex/Gemini/Cursor/OpenCode/Amp/Kimi/Kiro/… 的安装器(文档② §4.2)。
- **Windows / Linux**:命名管道、Linux 合成器聚焦、Hyprland 窗口规则。
- **SSH 远程**(文档② §9):`SshRemoteManager` + 三个 ssh 命令 + 前端 UI(真品后端先行,UI 待补)。
- **子代理分组**:`subagent_parent_id` 嵌套渲染。

---

## 推荐改进点（真实代码的不足,复刻时可顺手修)

> 这些是核对源码发现的硬伤,Agent 可在对应阶段择机改善——但 **改前先和用户确认**,因为严格复刻 vs 改进是两种取向。

1. **macOS 平台信息硬编码**(`platform/mod.rs:18-27`):`screen_width/height` 写死 1920×1080、`has_notch` 写死 true、`notch_width` 写死 180。应改为运行时用 `NSScreen` 真实查询屏幕尺寸与刘海安全区,否则多屏/非刘海 Mac 上 `display.monitor`、`notch_follows_active_window` 等设置形同虚设。
2. **config.shortcuts 未接线**(文档② §7):结构里定义了 4 个全局快捷键,但没注册到 `global-shortcut` 插件,实际只有 ⌘Y/N、数字键、⌥G 生效。要么接线,要么从设置里移除避免误导。
3. **OnboardingScreen 是死代码**(文档① §2 注意):组件写好却没在 `App.tsx` 渲染。要么接首启引导(判断首次运行 → 渲染 → 完成后装 hook),要么删掉。
4. **不打包默认音效**:`pack="default"` 但无内置文件 → 开了声音也没声。应在 `resources/` 打包一套默认音效并在 `SoundManager::new` 预载,或在 UI 标注"需自备音效"。
5. **socket 分帧粗糙**(`socket/mod.rs:82-89`):靠"能解析成 JSON 就停"分帧,大消息或粘包可能误判。可改用长度前缀或换行分隔(hook 脚本侧也要配套)。
6. **托盘菜单缺失**:`tauri.conf.json` 配了 `trayIcon`,但 `lib.rs` 没有托盘菜单构建逻辑,托盘点击无反馈。可补 tray menu(Show/Settings/Quit)。
7. **审批超时静默**(`socket/mod.rs:194/219`):300s 超时后直接返回 None,hook 侧会拿不到决策。可在超时时给 hook 一个明确的默认拒绝/放行并在 UI 提示。

---

## 给 Agent 的总原则

- **数据契约不可改**:前后端靠 JSON 字段名对齐(snake_case),Session/HookEvent/Config 的字段名、SessionStatus 取值、hook 协议 `vi-e7c4` 必须与文档②一致,否则整条链路断。
- **先 mock 后真值**:阶段 1-2 不碰 Rust 数据,纯靠假数据验证 UI;这是"先壳后内容"的具体落法。
- **每阶段可独立验收**:不要跨阶段并行接线,先让每层单独跑通。
- **改进前先问**:遇到上面 7 个不足,先确认用户要"严格复刻"还是"顺手修"。

---

## 三份文档索引

- `AGENTS-01-结构与外壳与UI.md` — 项目规模、目录、窗口外壳、UI 布局、设计令牌、资源清单
- `AGENTS-02-功能与架构.md` — 数据流、IPC、状态机、Hook、终端跳转、设置、快捷键、SSH、更新、命令表
- `AGENTS-03-分阶段计划.md` — 本篇,施工路线图 + 改进点
