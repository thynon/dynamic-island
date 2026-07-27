# Data Token Usage Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` for the recommended same-session execution path, or `superpowers:executing-plans` for inline batch execution. Implement one task at a time and run every listed verification before moving on.

**Goal:** 在现有 Data 一级页面中实现准确的本地 Token 汇总卡，并提供默认“今日”的 Liquid Glass 时间范围抽屉与手动刷新。

**Architecture:** `DynamicIslandCore` 负责自然日窗口、Token 归一化、累计差分、聚合与格式化；两个只读 app-layer source 分别读取 Codex rollout 和 CC Switch 非 Codex 记录；actor service 并发加载并产出不可变 snapshot；`IslandPanelController` 只编排查询世代与页面状态；SwiftUI 视图只负责展示和抽屉交互。

**Tech Stack:** Swift 6、Foundation、SwiftUI、AppKit、系统 `/usr/bin/sqlite3`、macOS 26 Liquid Glass（带 macOS 14/15 后备）、现有 SwiftPM 与源码合同检查。

**已确认设计:** [`docs/superpowers/specs/2026-07-19-data-token-usage-design.md`](../specs/2026-07-19-data-token-usage-design.md)

## 实施边界

- 只统计 Token 总消耗，不增加来源、模型或客户端筛选，不增加曲线图。
- Codex 以原始 rollout 累计差分为准；CC Switch 只提供非 Codex 行，避免双算。
- 所有 SQLite 和文件读取保持只读；不增加生产依赖、权限、数据库写入或后台定时器。
- 当前工作树包含用户未提交改动。每个任务只修改列出的文件；不要执行 reset、checkout、批量格式化，也不要自动 stage/commit 共享脏文件。
- 每个任务完成后以 `git diff --check -- <本任务文件>` 留下安全检查点；提交由用户后续明确决定。

---

### Task 1: 建立自然日窗口、Token 归一化与 snapshot 合同

**Files:**

- Create: `Sources/DynamicIslandCore/UsageTimeRange.swift`
- Create: `Sources/DynamicIslandCore/UsageSnapshot.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Step 1: 先写会失败的核心检查**

在 `Tests/DynamicIslandCoreChecks/main.swift` 增加以下测试函数，并在文件底部测试调用区调用它们：

```swift
private func testUsageTimeRangeUsesCapturedLocalNaturalDays() { /* Asia/Shanghai 固定 now */ }
private func testUsageTimeRangeHandlesDSTAndHalfOpenBounds() { /* America/Los_Angeles */ }
private func testUsageCumulativeCountersDiffNormalResetAndNoChange() { /* 每字段独立 */ }
private func testUsageTokenNormalizationAvoidsCacheDoubleCounting() { /* fresh/cache/output */ }
private func testUsageAggregatorCalculatesRequestsCoverageCostAndCompleteness() { /* complete/partial */ }
private func testUsageSnapshotFormattingAndCacheHitRate() { /* 982,233 / 98.22万 / N/A */ }
```

至少覆盖这些固定断言：

- `2026-07-19 11:00 Asia/Shanghai` 的今日起点是本地 `2026-07-19 00:00`，3 天起点是 `2026-07-17 00:00`，结束点都是捕获的 `now`。
- `[startUTC, endUTC)`：起点事件计入、终点事件排除。
- 洛杉矶跨 DST 的 3 个自然日由 `Calendar.date(byAdding:.day, ...)` 推导，不能用 `86_400 * n`。
- 累计值 `100 -> 150` 差分为 `50`，`150 -> 20` 重置差分为 `20`，不变差分为 `0`；input、cached input、output 各自独立处理。
- Codex `input=100, cached=40, output=20` 归一化为 fresh `60`、cache read `40`、output `20`、真实总量 `120`，reasoning output 不重复加入。
- 缓存命中率分母为 `fresh + cacheCreation + cacheRead`；分母为零时结果是 `nil`。
- `982_233` 精确格式为 `982,233`，近似格式为 `≈98.22万`；`145_000` 紧凑格式为 `14.5万`；`1_332` 为 `1,332`；`5_941_400_123` 为 `≈59.41亿`。
- 只有 `.unpricedUsage` 时 Token 完整性仍可为 `.complete`，但估算成本必须为 `nil`；数据源缺失、冲突或未知语义才使 Token 完整性为 `.partial`。

**Step 2: 运行检查，确认因类型尚不存在而失败**

Run:

```bash
swift run DynamicIslandCoreChecks
```

Expected: 编译失败，错误明确指向 `UsageTimeRange`、`UsageTokenCounts` 或 `UsageAggregator` 未定义；不是既有测试失败。

**Step 3: 实现最小核心类型**

在 `UsageTimeRange.swift` 建立以下公共合同：

```swift
public enum UsageTimeRange: String, CaseIterable, Identifiable, Sendable {
    case today, threeDays, sevenDays, thirtyDays

    public var id: String { rawValue }
    public var dayCount: Int { /* 1, 3, 7, 30 */ }
    public var displayName: String { /* 今日、3天、一周、30天 */ }
    public func queryWindow(now: Date, timeZone: TimeZone) -> UsageQueryWindow
}

public struct UsageQueryWindow: Equatable, Sendable {
    public let range: UsageTimeRange
    public let startUTC: Date
    public let endUTC: Date
    public let timeZoneIdentifier: String

    public func contains(_ date: Date) -> Bool {
        date >= startUTC && date < endUTC
    }
}
```

`queryWindow` 使用带入时区的 Gregorian `Calendar`，先求今日 `startOfDay`，再按 `-(dayCount - 1)` 个 calendar day 计算起点；`endUTC` 直接使用传入的 `now`。不要读取全局时钟或在查询中途重新读取时区。

在 `UsageSnapshot.swift` 建立这些公共类型和字段：

```swift
public enum UsageInputTokenSemantics: Sendable {
    case fresh
    case includesCacheRead
    case includesCacheReadAndCreation
}

public struct UsageTokenCounts: Equatable, Sendable {
    public var freshInput: Int64
    public var output: Int64
    public var cacheCreation: Int64
    public var cacheRead: Int64
    public var realTotal: Int64 { /* overflow-safe sum */ }

    public static func normalized(
        input: Int64,
        output: Int64,
        cacheCreation: Int64,
        cacheRead: Int64,
        semantics: UsageInputTokenSemantics
    ) -> UsageTokenCounts
}

public struct UsageCumulativeCounters: Equatable, Sendable {
    public var input: Int64
    public var cachedInput: Int64
    public var output: Int64
    public var cacheCreation: Int64

    public func delta(from previous: UsageCumulativeCounters?) -> UsageCumulativeCounters
    public func normalizedCodexDelta() -> UsageTokenCounts?
}
```

归一化必须使用钳制后的非负值；对 cache-inclusive 语义，cache 还是 input 的子集：

```text
fresh:                         input
includesCacheRead:             boundedRead = min(cacheRead, input); fresh = input - boundedRead
includesCacheReadAndCreation:  boundedRead = min(cacheRead, input);
                                boundedCreation = min(cacheCreation, input - boundedRead);
                                fresh = input - boundedRead - boundedCreation
