---
name: llm-wiki-query
description: 基于 `wiki/` 里的结构化知识回答问题。当用户让你查询 wiki、总结主题、比较概念、梳理关系、查看最近变化时使用。优先读取 `wiki/index.md` 和相关页面，在必要时将新综合结果写回 wiki。当用户提到"查一下"、"有没有关于X的"、"wiki里记录了什么"、"最近更新了什么"、"给我讲讲X"、"X和Y有什么区别"时，都应该使用本 skill。
---

# LLM Wiki Query

查询时优先利用 wiki 已经积累好的结构，而不是每次重新从原始资料开始挖。

## 何时使用

- 用户问“wiki 里关于 X 有什么”
- 用户要总结一个主题
- 用户想比较两个概念或实体
- 用户想了解最近更新或整体结构

## 默认原则

- 先查 `wiki/`，不要默认直接查 `raw/`
- 广域问题先读 `wiki/index.md`
- 回答必须可追溯到具体页面
- 只有出现真正的新综合洞察时，才把结果写回 wiki
- 没有 `qmd` 也必须能工作

## 查询流程

### 1. 判断问题类型

常见类型：

- 事实查询：定义、时间、单点信息
- 关系查询：A 和 B 的联系、影响、区别
- 综合查询：某主题的完整总结
- 探索查询：wiki 结构、最近更新、覆盖范围

### 2. 先读 index.md

对于非极小问题，先读：

```bash
cat wiki/index.md
```

必要时再看：

```bash
tail -n 80 wiki/log.md
```

`index.md` 负责找内容入口，`log.md` 负责看近期发生了什么。

### 3. 搜索相关页面

默认使用：

```bash
rg -n "<query or keyword>" wiki
rg --files wiki
```

如果 `qmd` 可用，可作为增强：

```bash
qmd search "<query>"
```

### 4. 读取最相关页面

优先读取：

- 直接命中的页面
- 从这些页面里的 wikilink 指向的 1 跳相关页面
- 最近更新且与问题强相关的页面

避免无节制地全库扫描。

### 5. 综合回答

回答应包含：

- 直接答案
- 关键依据
- 相关页面
- 不确定性或冲突说明

简短格式：

```markdown
<直接答案>

Sources:
- [[page-a]]
- [[page-b]]
```

较完整格式：

```markdown
## Answer

<直接回答>

## Key Evidence

- [[page-a]]: <要点>
- [[page-b]]: <要点>

## Open Questions

- <缺口或冲突>
```

### 6. 判断是否写回 wiki

只有满足以下任一条件才考虑写回：

- 跨多个页面形成了新的稳定综合
- 发现了重要但缺失的交叉链接
- 用户明确要求把回答沉淀成页面

可写回的内容包括：

- 新的 synthesis 页面
- 页面间新增交叉链接
- `gaps` / `open-questions` 页面

写回后同步：

- 更新 `wiki/index.md`
- 追加 `wiki/log.md`

## 探索性查询

如果用户问“wiki 里有什么”或“最近发生了什么”，优先输出：

- 主要主题
- 关键入口页面
- 最近更新
- 可能的知识缺口

建议读：

```bash
cat wiki/index.md
tail -n 120 wiki/log.md
find wiki -type f -name "*.md" -mtime -14
```

## 常见错误

- 直接跳过 `index.md`
- 把 `raw/` 当主检索层
- 引用不清楚，让答案不可回溯
- 为了“沉淀知识”而机械创建低价值页面
- 没区分内容索引和操作日志

## 与其他技能的边界

- 缺结构时先用 `$llm-wiki-setup`
- 缺内容时用 `$llm-wiki-ingest`
- 需要健康检查或结构巡检时用 `$llm-wiki-lint`
- 需要报告、幻灯片、交付物时用 `$llm-wiki-generate`
