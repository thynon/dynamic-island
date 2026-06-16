# Codex + Git 协作流程

## 当前项目状态

Island 是一个已有 SwiftPM macOS 项目，不是空仓库。

因此提交时必须特别小心：

- 不要把不相关业务代码顺手提交。
- 不要用 `git add .` 提交整个工作区。
- 先看 `git status --short`，再明确选择要提交的文件。
- 如果有用户未确认的代码改动，保留它们，不回滚、不覆盖。

## 推荐流程

查看状态：

```bash
git status --short --branch
```

查看改动摘要：

```bash
git diff --stat
```

只提交指定文件：

```bash
./script/safe_git_save.sh "Update docs" docs/CODEX_GIT_WORKFLOW.md script/safe_git_save.sh AGENTS.md
```

推送：

```bash
git push
```

## Codex 操作规则

让 Codex 改 Island 时，建议这样说：

```text
只修改和这个任务相关的文件，不要提交其他未提交改动。
```

```text
提交前先给我看 git status 和 git diff --stat。
```

```text
只 stage 你本轮新建或修改的文件。
```

## 验证要求

按改动类型选择：

- 核心逻辑：`swift run IslandCoreChecks`
- 主程序编译：`swift build --product Island`
- 运行应用：`./script/build_and_run.sh`

无法运行时要说明原因。

## 不要提交的内容

- `.build/`
- `dist/`
- `output/`
- `.env*`
- secrets、tokens、keys、credentials
- `.reference/`