```

累计差分逐字段执行：没有 previous 时取 current；`current >= previous` 时取差；发生重置时取 current。Codex delta 的 cache read 使用 `min(cachedInputDelta, inputDelta)`；若原始 cached delta 超过 input delta，parser 必须把该事件视为不可确认、重建 baseline 并标 partial，而不是静默接受钳制值。若未来 Codex 记录出现正的 `cacheCreation` 增量，`normalizedCodexDelta()` 返回 `nil`，由 parser 标为不完整，不猜测其 input 语义。

继续建立 snapshot 合同：

```swift
public struct UsageEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let occurredAt: Date
    public let tokens: UsageTokenCounts
    public let requestCount: Int64
    public let estimatedCostUSD: Decimal?
}

public enum UsageWarningCategory: String, Hashable, Sendable {
    case codexStateUnavailable
    case codexRolloutUnreadable
    case codexRolloutConflict
    case codexRolloutChangedDuringRead
    case ccSwitchUnavailable
    case ccSwitchQueryFailed
    case unknownInputSemantics
    case insufficientCoverage
    case unpricedUsage
    case numericOverflow

    public var affectsTokenCompleteness: Bool { self != .unpricedUsage }
}

public struct UsageSourceBatch: Equatable, Sendable {
    public let entries: [UsageEntry]
    public let coverageStart: Date?
    public let coverageEnd: Date?
    public let warnings: Set<UsageWarningCategory>
    public let scannedFileCount: Int
}

public enum UsageSnapshotCompleteness: Equatable, Sendable { case complete, partial }

public struct UsageSnapshot: Equatable, Sendable {
    public let tokens: UsageTokenCounts
    public let requestCount: Int64
    public let estimatedCostUSD: Decimal?
    public let coverageStart: Date?
    public let coverageEnd: Date?
    public let scannedFileCount: Int
    public let refreshedAt: Date
    public let queryWindow: UsageQueryWindow
    public let completeness: UsageSnapshotCompleteness
    public let warnings: Set<UsageWarningCategory>

    public var cacheHitRate: Double? { /* normalized denominator */ }
}

public enum UsagePresentationState: Equatable, Sendable {
    case idle
    case loading(previous: UsageSnapshot?)
    case available(UsageSnapshot)
    case empty(UsageSnapshot)
    case partial(UsageSnapshot)
    case failed(Set<UsageWarningCategory>)

    public var snapshot: UsageSnapshot? { /* loading previous + terminal snapshots */ }
}

public enum UsageAggregator {
    public static func snapshot(
        batches: [UsageSourceBatch],
        window: UsageQueryWindow,
        refreshedAt: Date
    ) -> UsageSnapshot
}

public enum UsageTokenFormatter {
    public static func exact(_ value: Int64) -> String
    public static func compact(_ value: Int64) -> String
    public static func approximate(_ value: Int64) -> String
}
```

所有会跨 `DynamicIslandCore` module 边界构造的 public struct（`UsageQueryWindow`、`UsageTokenCounts`、`UsageCumulativeCounters`、`UsageEntry`、`UsageSourceBatch`、`UsageSnapshot`）都必须提供显式 `public init`；不能依赖默认 memberwise initializer，因为它对 app target 不可见。

聚合只接纳窗口内且 `realTotal > 0` 的条目。所有 Int64 相加使用 `addingReportingOverflow`；溢出时饱和到 `Int64.max` 并加入 `.numericOverflow`，不能 crash 或 wrap。请求数与 scanned file count 相加。coverage 展示值取所有 batch 已知范围的最小/最大值；在合并前逐个检查每个成功 batch，任一有完整性警告，或该 batch 的已知 coverageStart 晚于窗口起点，snapshot 为 partial，并加入 `.insufficientCoverage`。估算成本仅在每个正 Token 条目都有成本且没有 Token 完整性警告时求和；否则为 `nil`，并自动加入不影响 Token 完整性的 `.unpricedUsage`。完整空结果的成本为 `Decimal.zero`。

把精确、紧凑、近似中文量级格式实现为 `UsageSnapshot`/`Int64` 附近的纯格式化 helper，固定 `Locale(identifier: "en_US_POSIX")`，避免依赖用户当前数字格式导致测试漂移。

**Step 4: 运行核心检查，确认通过**

Run:

```bash
swift run DynamicIslandCoreChecks
```

Expected: `DynamicIslandCoreChecks passed`。

**Step 5: 留下安全检查点**

Run:

```bash
git diff --check -- Sources/DynamicIslandCore/UsageTimeRange.swift Sources/DynamicIslandCore/UsageSnapshot.swift Tests/DynamicIslandCoreChecks/main.swift
```

Expected: 无输出、退出码 0。不要自动提交。

---

### Task 2: 以完整事件序列解析 Codex 累计 Token

**Files:**

- Create: `Sources/DynamicIslandCore/CodexRolloutUsageParser.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Step 1: 先添加 parser fixture 检查**

添加真实 `event_msg/token_count` 形状的 JSONL fixture 字符串，覆盖：

1. 窗口之前的累计基线、窗口内正常增量、窗口结束点事件。
2. input/cached/output 中单字段重置。
3. 两个完全相同累计快照不产生请求。
4. `reasoning_output_tokens` 存在但不增加总量。
5. 非 token_count、坏的非-token JSON 与最后不完整行不改变计数。
6. 未来出现正 `cache_creation_input_tokens` 时更新累计基线、跳过该笔增量并加入完整性警告。
7. `valid -> malformed/negative token_count -> valid` 会留下 baseline 断点，最后一条只重建 baseline，不产生跨损坏段的 delta；parse result 缓存后重放仍保持相同行为。

关键断言必须证明“先对完整序列差分，再按日期过滤”：窗口前累计 `input=100/output=20`，窗口内累计 `input=150/output=30`，窗口内只能得到 `50+10`，不能得到 `150+30`。

**Step 2: 运行并确认失败**

Run:

```bash
swift run DynamicIslandCoreChecks
```

Expected: 编译失败，指向 `CodexRolloutUsageParser` 未定义。

**Step 3: 实现可流式喂行的纯 parser**

建立以下状态化 API；source 负责按块拆完整行，parser 只保留稀疏的 token 累计快照，不持有整份 rollout 原文：

```swift
public struct CodexCumulativeUsageSample: Equatable, Sendable {
    public let occurredAt: Date
    public let counters: UsageCumulativeCounters
    public let endingByteOffset: Int64
    public let startsNewBaseline: Bool
}

public struct CodexRolloutWindowResult: Equatable, Sendable {
    public let entries: [UsageEntry]
    public let warnings: Set<UsageWarningCategory>
}

public struct CodexRolloutParseResult: Equatable, Sendable {
    public let threadID: String
    public let samples: [CodexCumulativeUsageSample]
    public let firstTokenEventAt: Date?
    public let lastTokenEventAt: Date?
    public let lastCumulativeCounters: UsageCumulativeCounters?
    public let completeByteCount: Int64
    public let tokenEventFingerprint: UInt64
    public let warnings: Set<UsageWarningCategory>

    public func entries(in window: UsageQueryWindow) -> CodexRolloutWindowResult
}

public struct CodexRolloutUsageParser: Sendable {
    public init(threadID: String)

    public mutating func consumeCompleteLine(
        _ line: Data,
        endingByteOffset: Int64
    )

    public func finish(completeByteCount: Int64) -> CodexRolloutParseResult
}
```

实现要求：

