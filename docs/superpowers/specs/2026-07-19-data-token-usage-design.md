# Data Token Usage Design

## 目标

在现有 Data 一级页面中加入一张紧凑的 Token 使用统计卡。界面参考 CC
Switch 的信息层级，但不加入曲线图、来源筛选、模型筛选或客户端筛选。用户只看
所选时间范围内的全量汇总，并能通过默认显示“今日”的 Liquid Glass 时间按钮
切换“今日、3天、一周、30天”。

Token 数量是本功能的准确性主指标。成本只能作为本地价格数据推导出的估算值，
不能伪装成供应商账单。

## 已确认的产品决策

1. 默认范围是“今日”。应用进程内保留用户最后一次选择，重新启动后恢复“今日”。
2. “今日”使用刷新开始时捕获的系统本地时区，从当天 00:00 到当前时间；3、7、
   30 天分别包含今天和前 2、6、29 个本地自然日。一次刷新期间时区保持不变。
3. 时间范围统一使用半开区间 `[startUTC, endUTC)` 查询。
4. 前台不区分来源、模型或客户端，只显示聚合结果。
5. 数据源采用全量聚合：Codex 读取原始会话日志，非 Codex 读取 CC Switch。
6. 不加入图表，不加入自定义日期，不加入后台持续轮询。

## 统计架构

### `CodexUsageSource`

- 通过只读 `~/.codex/state_5.sqlite` 建立 thread id 到 canonical rollout
  路径的映射。
- 同时扫描 `~/.codex/sessions` 和 `~/.codex/archived_sessions`，包含主任务、
  子代理和归档任务。
- 对每个线程按事件顺序读取 `token_count.total_token_usage`，对 input、cached
  input、output 分别计算累计差分，再按事件时间归入查询窗口。
- 正常递增时差分为 `current - previous`；某一字段发生累计重置、即
  `current < previous` 时，把 `current` 视为新基线的首笔用量并计入。
- 不求和累计值，不直接求和 `last_token_usage`。
- `cached_input_tokens` 是 input 的子集，`reasoning_output_tokens` 是 output 的
  子集，两者都不能再次加入总量。
- active 和 archive 文件按 canonical thread id 分组。优先使用 state 数据库当前
  `rollout_path` 指向的完整文件；没有匹配路径时选择最后一个完整 Token 事件时间最新的
  文件，时间相同时选择完整字节数更大的文件，并把路径冲突标记为不完整。

### `CCSwitchUsageSource`

- 以只读模式查询 `~/.cc-switch/cc-switch.db` 的原始请求记录。
- 排除所有 Codex 记录，避免与 `CodexUsageSource` 双重计算。
- 非 Codex 记录以 CC Switch 的唯一 `request_id` 为去重依据，不使用时间、模型、
  Token 相同等启发式规则删除可能真实并发的请求。
- 历史成本优先使用请求行已经保存的成本；不使用当前价格表回算旧请求。
- 对 CC Switch 官方定义为 cache-inclusive 的非 Codex 应用，fresh input 使用
  `max(input - cache read, 0)`；其他已知 cache-exclusive 应用使用原始 input。
- 未知 input/cache 语义的记录不猜测，排除该记录并把 snapshot 标记为不完整。

### `UsageAggregator`

两个数据源先归一化为同一条目：

- `freshInputTokens`
- `outputTokens`
- `cacheCreationTokens`
- `cacheReadTokens`
- `requestCount`
- `estimatedCostUSD`
- `occurredAt`

真实总 Token 公式是：

```text
fresh input + output + cache creation + cache read
```

Codex 的 fresh input 为 `max(input - cached input, 0)`，所以在有效记录中其真实总量
最终等于 `input + output`。“请求数”统一表示有正 Token 用量的模型调用：Codex 统计正 Token
增量事件，CC Switch 只统计归一化真实总 Token 大于零的唯一非 Codex 请求。零 Token
失败请求不进入这个数字。

输出为不可变 `UsageSnapshot`，至少包含分项 Token、真实总量、请求数、缓存命中率、
可选估算成本、数据覆盖起止时间、刷新时间、完整性和警告。

缓存命中率使用归一化后的以下公式计算：

```text
cache read / (fresh input + cache creation + cache read)
```

分母为零时显示 `N/A`，不显示 0%。

## 数据流与刷新

