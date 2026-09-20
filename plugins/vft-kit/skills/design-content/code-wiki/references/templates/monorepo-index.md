# Monorepo: INDEX.md 模板

当 `project_type` 为 `monorepo` 时，使用此模板替代标准 INDEX.md 模板。

```markdown
# {项目名} 工程知识库

> {一句话描述项目做什么}

## 技术栈

{语言} / {框架} / {关键依赖}
Monorepo 工具: {workspace_tool}

## 快速导航

| 我需要... | 读这个文件 |
|-----------|-----------|
| 了解项目全貌 | [overview.md](overview.md) |
| 理解架构和包间关系 | [architecture.md](architecture.md) |
| 写代码前了解规范和约束 | [conventions.md](conventions.md) |
| 改完代码后知道怎么验证 | [verification.md](verification.md) |
| 了解包间和外部依赖 | [dependencies.md](dependencies.md) |
| 构建、部署、CI/CD | [infrastructure.md](infrastructure.md) |
| 涉及数据操作 | [data-model.md](data-model.md) |
| 遇到不明术语 | [glossary.md](glossary.md) |

## 包一览

| 包 | 角色 | 职责 | 文档入口 |
|----|------|------|---------|
| {name} ({package_name}) | {package_role} | {一句话职责} | [packages/{name}/overview.md](packages/{name}/overview.md) |

## 包间依赖关系

```mermaid
graph LR
    {包A} --> {包B}
    {包A} --> {包C}
```

> 从 skeleton.json 的 cross_package_deps 生成。

## 按包快速导航

### {包名} — {package_role}

| 文档 | 说明 |
|------|------|
| [packages/{name}/overview.md](packages/{name}/overview.md) | 包概览 |
| [packages/{name}/api-surface.md](packages/{name}/api-surface.md) | API 接口（如有） |
| [packages/{name}/modules/](packages/{name}/modules/) | 内部模块文档（如有） |

---
_由 code-wiki skill 自动生成 | {生成时间} | 深度: {logic|full}_
```