- 只识别顶层 `timestamp`、`type == "event_msg"`、`payload.type == "token_count"` 与 `payload.info.total_token_usage`。
- 先在 Data 字节中搜索 `token_count` marker，再对候选行做 JSON decode；不要把 rollout 的每一行都转成 String/Dictionary。
- 兼容整数 JSON 数值，不把大 Token 值经过 `Double`；可用小型 `Decodable` 结构和 `Int64?`。
- parser 的 stored state 只能包含 Sendable value；不要把共享 `ISO8601DateFormatter` 存进 `Sendable` struct，可使用局部解析策略或 Foundation 的 value-style ISO8601 format style。
- parser 只把有效累计快照追加到 `samples`；`entries(in:)` 必须从第一条 sample 开始依序差分，每次先更新 previous，再决定 timestamp 是否在 window 内。若 sample 的 `startsNewBaseline == true`，只把它设为 previous 并继续，不为该 sample 生成 delta。这样同一份 parse cache 可以安全用于今日、3 天、一周和 30 天，也不会跨损坏记录差分。
- 只有窗口内归一化 `realTotal > 0` 才创建 `UsageEntry(id: "\(threadID):\(endingByteOffset)", requestCount: 1, estimatedCostUSD: nil)`。
- `cached_input_tokens` 是 input 子集；`reasoning_output_tokens` 只解析但不计入。负数 counter 不猜测：标记 `.codexRolloutUnreadable`，并让下一条有效快照只重建 baseline、不产生 delta。
- 对完整 token_count 行做稳定的 64-bit FNV-1a fingerprint，使用 Swift wrapping arithmetic，供 active/archive 快速预筛；不要引入 CryptoKit 或第三方库。
- 普通坏 JSON 行忽略；若原文含 token_count 标记却无法解码，则标记 `.codexRolloutUnreadable`，并把下一条有效 sample 标为 `startsNewBaseline`。负 counter 使用同一断点规则。source 只会传完整换行结束的行，因此活动文件残尾不会进入 parser，也不因此标 partial。

**Step 4: 运行核心检查**

Run:

```bash
swift run DynamicIslandCoreChecks
```

Expected: 新 parser fixture 和既有检查全部通过。

**Step 5: 留下安全检查点**

Run:

```bash
git diff --check -- Sources/DynamicIslandCore/CodexRolloutUsageParser.swift Tests/DynamicIslandCoreChecks/main.swift
```

Expected: 无输出、退出码 0。不要自动提交。

---

### Task 3: 建立只读 SQLite runner、CC Switch source 与独立行为检查入口

**Files:**

- Create: `Sources/DynamicIsland/Support/UsageSQLiteQueryRunner.swift`
- Create: `Sources/DynamicIsland/Support/CCSwitchUsageSource.swift`
- Create: `Tests/DynamicIslandUsageChecks/main.swift`
- Create: `script/run_usage_checks.sh`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Step 1: 先写独立 source 行为检查**

仿照 `script/run_codex_approval_checks.sh`：先把所有 `Sources/DynamicIslandCore/*.swift` 编译成静态 `DynamicIslandCore`，再编译两个 support 文件和 `Tests/DynamicIslandUsageChecks/main.swift`。脚本最后把 `"$@"` 原样传给测试 binary，使后续 `--live` 模式可用。

在 usage checks 中先建立：

```swift
actor FakeSQLiteJSONQueryRunner: SQLiteJSONQueryRunning {
    var responses: [Data]
    private(set) var invocations: [(URL, String)] = []
    func query(databaseURL: URL, sql: String) async throws -> Data { /* FIFO */ }
}
```

测试 fixture 至少包含：

- `codex` 行被排除；SQL 同时使用 `lower(app_type) <> 'codex'` 与 `[start, end)` epoch 条件。
- 相同 `request_id` 只计一次；Token/时间相同但 request id 不同的并发请求均保留。
- `gemini + semantics 0` 映射 `.includesCacheRead`；`gemini + 1` 映射 `.includesCacheReadAndCreation`；包括未知 app 在内的任意 `semantics 2` 都映射 `.fresh`。
- `claude`、`claude-desktop`、`opencode` 的 semantics 0/1 保持 `.fresh`。
- 未知 app/semantics 组合被排除并加入 `.unknownInputSemantics`，不能猜测。
- cache-inclusive 行若 cache 子项之和超过 input，或任一 Token 字段为负，排除并加入 `.numericOverflow`；不能靠钳制后的数值冒充准确记录。
- `total_cost_usd` 用 `Decimal(string:)`；由于该列默认值可能是字符串 `"0"`，正 Token 行在没有显式可信零价标记时，cost `<= 0`、空值或解析失败都视为无可靠历史成本，设为 `nil` 并加入 `.unpricedUsage`，不能显示成可信 `$0`。
- SQL 查询失败映射 `.ccSwitchQueryFailed`；数据库不存在映射 `.ccSwitchUnavailable`。
- runner 自身只抛通用 `SQLiteJSONQueryError`；CC source 再映射 `.ccSwitchQueryFailed`，不能让 runner 猜测调用来源。
- runner 命令只含 `-batch -readonly -json`，SQL 以 `PRAGMA query_only=ON; BEGIN;` 开始并以 `COMMIT;` 结束，不含 INSERT/UPDATE/DELETE/CREATE/DROP。

**Step 2: 运行并确认失败**

Run:

```bash
chmod +x script/run_usage_checks.sh
./script/run_usage_checks.sh
```

Expected: 编译失败，因为 runner/source 尚未实现；若脚本本身有语法问题，先只修脚本再重新确认是类型缺失失败。

**Step 3: 实现异步只读 SQLite runner**

在 `UsageSQLiteQueryRunner.swift` 定义：

```swift
protocol SQLiteJSONQueryRunning: Sendable {
    func query(databaseURL: URL, sql: String) async throws -> Data
}

struct SystemSQLiteJSONQueryRunner: SQLiteJSONQueryRunning {
    func query(databaseURL: URL, sql: String) async throws -> Data
}

enum SQLiteJSONQueryError: Error, Equatable, Sendable {
    case executableUnavailable
    case launchFailed
    case nonzeroExit(Int32)
}

protocol UsageEntrySource: Sendable {
    func load(in window: UsageQueryWindow) async throws -> UsageSourceBatch
}

struct UsageSourceFailure: Error, Sendable {
    let warning: UsageWarningCategory
}
```

`SystemSQLiteJSONQueryRunner` 使用 `/usr/bin/sqlite3` 和参数数组，绝不经 shell 拼接，并在 utility-priority detached task 中执行阻塞 Process I/O。设置 stdout pipe、stderr 指向空设备或只转成无敏感路径的错误类别；`process.run()` 后必须先 `readDataToEndOfFile()` 再 `waitUntilExit()`，防止 3 万行 JSON 填满 pipe 死锁。launch/非零退出只抛通用 `SQLiteJSONQueryError`，不把数据库路径、SQL 内容或 stderr 原文放入日志；`CCSwitchUsageSource` 和 `CodexUsageSource` 分别把它映射成自己的 warning。

**Step 4: 实现 CC Switch source**

`CCSwitchUsageSource` 的构造函数接受数据库 URL 与 runner，默认 URL 为 `~/.cc-switch/cc-switch.db`，方便 fixture 注入：

