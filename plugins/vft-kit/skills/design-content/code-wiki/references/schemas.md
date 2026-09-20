# JSON 数据结构定义

本文档定义 code-wiki skill 中使用的所有 JSON 结构。

---

## skeleton.json

Phase 1 全局扫描的输出，Phase 2 子 Agent 的输入。中间产物，最终清理。

**非 monorepo 项目**使用 `modules` 字段（扁平模块列表），**monorepo 项目**使用 `packages` 字段（两层结构）。两者互斥，不同时存在。

### 非 monorepo 结构（保持不变）

```json
{
  "project_name": "string — 项目名称，从 package.json name 或目录名推断",
  "project_type": "string — web-app | api-service | library | cli",
  "tech_stack": {
    "language": "string — 主要编程语言",
    "framework": "string — 主要框架，无则为 none",
    "runtime": "string — 运行时和版本，如 Node.js 20",
    "database": "string — 数据库类型，无则为 none",
    "key_deps": ["string — 关键第三方依赖列表"]
  },
  "scale": {
    "file_count": "number — 源码文件总数（不含排除目录）",
    "loc_estimate": "number — 代码行数估算",
    "module_count": "number — 识别出的模块数"
  },
  "modules": [
    {
      "name": "string — 模块名（用于文件命名和引用）",
      "path": "string — 模块相对路径",
      "file_count": "number — 模块内文件数",
      "source_lines": "number — 源码行数（不含空行）",
      "export_count": "number — 公开导出符号数"
    }
  ],
  "test_system": {
    "framework": "string — 测试框架名称，如 vitest / jest / pytest",
    "test_dir": "string — 测试目录路径",
    "test_command": "string — 运行全部测试的命令",
    "has_e2e": "boolean — 是否有 E2E 测试",
    "e2e_command": "string — E2E 测试命令，无则为空"
  },
  "existing_docs": ["string — 已有文档文件路径"],
  "ignore_patterns": ["string — 排除的目录/文件模式"],
  "lsp_support": {
    "available": "boolean — LSP 是否可用",
    "languages": ["string — 支持的语言列表"],
    "operations_verified": ["string — 已验证可用的 LSP 操作"]
  }
}
```

### Monorepo 结构

当 `project_type` 为 `monorepo` 时，使用 `packages` 替代 `modules`。每个 package 包含自身的元数据、包类型、推荐的维度文档列表、以及可选的内部模块列表。

```json
{
  "project_name": "string — 项目名称",
  "project_type": "monorepo",
  "workspace_tool": "string — pnpm | yarn | npm | lerna | turborepo | nx",
  "tech_stack": {
    "language": "string",
    "framework": "string",
    "runtime": "string",
    "database": "string",
    "key_deps": ["string"]
  },
  "scale": {
    "file_count": "number — 全部包的源码文件总数",
    "loc_estimate": "number — 全部包的代码行数估算",
    "package_count": "number — 包数",
    "total_module_count": "number — 所有包内模块总数"
  },
  "packages": [
    {
      "name": "string — 包名（如 proxy、sdk），用于目录命名",
      "package_name": "string — npm 包名（如 @h5-order/proxy），用于显示",
      "path": "string — 包相对路径（如 packages/proxy）",
      "version": "string — 包版本号",
      "private": "boolean — 是否私有包",
      "package_role": "string — bff | sdk | ui | types | app | tool | shared | other",
      "file_count": "number — 包内源码文件数",
      "source_lines": "number — 源码行数（不含空行）",
      "export_count": "number — 对外导出符号数",
      "entry_point": "string — 入口文件路径",
      "tech_stack": {
        "framework": "string — 包级框架（如 Koa、Vite），覆盖全局 tech_stack",
        "key_deps": ["string — 包级关键依赖"]
      },
      "recommended_dimensions": ["string — 推荐生成的维度文档: api-surface | message-protocol | type-exports | ..."],
      "modules": [
        {
          "name": "string — 模块名",
          "path": "string — 模块相对于包根的路径（如 src/router）",
          "file_count": "number",
          "source_lines": "number",
          "export_count": "number"
        }
      ]
    }
  ],
  "cross_package_deps": [
    {
      "from": "string — 依赖方包名",
      "to": "string — 被依赖方包名",
      "type": "string — workspace | build-copy | runtime | types-only"
    }
  ],
  "test_system": {
    "framework": "string",
    "test_dir": "string",
    "test_command": "string",
    "has_e2e": "boolean",
    "e2e_command": "string"
  },
  "existing_docs": ["string"],
  "ignore_patterns": ["string"],
  "lsp_support": {
    "available": "boolean",
    "languages": ["string"],
    "operations_verified": ["string"]
  }
}
```