1. 第一次进入 Data 页时异步加载默认“今日”范围。
2. 点击时间按钮只改变抽屉状态，不读取数据。
3. 选择一个范围后立即关闭抽屉、更新按钮标签并启动新查询。
4. 点击刷新按钮重新查询当前范围。
5. 新查询会取消或淘汰旧查询；旧结果不能覆盖较新的范围。
6. 切离 Data 页后不启动新扫描。正在完成的扫描可以缓存，但不能修改其他页面状态。
7. 不设置轮询计时器，避免后台 CPU 和磁盘读取。

Rollout 扫描以文件 `size + mtime` 缓存解析结果，只解析完整换行；解析后文件若变化，
重试该文件。SQLite 使用只读连接、`query_only` 和单次读事务，确保一次 snapshot
内部一致。

## 界面布局

Data 内容继续使用现有 primary content frame，位于顶部 32pt 安全带下方，不改变
camera 禁区和一级导航布局。

统计卡的信息顺序为：

```text
⚡ 真实消耗 Tokens                         [今日⌄] [刷新]
5,941,400,123  ≈59.41亿          请求 43,500 · 估算成本 $—
新增输入          Output          创建缓存          缓存命中
12.4亿            2.1亿           N/A               45.0亿
缓存命中率 78.4%  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- 可用统计网格宽度达到 560pt 时使用单行四项分栏，每列至少 128pt；不足 560pt 时
  使用 2×2 分栏。判定只看容器可用宽度，不硬编码屏幕型号，也不扩大 shell。
- 数字使用等宽位数，避免刷新时横向跳动。
- 卡片沿用项目现有低透明白色填充、细描边和连续圆角；蓝色用于总量，紫色用于
  Output，绿色只用于缓存命中率。
- 无数据时显示 `—` 或 `N/A`，不把读取失败伪装成零消耗。
- 数据覆盖不足时显示一个低强调信息标记，通过 help/accessibility 文案说明记录起点。

## Liquid Glass 时间抽屉

静止状态只显示时间按钮和独立刷新按钮：

```text
[ 今日⌄ ] [↻]
```

点击时间按钮后，单块抽屉从按钮原位置向下展开，浮在统计内容上方，不推动卡片布局、
不加入模态遮罩。抽屉是统计卡的上层 sibling，不受卡片圆角裁剪，并使用 Data 页内部
最高 z-index：

```text
┌──────────┐
│ ✓ 今日   │
│   3天    │
│   一周   │
│   30天   │
└──────────┘
```

### macOS 26 及以上

- 使用原生 `GlassEffectContainer`、`.glassEffect(.regular.interactive())`、
  `glassEffectID` 和 `.glassEffectTransition(.matchedGeometry)`。
- 触发胶囊直接变形成单块抽屉，保持空间来源清楚。
- 选项行使用普通 vibrancy/fill，不在玻璃表面再叠一层玻璃。
- 只对当前选中项使用克制的蓝色强调，不给所有项目着色。

### macOS 14 和 15 后备

- 使用系统 material、同一圆角几何、描边和阴影近似层级，不宣称为原生 Liquid
  Glass。
- 布局、键盘操作和状态变化与 macOS 26 路径一致。

### 动效与输入

- 展开和收回使用可中断弹簧：response `0.30`、damping `0.80`。
- 动画始终从当前呈现状态继续；快速重复点击可以即时反向，不锁定输入。
- 按下时立即产生轻微压缩/高亮反馈，松开时提交。
- 点击灵动岛内、抽屉以外的区域时沿原路径收回；面板当前接收键盘事件时，按 `Esc`
  也收回。选择选项后同样沿原路径收回。
- 不为窗口外点击或全局 `Esc` 安装系统级键盘监听，也不新增辅助功能权限；切换一级页面、
  收起或隐藏灵动岛时总是关闭抽屉。
- Reduce Motion 使用短交叉淡化，不进行弹簧位移或弹性形变。
- Reduce Transparency 使用更不透明的后备表面；提高对比度时增加边界和文字对比。

## 状态与错误处理

Data 页包含 `idle`、`loading`、`available`、`empty`、`partial`、`failed` 状态：

- `loading`：显示“正在统计…”，不使用闪烁 skeleton 或循环动画。
- `available`：显示完整 snapshot。
- `empty`：数据源可读但范围内无记录，显示真实的零值。
- `partial`：保留已确认的数据，同时显示覆盖不足或某个数据源不可用的提示。
- `failed`：没有可信结果时显示“统计数据暂不可用”和刷新按钮，不显示零值。

CC Switch 不存在时，Codex 结果仍可显示但标记为 partial。Codex canonical 映射或
rollout 读取失败时，不把 CC Switch 中不完整的 Codex 导入记录补回，以免悄悄改变
统计口径。

估算成本只有在范围内所有正 Token 记录都能得到可信历史成本或版本化模型价格时才显示；
否则显示 `N/A`。由于 Codex rollout 不保存历史成本，范围内存在无法可靠定价的 Codex
记录时通常会显示 `N/A`，不会用非 Codex 的部分成本冒充总成本。供应商账单始终是
成本真相源。

## 隐私与日志

- 数据源全部只读，不修改 Codex、CC Switch 或供应商数据。
- 不申请 Screen Recording、Microphone 或 Apple Events 权限。
- Dynamic Island 日志只能记录范围、聚合数量、耗时、文件数量、完整性和错误类别。
- 不记录提示词、会话标题、原始文件路径、供应商凭证或请求正文。

## 组件边界

- `DynamicIslandCore/UsageTimeRange.swift`：自然日边界和展示标签。
- `DynamicIslandCore/UsageSnapshot.swift`：归一化条目、聚合结果、完整性和格式化合同。
- `DynamicIsland/Support/CodexUsageSource.swift`：只读 Codex state/rollout 解析。
- `DynamicIsland/Support/CCSwitchUsageSource.swift`：只读非 Codex 请求读取。
- `DynamicIsland/Support/UsageAggregationService.swift`：合并、取消、缓存和 snapshot。
- `DynamicIsland/Views/DataPrimaryContentView.swift`：统计卡、时间按钮、抽屉和状态展示。
- `IslandPanelController`：仅负责编排进入页面、范围选择、刷新和发布 snapshot。

每个数据源都通过小型协议注入，使核心聚合和控制器测试可以使用固定 fixture，UI 不直接
访问 SQLite 或文件系统。

## 验证方案

### 纯逻辑与 fixture

- 注入 Asia/Shanghai 等固定时区后验证今日、3、7、30 天边界、跨月边界，以及一次
  查询期间系统时区变化不改变已捕获边界。
- 半开区间端点：起点计入，终点不计入。
- Codex 累计值差分、不变与重置累计值、子代理、active/archive 移动、canonical
  文件选择和路径冲突。
- cached input 与 reasoning output 不重复计算。
- 非 Codex cache-inclusive / cache-exclusive 归一化。
- CC Switch `request_id` 去重和未知语义的 partial 结果。
- 请求数、缓存命中率、成本 N/A、覆盖范围和大数字格式化。
- 固定时钟下旧查询不能覆盖新查询。

### UI 与运行时

- Data 与 Tasks/Files 使用相同的 opacity、offset、hit testing、accessibility 和
  z-index 进入合同。
- 850pt 和较窄外接屏布局都不越过顶部 32pt 安全带。
- macOS 26 原生玻璃路径与 macOS 14/15 后备路径都能编译。
- 抽屉来源、反向中断、岛内抽屉外点击、可用时的 Esc、切页/收起关闭、选择后刷新、
  Reduce Motion、Reduce Transparency 和提高对比度。
- `swift run DynamicIslandCoreChecks`、`swift build --product DynamicIsland`、
  `./script/build_and_run.sh` 全部通过。
- 启动后核对今日、3、7、30 天结果与独立只读聚合脚本一致。
- 页面静止后检查 DynamicIsland CPU，不应因 Data 页产生持续高占用。

## 验收标准

- 默认显示“今日”，没有横排四段选择器。
- 时间按钮以原生 Liquid Glass（可用时）从胶囊变形成抽屉。
- 卡片包含真实总 Token、近似中文量级、请求数、估算成本、新增输入、Output、
  缓存创建、缓存命中和缓存命中率。
- 四个自然日范围能手动选择并刷新，结果包含 Codex 子代理且不重复统计 Codex。
- 不显示曲线图和来源/模型/客户端区分。
- 数据不完整时明确显示“不完整”提示；成本不可验证时显示 `N/A`，不伪造精确值。

## 范围外

- 自定义起止日期、小时图、日趋势图或导出。
- 来源、供应商、模型、客户端筛选。
- Token 配额、预算提醒或账单同步。
- 数据库写入、长期汇总表或新的生产依赖。
- 修改顶部 32pt 安全带、camera housing 合同、Files、Tasks、审批或音乐行为。

## 参考

- [CC Switch 用量统计](https://github.com/farion1231/cc-switch/blob/main/docs/user-manual/zh/4-proxy/4.4-usage.md)
- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Apple: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