```swift
actor CCSwitchUsageSource: UsageEntrySource {
    init(
        databaseURL: URL = /* home/.cc-switch/cc-switch.db */,
        queryRunner: any SQLiteJSONQueryRunning = SystemSQLiteJSONQueryRunner()
    )

    func load(in window: UsageQueryWindow) async throws -> UsageSourceBatch
}
```

SQL 一次返回窗口内原始行和 coverage 元信息。选择字段只限：request id、app type、四项 Token、cost、created_at、input semantics。使用一个 sentinel/meta row 或等价的同事务查询，保证范围内空结果仍能读取表的覆盖起止。coverage sentinel 必须在全表非 Codex 历史上计算 `MIN/MAX(created_at)`，不能只看窗口行；coverage 和数据行使用完全相同的 `lower(app_type) <> 'codex'` 条件。`created_at` 是 Unix seconds；边界以 POSIX locale 的有限小数秒数字 literal 写入静态 SQL，不把 `Date` 截断为整数，从而保留 end 秒内的半开区间语义。成本在 SQL 中 `CAST(total_cost_usd AS TEXT)`，Swift 再用 `Decimal(string:locale:)`，不能先经过 `Double`。Swift 端再次以 `Set<String>` 按 request id 防御性去重并验证 `[start,end)`。

固定语义映射：

```text
input_token_semantics 2（任何 app）              -> fresh
gemini + 0                                      -> includesCacheRead
gemini + 1                                      -> includesCacheReadAndCreation
claude/claude-desktop/opencode + 0 or 1         -> fresh
其他 0/1 组合                                    -> exclude + unknownInputSemantics
```

只有归一化 `realTotal > 0` 的唯一请求生成 `UsageEntry(requestCount: 1)`。不要读取 `usage_daily_rollups`，不要包含 CC Switch 的 Codex 行，不用当前价格表回算旧请求。

**Step 5: 在 CoreChecks 加入静态安全合同**

把两个新 support 文件和 `script/run_usage_checks.sh` 加入源码读取，断言：

- `-readonly`、`query_only`、`BEGIN`、`COMMIT` 存在。
- `lower(app_type) <> 'codex'` 存在。
- 不出现写 SQL、轮询 timer、prompt/title/request body 等字段。
- stdout 在 `waitUntilExit()` 之前 drain。
- usage 脚本只编译已列出的 source，不触碰生产数据库。

**Step 6: 运行两套检查**

Run:

```bash
./script/run_usage_checks.sh
swift run DynamicIslandCoreChecks
```

Expected: 分别输出 `DynamicIslandUsageChecks passed` 与 `DynamicIslandCoreChecks passed`。

**Step 7: 留下安全检查点**

Run:

```bash
git diff --check -- Sources/DynamicIsland/Support/UsageSQLiteQueryRunner.swift Sources/DynamicIsland/Support/CCSwitchUsageSource.swift Tests/DynamicIslandUsageChecks/main.swift script/run_usage_checks.sh Tests/DynamicIslandCoreChecks/main.swift
```

Expected: 无输出、退出码 0。不要自动提交。

---

### Task 4: 实现 Codex actor source、canonical 去重与增量缓存

**Files:**

- Create: `Sources/DynamicIsland/Support/CodexUsageSource.swift`
- Modify: `Tests/DynamicIslandUsageChecks/main.swift`
- Modify: `script/run_usage_checks.sh`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Step 1: 先写临时目录 fixture**

usage checks 使用临时 home、临时 `state_5.sqlite` 和 `sessions`/`archived_sessions` 目录；fixture URL 全部通过 initializer 注入，禁止改真实 `~/.codex`。覆盖：

1. state 当前 `rollout_path` 可读时，即使 archive 有同 thread id 的旧副本，也只采用 state 指向文件。
2. state 同时列出主 thread 与 child-agent thread 时，两者都按各自 canonical id 计入；不能只筛主任务。
3. state path 缺失时，active/archive 内容与 token fingerprint 相同视为移动副本，只计一次且不标冲突。
4. 同 thread id 的候选内容冲突时，选择最后完整 token event 时间较新的文件；时间相同选 `completeByteCount` 较大者，并加入 `.codexRolloutConflict`。
5. 同一 rollout 的窗口前基线和窗口内增量按 Task 2 口径统计。
6. 64 KiB 边界跨行、最后一行无换行、读到一半追加内容都不会解析残尾。
7. 读前后 size/mtime 改变时重试一次；第二次仍变化则返回已确认条目并加入 `.codexRolloutChangedDuringRead`。
8. 相同 size+mtime 的第二次查询命中 actor cache；追加后签名变化会重新读取。
9. `Task.cancel()` 在目录、文件和 chunk 循环中被检查。
10. rollout `mtime < window.startUTC` 时可以跳过正文，但 coverage 仍从 state 的 thread `created_at` 得到。
11. state 有多个 thread、其中一个 canonical rollout 缺失/损坏时，保留其他 thread 的确定数据并加入 `.codexRolloutUnreadable`；不能让单文件失败丢掉整批结果。
12. 可读且合法的空 state 加可枚举的空 rollout roots 返回 complete empty batch，不抛 source failure。

测试辅助对象不要依赖 sleep。为稳定模拟文件变化，给 source 注入一个只在测试使用的 read observer：

```swift
struct CodexUsageSourceHooks: Sendable {
    var didFinishReadAttempt: @Sendable (URL, Int) -> Void = { _, _ in }
}
```

**Step 2: 更新独立脚本并确认失败**

把 `CodexUsageSource.swift` 加入 `script/run_usage_checks.sh` 的 swiftc 输入，然后运行：

```bash
./script/run_usage_checks.sh
```

Expected: 编译失败，指向 `CodexUsageSource` 尚未定义。

**Step 3: 实现 source 的可注入边界**

建立 actor，并让默认值只在生产初始化时解析用户 home：

```swift
actor CodexUsageSource: UsageEntrySource {
    init(
        stateDatabaseURL: URL = /* ~/.codex/state_5.sqlite */,
        rolloutRoots: [URL] = /* sessions + archived_sessions */,
        queryRunner: any SQLiteJSONQueryRunning = SystemSQLiteJSONQueryRunner(),
        hooks: CodexUsageSourceHooks = CodexUsageSourceHooks()
    )

    func load(in window: UsageQueryWindow) async throws -> UsageSourceBatch
}
```

state 查询只读读取所有 thread 的 `id, rollout_path, created_at`。state 不可用时仍扫描目录并加入 `.codexStateUnavailable`；是否抛 source failure 按下面“无法证明为空且无法恢复数据”的边界决定，不能把合法空目录当失败。

失败边界必须区分：

- runner 的通用 `SQLiteJSONQueryError` 只在 Codex source 内映射为 `.codexStateUnavailable`。
- 单个已知 thread 的 canonical/fallback 文件缺失、不可读或 token 内容损坏：继续其他 thread，返回 batch 并加入 `.codexRolloutUnreadable`。
- state 查询成功且为空时，rollout roots 可枚举为空，或 fresh install 下预期的 sessions/archive roots 尚不存在，都按可信空数据处理并返回无 warning 的空 batch。
- 只有 state 无法读取且所有 rollout roots 也无法枚举、因而既不能证明为空也不能恢复任何数据时，才抛 `UsageSourceFailure(.codexRolloutUnreadable)`。

**Step 4: 实现 canonical candidate 选择**

