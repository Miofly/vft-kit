# 高级参数说明

SKILL.md 中仅保留 4 个核心参数，其余高级参数在此说明。

## 分析深度

### --depth

- **默认值**: `logic`
- **可选值**: `logic` | `full`
- **说明**:
  - `logic`: 分析模块职责、接口、数据流
  - `full`: 额外包含函数/类级实现细节

## 范围控制

### --modules

- **默认值**: 全部
- **格式**: 逗号分隔的模块名
- **说明**: 仅生成指定模块文档（全局文件仍完整生成）
- **Monorepo 格式**: `pkg:模块名`（如 `sdk:auth,ui:components`）

### --packages

- **默认值**: 全部
- **格式**: 逗号分隔的包名
- **说明**: (Monorepo) 仅生成指定包的文档

## 模式开关

### --batch

- **默认值**: `false`（模块数 > 15 自动启用）
- **说明**: 分批交互模式，避免一次性派发过多子 Agent

### --domains

- **默认值**: `false`
- **说明**: 按业务领域分层组织模块目录（如 `modules/auth/`, `modules/payment/`）

### --upgrade

- **默认值**: `false`
- **说明**: 质量升级模式，重新生成低于质量阈值的文档

## 参数持久化

首次生成时使用的参数会保存到 `_meta.json` 的 `generation_params` 字段。

后续运行时，如果未显式指定参数，会自动读取上次的参数作为默认值。

**示例**:
```bash
# 首次生成，使用 full 深度
/code-wiki --depth full

# 后续增量更新，自动继承 --depth full
/code-wiki --update
```
