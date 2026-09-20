# code-wiki

一个 Claude Code Skill，通过深度分析代码工程自动生成结构化知识库（`.wiki/`），让任何 AI Code Agent 读完即可掌握工程全貌。

## 安装

将本项目复制到 Claude Code 的 skills 目录：

```bash
cp -r code-wiki ~/.claude/skills/code-wiki
```

或在任意位置保留，通过 Claude Code 的 skill 配置指向该目录。

## 使用方式

在项目目录下启动 Claude Code，输入以下任意触发语：

```
/code-wiki
```

```
生成知识库
```

```
帮我分析这个项目的架构，生成文档
```

## 参数

| 参数 | 默认值 | 说明 |
|------|-------|------|
| `--depth` | `logic` | `logic` 分析模块职责/接口/数据流；`full` 额外含函数/类级实现细节 |
| `--output` | `.wiki/` | 输出目录路径 |
| `--modules` | 全部 | 逗号分隔的模块名，仅生成指定模块文档 |
| `--lang` | `zh` | 输出语言，`zh` 或 `en` |
| `--update` | `false` | 增量更新，仅刷新有变更的模块 |
| `--upgrade` | `false` | 质量升级，重新生成低于质量阈值的文档 |
| `--batch` | `false` | 分批交互模式（>15 模块自动启用） |
| `--domains` | `false` | 按业务领域分层组织模块目录 |

使用示例：

```
/code-wiki --depth full --lang en
```

```
/code-wiki --modules auth,user,order
```

```
/code-wiki --update
```

```
/code-wiki --upgrade
```

```
/code-wiki --domains --batch
```

## 生成流程

```
Phase 1 全局扫描 → Phase 2 并行深度分析 → Phase 3 合成生成 → Phase 4 质量校验 → Phase 5 注入指令(可选)
```

1. **Phase 1**: 扫描项目结构、技术栈、模块划分，生成 skeleton.json
2. **Phase 2**: 并行派发子 Agent 分析架构、API、数据模型、依赖、测试、基础设施及各模块
3. **Phase 3**: 合成各分析结果，生成交叉引用的文档集
4. **Phase 4**: 质量校验（来源引用、动态质量公式、图表类型、交叉引用）
5. **Phase 5**: 可选，将知识库使用方法写入 CLAUDE.md / AGENTS.md

## 输出结构

```
.wiki/
├── INDEX.md            ← 导航入口
├── overview.md         ← 项目概览
├── architecture.md     ← 架构设计
├── conventions.md      ← 编码约定
├── verification.md     ← 验证体系
├── modules/            ← 模块文档
│   ├── auth.md
│   └── ...
├── api-surface.md      ← API 接口
├── data-model.md       ← 数据模型
├── dependencies.md     ← 依赖图谱
├── infrastructure.md   ← 构建部署
├── glossary.md         ← 术语表
└── _meta.json          ← 元信息
```

## 三种运行模式

### 全量生成（默认）

首次使用，完整分析项目并生成全部文档。

### 增量更新（--update）

基于 git diff 检测代码变更，仅重新生成受影响的模块和维度文档。适合日常迭代后保持知识库同步。

### 质量升级（--upgrade）

根据动态质量公式评估已有文档，自动识别并重新生成不达标的模块文档。适合提升已有知识库的文档质量。

## 用户自定义内容保留

在模块文档中，`<!-- user-content-start -->` 和 `<!-- user-content-end -->` 标记对之间的内容会在 `--update` 和 `--upgrade` 时自动保留。你可以在任意段落后添加这对标记来保护自定义笔记。

## 项目结构

```
code-wiki/
├── SKILL.md                        ← 主流程编排（skill 入口）
├── README.md                       ← 本文件
└── references/
    ├── schemas.md                  ← JSON 数据结构定义
    ├── advanced-params.md          ← 高级参数说明
    ├── decision-trees.md           ← 决策树可视化
    ├── templates/                  ← 文档模板（按类型拆分）
    │   ├── common.md               ← 通用规范（来源引用、图表类型）
    │   ├── architecture.md          ← 架构文档模板
    │   ├── api-surface.md           ← API 接口模板
    │   ├── module.md                ← 模块文档模板
    │   ├── monorepo-*.md            ← Monorepo 专用模板
    │   └── ...                      ← 共 18 个模板文件
    └── prompts/                    ← 子 Agent prompt 模板
        ├── README.md               ← prompt 组织说明
        ├── module.md               ← 标准项目模块分析
        ├── standard/               ← 标准项目维度 prompts
        │   ├── architecture.md
        │   ├── api-surface.md
        │   ├── data-model.md
        │   ├── dependencies.md
        │   ├── verification.md
        │   └── infrastructure.md
        ├── monorepo/               ← Monorepo 全局维度 prompts
        │   ├── architecture.md
        │   └── dependencies.md
        └── package/                ← Monorepo 包级 prompts
            ├── overview.md
            ├── api-surface.md
            ├── message-protocol.md
            └── module.md
```

## License

MIT