处理顺序固定为：

1. 读取 state 的 thread id -> current rollout path。
2. 递归枚举两个 roots 的 `.jsonl`，从文件名 UUID 建立候选，必要时用首个 `session_meta.id` 校验。
3. 同一 canonical thread 分组。
4. state 当前路径存在且可读时优先选择该文件。
5. state 路径不可用时才比较候选：fingerprint、最后 token event、complete bytes。
6. fingerprint 与 sample count 先做快速预筛，再以完整 `samples` 相等确认 active/archive 是移动副本；只计一次。不要只凭 64-bit hash 判等。
7. 内容冲突按“最后完整 token event 更新者优先、再按 complete bytes”选一份，同时标 partial。

不得用路径字符串、mtime 或“Token/时间恰好相同”跨 thread 去重。日志/错误里不得暴露原始路径。

**Step 5: 实现 64 KiB 流式读取和 actor cache**

每次文件尝试：

- 读取开始的 `fileSize + contentModificationDate` 作为 `FileSignature`。
- `FileHandle.read(upToCount: 65_536)` 循环，并在每个目录、文件、chunk 循环调用 `try Task.checkCancellation()`。
- 维护最多一条未换行 remainder；只把以 `\n` 结束的完整行喂给 `CodexRolloutUsageParser`。
- EOF 时丢弃 remainder；绝不对整个 rollout 使用 `Data(contentsOf:)`。
- 到达 EOF 后、读取 post-read signature 之前调用测试 hook；随后再次取 signature。变化则清除本次 cache 并完整重试一次。这个固定位置让 fixture 不需要 sleep 就能稳定追加文件。
- 第二次仍变化，使用第二次完整行得到的结果，附加 `.codexRolloutChangedDuringRead`。

cache 以 canonical URL 索引，并在 value 中保存当前 `FileSignature(size, mtime)` 与 Task 2 定义的完整 `CodexRolloutParseResult.samples`；同 URL 签名变化时替换旧 value，每个 URL 最多保留一份，避免活动 rollout 每次追加都累积旧缓存。每次调用 `entries(in:)` 从 sample 序列重新做累计差分和窗口过滤。不能缓存“上一次窗口的 entries”并直接复用。

state canonical path 可读且文件 `mtime < window.startUTC` 时，允许不读正文并返回空 entries。state path 缺失且存在多个 fallback candidate 时，只要任一 candidate 可能与窗口相交，就必须解析后按 samples 解决移动/冲突；若全部 mtime 都早于窗口起点，它们不可能贡献本窗口 entries，可以跳过内容比较。coverageStart 取 state 最早 Unix-second `created_at` 与已解析首事件的较早者，coverageEnd 取已解析末事件的较晚者。

**Step 6: 加入静态资源合同**

CoreChecks 断言：

- 同时出现 `sessions` 与 `archived_sessions`。
- chunk size 为 `65_536`，不存在 `Data(contentsOf:` 读取 rollout。
- 读取循环有 cancellation 检查。
- cache signature 同时包含 size 与 mtime。
- canonical 选择优先 state rollout path，并有 conflict warning。
- state SQL 必须读取 `rollout_path`，因此静态隐私检查只切片检查 logger/metadata 调用不包含原始 path、prompt、title 或文件名；不能对整个 source 禁止 `rollout_path` 字符串。

**Step 7: 运行行为与核心检查**

Run:

```bash
./script/run_usage_checks.sh
swift run DynamicIslandCoreChecks
```

Expected: 两套检查通过；fixture 不读取真实用户目录。

**Step 8: 留下安全检查点**

Run:

```bash
git diff --check -- Sources/DynamicIsland/Support/CodexUsageSource.swift Tests/DynamicIslandUsageChecks/main.swift script/run_usage_checks.sh Tests/DynamicIslandCoreChecks/main.swift
```

Expected: 无输出、退出码 0。不要自动提交。

---

### Task 5: 合并两个数据源并淘汰过期查询

**Files:**

- Create: `Sources/DynamicIsland/Support/UsageAggregationService.swift`
- Modify: `Tests/DynamicIslandUsageChecks/main.swift`
- Modify: `script/run_usage_checks.sh`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Step 1: 先写 service failure matrix 与并发检查**

添加可控 source actor：

```swift
actor ControlledUsageSource: UsageEntrySource {
    enum Result { case success(UsageSourceBatch), failure(UsageWarningCategory) }
    // continuation 允许测试控制两个 source 的完成顺序
}
```

固定测试：

- 两源成功 -> 合并 snapshot；无记录且无 warning -> 完整的零值 snapshot，由 controller 映射为 `.empty`。
- Codex 成功、CC Switch 失败 -> 保留 Codex 数字并返回 completeness `.partial` 的 snapshot，包含 `.ccSwitchQueryFailed`。
- CC Switch 成功、Codex 失败 -> 保留非 Codex 数字并返回 completeness `.partial` 的 snapshot，不把 CC Switch Codex 行补回。
- 两源失败 -> `.failed`，不能显示零值。
- 两个 controlled source 都已开始后再分别恢复，证明使用并发加载而非串行 await。
- coverageStart 晚于窗口起点 -> snapshot completeness 为 `.partial` 且包含 `.insufficientCoverage`。
- 只有 `.unpricedUsage` -> snapshot completeness 仍为 `.complete`，但 cost 为 `nil`；后续 controller 会映射为 `.available`。
- 注入刷新时间后 snapshot 的 `refreshedAt` 完全等于捕获值。
- 用 continuation 先启动 generation 1/今日，再启动 generation 2/30天；先完成新请求并发布，再完成旧请求，实际 `UsageRefreshRequestIdentity` 必须拒绝旧结果，最终 snapshot 仍是 30天。

**Step 2: 把文件加入脚本并确认失败**

Run:

```bash
./script/run_usage_checks.sh
```

Expected: 编译失败，指向 service 类型缺失。

**Step 3: 实现最小 service API**

```swift
protocol UsageSnapshotLoading: Sendable {
    func loadSnapshot(
        in window: UsageQueryWindow,
        refreshedAt: Date
    ) async -> UsageAggregationOutcome
}

enum UsageAggregationOutcome: Equatable, Sendable {
    case snapshot(UsageSnapshot)
    case failed(Set<UsageWarningCategory>)
}

struct UsageRefreshRequestIdentity: Equatable, Sendable {
    let generation: Int
    let range: UsageTimeRange

    func permitsPublication(
        currentGeneration: Int,
        currentRange: UsageTimeRange,
        isCancelled: Bool
    ) -> Bool
}

actor UsageAggregationService: UsageSnapshotLoading {
    init(
        codexSource: any UsageEntrySource,
        ccSwitchSource: any UsageEntrySource
    )

    static func live() -> UsageAggregationService

    func loadSnapshot(
        in window: UsageQueryWindow,
        refreshedAt: Date
    ) async -> UsageAggregationOutcome
}
```

实现时用两个 `async let` 同时启动 source。把每个 source 的 typed failure 转成独立 result，不让一个 throw 取消另一个已经可用的结果。两个都失败才返回 `.failed`；一个成功时把失败类别并入成功 batch 的 warnings 再聚合并返回 `.snapshot`。`.available/.empty/.partial` 是 controller 发布到 UI 时的映射，不塞进 service。

