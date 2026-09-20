---
name: code-wiki
description: Use when the user wants to generate a project knowledge base, create documentation for a codebase, build a wiki for their repository, or help AI agents understand a project. Trigger this skill whenever the user says "generate wiki", "create knowledge base", "document this project", "analyze codebase", "code-wiki", or asks for project documentation that would help AI agents or new developers understand the full picture of a codebase. Also use when the user wants to understand project architecture, module relationships, or create a structured overview of their code.
---

# Code-Wiki: 工程知识库生成器

通过 5 个阶段深度分析代码工程，生成 `.wiki/` 目录下的结构化知识库，让任何 Code Agent 读完即可掌握工程全貌。

## 快速开始

### 基础用法

```bash
# 标准项目 - 生成完整知识库
/code-wiki

# Monorepo - 生成完整知识库
/code-wiki

# 仅生成指定模块
/code-wiki --modules auth,user

# 增量更新（仅刷新变更部分）
/code-wiki --update
```

### 使用场景决策树

```
用户需求
├─ 首次生成？
│  ├─ 是 → 标准流程（Phase 1-5）
│  └─ 否 →
│     ├─ 代码有变更？→ --update 模式
│     └─ 文档质量不足？→ --upgrade 模式
│
├─ 项目类型？
│  ├─ 标准项目 → 6 个维度 + N 个模块
│  └─ Monorepo → 4 个全局维度 + 每包独立分析
│
└─ 模块数量？
   ├─ < 15 → 全量并行
   └─ > 15 → 自动启用分批模式
```

## 核心参数

| 参数 | 默认值 | 说明 |
|------|-------|------|
| `--output` | `.wiki/` | 输出目录路径 |
| `--update` | `false` | 增量更新模式 |
| `--modules` | 全部 | 逗号分隔的模块名 |
| `--lang` | `zh` | 输出语言（zh/en）|

更多高级参数见 `references/advanced-params.md`

## 核心流程

### Phase 1: 全局扫描

**目标**: 建立项目骨架，识别项目类型和模块边界

