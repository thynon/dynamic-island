# Vibe Island — AGENTS 文档 ① 项目结构 / 外壳 / UI

> 本文档基于 **真实源码** `~/Downloads/vibe-island-1.0.0` 逐行核对编写，每个数据都标注了来源文件与行号，供 Codex / AI Agent 1:1 复刻。
> 共三份：① 结构与外壳与UI（本篇）→ ② 功能与架构 → ③ 分阶段计划。

---

## 0. 一句话定位

Vibe Island 是一个 **吸附在屏幕顶部正中、纯黑色的悬浮"灵动岛"药丸**。AI 编码工具（Claude Code / Codex / Gemini / Cursor 等 16 个）通过注入的 hook 脚本，把会话事件经 Unix socket 发给本应用；应用在药丸里实时显示会话状态、权限审批卡片，点一下会话就跳到对应终端窗口。

技术栈:**Tauri v2 + Rust + React 19 + TypeScript + Tailwind v3 + Framer Motion v11 + Zustand v5**(来源:`package.json`、`src-tauri/Cargo.toml`)。

---

## 1. 真实项目规模（来源:实测 `du` / `wc`）

| 项 | 实测值 |
|----|--------|
| 项目总大小 | **3.6 MB**(含 assets 2.7MB,其中 og.png 单文件 1.9MB) |
| 前端 `src/` | 92 KB,**10 个 .tsx/.ts 文件,共 1643 行** |
| 后端 `src-tauri/src/` | **10 个 .rs 文件,共 2776 行** |
| 最大单文件 | `src-tauri/src/hooks/mod.rs` **1076 行**(含所有 hook 脚本字符串) |

> 这是一个 **小型项目**。整个前端 UI 逻辑只有 1600 多行,Agent 完全可以全部读进上下文。

---

## 2. 真实目录结构（来源:实测 `find`）

```
vibe-island-1.0.0/
├── package.json                # 前端依赖 + npx bin 入口
├── index.html / vite.config.ts / tailwind.config.js / tsconfig.json
├── bin/vibe-island.js          # npx @voidchecksum/vibe-island install 入口
├── scripts/                    # Linux waybar 集成脚本(waybar.py/.css/popup.py/build-all.sh)
├── assets/                     # README 用图(banner/og/arch.svg 等),非 app 运行资源
├── dist/                       # Vite 构建产物
├── src/                        # ── React 前端(全部 10 个文件)──
│   ├── main.tsx                # 10 行,React 挂载入口
│   ├── App.tsx                 # 150 行,根组件 + 全局快捷键 + 更新提示条
│   ├── store/useStore.ts       # 137 行,Zustand store(唯一状态源)
│   ├── types/index.ts          # 123 行,Session/Config/PlatformInfo 类型 + 工具色表
│   ├── styles/index.css        # 260 行,设计令牌(CSS 变量)+ 全部组件样式
│   └── components/
│       ├── notch/
│       │   ├── NotchPanel.tsx  # 261 行,药丸外壳 + 展开/收起 + 右键菜单
│       │   ├── SessionRow.tsx  # 182 行,单条会话行 + 终端徽章 + 右键菜单
│       │   └── PixelPet.tsx    # 88 行,8-bit 像素宠物(纯 SVG rect 绘制)
│       ├── approval/
│       │   └── ApprovalCard.tsx# 356 行,权限审批卡 + 问答卡 + diff 渲染
│       ├── onboarding/
│       │   └── OnboardingScreen.tsx # 143 行 ⚠️ 见下方"注意"——当前未被渲染
│       └── settings/
│           └── SettingsPanel.tsx # 193 行,独立设置窗口内容
└── src-tauri/                  # ── Rust 后端 ──
    ├── Cargo.toml              # Rust 依赖
    ├── tauri.conf.json         # 窗口/打包/更新器配置(外壳关键文件!)
    ├── icons/                  # 应用图标(见 §6)
    ├── resources/terminal-focus/ # VS Code/Cursor URI 跳转扩展
    └── src/
        ├── main.rs             # 6 行,调 lib::run()
        ├── lib.rs              # 288 行,Tauri 入口 + 17 个 command + setup
        ├── sessions/mod.rs     # 320 行,会话状态机 + 事件处理
        ├── socket/mod.rs       # 232 行,Unix socket / Windows 命名管道服务器
        ├── hooks/mod.rs        # 1076 行,16 工具 hook 安装/卸载 + hook 脚本
        ├── config/mod.rs       # 155 行,配置结构 + 持久化
        ├── sound/mod.rs        # 102 行,rodio 音频
        ├── platform/mod.rs     # 385 行,jump_to_terminal + 窗口设置
        ├── updater.rs          # 80 行,自动更新
        └── ssh_remote/mod.rs   # 132 行,SSH 隧道远程会话监控
```

