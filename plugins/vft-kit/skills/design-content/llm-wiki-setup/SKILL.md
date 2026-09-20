---
name: llm-wiki-setup
description: 初始化 LLM Wiki 知识库。当用户想创建 wiki、搭建个人知识库、初始化研究仓库或设置可被 Claude Code / Codex 维护的 wiki 时使用。创建 raw/wiki/output 目录、index.md、log.md、AGENTS.md、CLAUDE.md，并按领域生成基础 schema。即使用户只是说"帮我整理资料"、"建个笔记系统"、"我想开始记录这个主题"，也应该考虑使用本 skill。
---

# LLM Wiki Setup

初始化一个可被 LLM 持续维护的 wiki 仓库。目标不是做一次性 RAG，而是创建一个可累积、可查询、可持续更新的 markdown 知识库。

## 何时使用

- 用户要从零创建一个新 wiki
- 用户已有原始资料，但还没有规范化的目录和 schema
- 用户希望这个目录能同时被 Codex 和 Claude Code 顺畅使用

## 默认原则

- 缺少信息时，先做合理默认，不要因为小问题卡住
- 默认在当前工作目录下创建知识库根目录
- 默认目录为 `raw/`、`wiki/`、`output/`
- 默认创建 `wiki/index.md` 与 `wiki/log.md`
- 默认同时创建根目录下的 `AGENTS.md` 和 `CLAUDE.md`
- 默认 schema 先偏通用，后续再演化

## 建议目录结构

```text
<knowledge-base>/
├── AGENTS.md
├── CLAUDE.md
├── README.md
├── raw/
│   └── assets/
├── wiki/
│   ├── index.md
│   └── log.md
└── output/
```

按主题可以额外创建子目录，例如：

- 研究主题：`wiki/concepts/`、`wiki/sources/`、`wiki/people/`
- 书籍阅读：`wiki/chapters/`、`wiki/characters/`、`wiki/themes/`
- 商业分析：`wiki/companies/`、`wiki/products/`、`wiki/market/`

## 执行流程

### 0. 定位 Obsidian Vault

运行：

```bash
obsidian vault
```

输出示例：

```bash
name       Documents
path       /Users/xxx/Documents
files      744
folders    89
size       17025435
```

- 成功：取 `path` 字段作为 wiki 根目录的父目录候选，在其下创建知识库
- 失败（未安装 obsidian CLI）：回退到当前工作目录

### 1. 确认最少必要信息

优先获取：

- 知识库名称
- 主题或领域
- 是否有明显的 schema 偏好

如果用户没说清楚，使用：

- 名称：当前目录名或 `llm-wiki`
- 主题：`General Research Wiki`
- schema：通用研究型结构

### 2. 创建目录

创建：

- `raw/`
- `raw/assets/`
- `wiki/`
- `output/`

如用户主题明确，再补对应子目录。

### 3. 创建核心文件

至少创建以下文件：

- `wiki/index.md`
- `wiki/log.md`
- `AGENTS.md`
- `CLAUDE.md`
- `README.md`

其中：

- `index.md` 是内容索引
- `log.md` 是时间顺序操作日志
- `AGENTS.md` / `CLAUDE.md` 是 agent schema，告诉不同 agent 如何维护 wiki

### 4. 写入 index.md

`wiki/index.md` 应包含：

- 知识库目标
- 目录结构说明
- 主要入口页面
- 基础统计
- 最近更新时间

建议模板：

```markdown
---
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# <Knowledge Base Name>

## Purpose

<这个 wiki 的范围、目标、边界>

## Stats

- Raw sources: 0
- Wiki pages: 1
- Last updated: YYYY-MM-DD

## Main Entry Points

- [[index]]

## Structure

- `raw/`：原始资料，只读
- `wiki/`：LLM 维护的知识页
- `output/`：报告、幻灯片、导出物

## Conventions

- 优先更新现有页面，而不是重复建页
- 重要结论要保留来源
- 新洞察优先写入 wiki，再在对话中复述
```

### 5. 写入 log.md

`wiki/log.md` 应为 append-only：

```markdown
# Wiki Log

## [YYYY-MM-DD] setup | initialize wiki

- Created base structure
- Added schema files
- Initialized index and log
```

### 6. 创建 AGENTS.md 与 CLAUDE.md

这两个文件建议内容尽量一致，核心是让不同 agent 在打开仓库时立刻知道约束。

优先复用本 skill 自带模板：

- `references/AGENTS.template.md`
- `references/CLAUDE.template.md`

必须覆盖：

- `raw/` 只读，不修改原始资料
- `wiki/` 是主要工作区
- 查询优先读 `wiki/index.md`，再读相关页面
- ingest 时更新 `wiki/log.md`
- 新洞察可以写回 `wiki/`
- 引用时优先链接到 wiki 页面，必要时再指向 raw 来源

建议模板要点：

```markdown
# LLM Wiki Schema

## Purpose
This repository is a persistent LLM-maintained wiki built from raw sources.

## Rules
- Never edit files under `raw/` except when the user explicitly asks to add new sources.
- Treat `wiki/` as the maintained knowledge layer.
- Read `wiki/index.md` before broad queries.
- Update `wiki/log.md` after ingest, synthesis, or major maintenance passes.
- Prefer updating existing pages over creating near-duplicate pages.
- Preserve uncertainty, disagreement, and source boundaries.

## Workflows
- Ingest: read raw source, update relevant wiki pages, then append log.
- Query: answer from wiki first; only inspect raw if the wiki is clearly insufficient and the user asks.
- Generate: produce outputs from wiki content and preserve traceability.
```

`AGENTS.md` 服务 Codex，`CLAUDE.md` 服务 Claude Code。两者都存在会明显降低首次进入仓库时的“重新解释规则”成本。

### 7. 可选工具集成

如果本地有 `qmd`，可以配置它；没有就跳过，不要把 setup 卡死在外部依赖上。

优先级：

1. 纯 markdown + `rg`
2. `qmd`
3. Obsidian / Dataview / Marp 等增强能力

## 工具建议

- 列文件：`rg --files`
- 关键词检索：`rg -n "<pattern>" wiki raw`
- 最近修改：`find wiki -type f -name "*.md" -mtime -7`
- 可选搜索：`qmd search "<query>"`

## 完成标准

- 目录结构存在
- `wiki/index.md` 存在
- `wiki/log.md` 存在
- 根目录 `AGENTS.md` 存在
- 根目录 `CLAUDE.md` 存在
- README 说明了基本用法

## 注意事项

- 不要只创建目录，不写 schema 文件
- 不要把 agent 约束只写在 README 里
- 不要把 `index.md` 当成日志文件使用
- 不要假设用户一定安装了 Obsidian CLI 或 qmd
