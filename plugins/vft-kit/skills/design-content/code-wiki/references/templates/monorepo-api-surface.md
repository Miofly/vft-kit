# Monorepo: packages/{name}/api-surface.md 模板

包级 API Surface 文档。仅当包的 `recommended_dimensions` 包含 `api-surface` 时生成。

```markdown
# {package_name} API 接口

## 概览

{API 类型: REST 端点 / 公开方法 / CLI 命令}
{基础 URL / 导入路径}
{认证方式}
路由/导出文件数: {N}，分析模式: {全量/摘要/采样}

## {针对 package_role 的端点/方法列表}

{package_role == bff 时: 与标准 api-surface.md 的端点列表格式相同}

{package_role == sdk 时: 列出公开方法}

### {分组名}

| 方法名 | 签名 | 说明 |
|-------|------|------|
| {name} | `{signature}` | {描述} |

{package_role == tool 时: 列出 CLI 命令}

### 命令列表

| 命令 | 参数 | 说明 |
|------|------|------|
| {command} | {args} | {描述} |

## 调用约定

{请求/响应格式、错误处理、超时配置等}

## 与其他包的接口契约

{本包与其他包之间的调用关系和协议约定}
```
