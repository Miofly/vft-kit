---
name: llm-wiki-lint
description: 当用户要求对 `wiki/` 做健康检查、lint、巡检、结构整理，或查找矛盾、陈旧结论、孤儿页面、缺失交叉引用与知识缺口时使用。当用户说"整理一下 wiki"、"检查一下有没有问题"、"wiki 质量怎么样"、"有没有过时的内容"、"帮我维护一下知识库"时，也应该使用本 skill。wiki 运行超过 10 次 ingest 后，应主动建议用户运行一次 lint。
---

# LLM Wiki Lint

对整个 `wiki/` 做周期性健康检查。这个 skill 的重点不是导入新资料，而是发现结构问题、内容漂移和下一步值得补的空白。

## 何时使用

- 用户说“lint 一下 wiki”
- 用户要健康检查、巡检、maintenance pass
- 用户要查 orphan pages、broken structure、missing links
- 用户要找被新资料淘汰的旧结论
- 用户要找 gaps、open questions、下一步该补什么

## 默认原则

- 优先检查 `wiki/`，不要默认深读 `raw/`
- 这是全库检查，不是单次 source ingest
- 先产出发现，再决定是否批量修复
- 不确定的矛盾要标注，不要强行裁决
- 完成 lint pass 后更新 `wiki/log.md`

## 工作流程

### 1. 读取全局入口

先读：

```bash
cat wiki/index.md
tail -n 120 wiki/log.md
rg --files wiki
```

必要时补充：

```bash
find wiki -type f -name "*.md" -mtime -30
```

目标是先掌握当前结构、近期改动和页面分布。

### 2. 做全库检查

至少检查以下项目：

- 页面间是否存在明显矛盾
- 旧结论是否已被较新的来源或页面淘汰
- 是否存在孤儿页面或几乎没有连接的页面
- 重要概念是否被反复提及却没有独立页面
- 是否缺少关键 cross-references
- `index.md` 是否遗漏重要页面或入口
- `log.md` 是否长期未记录关键维护动作
- 是否存在明显的数据缺口，值得后续补 source 或做 web research

默认工具：

```bash
rg -n "<keyword>" wiki
rg -n "\\[\\[" wiki
```

如果本地有 `qmd`，可作为增强搜索，但不是硬依赖：

```bash
qmd search "<query>"
```

### 3. 输出发现

先给出 lint 结果，再决定是否改写 wiki。结果建议分为：

- Critical：会误导后续 query 的结构或内容问题
- Important：应该尽快整理，但不至于立刻误导
- Opportunities：可提升可导航性和长期价值的改进点

发现应尽量指向具体页面，并说明：

- 问题是什么
- 影响是什么
- 建议如何修复

#### 健康度评分机制

为 wiki 计算 0-10 分的健康度评分，让用户直观了解状态。

**评分维度**（每项 0-10 分，加权平均）：

1. **结构完整性（权重 25%）**
   - 10 分：`index.md` 和 `log.md` 存在且最近更新，所有重要页面都有入口
   - 7 分：核心文件存在，但部分页面缺少索引
   - 4 分：`index.md` 过时超过 30 天，或缺少关键入口
   - 0 分：核心文件缺失或严重过时

2. **内容一致性（权重 30%）**
   - 10 分：无明显矛盾，旧结论有明确标注
   - 7 分：存在 1-2 处矛盾但已标注在 `## Contradictions`
   - 4 分：存在 3+ 处未标注的矛盾
   - 0 分：大量矛盾且无标注，严重误导

3. **连接性（权重 20%）**
   - 10 分：无孤儿页面，重要概念间有充分交叉引用
   - 7 分：1-2 个孤儿页面，大部分概念有链接
   - 4 分：3+ 个孤儿页面，或重要概念缺少链接
   - 0 分：大量孤儿页面，wiki 碎片化严重

4. **可追溯性（权重 15%）**
   - 10 分：所有关键结论都有来源链接
   - 7 分：80%+ 的结论有来源
   - 4 分：50-80% 的结论有来源
   - 0 分：大量结论无来源，不可验证

5. **维护活跃度（权重 10%）**
   - 10 分：最近 7 天有更新，`log.md` 记录完整
   - 7 分：最近 30 天有更新
   - 4 分：30-90 天未更新
   - 0 分：90+ 天未更新，wiki 可能已过时

**计算公式**：

```
健康度 = (结构完整性 × 0.25) + (内容一致性 × 0.30) +
         (连接性 × 0.20) + (可追溯性 × 0.15) + (维护活跃度 × 0.10)
```

**评分解读**：

- **9-10 分**：优秀，wiki 运行良好
- **7-8 分**：良好，有小问题但不影响使用
- **5-6 分**：及格，需要维护但不紧急
- **3-4 分**：较差，应尽快修复关键问题
- **0-2 分**：严重，wiki 可能误导用户

