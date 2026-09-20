# 领域目录组织（--domains 模式）(P2)

当启用 `--domains` 时，模块文件按业务领域自动分组组织，而非扁平排列在 `modules/` 下。

## 领域自动检测规则

1. **路径关键词检测**: 从模块路径中提取领域标识（如 `src/auth/` → `auth`，`src/payment/` → `payment`）
2. **同前缀归组**: 共享相同路径前缀的模块归入同一领域（如 `src/order/create`, `src/order/query` → `order` 领域）
3. **小领域合并**: 包含少于 2 个模块的领域合并至 `core` 领域
4. **手动覆盖**: 如果 `_meta.json` 中 `generation_params.domains_mapping` 存在，优先使用手动映射

## 目录结构变更

```
modules/
├── auth/
│   ├── _index.md       ← 领域概览
│   ├── login.md
│   └── permission.md
├── order/
│   ├── _index.md
│   ├── create.md
│   └── query.md
└── core/
    ├── _index.md
    ├── config.md
    └── utils.md
```

## 领域 _index.md 模板

```markdown
# {领域名} 领域

> {一句话描述该领域的业务范围}

## 包含模块

| 模块 | 职责 | 文档 |
|------|------|------|
| {name} | {一句话职责} | [{name}.md]({name}.md) |

## 领域边界

- **负责**: {该领域处理的业务}
- **不负责**: {明确不属于该领域的事项}

## 与其他领域的关系

| 关联领域 | 关系类型 | 说明 |
|---------|---------|------|
| {domain} | {调用/被调用/共享数据} | {具体说明} |
```

## INDEX.md 领域分组视图

当 `--domains` 启用时，INDEX.md 的"模块一览"段落改为按领域分组：

```markdown
## 模块一览

### {领域名}
> {领域描述}

| 模块 | 职责 | 文档 |
|------|------|------|
| {name} | {一句话职责} | [modules/{domain}/{name}.md](modules/{domain}/{name}.md) |

### {另一个领域}
...
```