1. 扫描目录树，识别技术栈和项目类型（见下方"多语言项目检测"）
2. 判断是否为 Monorepo（检查 workspace 配置）
3. 识别模块边界（src/ 子目录、packages/*、或语言特定的模块结构）
4. 计算模块代码指标（source_lines, export_count）
5. 检测 LSP 可用性
6. 生成 `{output}/skeleton.json`（格式见 `references/schemas.md`）

**多语言项目检测**:

Phase 1 需根据项目入口文件判定语言生态，不同语言的模块边界识别方式不同：

| 语言/生态 | 入口标志 | 模块边界 | Monorepo 判定 |
|----------|---------|---------|--------------|
| JS/TS | `package.json` | `src/` 子目录 | `pnpm-workspace.yaml`, `workspaces` |
| Python | `pyproject.toml`, `setup.py` | 顶层包目录（含 `__init__.py`） | 多个 `pyproject.toml` |
| Go | `go.mod` | 顶层包目录 | `go.work` |
| Rust | `Cargo.toml` | `src/` + `mod.rs` 结构 | `[workspace]` in `Cargo.toml` |
| Java/Kotlin | `pom.xml`, `build.gradle` | `src/main/java/` 包结构 | `<modules>` in `pom.xml` |

当检测到非 JS/TS 项目时，调整 `skeleton.json` 的 `tech_stack` 和模块识别逻辑。LSP 指南中的操作仍然通用。

**Monorepo 额外步骤**:
- 读取 workspace 配置获取包列表
- 判定每个包的 package_role（bff/sdk/ui/tool/app/shared）
- 推导 recommended_dimensions（每个包应生成的维度文档）
- 分析包内模块（src/ 有 3+ 子目录且 > 500 行）。**跳过 source_lines < 500 的小模块**，其内容由包级 overview 覆盖
- 构建 cross_package_deps（包间依赖关系）

**输出**: `skeleton.json`, `_progress.json`

### Phase 2: 并行深度分析

**目标**: 派发子 Agent 并行分析各维度和模块

读取 `skeleton.json`，根据项目类型派发子 Agent。

**并发控制**: 同时运行的子 Agent 不超过 8 个。超出时按优先级排队：维度子 Agent 优先于模块子 Agent，入口模块优先于叶子模块。

**标准项目**:
- 5-6 个维度子 Agent（architecture, api-surface, dependencies, verification, infrastructure，**data-model 仅在检测到 ORM/model/schema/migration 文件或数据库配置时派发**）
- N 个模块子 Agent（每模块 1 个）

**Monorepo 项目**:
- 4 个全局维度子 Agent（architecture, dependencies, infrastructure, verification）
- 每包派发: overview（必有）+ api-surface/message-protocol（按条件）+ 包内模块

**子 Agent Prompt**: 从 `references/prompts/` 读取对应模板。构造 prompt 时需在**开头**（角色说明之后、项目信息之前）插入以下强制要求，确保模型在生成过程中始终遵守：

```
## 输出格式要求（贯穿全文，不可省略）
- 每个 ## 段落末尾必须附 `> 📄 Sources:` 行，标注来源文件和行号范围
- 文档中必须包含至少 1 个 Mermaid 图表（选择最适合内容的图表类型）
- 分析完成后将结果直接写入指定的输出文件路径
这三条是质量校验的硬指标，缺失会导致文档不通过 Phase 4 检查。
```

**子 Agent 派发方式**: 使用 Agent tool，设置 `run_in_background: true`，prompt 中包含完整的分析指令（强制要求 + 替换模板变量后的内容）。

**小模块跳过规则**: `source_lines < 500` 的模块不派发独立子 Agent，其内容由包级 overview 覆盖。跳过时在 `_progress.json` 中标记 `status: "skipped"`。

**输出**: 各子 Agent 将结果写入 `{output}/_drafts/`

### Phase 3: 合成与生成

**目标**: 合并子 Agent 输出，生成最终文档

**步骤 1: 读取与去重**
1. 读取 `_drafts/` 中的所有文件
2. 消除跨文件信息冗余：
   - 同一概念在多个文件重复描述时，保留最详细的版本，其他处改为交叉引用
   - 模块文档中的架构描述如与 `architecture.md` 重复，缩减为一句话 + 链接

**步骤 2: 合成文档**（派发独立子 Agent，避免主流程上下文过重）

3. **`conventions.md`** — 派发子 Agent，指令：
   - 读取项目的 linter/formatter 配置（ESLint/Prettier/Black/rustfmt 等）
   - 读取 tsconfig/编译配置提取编译选项
   - 读取几个代表性源文件的前 50 行推断命名规范
   - 从 `_drafts/` 文件中提取重复出现的设计模式和依赖方向约束

4. **`glossary.md`** — 派发子 Agent，指令：
   - 读取 `_drafts/` 下所有文件
   - 收集非通用技术术语、领域缩写、项目专有命名
   - 按业务术语/技术术语/缩写分组

5. **`overview.md` + `INDEX.md`** — 派发子 Agent，指令：
   - 读取 `skeleton.json` 获取技术栈、规模、包列表
   - 读取 `_drafts/architecture.md` 获取项目目的和架构概要
   - 读取 `_drafts/infrastructure.md` 获取快速上手命令
   - overview: 汇总为项目概览文档
   - INDEX: 生成 Monorepo/标准项目对应的导航入口（含 Mermaid 依赖图）

**步骤 3: 建立交叉引用**
6. 扫描所有文档，将模块名/实体名替换为 markdown 链接
7. 确保每个模块文档的"依赖关系"段落中的模块名都链接到对应文档

**步骤 4: 元信息**
8. 生成 `_meta.json`（含 git_sha, generation_params, quality_scores）

**文件组织**:
- 标准项目: 维度文档在根目录，模块文档在 `modules/`
- Monorepo: 全局维度在根目录，包文档在 `packages/{pkg}/`

**输出**: 完整的 `.wiki/` 目录结构

### Phase 4: 质量校验

**目标**: 验证文档完整性和质量

1. **覆盖检查**: 每个模块/包有对应文档
2. **模板合规**: 文档包含必需段落
3. **来源引用**: 每个段落有 `> 📄 Sources:` 行
4. **动态质量校验**: 根据代码规模计算质量阈值
   - `effective_exports = min(export_count, source_lines / 10)` — 防止验证器/工厂等高 export 低复杂度模块被过度要求
   - `min_doc_lines = min(600, max(80, source_lines × 0.3 + effective_exports × 15))`
   - `min_code_examples = min(8, max(1, ceil(effective_exports × 0.4)))`
   - `min_diagrams = min(3, max(1, ceil(file_count / 8)))` — 图表要求适度放宽，重质量不重数量
5. **统计报告**: 文件数、覆盖率、质量通过率

**输出**: 质量报告，更新 `_meta.json` 的 `quality_scores`

### Phase 4.5: 清理中间文件

Phase 4 完成后，清理所有中间产物：

1. 删除 `{output}/_drafts/` 目录
2. 删除 `{output}/_progress.json`
3. 删除 `{output}/skeleton.json`
4. 保留 `{output}/_meta.json`（这是最终输出的一部分）

### Phase 5: 注入指令文件（可选）

询问用户是否将知识库使用方法写入 CLAUDE.md/AGENTS.md，便于新会话自动加载。

## 项目类型适配

### 标准项目 vs Monorepo

**判定依据**: Phase 1 检查 workspace 配置文件（pnpm-workspace.yaml, package.json workspaces, lerna.json）

**标准项目**:
- 派发 6 个维度子 Agent + N 个模块子 Agent
- 输出结构: 维度文档在根目录，模块文档在 `modules/`

**Monorepo 项目**:
- 派发 4 个全局维度子 Agent（不含 api-surface, data-model）
- 每包派发: overview + 条件维度（api-surface/message-protocol）+ 包内模块
- 输出结构: 全局维度在根目录，包文档在 `packages/{pkg}/`

### Package Role 判定规则

Monorepo 中每个包根据依赖和目录结构判定角色：

| Role | 判定条件 | 推荐维度 |
|------|---------|---------|
| bff | 有 router/controller 目录 | api-surface |
| sdk | 有 main/exports 且被其他包依赖 | api-surface |
| ui | 有 src/components 且依赖 React/Vue | message-protocol |
| tool | 有 bin 字段 | api-surface |
| app | 有 main 且不被依赖 | - |
| shared | 被多个包依赖的工具包 | - |

详见 `references/schemas.md` 的 package_role 定义。

### Monorepo 适配层

**设计原则**: 用统一的适配层封装 Monorepo 差异，避免逻辑散布在各 Phase。

**适配点**:

1. **Phase 1 扫描**:
   - 标准项目 → 识别模块
   - Monorepo → 识别包 + 包内模块 + 包间依赖

2. **Phase 2 派发**:
   - 标准项目 → 读取 `prompts/standard/`
   - Monorepo → 读取 `prompts/monorepo/` + `prompts/package/`

3. **Phase 3 合成**:
   - 标准项目 → 维度在根目录，模块在 `modules/`
   - Monorepo → 全局维度在根目录，包在 `packages/{pkg}/`

4. **Phase 4 校验**:
   - 标准项目 → 检查模块覆盖
   - Monorepo → 检查包覆盖 + 包内模块覆盖

**实现**: 在每个 Phase 开始前读取 `skeleton.json` 的 `project_type` 字段，选择对应分支。

## 高级特性

### 增量更新模式（--update）

**触发条件**: 指定 `--update` 且存在 `_meta.json`

**流程**:
1. 读取 `_meta.json` 中的 `source_snapshot.git_sha`
2. 执行 `git diff <old_sha>..HEAD --name-only` 获取变更文件
3. 将变更文件映射到模块，判定需刷新的维度
4. 仅派发脏模块和受影响维度的子 Agent
5. 合并时保留 `<!-- user-content-start -->` 到 `<!-- user-content-end -->` 之间的用户内容

**非 git 项目回退**: 如果项目未使用 git（无 `.git` 目录），`--update` 模式不可用。提示用户："当前项目不是 git 仓库，无法使用增量更新。请使用全量重新生成：`/code-wiki`"。

**影响范围判定**:
- 路由/控制器变更 → 刷新 `api-surface.md`
- 模型/实体变更 → 刷新 `data-model.md`
- 配置/CI 变更 → 刷新 `infrastructure.md`
- 测试文件变更 → 刷新 `verification.md`
- 模块入口变更 → 刷新 `dependencies.md`, `architecture.md`

### 质量升级模式（--upgrade）

**触发条件**: 指定 `--upgrade` 且存在 `_meta.json`

**流程**:
1. 读取 `_meta.json` 的 `quality_scores`
2. 用动态质量公式评估每个模块文档
3. 标记不达标的模块和维度
4. 仅重新生成不达标的文档
5. 保留用户内容块（user-content 标记）

### 分批模式（--batch）

**触发条件**: 模块数 > 15 或手动指定 `--batch`

**策略**:
- 维度子 Agent 首批全部派发
- 模块子 Agent 按优先级分批（入口模块、被依赖数、代码行数）
- 大模块（> 2000 行）每批 3 个，小模块每批 5 个
- 每批完成后等待用户确认

### LSP 加速

**触发条件**: Phase 1 检测到 LSP 可用

**优先使用场景**:
- `documentSymbol` → 文件结构扫描
- `hover` → 类型签名获取
- `findReferences` → 依赖追踪
- `outgoingCalls` / `incomingCalls` → 调用关系

**回退场景**: 动态调用、事件监听、业务逻辑理解时回退到读源码

## 故障排查

### 上下文压缩容灾

**问题**: 大型项目分析时上下文被压缩，中间结果丢失

**解决方案**:
- 每步产出先写文件到 `{output}/_drafts/`
- 更新 `_progress.json` 记录进度
- Phase 3 从文件读取，不依赖上下文历史
- 支持断点恢复

### 子 Agent 失败处理

**问题**: 某个子 Agent 超时或失败

**解决方案**:
1. 检查 `_progress.json` 确认失败的子 Agent
2. 单独重新派发失败的子 Agent
3. 如果反复失败，切换到摘要模式或跳过该维度

### Token 预算超限

**问题**: api-surface 子 Agent 输出超过 800 行

**解决方案**:
- 检查路由文件数和最大行数
- 强制切换到摘要/采样模式
- 使用 Grep 提取而非 Read 全文
- 优先使用 LSP 操作

### 断点恢复机制

**场景**: 执行中断（网络、超时、用户取消）

**恢复步骤**:
1. 读取 `_progress.json` 确认当前 Phase 和已完成的子 Agent
2. 跳过已完成的子 Agent，从中断点继续
3. 分批模式下，从 `current_batch` 继续

**示例**:
```json
// _progress.json
{
  "phase": 2,
  "agents": [
    {"name": "architecture", "status": "done"},
    {"name": "api-surface", "status": "running"},
    {"name": "data-model", "status": "pending"}
  ]
}
```
恢复时跳过 architecture，重新派发 api-surface。

### 子 Agent 重试策略

**问题**: 子 Agent 超时或返回错误

**重试规则**:
1. 首次失败 → 立即重试 1 次
2. 二次失败 → 检查是否因范围过大，切换到摘要模式重试
3. 三次失败 → 记录警告，跳过该子 Agent，继续其他任务

**降级策略**:
- api-surface: 全量 → 摘要 → 采样
- 模块分析: full → logic
- 大文件: Read → Grep → 跳过

### 质量不达标处理

**问题**: Phase 4 发现多个模块文档质量不足

**处理方式**:
1. 展示质量报告，标记不达标项
2. 询问用户: "发现 N 个模块文档质量不足，是否立即升级？"
3. 用户确认后执行 `--upgrade` 模式
4. 或提示用户后续手动执行 `/code-wiki --upgrade`

## Token 消耗预估

在 Phase 1 完成后，根据子 Agent 数量向用户展示预估消耗：

| 项目规模 | 子 Agent 数 | 预估 token | 预估耗时 |
|---------|-----------|-----------|---------|
| 小型（< 5 模块） | 8-12 | ~80-120 万 | 5-10 分钟 |
| 中型（5-15 模块） | 12-20 | ~120-200 万 | 10-20 分钟 |
| 大型 / Monorepo | 20-30 | ~200-300 万 | 15-30 分钟 |

在 Phase 2 每波子 Agent 完成后输出进度，格式如：
> Phase 2: 8/22 子 Agent 已完成（architecture ✓, dependencies ✓, lib-overview ✓ ...）

## 参考文件

- `references/schemas.md` - JSON 结构定义（skeleton.json, _progress.json, _meta.json）
- `references/templates/` - 文档模板（按文档类型拆分，子 Agent 只需读取对应模板 + common.md）
- `references/prompts/` - 子 Agent Prompt 模板（按 standard/monorepo/package 分组）
- `references/advanced-params.md` - 高级参数说明
- `references/decision-trees.md` - 复杂决策逻辑可视化
