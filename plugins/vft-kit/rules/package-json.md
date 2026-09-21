---
name: package-json
description: package.json 依赖版本规范（锁定精确版本，不写 ^ / ~ 范围）
paths:
  - '**/package.json'
checks:
  - pin-exact-version
---

# package.json 规范（vft-kit 注入）

改 `package.json` 时遵守以下规范。标注「自动检查」的条目会在保存后由 vft-kit 校验，违反 error 级会被退回修改。

## 1. 依赖写精确版本

- **`dependencies` / `devDependencies` / `optionalDependencies` 一律写精确版本号**，不带 `^`、`~`，也不写 `>=`、`*`、`x`、`latest` 这类范围（自动检查 `pin-exact-version`）：

  ```json
  // ✅
  "font-spider": "1.3.5"
  // ❌
  "font-spider": "^1.3.5"
  ```

- **原因**：范围版本在重新安装、换机器、CI 构建或锁文件丢失时会装到不同的小版本，老项目（尤其 Vue 2 / webpack 时代依赖）容易因此构建失败或行为变化。
- **改成哪个版本**：用当前实际安装的版本（`node_modules/<包名>/package.json` 的 `version`，或锁文件里的版本），不要直接去掉 `^` 取范围下限，否则等于降级。自动检查会在提示里给出已安装的版本。
- 以下写法不是范围版本，保持原样：`workspace:*`、`catalog:`、`file:`、`link:`、git 地址、tarball URL。`npm:` 别名里的版本同样要写精确版本（`"vue2": "npm:vue@2.7.16"`）。
- `peerDependencies` 不受此限制：它描述兼容范围，本来就应该写范围。

## 2. 安装时就写精确版本

- 用命令安装时加精确版本参数，避免装完再手改：`pnpm add -E xxx`、`npm i -E xxx`、`yarn add -E xxx`。
- 项目可以在 `.npmrc` 写 `save-exact=true`，之后 `pnpm add` / `npm i` 默认写精确版本。

## 项目覆盖

项目根的 `.claude/vft-rules.json` 可以关闭本规则或调整检查级别。例如某个对外发布的库需要保留范围版本：

```json
{
  "checks": { "pin-exact-version": "off" }
}
```
