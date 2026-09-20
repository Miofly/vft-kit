# 子 Agent Prompt 模板

派发子 Agent 时，读取对应 prompt 模板，将 `{变量}` 替换为 skeleton.json 中的实际数据。

## 文件组织

- `standard/` - 标准项目的维度 prompts（6 个）
  - `architecture.md` - 架构分析
  - `api-surface.md` - API 接口提取（含 token 预算策略）
  - `data-model.md` - 数据模型分析
  - `dependencies.md` - 依赖图谱构建
  - `verification.md` - 测试验证体系
  - `infrastructure.md` - 构建部署分析
- `monorepo/` - Monorepo 项目的全局维度 prompts（2 个）
  - `architecture.md` - 包间架构分析
  - `dependencies.md` - 包间依赖分析
- `package/` - Monorepo 包级 prompts（4 个）
  - `overview.md` - 包概览（必定派发）
  - `api-surface.md` - 包级 API 接口
  - `message-protocol.md` - 消息通信协议
  - `module.md` - 包内模块分析
- `module.md` - 标准项目模块分析通用 prompt

## 使用规则

1. 非 Monorepo: 读取 `standard/` 下的维度 prompts + `module.md`
2. Monorepo: 读取 `monorepo/` 下的全局维度 prompts + `package/` 下的包级 prompts + `module.md`（如有包内模块）

## Monorepo 注意事项

- 全局 api-surface 和 data-model **不派发**，改为按包派发
- verification 和 infrastructure 使用 `standard/` 中的 prompt（Monorepo 无需单独变体）