**package_role 判定规则:**

| 特征 | 角色 |
|------|------|
| 有 koa/express/fastify/hapi 依赖 + router 目录 | `bff` |
| 有 rollup/webpack + 浏览器入口 + 对外导出 init/API 方法 | `sdk` |
| 有 vite/webpack + HTML 入口 + views 目录 | `ui` |
| 只有 .d.ts 或仅导出 type/interface/enum/const | `types` |
| 有 bin 字段或 CLI 入口 | `tool` |
| 有 main/module 入口 + 被多个包依赖 | `shared` |
| 其他 | `other` |

**recommended_dimensions 推导规则:**

| package_role | 推荐维度文档 |
|-------------|------------|
| `bff` | `api-surface`（REST/GraphQL 端点） |
| `sdk` | `api-surface`（公开方法签名） |
| `ui` | `message-protocol`（如有 postMessage/iframe 通信）；否则不生成 |
| `types` | `type-exports`（类型/常量导出清单，合并到 overview 中，不单独文件） |
| `app` | `api-surface`（如有对外 API） |
| `tool` | `api-surface`（CLI 命令列表） |
| `shared` | 无额外维度，overview 覆盖 |

**modules 拆分规则:** 包内 `src/` 有 3 个以上功能性子目录且包的 `source_lines > 500` 时拆分模块，否则 `modules` 为空数组，仅生成包级 overview。

---

## _progress.json

任务进度追踪文件，用于上下文压缩后恢复。中间产物，最终清理。

```json
{
  "phase": "number — 当前阶段: 1 | 2 | 3 | 4",
  "started_at": "string — ISO-8601 格式的开始时间",
  "output_dir": "string — 输出目录路径",
  "depth": "string — 分析深度: logic | full",
  "lang": "string — 输出语言: zh | en",
  "is_monorepo": "boolean — 是否为 monorepo 项目",
  "batch_mode": {
    "enabled": "boolean — 是否启用分批模式",
    "batch_size": "number — 每批模块数 (3-5)",
    "current_batch": "number — 当前批次 (1-indexed)",
    "total_batches": "number",
    "completed_batches": ["number — 已完成批次编号"],
    "module_order": ["string — 优先级排序后的模块名"],
    "awaiting_user": "boolean — 暂停等待用户确认时为 true"
  },
  "agents": {
    "{agent_name}": {
      "status": "string — pending | running | done | failed",
      "output": "string — 输出文件路径（status 为 done 时必填）",
      "error": "string — 错误信息（status 为 failed 时可选）"
    }
  }
}
```

**agent_name 命名规则:**

非 monorepo:
- 维度子 Agent: `architecture`, `api-surface`, `data-model`, `dependencies`, `verification`, `infrastructure`
- 模块子 Agent: `module:{模块名}`，如 `module:auth`, `module:user`

Monorepo:
- 全局维度子 Agent: `architecture`, `dependencies`, `infrastructure`, `verification`
- 包级子 Agent: `pkg:{包名}:overview`，如 `pkg:proxy:overview`
- 包级维度子 Agent: `pkg:{包名}:{维度}`，如 `pkg:proxy:api-surface`, `pkg:webjs:message-protocol`
- 包内模块子 Agent: `pkg:{包名}:module:{模块名}`，如 `pkg:proxy:module:router`

