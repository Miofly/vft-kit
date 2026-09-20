# Monorepo: packages/{name}/overview.md 模板

包级概览文档。每个 monorepo 包必须生成此文件。

```markdown
# {package_name}

> {一句话描述包的职责}
>
> 角色: {package_role} | 版本: {version} | {private ? "私有" : "已发布"}

## 技术栈

| 类别 | 技术 | 版本 |
|------|------|------|
| 框架 | {framework} | {version} |
| 关键依赖 | {dep1}, {dep2} | — |

## 目录结构

```
{包内目录树，标注各目录职责}
```

## 入口点

- 主入口: {entry_point}
- {其他入口（如路由入口、CLI 入口等）}

## 职责边界

- **负责**:
  - {职责1}
  - {职责2}
- **不负责**:
  - {不做的事1}
  - {不做的事2}

## 包间依赖

- **依赖的包**:
  - {包名} — {依赖类型: workspace/build-copy/runtime/types-only} — {说明}
- **被依赖的包**:
  - {包名} — {说明}

## 对外接口概要

{如果有 api-surface.md，简要列出对外提供的核心接口，指向 api-surface.md 查看详情}
{如果是 types 包，直接在此列出导出的类型/常量/实体}

## 内部模块

{如果包内有 modules/ 子目录}

| 模块 | 职责 | 文档 |
|------|------|------|
| {name} | {一句话职责} | [modules/{name}.md](modules/{name}.md) |

{如果包太小不拆模块}
> 本包规模较小，内部结构见上方目录结构。

## 快速上手

```bash
# 开发
{dev_command}

# 构建
{build_command}

# 测试
{test_command}
```

## 补充说明
<!-- user-content-start -->
<!-- 在此标记之间添加自定义内容，--update 和 --upgrade 时会自动保留 -->
<!-- user-content-end -->
```
