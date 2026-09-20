---
name: llm-wiki-ingest
description: 读取 `raw/` 中的新资料并整合进 LLM Wiki。当用户要求处理文档、导入资料、更新知识库、将文章/论文/笔记整合到 wiki 时使用。优先更新 `wiki/` 页面，维护交叉引用、来源和 `wiki/log.md`。当用户说"处理这个文档"、"把这篇文章加进去"、"更新知识库"、"导入资料"，甚至只是粘贴了一段文本说"记下来"、"整合进去"时，都应该使用本 skill。
---

# LLM Wiki Ingest

把原始资料增量编译进 wiki。这个 skill 的重点不是“做摘要”，而是“更新知识结构”。

## 何时使用

- 用户让你处理 `raw/` 中的新文件
- 用户给出文章、论文、笔记、纪要，希望并入 wiki
- 查询时发现知识缺口，用户决定补资料

## 默认原则

- `raw/` 只读，不修改原始资料
- 优先更新现有页面，而不是重复建页
- 每次 ingest 都更新 `wiki/index.md` 和 `wiki/log.md`
- 有矛盾时明确标注，不强行统一
- 没有 `qmd` 也能工作，默认使用 `rg` 和直接读文件

## 工作流程

### 1. 确定处理对象

优先级：

1. 用户明确指定的文件
2. 用户指定的目录
3. 如果只说”处理新资料”，找最近新增或最近修改的 `raw/` 文件

可用命令：

```bash
rg --files raw
find raw -type f | xargs ls -t
```

#### 批量处理策略

当用户要求”处理 raw/ 下所有新文件”或”批量导入”时：

1. **识别新文件**：
   ```bash
   find raw -type f -name “*.md” -mtime -7  # 最近 7 天
   find raw -type f -newer wiki/log.md      # 比 log.md 更新的文件
   ```

2. **按优先级排序**：
   - 先处理明确的主题文件（如 `concepts/`, `papers/`）
   - 再处理杂项文件（如 `misc/`, `inbox/`）

3. **批量处理模式**：
   - 每处理 3-5 个文件后，更新一次 `wiki/index.md` 和 `wiki/log.md`
   - 避免一次性处理超过 10 个文件而不记录中间状态
   - 如果某个文件处理失败，跳过并记录到日志的 `## Skipped` 部分

4. **批量日志格式**：
   ```markdown
   ## [YYYY-MM-DD] ingest | batch import (N files)

   - Sources: [[../raw/file1]], [[../raw/file2]], [[../raw/file3]]
   - Created: [[new-page-1]], [[new-page-2]]
   - Updated: [[existing-page-1]], [[existing-page-2]]
   - Skipped: [[../raw/problematic-file]] (reason: <说明>)
   - Notes: <整体观察>
   ```

### 2. 读取资料

按文件类型处理：

- Markdown / text：直接读取
- PDF：提取文本或要求已有可读版本
- 图片：只在图片包含关键信息时再额外分析

先读文本，再决定是否需要读图片或附件。

### 3. 找到受影响的 wiki 页面

先读：

```bash
cat wiki/index.md
```

然后用关键词在 `wiki/` 中搜索：

```bash
rg -n "<keyword>" wiki
```

如果本地存在 `qmd`，可额外使用：

```bash
qmd search "<query>"
```

### 4. 选择“更新”还是“新建”

优先更新已有页面，只有在以下情况才新建：

- 明显是新的实体 / 概念 / 主题
- 当前信息塞进现有页面会让页面失焦
- 需要独立承载长期累积的信息

### 5. 写入页面内容

页面建议包含：

- 简短概述
- 本次新增的信息
- 相关页面链接
- 来源列表

可选 frontmatter：

```yaml
---
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources:
  - [[../raw/<source-file>]]
tags:
  - topic
---
```

正文建议：

```markdown
# <Title>

## Summary

<一句话说明页面主题>

## Key Points

- <新增信息 1>
- <新增信息 2>

## Related

- [[related-page]]

## Sources

- [[../raw/<source-file>]]
```

### 6. 处理矛盾和不确定性

如果新资料与现有 wiki 冲突：

- 在对应页面增加 `## Open Questions` 或 `## Contradictions`
- 明确写出不同来源各自主张什么
- 不要删除旧结论，除非已有更高置信度的修订共识

### 7. 更新 index.md

至少更新：

- 页面数量或结构性入口
- 新建的重要页面链接
- `updated` 日期

`index.md` 负责帮助后续查询快速定位内容，而不是记录每次细节变更。

### 8. 追加 log.md

在 `wiki/log.md` 追加一条日志：

```markdown
## [YYYY-MM-DD] ingest | <source title>

- Source: [[../raw/<source-file>]]
- Created: [[new-page]]（如果有）
- Updated: [[existing-page-1]], [[existing-page-2]]
- Notes: <矛盾、空白、后续建议>
```

### 9. 向用户汇报结果

简要说明：

- 处理了哪些来源
- 新建了哪些页面
- 更新了哪些页面
- 是否发现矛盾或知识缺口

## 搜索与回退策略

按以下顺序工作：

1. `wiki/index.md`
2. `rg -n` 搜索 `wiki/`
3. 直接读取相关页面
4. 可选使用 `qmd`
5. 仅当 wiki 明显不足时，再继续深读 `raw/`

## 常见错误

- 只写摘要，不更新相关概念页
- 新建过多重复页面
- 忘记更新 `wiki/log.md`
- 把未经确认的推断写成确定结论
- 直接改写 `raw/` 文件

## 与其他技能的边界

- 初始化仓库结构：使用 `$llm-wiki-setup`
- 基于现有 wiki 回答问题：使用 `$llm-wiki-query`
- 周期性健康检查与维护：使用 `$llm-wiki-lint`
- 从 wiki 生成报告或幻灯片：使用 `$llm-wiki-generate`