> ⚠️ **三个与 README 不符的真实情况(Agent 必须知道):**
> 1. **没有 `src/assets/` 目录**——README 写的 brand 字体/壁纸/二维码在 1.0.0 源码里 **不存在**;字体走 Google Fonts CDN(`index.css:5`)。
> 2. **`OnboardingScreen.tsx` 存在但从未被渲染**——`App.tsx` 只渲染 `<NotchPanel>`,没有引导流程逻辑(死代码)。
> 3. **不打包任何音效文件**——`SoundManager` 只从用户数据目录 `~/.local/share/vibe-island/sound-packs/` 加载用户自备音效(`sound/mod.rs:79`),默认无声。

---

## 3. 外壳:窗口定义（来源:`src-tauri/tauri.conf.json:12-41`）

应用有 **两个窗口**,这是做"壳子"阶段的核心。

### 窗口 A — `notch`(主药丸)

| 属性 | 值 | 说明 |
|------|-----|------|
| `label` | `"notch"` | 代码里靠这个 label 找窗口 |
| `width` × `height` | **420 × 48** | 窗口容器固定大小;内部药丸宽度再由 JS 动画控制 |
| `y` | `0` | 贴顶 |
| `center` | `true` | 水平居中 → 顶部正中 |
| `decorations` | `false` | 无标题栏/边框 |
| `transparent` | `true` | 窗口透明,只有药丸本体可见 |
| `alwaysOnTop` | `true` | 始终置顶 |
| `skipTaskbar` | `true` | 不进 Dock/任务栏 |
| `shadow` | `false` | 无系统阴影(阴影由 CSS 画) |
| `resizable` | `false` | 不可拉伸 |

### 窗口 B — `settings`(设置窗,默认隐藏)

| 属性 | 值 |
|------|-----|
| `label` | `"settings"` |
| `width` × `height` | **560 × 640** |
| `decorations` | `true`(正常带标题栏的窗口) |
| `transparent` | `false` |
| `visible` | `false`(初始隐藏,右键药丸菜单里"Settings"才 `show()`) |
| `resizable` | `true` |

> 设置不是"悬浮按钮面板",而是 **一个独立的标准窗口**。打开逻辑:`NotchPanel.tsx:76-86` 用 `WebviewWindow.getByLabel("settings")` → `show()` + `setFocus()`。

### 置顶与平台规则（来源:`platform/mod.rs:345-385` `setup_window`）

- **macOS**:仅 `window.set_always_on_top(true)`。**没有** NSPanel / spaces / 刘海安全区适配代码——`has_notch` 是硬编码 `true`,`notch_width` 硬编码 `180`,屏幕尺寸硬编码 `1920×1080`(`platform/mod.rs:18-27`)。这是真实现状,也是可改进点(见文档③)。
- **Linux**:置顶 + 若检测到 Hyprland,用 `hyprctl keyword windowrulev2` 注入 6 条规则(float/pin/noborder/noshadow/noanim/move 33% 0)。
- **窗口关闭拦截**(`lib.rs:278-285`):点 notch 窗口关闭时 `prevent_close()` + `hide()`,不退出进程。

---

## 4. 外壳:药丸的两态动画（来源:`NotchPanel.tsx`）

药丸有 **收起 / 展开** 两态,用 Framer Motion 的 `animate` + spring 过渡。

| 状态 | 宽度 | 触发 | 代码 |
|------|------|------|------|
| 收起(compact) | **240px** | 默认 | `NotchPanel.tsx:99` |
| 展开(expanded) | **380px** | 点药丸 / 悬停(若 `expand_on_hover`)/ 有待审批 | `NotchPanel.tsx:42,99` |
| 最大宽度上限 | 400px | — | `NotchPanel.tsx:102` |

- spring 参数:`stiffness: 500, damping: 35`(`NotchPanel.tsx:100`)。
- **dwell-time 自动收起**:主会话从非 idle 变 idle 后,若展开中且无待审批,延时 `dwell_time_secs`(默认 4s)自动收起(`NotchPanel.tsx:56-67`)。有待审批时取消该定时器。
- 收起态高度 = `.compact-pill` 的 **36px**(`index.css:74-81`);窗口本身 48px 给阴影留空间。
- 展开内容区:会话列表 `max-h-72 overflow-y-auto`(`NotchPanel.tsx:209`),底部一行显示 "N sessions · compositor" + Settings 链接。

---

## 5. UI 布局与设计令牌（来源:`src/styles/index.css`,这是唯一真相）