---

## _meta.json

最终输出的元信息文件，保留在 .wiki/ 中。

### 非 monorepo 结构（保持不变）

```json
{
  "generated_at": "string — ISO-8601 格式的生成时间",
  "generator": "code-wiki",
  "version": "2.0.0",
  "depth": "string — logic | full",
  "lang": "string — zh | en",
  "project": {
    "name": "string — 项目名",
    "type": "string — 项目类型",
    "tech_stack": ["string — 技术栈摘要"],
    "file_count": "number — 源码文件总数",
    "module_count": "number — 模块数"
  },
  "stats": {
    "files_generated": "number — 生成的文档文件数",
    "modules_covered": "number — 已覆盖的模块数",
    "total_tokens_estimate": "number — 所有文档的 token 总数估算"
  },
  "generation_params": {
    "depth": "string — logic | full",
    "lang": "string — zh | en",
    "modules_filter": "string | null — 逗号分隔的模块名，null 表示全部",
    "batch_mode": "boolean — 是否使用分批模式",
    "domains": "boolean — 是否使用领域分层组织"
  },
  "quality_scores": {
    "{module_name}": {
      "threshold": {
        "min_doc_lines": "number",
        "min_code_examples": "number",
        "min_diagrams": "number"
      },
      "actual": {
        "doc_lines": "number",
        "code_examples": "number",
        "diagrams": "number"
      },
      "pass": "boolean"
    }
  },
  "source_snapshot": {
    "git_sha": "string",
    "modules": [
      {
        "name": "string",
        "path": "string",
        "file_count": "number",
        "source_lines": "number",
        "export_count": "number"
      }
    ]
  }
}
```

### Monorepo 结构

```json
{
  "generated_at": "string",
  "generator": "code-wiki",
  "version": "2.0.0",
  "depth": "string — logic | full",
  "lang": "string — zh | en",
  "project": {
    "name": "string — 项目名",
    "type": "monorepo",
    "workspace_tool": "string — pnpm | yarn | npm | ...",
    "tech_stack": ["string — 技术栈摘要"],
    "file_count": "number — 全部包的源码文件总数",
    "package_count": "number — 包数",
    "total_module_count": "number — 所有包内模块总数"
  },
  "stats": {
    "files_generated": "number",
    "packages_covered": "number — 已覆盖的包数",
    "modules_covered": "number — 已覆盖的包内模块总数",
    "total_tokens_estimate": "number"
  },
  "generation_params": {
    "depth": "string",
    "lang": "string",
    "packages_filter": "string | null — 逗号分隔的包名，null 表示全部",
    "batch_mode": "boolean",
    "domains": "boolean"
  },
  "quality_scores": {
    "{package_name}": {
      "overview": {
        "threshold": { "min_doc_lines": "number", "min_code_examples": "number", "min_diagrams": "number" },
        "actual": { "doc_lines": "number", "code_examples": "number", "diagrams": "number" },
        "pass": "boolean"
      },
      "modules": {
        "{module_name}": {
          "threshold": { "min_doc_lines": "number", "min_code_examples": "number", "min_diagrams": "number" },
          "actual": { "doc_lines": "number", "code_examples": "number", "diagrams": "number" },
          "pass": "boolean"
        }
      }
    }
  },
  "source_snapshot": {
    "git_sha": "string",
    "packages": [
      {
        "name": "string — 包名",
        "package_name": "string — npm 包名",
        "path": "string",
        "package_role": "string",
        "file_count": "number",
        "source_lines": "number",
        "export_count": "number",
        "modules": [
          {
            "name": "string",
            "path": "string",
            "file_count": "number",
            "source_lines": "number",
            "export_count": "number"
          }
        ]
      }
    ]
  }
}
```