`permitsPublication` 只在未取消、generation 相等且 range 相等时返回 true。不要在 service 内创建 timer、读取 UI 状态或访问 `IslandOverlayState`。旧查询覆盖由 controller 使用这个已行为测试的 identity guard 处理，service 保持纯加载职责。

**Step 4: 添加可选只读 live 校验模式**

`Tests/DynamicIslandUsageChecks/main.swift` 默认只运行 fixture。传入 `--live` 时才构建 `.live()`；先捕获同一个 `now + TimeZone.current`，再为四个范围建立相同 endUTC 的窗口并查询，只输出：

```text
range,totalTokens,requests,cacheHitRate,completeness,coverage,durationMs
```

禁止输出路径、thread id、模型、provider、prompt 或标题。live 模式不是默认 CI 门槛，真实数据异常时要返回非零并只打印 sanitized warning category。

若四个 snapshot 都是 complete，同一 endUTC 下的总 Token 和请求数必须满足 `今日 <= 3天 <= 一周 <= 30天`；这是半开区间子集关系的硬性 invariant。任一 snapshot partial 时不强行断言单调，但必须输出对应 sanitized warning，不能把缺源误报为算法通过。

**Step 5: 运行检查**

Run:

```bash
./script/run_usage_checks.sh
swift run DynamicIslandCoreChecks
```

Expected: fixture 行为与静态合同全部通过。

**Step 6: 留下安全检查点**

Run:

```bash
git diff --check -- Sources/DynamicIsland/Support/UsageAggregationService.swift Tests/DynamicIslandUsageChecks/main.swift script/run_usage_checks.sh Tests/DynamicIslandCoreChecks/main.swift
```

Expected: 无输出、退出码 0。不要自动提交。

---

### Task 6: 实现统计卡与 Apple 风格 Liquid Glass 时间抽屉

**Files:**

- Create: `Sources/DynamicIsland/Views/DataPrimaryContentView.swift`
- Modify: `Sources/DynamicIslandCore/IslandAnimationProfile.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`

**Step 1: 先写 UI 源码合同检查**

把 `DataPrimaryContentView.swift` 加入 `islandOverlaySources()`，并添加断言：

- 视图接口包含 presentation、selected range、active、drawer presented 与三个回调。
- 只出现一个当前范围按钮，不存在横排 `ForEach(UsageTimeRange.allCases)` segment。
- 单击当前范围 trigger 只切换本地抽屉状态，不调用选择或刷新回调。
- 没有 Chart、曲线、来源/模型/客户端 filter 或 timer。
- 560pt 以上四列，以下 2×2；每列最小 128pt。
- 数字使用 `.monospacedDigit()`，空/失败不伪装为 0。
- macOS 26 路径包含 `GlassEffectContainer`、interactive glass、`glassEffectID`、matched geometry transition。
- macOS 14/15 路径包含 material fallback；Reduce Transparency/Contrast/Reduce Motion 都有显式分支。
- 弹簧参数来自 `IslandAnimationProfile.default`，视图里不硬编码 `0.30/0.80`。
- drawer 选项本身不叠加第二层 glass。
- press feedback 是可中断状态反馈，不禁用快速反向点击。
- 保留 `testRemovedFeatureFilesAreGone` 的旧功能删除合同；新类型继续使用 `DataPrimaryContentView`、`CodexUsageSource`、`CCSwitchUsageSource`，不要复活旧 `DataPanelView`、`CodexUsageDataSource` 或 `CCSwitchUsageDataSource` 文件名。

在 animation profile 测试中断言：

```swift
expectEqual(IslandAnimationProfile.default.dataRangeDrawerResponse, 0.30, ...)
expectEqual(IslandAnimationProfile.default.dataRangeDrawerDampingFraction, 0.80, ...)
```

**Step 2: 运行并确认失败**

Run:

```bash
swift run DynamicIslandCoreChecks
```

Expected: Data 视图/animation 参数缺失导致失败。

**Step 3: 扩展统一动画参数**

在 `IslandAnimationProfile` 的 stored properties、initializer 与 `.default` 同步加入：

```swift
public let dataRangeDrawerResponse: Double
public let dataRangeDrawerDampingFraction: Double
```

默认分别为 `0.30` 与 `0.80`。不要顺手改动其他既有动画值。

**Step 4: 实现 Data 视图公共接口**

```swift
struct DataPrimaryContentView: View {
    let presentation: UsagePresentationState
    let selectedTimeRange: UsageTimeRange
    let isActive: Bool
    let isTimeRangeDrawerPresented: Bool
    let onTimeRangeDrawerPresentationChange: @MainActor (Bool) -> Void
    let onSelectTimeRange: @MainActor (UsageTimeRange) -> Void
    let onRefresh: @MainActor () -> Void
}
```

视图内部使用 `@Environment` 读取：

```swift
accessibilityReduceMotion
accessibilityReduceTransparency
colorSchemeContrast
```

布局固定遵守现有 primary content frame，不自行改 shell 尺寸：左上标题与总量、右上 `[今日⌄] [刷新]`，中间 4 项数据，底部缓存命中率。用 `GeometryReader` 的内容宽度决定 `>= 560` 四列，否则 2×2；不要按屏幕型号判断。

状态展示：

- `.idle/.loading(nil)`：静态“正在统计…”，无 skeleton/循环动画。
- `.loading(previous)`：保留旧 snapshot 并给刷新按钮静态 progress 状态。
- `.available/.partial`：显示 snapshot；partial 增加低强调提示与 help/accessibility 文案。
- `.empty`：显示可信的 0；缓存比率仍为 `N/A`。
- `.failed`：显示“统计数据暂不可用”和刷新入口，不显示零值。

**Step 5: 实现原生玻璃与后备表面**

用编译器和运行时双层保护，确保 macOS 14 deployment 可编译：

```swift
#if compiler(>=6.2)
if #available(macOS 26.0, *), !accessibilityReduceTransparency {
    nativeLiquidGlassControls
} else {
    fallbackControls
}
#else
fallbackControls
#endif
```

macOS 26 路径：

- 一个 `GlassEffectContainer(spacing: 0)` 管理 trigger、drawer、refresh。
- `@Namespace` 配合三个互不重复的 trigger/drawer/refresh IDs。Apple 的 custom Liquid Glass 指南要求每个 glass effect 在 namespace 内有唯一 identity；互斥 trigger/drawer 依靠同一 anchor、0 间距和 matched-geometry proximity 形变，不复用 ID。
- trigger 使用 Capsule，drawer 使用 `RoundedRectangle(cornerRadius: 12, style: .continuous)`，两者都使用 `.glassEffect(.regular.interactive(), in: shape)`，并在同一个 `withAnimation` hierarchy transition 中互换。
- 正常动效用 `.glassEffectTransition(.matchedGeometry)`；Reduce Motion 时改 identity/短交叉淡化。
- 抽屉宽度约 104pt，trigger 高度 24pt；从 trigger 位置向下浮出，不推动统计卡。
- 选项行用普通 fill/vibrancy，只有当前项用克制蓝色强调，不对每行调用 `glassEffect`。

身份和 morph 行为以 [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) 为准，并在 Task 7 做实机视觉确认；不要用传统 `matchedGeometryEffect` 代替 glass transition。