### 5.1 设计令牌 / 颜色变量(`index.css:20-40`)— 必须照抄

```css
:root {
  /* 状态色(像素宠物 + 圆点都用它) */
  --vi-idle:    #22c55e;  --vi-idle-bright:    #4ade80;  /* 绿:空闲/完成 */
  --vi-work:    #3b82f6;  --vi-work-bright:    #60a5fa;  /* 蓝:进行中 */
  --vi-alert:   #f97316;  --vi-alert-bright:   #fb923c;  /* 橙:待权限审批 */
  --vi-question:#c084fc;  --vi-question-bright:#d8b4fe;  /* 紫:待回答问题 */
  --vi-explore: #06b6d4;  --vi-explore-bright: #22d3ee;  /* 青:链接/Always Allow */

  /* 外壳 */
  --notch-bg:     #000000;                    /* 纯黑,不是毛玻璃! */
  --notch-surface:#111111;
  --notch-border: rgba(255,255,255,0.08);
  --notch-hover:  rgba(255,255,255,0.06);
  --notch-text:   #ffffff;
  --notch-muted:  rgba(255,255,255,0.4);
  --notch-radius: 14px;
  --font-mono: 'JetBrains Mono','SF Mono','Fira Code',ui-monospace,monospace;
}
```

> 关键事实:背景是 **纯黑 `#000000`,无毛玻璃模糊**。药丸圆角只在底部:`border-radius: 0 0 14px 14px`(`index.css:64`),因为它从屏幕顶部"垂"下来。字体是 **JetBrains Mono**(CDN 引入,`index.css:5`),不是 Departure Mono。

### 5.2 外壳样式(`index.css:62-71`)

```css
.notch-shell {
  background: var(--notch-bg);          /* #000 */
  border-radius: 0 0 14px 14px;          /* 仅底部圆角 */
  box-shadow:
    rgba(0,0,0,0.6) 0 2px 8px,
    rgba(0,0,0,0.3) 0 8px 24px,
    rgba(255,255,255,0.04) 0 0 15px;
  overflow: hidden;
}
```

待审批时,`NotchPanel.tsx:103-109` 会动态把 box-shadow 换成带橙色(审批)或青色(问答)辉光,并在药丸背后加一层 `blur-2xl animate-pulse` 的橙色光晕(`NotchPanel.tsx:253-257`)。

### 5.3 收起态药丸内布局(`compact-pill`,`index.css:73-102` + `NotchPanel.tsx:113-196`)

水平 flex,高 36px,padding `0 14px`,gap 8px,从左到右:

```
[PixelPetLarge 26×16] [标题文字 idle-text] [会话数 idle-count] [待审批徽章] [▼/▲ 按钮]
```

- `PixelPetLarge`:像素宠物,颜色随主会话状态(`NotchPanel.tsx:169`)。
- 标题:主会话的 `title || codex_title || last_user_text[:30] || "No sessions"`(`NotchPanel.tsx:50-53`),11px 半透明白,省略号截断。
- 会话数 `idle-count`:9px,白底圆角小标(`index.css:93-102`)。
- 待审批徽章:橙色背景 `rgba(249,115,22,0.15)`,带脉冲圆点 + 数量(`NotchPanel.tsx:176-184`)。
- 整个 pill 设 `data-tauri-drag-region`(可拖动);展开态光标 `grab`,收起态 `pointer`(`NotchPanel.tsx:115-118`)。
- **右键药丸** → 自绘上下文菜单:Settings / Mute-Unmute Sounds / Check for Updates / Quit(`NotchPanel.tsx:120-168`)。

### 5.4 展开态:会话列表(`NotchPanel.tsx:198-248`)

- 顶部一条 1px 分隔线。
- 列表区 `max-h-72`(288px)可滚动,只渲染父会话;子代理(subagent)以 **左缩进 12px + 左边框** 的嵌套行显示(`NotchPanel.tsx:211-220`)。
- 某会话 `waiting_for_approval/answer` 时,在该行下方插入 `<ApprovalCard>`(`NotchPanel.tsx:221-223`)。
- 底栏:左 "N session(s) · {compositor}",右 "Settings" 链接(`NotchPanel.tsx:229-247`)。

### 5.5 会话行 SessionRow(`SessionRow.tsx` + `index.css:104-202`)

`.sess-card`:flex,gap 10px,padding 8px,圆角 6px,hover 背景 `rgba(255,255,255,0.05)`。两种尺寸:hero(第一条,带像素宠物 16px)和 mini(其余,仅 6px 圆点)。

一行结构:

```
[宠物/圆点] [标题 sess-name] [工具标签] [终端标签] [bypass标签?] [时长 sess-dur]
            [第二行(仅hero): You: 用户输入 / 当前工具(文件名) / Done—click to jump]
```

- 标签 `.sess-tag`:9px,`rgba(255,255,255,0.1)` 底,圆角 4px(`index.css:167-176`)。
- 圆点/宠物颜色:待审批/问答→橙,完成/空闲→绿,其余→蓝(`SessionRow.tsx:76-80`)。
- **点击整行** → `jumpToTerminal(session.id)`(`SessionRow.tsx:91`)。
- **右键行** → 菜单:Jump to Terminal / Enable-Disable Auto Mode(bypass)(`SessionRow.tsx:112-114`)。
- 终端名:先查 `terminal_bundle_id` 映射表(11 个 bundle id,`SessionRow.tsx:12-24`),再退回 `env.TERM_PROGRAM`。
- 时长:`<1m` / `Nm` / `Nh`(`SessionRow.tsx:68-74`)。

### 5.6 像素宠物 PixelPet(`PixelPet.tsx`)

纯 SVG `<rect>` 在 8×8(行内)/13×8(药丸 Large)网格上画的 8-bit 小生物:两眼 + 黑瞳 + 两行身体 + 两只脚。`image-rendering: pixelated` + `shape-rendering: crispEdges` 保持像素硬边(`PixelPet.tsx:35` / `index.css:56-59`)。待审批/问答态会多画一个 **感叹号**(`PixelPet.tsx:54-60`)。颜色取自状态色变量(`PixelPet.tsx:14-22`)。CSS 给宠物加了 `drop-shadow(0 0 3px var(--vi-idle))` 辉光(`index.css:228-230`)。

---

## 6. 资源清单（来源:实测 `src-tauri/icons/`、`assets/`）

### 6.1 App 真正用到的图标(`tauri.conf.json:54-60` bundle.icon + trayIcon)

| 文件 | 用途 |
|------|------|
| `src-tauri/icons/32x32.png` / `128x128.png` / `128x128@2x.png` | 通用图标 |
| `src-tauri/icons/icon.icns` | **macOS app 图标**(打 .app/.dmg 用) |
| `src-tauri/icons/icon.ico` | Windows 图标 |
| `src-tauri/icons/tray.png` | 托盘图标,`iconAsTemplate:true`(模板图,系统自动染色) |
| `src-tauri/icons/icon.svg` | 矢量源 |

> 注意:1.0.0 里这些 png 是 **占位图**(32x32 仅 176 字节)。复刻时要准备真实的多尺寸图标,尤其 macOS 的 `.icns` 需含 16→1024 各 @1x/@2x。

### 6.2 README 展示图(`assets/`,**不参与 app 运行**)

`banner.svg`、`og.png`(1.9MB)、`arch.svg`、`footer.svg`、`terminal.png`、`vibe-island-icon.png` 等——这些只在 README/网站用,做 app 壳子时 **不用管**。

### 6.3 字体

无本地字体文件。`index.css:5` 从 Google Fonts CDN 引入 **JetBrains Mono**(400-700)与 Instrument Serif。等宽场景用 JetBrains Mono,正文用系统 `-apple-system`(`index.css:13`)。

### 6.4 音效

**无打包音效**。`SoundManager::load_pack` 从 `~/.local/share/vibe-island/sound-packs/{pack}/` 读用户放置的 wav/mp3/ogg/flac/m4a(`sound/mod.rs:52-76`)。默认 `pack="default"`,目录为空 → 无声。

---

## 7. 做"壳子"阶段需要交付的东西（清单）

给 Agent 的明确验收项(对应文档③第一阶段):

1. Tauri v2 工程骨架,两窗口(notch 420×48 透明无边框置顶居中贴顶 / settings 560×640 隐藏)。
2. `index.css` 设计令牌原样落地(§5.1)。
3. 纯黑底部圆角药丸外壳 `.notch-shell`,带三层 box-shadow。
4. 收起 240px / 展开 380px 的 spring 动画两态切换 + 点击切换 + 悬停展开开关。
5. 收起态内布局:像素宠物占位 + 标题 + 会话数 + ▼ 按钮。
6. 展开态空列表骨架 + 底栏。
7. 右键药丸上下文菜单(4 项,先连 Quit/Settings)。
8. 设置窗能从右键菜单打开/聚焦。
9. macOS `set_always_on_top` + 关闭拦截 `hide()`。

> 这一阶段 **不接任何真实数据**:会话、审批、终端跳转全用假数据(mock)驱动 UI,验证外壳与交互。真实功能在文档②描述、文档③第二阶段起接入。
```
