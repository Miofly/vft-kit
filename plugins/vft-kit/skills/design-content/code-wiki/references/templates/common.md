# 通用规范

生成知识库文档时，严格遵循以下规范。`{变量}` 表示需要填入实际内容的占位符。

## 段落来源引用 (P0)

每个 `##` 段落末尾必须标注该段落信息的来源文件，格式如下：

```markdown
> 📄 Sources: [`filename:start-end`](file://relative/path#Lstart-Lend), [`filename2:start-end`](file://relative/path2#Lstart-Lend)
```

**规则:**
- 合成文档（INDEX.md、overview.md、glossary.md、conventions.md）免除此要求
- 超过 5 个来源文件时，取最关键的 5 个，末尾注明"等 N 个文件"
- 来源行放在段落最末尾，与正文间空一行
- 行号范围应精确到实际引用的代码/配置区域

## 图表类型精确映射

文档中使用 Mermaid 图表时，根据内容类型选择正确的图表类型：

| 内容类型 | 图表类型 |
|---------|---------|
| 模块调用/依赖 | `flowchart TD` / `graph LR` |
| 请求/响应时序 | `sequenceDiagram` |
| 实体关系 | `erDiagram` |
| 类/接口层级 | `classDiagram` |
| 状态变迁 | `stateDiagram-v2` |
| CI/CD 流水线 | `flowchart LR` |