后备路径使用系统 material、相同连续圆角、细描边与阴影；Reduce Transparency 时改更不透明纯色，提高对比度时加强边界和前景对比。两条路径共享相同选项、键盘标签、accessibility 与点击回调。

抽屉 animation：正常为 `.spring(response: animationProfile.dataRangeDrawerResponse, dampingFraction: animationProfile.dataRangeDrawerDampingFraction)`；Reduce Motion 为 `easeOut(duration: animationProfile.reducedMotionFadeDuration)` 且不做位移/缩放形变。trigger、选项与刷新按钮统一复用 `IslandPressButtonStyle()`，不要再造第二套按压参数；快速再次点击要能立即反向。

Data 视图自身层级固定为 card 0、card 内透明关闭层 1、controls/drawer 2；抽屉不被 card 圆角裁剪。选择任一范围先调用关闭，再调用 `onSelectTimeRange`；刷新先关闭再调用 `onRefresh`。

**Step 6: 运行核心检查与编译**

Run:

```bash
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
```

Expected: 两者通过；特别确认 availability guard 没有 macOS 14 编译错误。

**Step 7: 留下安全检查点**

Run:

```bash
git diff --check -- Sources/DynamicIsland/Views/DataPrimaryContentView.swift Sources/DynamicIslandCore/IslandAnimationProfile.swift Tests/DynamicIslandCoreChecks/main.swift
```

Expected: 无输出、退出码 0。不要自动提交。

---

### Task 7: 接入 Data 页面、控制器刷新世代并完成视觉/运行时验收

**Files:**

- Modify: `Sources/DynamicIsland/Views/IslandOverlayState.swift`
- Modify: `Sources/DynamicIsland/Views/IslandOverlayView.swift`
- Modify: `Sources/DynamicIsland/Controllers/IslandPanelController.swift`
- Modify: `Tests/DynamicIslandCoreChecks/main.swift`
- Modify: `MEMORY.md`

**Step 1: 先写挂载与 controller 合同检查**

在 CoreChecks 增加源码合同，要求 Data 挂载完整复制 Tasks/Files 的过渡约束：

```text
frame(primaryContentFrame)
position(primaryContentFrame.midX/midY)
opacity(selected == .data)
offset(primaryContentOffset(for: .data))
disabled(!expanded || selected != .data)
allowsHitTesting(expanded && selected == .data)
accessibilityHidden(!expanded || selected != .data)
transition(primaryContentTransition)
zIndex(selected data ? 21 : 20；drawer 展开时 24)
```

再断言：

- `IslandOverlayState` 默认 range `.today`、presentation `.idle`。
- 抽屉是否展开只存在于 `IslandOverlayView @State`，不进入 `IslandOverlayState`。
- 外层关闭层 drawer 打开时为 z-index 23，File Shelf 仍为 22；Data drawer 为 24。
- 切页、收起、隐藏、选择、刷新、Data/card 外点击和 `onExitCommand` 都会关闭抽屉。
- 顶部导航位于关闭层上方，因此 primary binding setter 和独立 Files button action 都必须先显式关闭抽屉；再次点击已经选中的 Data 也能关闭，不能只依赖 selection `onChange`。
- 没有 `NSEvent.addGlobalMonitorForEvents`、local keyboard monitor 或新权限。
- controller 注入 `any UsageSnapshotLoading`，包含 task + generation + selected range 双 guard。
- controller 使用已经过 continuation 行为测试的 `UsageRefreshRequestIdentity`，并在现有 `deinit` 取消 Data refresh task。
- 首次进入 Data 且状态 idle 自动刷新；选择相同范围也刷新。
- 手动刷新同一范围可保留 previous snapshot；切到不同范围时 loading 必须清空旧范围 snapshot，不能在新标签下暂时显示旧数据。
- 日志只包含范围、总量、请求数、耗时、文件数、完整性、warning category，不含路径/thread/model/provider/prompt/title。

**Step 2: 运行并确认合同失败**

Run:

```bash
swift run DynamicIslandCoreChecks
```

Expected: Data 尚未挂载、controller 尚未编排，因此新检查失败。

**Step 3: 扩展 overlay state 与 view 回调**

在 `IslandOverlayState` 只加入：

```swift
@Published var dataUsageTimeRange: UsageTimeRange = .today
@Published var dataUsagePresentation: UsagePresentationState = .idle
```

在 `IslandOverlayView` 加入：

```swift
let onDataUsageTimeRangeChange: @MainActor (UsageTimeRange) -> Void
let onRefreshDataUsage: @MainActor () -> Void
@State private var isDataTimeRangeDrawerPresented = false
```

initializer 为两个回调提供 no-op 默认值，保持现有测试构造方便。将 `DataPrimaryContentView` 常驻挂载在 `isPrimaryContentEntranceActive` 区域，与 Tasks/Files 使用相同 frame、opacity、offset、disabled、hit testing、accessibility、transition 合同。

层级实现：

- 普通选中 Data 为 21。
- File Shelf overlay 保持 22。
- drawer 打开时在 `islandShell` 内加满 shell 的透明 contentShape 关闭层，z-index 23。
- Data mount 在 drawer 打开时提升到 24，否则使用 21/20。
- 顶部 primary navigation 是 `islandShell` 外部 sibling，继续可点击；不要让关闭层覆盖 navigation。

用 `onChange` 处理 `selectedPrimaryFeature`、`isExpanded`、`state.isShellHidden`，任一不再满足“展开且 Data 可见”即关闭。Data card/岛内空白关闭层点击也关闭。`.onExitCommand` 只在面板实际收到键盘命令时工作，不安装全局监听。

由于顶部 `PrimaryFeatureSwitcher` 与 `FilesPrimaryFeatureButton` 是 `islandShell` 外部 sibling、位于 z23 关闭层之上，还要修改现有转发点：`primaryFeatureSelection` 的 setter 先调用 `setDataTimeRangeDrawerPresented(false)` 再 `onPrimaryFeatureChange(feature)`；Files button action 也先关闭再调用 `fileShelfActions.onOpenFilesPrimaryFeature()`。这使重复点击当前 Data（selection 没变）和点击 Files 都能关闭抽屉，不能只靠 `.onChange(of: selectedPrimaryFeature)`。

**Step 4: 注入 loader 并实现 controller 查询世代**

在 controller 增加：

```swift
private let usageSnapshotLoader: any UsageSnapshotLoading
private var dataUsageRefreshTask: Task<Void, Never>?
private var dataUsageRefreshGeneration = 0
```

initializer 增加默认 `UsageAggregationService.live()` 的注入参数。`updateRootView()` 传入两个新回调。

实现：

```swift
private func selectDataUsageTimeRange(_ range: UsageTimeRange) {
    overlayState.dataUsageTimeRange = range
    refreshDataUsage()
}

private func refreshDataUsage() {
    let selectedRange = overlayState.dataUsageTimeRange
    let now = Date()
    let timeZone = TimeZone.current
    let window = selectedRange.queryWindow(now: now, timeZone: timeZone)
    dataUsageRefreshGeneration += 1
    let generation = dataUsageRefreshGeneration
    let requestIdentity = UsageRefreshRequestIdentity(
        generation: generation,
        range: selectedRange
    )
    let previous = overlayState.dataUsagePresentation.snapshot.flatMap {
        $0.queryWindow.range == selectedRange ? $0 : nil
    }
    overlayState.dataUsagePresentation = .loading(previous: previous)
    dataUsageRefreshTask?.cancel()
    let loader = usageSnapshotLoader
    dataUsageRefreshTask = Task { [weak self, loader] in
        let outcome = await loader.loadSnapshot(in: window, refreshedAt: now)
        guard let self,
              requestIdentity.permitsPublication(
                  currentGeneration: self.dataUsageRefreshGeneration,
                  currentRange: self.overlayState.dataUsageTimeRange,
                  isCancelled: Task.isCancelled
              ) else { return }
        self.publishDataUsage(outcome)
    }
}
```