**输出示例**：

```markdown
## Wiki Health Score: 7.2/10

### Breakdown
- Structure Integrity: 8/10 (index.md updated 3 days ago, all major pages indexed)
- Content Consistency: 6/10 (2 contradictions found, 1 unmarked)
- Connectivity: 8/10 (1 orphan page: [[old-draft]])
- Traceability: 7/10 (85% of claims have sources)
- Maintenance Activity: 7/10 (last update 5 days ago)

### Interpretation
Good overall health. Main issue: unmarked contradiction in [[llm-architectures]] needs attention.
```

### 4. 选择修复策略

如果用户只是要报告，可只输出发现，不修改文件。

如果用户允许修复，优先做以下类型的改动：

- 给相关页面补 `## Open Questions` / `## Contradictions`
- 增加缺失的 wikilinks
- 在 `wiki/index.md` 增补入口或结构说明
- 创建高价值但明显缺失的概念页 / synthesis 页
- 在页面中标记 stale claims，而不是悄悄删除历史判断

不要为了“更整齐”机械改写大量页面。

### 5. 记录 lint pass

如果执行了完整 lint pass，在 `wiki/log.md` 追加：

```markdown
## [YYYY-MM-DD] lint | wiki health check

- Checked: structure, contradictions, stale claims, links, gaps
- Updated: [[page-a]], [[page-b]]
- Created: [[page-c]]（如果有）
- Findings: <最重要的 1-3 个发现>
- Next: <建议补充的 source / query / follow-up>
```

## 常见输出格式

简短报告：

```markdown
## Wiki Health Score: 7.2/10

### Breakdown
- Structure: 8/10
- Consistency: 6/10
- Connectivity: 8/10
- Traceability: 7/10
- Activity: 7/10

## Lint Findings

- Critical: Unmarked contradiction in [[llm-architectures]] between SSM performance claims
- Important: [[old-draft]] is an orphan page with no incoming links
- Opportunities: Add cross-references between [[transformers]] and [[attention-mechanisms]]
```

较完整报告：

```markdown
## Wiki Health Score: 7.2/10

### Score Breakdown
- Structure Integrity: 8/10 (index.md updated 3 days ago, all major pages indexed)
- Content Consistency: 6/10 (2 contradictions found, 1 unmarked)
- Connectivity: 8/10 (1 orphan page: [[old-draft]])
- Traceability: 7/10 (85% of claims have sources)
- Maintenance Activity: 7/10 (last update 5 days ago)

### Interpretation
Good overall health. Main issue: unmarked contradiction in [[llm-architectures]] needs attention.

## Summary

Wiki is in good shape overall. 45 pages, well-structured, actively maintained. One critical issue (unmarked contradiction) and a few minor improvements needed.

## Findings

### Critical

- [[llm-architectures]]: Contradictory claims about SSM inference speed
  - Line 23 says "15-20% faster"
  - Line 67 says "2-3x faster"
  - Source: [[../raw/mamba-paper]] vs [[../raw/striped-hyena-paper]]
  - Impact: Misleads users about performance expectations
  - Fix: Add `## Performance Claims` section with both claims and context

### Important

- [[old-draft]]: Orphan page with no incoming links
  - Created 45 days ago, never referenced
  - Impact: Dead content clutters wiki
  - Fix: Either link from [[index]] or delete if obsolete

- [[transformers]] and [[attention-mechanisms]]: Missing cross-reference
  - Both pages discuss attention but don't link to each other
  - Impact: Users may miss related content
  - Fix: Add mutual wikilinks

### Opportunities

- [[index.md]]: Could add "Recently Updated" section
  - Would help users discover fresh content
  - Low effort, high value

- Several pages lack `## Open Questions` sections
  - Pages: [[ssm]], [[hybrid-architectures]], [[scaling-laws]]
  - Would make knowledge gaps explicit

## Suggested Next Steps

1. Fix critical contradiction in [[llm-architectures]]
2. Decide on [[old-draft]]: link or delete
3. Add cross-references between related pages
4. Consider adding "Recently Updated" to index
```

## 常见错误

- 把 lint 当成 ingest，用它处理新资料
- 只查单页，不做全库视角检查
- 看到冲突就直接覆盖旧内容
- 只做格式清理，不处理知识结构问题
- 忘记把 lint pass 记入 `wiki/log.md`

## 与其他技能的边界

- 初始化结构：使用 `$llm-wiki-setup`
- 导入新资料并更新知识页：使用 `$llm-wiki-ingest`
- 基于现有 wiki 回答问题：使用 `$llm-wiki-query`
- 从 wiki 生成报告、摘要、幻灯片：使用 `$llm-wiki-generate`

`$llm-wiki-lint` 只负责健康检查和维护，不负责把新的 `raw/` source 编译进 wiki。
