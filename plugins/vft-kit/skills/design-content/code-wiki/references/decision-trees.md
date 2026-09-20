# 决策树

复杂决策逻辑的可视化指南。

## 1. 项目类型判定

```mermaid
flowchart TD
    A[扫描项目] --> B{存在 workspace 配置?}
    B -->|是| C[Monorepo]
    B -->|否| D[标准项目]

    C --> E{packages 数量}
    E -->|1个| F[单包项目<br/>按标准项目处理]
    E -->|2+| G[真 Monorepo]

    D --> H{模块数量}
    H -->|< 3| I[小型项目<br/>合并维度分析]
    H -->|3-15| J[中型项目<br/>标准流程]
    H -->|> 15| K[大型项目<br/>启用分批模式]
```

**判定依据**:
- workspace 配置: `pnpm-workspace.yaml`, `package.json` workspaces, `lerna.json`
- 模块数量: `src/` 下的顶层子目录数

## 2. 运行模式选择

```mermaid
flowchart TD
    A[用户请求] --> B{存在 _meta.json?}
    B -->|否| C[首次生成<br/>标准流程]
    B -->|是| D{用户指定模式?}

    D -->|--update| E{代码有变更?}
    E -->|是| F[增量更新模式]
    E -->|否| G[提示: 无变更]

    D -->|--upgrade| H{文档质量不足?}
    H -->|是| I[质量升级模式]
    H -->|否| J[提示: 质量达标]

    D -->|无| K[标准流程<br/>全量重新生成]
```

**模式特点**:
- 标准流程: Phase 1-5 完整执行
- 增量更新: 仅刷新变更部分，保留用户内容
- 质量升级: 重新生成低质量文档，代码不变

## 3. 子 Agent 派发决策

### 标准项目派发

```
维度子 Agent (6 个固定)
├─ architecture
├─ api-surface
├─ data-model
├─ dependencies
├─ verification
└─ infrastructure

模块子 Agent (N 个)
└─ 每个模块 1 个
```

### Monorepo 派发

```
全局维度 (4 个)
├─ architecture (包间)
├─ dependencies (包间)
├─ infrastructure
└─ verification

每个包
├─ overview (必有)
├─ api-surface (条件: bff/sdk/tool)
├─ message-protocol (条件: ui)
└─ 包内模块 (条件: 有内部模块)
```

## 4. 分析策略选择

### API Surface 分析策略

```mermaid
flowchart TD
    A[定位路由文件] --> B[统计文件数 N 和最大行数 Lmax]
    B --> C{Lmax > 1000?}
    C -->|是| D[采样模式<br/>仅汇总表格]
    C -->|否| E{Lmax > 500?}
    E -->|是| F[摘要模式<br/>表格无参数详情]
    E -->|否| G{N > 40?}
    G -->|是| D
    G -->|否| H{N > 15?}
    H -->|是| F
    H -->|否| I[全量分析<br/>含参数和返回值]
```

**策略说明**:
- 全量: 每个端点列出参数和返回值
- 摘要: 仅表格（方法/路径/描述）
- 采样: 按模块汇总 + 端点总数
