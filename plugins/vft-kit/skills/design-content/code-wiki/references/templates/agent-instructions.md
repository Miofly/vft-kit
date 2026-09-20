# Agent 指令文件模板（CLAUDE.md / AGENTS.md）

Phase 5 中写入 Agent 指令文件时使用此模板。`{变量}` 从 `_meta.json` 和实际生成的文件中获取。

如果目标文件已存在，将以下内容插入到文件**第一个 `##` 标题之前**（保留原有文件标题行）。如果文件不存在，加上 `# CLAUDE.md` 或 `# AGENTS.md` 标题后写入。

```markdown
## 工程知识库

本项目有自动生成的结构化知识库，位于 `{output}/` 目录。在执行任务前，根据任务类型读取对应文件以获取完整上下文。

**首次接触本项目时**：读 `{output}/INDEX.md` 获取全局导航。

**执行任务前的阅读路径**：

| 任务类型 | 先读 | 再读 |
|---------|------|------|
| 修改某个模块的代码 | `{output}/conventions.md` | `{output}/modules/{对应模块}.md` |
| 添加新 API 接口 | `{output}/api-surface.md` | 对应模块文档 + `{output}/conventions.md` |
| 修改数据模型/实体 | `{output}/data-model.md` | `{output}/dependencies.md` 了解影响范围 |
| 架构性变更 | `{output}/architecture.md` | `{output}/dependencies.md` |
| 构建/部署问题 | `{output}/infrastructure.md` | — |
| 不确定影响范围 | `{output}/dependencies.md` | `{output}/verification.md` 查看影响矩阵 |

**修改完成后**：读 `{output}/verification.md` 和对应模块文档的"验证指南"段落，执行验证步骤确保无回归。

**模块列表**: {从 _meta.json 动态生成的模块名列表，逗号分隔}

```

## Monorepo: Agent 指令文件模板适配

当项目为 monorepo 时，Phase 5 的 Agent 指令文件模板调整阅读路径：

```markdown
## 工程知识库

本项目有自动生成的结构化知识库，位于 `{output}/` 目录。在执行任务前，根据任务类型读取对应文件以获取完整上下文。

**首次接触本项目时**：读 `{output}/INDEX.md` 获取全局导航和包一览。

**执行任务前的阅读路径**：

| 任务类型 | 先读 | 再读 |
|---------|------|------|
| 修改某个包的代码 | `{output}/packages/{包名}/overview.md` | 对应包内模块文档 |
| 对接或修改 BFF API | `{output}/packages/{bff包名}/api-surface.md` | `{output}/conventions.md` |
| 对接或修改 SDK 方法 | `{output}/packages/{sdk包名}/api-surface.md` | 对应包的 overview |
| 理解包间通信 | `{output}/architecture.md` | 相关包的 message-protocol.md |
| 修改共享类型 | `{output}/packages/{types包名}/overview.md` | `{output}/dependencies.md` 了解影响范围 |
| 架构性变更 | `{output}/architecture.md` | `{output}/dependencies.md` |
| 构建/部署问题 | `{output}/infrastructure.md` | — |
| 不确定影响范围 | `{output}/dependencies.md` | `{output}/verification.md` 查看影响矩阵 |

**修改完成后**：读 `{output}/verification.md` 和对应包文档的验证指南，执行验证步骤。

**包列表**: {从 _meta.json 动态生成的包名列表}
```