`Task` 从 `@MainActor` controller 方法创建并继承主 actor，只有 loader 的 await 在其 actor 上执行；发布无需额外 `MainActor.run`。若编译器要求调整捕获语法，可以等价改写，但必须保留三重淘汰条件：task cancellation、generation、selected range。sqlite Process 取消不一定立即终止，所以不能只靠 cancel。

`publishDataUsage` 对 `.snapshot` 的映射固定为：Token completeness partial -> `.partial`；否则真实总量为零 -> `.empty`；其余 -> `.available`。`.failed` 原样发布为 `.failed`。

在 controller 现有 `deinit` 的其他 task cancellation 旁加入 `dataUsageRefreshTask?.cancel()`；不要新建第二个 lifecycle 路径。

在 `selectPrimaryFeature` 中，完成既有 Files/Tasks 清理后切到 `.data`；若 presentation 是 `.idle` 才自动调用 `refreshDataUsage()`。同 range 的抽屉选择不做 `guard old != new`，必须刷新。离开 Data 不启动新扫描，也不把已完成结果写到其他页面；允许当前查询以 generation 保护后缓存到隐藏 Data 状态。

**Step 5: 添加脱敏日志和项目记忆**

刷新开始/结束只记录已批准的聚合 metadata。对 warning 只记录 `rawValue`；不要记录 database/rollout URL、thread id、app type 或 SQL。

更新项目 `MEMORY.md` 的当前事实并追加事件：

- 将 `Important Current Contracts` 中旧的“Data 只读 CC Switch 并镜像到 app support”条目替换为已实现事实：Codex rollout 全量累计差分 + CC Switch 非 Codex、全程只读、不写本地镜像、无后台轮询。
- 按既有 Event Format 在旧事件前追加一条 2026-07-19 记录，说明来源与 request/canonical 去重口径、自然日范围、验证命令以及回退涉及的文件。
- 不修改无关历史条目，也不把实现计划中的推测写成已完成事实。

**Step 6: 运行自动验证**

Run:

```bash
./script/run_usage_checks.sh
swift run DynamicIslandCoreChecks
swift build --product DynamicIsland
```

Expected: 三项均通过。

然后执行只读真实数据对照：

```bash
./script/run_usage_checks.sh --live
```

Expected: 四个范围都只打印 sanitized 汇总；当四项都 complete 时总 Token 与请求数满足 `今日 <= 3天 <= 一周 <= 30天`。若存在 partial，每个范围的 completeness/coverage 和 warning 必须可解释，不能静默丢源。

**Step 7: 构建、启动并做视觉验收**

Run:

```bash
./script/build_and_run.sh
```

人工检查：

1. 展开岛并进入 Data，默认只看到 `[今日⌄] [刷新]`，没有四段横排按钮、曲线图或筛选。
2. 点击“今日”后抽屉从胶囊原位向下展开且浮在 card 上，不推动布局、不越过顶部 32pt 合同。
3. 连续快速点击可中断反向；选择同一范围也关闭并刷新。
4. 选择 3天/一周/30天后标签与数字更新；旧慢查询不能覆盖新范围。
5. 岛内抽屉外、Data card、切 Tasks/Files、收起、隐藏、可用时 Esc 都关闭抽屉。
6. File Shelf overlay 与 Data drawer 层级没有相互穿透；顶部导航仍可点击。
7. 系统 Reduce Motion、Reduce Transparency、提高对比度下分别确认淡化/后备表面/边界可读。
8. 对照 `--live` 的 total/request/hit rate，UI 不能把 partial/failed 显示成可信零值。

若可用，分别在 macOS 26 原生路径与 macOS 14/15 兼容环境检查；当前机器无法覆盖的系统版本必须在最终汇报列为未运行，不能宣称已验证。

**Step 8: 检查进程健康与静止 CPU**

Run:

```bash
pid=$(pgrep -x DynamicIsland | head -n 1)
ps -o pid,stat,pcpu,pmem,etime,command -p "$pid"
```

等待页面静止后再次执行一次。Expected: 进程健康，Data 页没有 timer 或持续动画造成的长期高 CPU；记录实际 `%CPU` 到最终汇报。

**Step 9: 最终差异与安全检查**

Run:

```bash
git diff --check -- Sources/DynamicIslandCore/UsageTimeRange.swift Sources/DynamicIslandCore/UsageSnapshot.swift Sources/DynamicIslandCore/CodexRolloutUsageParser.swift Sources/DynamicIslandCore/IslandAnimationProfile.swift Sources/DynamicIsland/Support/UsageSQLiteQueryRunner.swift Sources/DynamicIsland/Support/CodexUsageSource.swift Sources/DynamicIsland/Support/CCSwitchUsageSource.swift Sources/DynamicIsland/Support/UsageAggregationService.swift Sources/DynamicIsland/Views/DataPrimaryContentView.swift Sources/DynamicIsland/Views/IslandOverlayState.swift Sources/DynamicIsland/Views/IslandOverlayView.swift Sources/DynamicIsland/Controllers/IslandPanelController.swift Tests/DynamicIslandCoreChecks/main.swift Tests/DynamicIslandUsageChecks/main.swift script/run_usage_checks.sh MEMORY.md
git status --short
```

Expected: `diff --check` 无输出；`git status` 中既有用户改动仍保留，没有无关文件被改写。不要自动 stage 或 commit。

## 最终汇报格式

```text
## 改动
- 文件: 变更内容

## 验证
- ./script/run_usage_checks.sh: 通过/失败
- swift run DynamicIslandCoreChecks: 通过/失败
- swift build --product DynamicIsland: 通过/失败
- ./script/build_and_run.sh: 通过/失败
- --live 对照: 通过/部分/失败
- CPU: x%

## 未运行
- 无法覆盖的系统版本、辅助功能设置或原因

## 风险/后续
- partial coverage、运行时视觉结果、未提交脏工作树说明
```

## 实施时必须保留的验收口径

- Codex 先对每个 canonical thread 的完整时间序列逐字段差分，再按窗口过滤；不能先截日期再差分。
- 同时扫描 active 与 archived，包含子代理；state 当前 rollout path 优先，移动副本只计一次，冲突明确 partial。
- CC Switch 永久排除 Codex；非 Codex 只按 request id 去重，未知 input 语义不猜测。
- 真实总 Token = fresh input + output + cache creation + cache read；cached input/reasoning output 都不重复加入。
- 时间窗口是刷新开始时捕获的本地自然日 `[startUTC,endUTC)`；默认今日，无自动轮询。
- 只有一个时间按钮，点击后才出现四项抽屉；可用时采用原生 Liquid Glass，不可用时诚实后备。
- 任何不完整数据都显示 partial/failed；成本不可验证时显示 `N/A`，不冒充供应商账单。
