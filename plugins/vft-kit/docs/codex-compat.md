# Codex / Claude Code 兼容约定

本插件同时保留 Claude Code 插件入口和 Codex 插件入口：

- Claude Code: `.claude-plugin/plugin.json`
- Codex: `.codex-plugin/plugin.json`

`skills/` 是唯一 skill 源码目录。不要为了两个平台复制两份 `SKILL.md`。

## 插件根目录

跨平台脚本统一使用 `VFT_PLUGIN_ROOT` 表示插件根目录。解析优先级：

1. `VFT_PLUGIN_ROOT`
2. `CLAUDE_PLUGIN_ROOT`
3. `CODEX_PLUGIN_ROOT`
4. `scripts/plugin-root.sh` 或 `scripts/plugin-root.mjs` 从自身位置推导

Shell 脚本示例：

```bash
PLUGIN_ROOT="${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}"
if [ -z "$PLUGIN_ROOT" ]; then
  PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
```

Node ESM 脚本示例：

```js
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const pluginRoot =
  process.env.VFT_PLUGIN_ROOT ||
  process.env.CLAUDE_PLUGIN_ROOT ||
  process.env.CODEX_PLUGIN_ROOT ||
  path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
```

## 写 skill 时的规则

- `SKILL.md` 保持 Claude/Codex 共享，frontmatter 只写 `name` 和 `description`。
- 命令示例优先写 `VFT_PLUGIN_ROOT`，不要只写 `CLAUDE_PLUGIN_ROOT`。
- 需要调用平台专属能力时，必须写 fallback：
  - Claude Code MCP 可用时走 MCP。
  - Codex 或普通 shell 环境走 bundled script。
  - 都没有时给出只读检查或明确阻塞原因。
- 写外部系统、上传、部署、清 CDN、GUI 自动化等有副作用操作时，执行前确认目标和影响范围。
- token / cookie / 私有账号优先读环境变量或 ignored local config，不要新增写死凭据。
- 不要把 Claude cache 做成指向源码的软链；源码目录必须只由 git 和人工编辑维护。

## 平台专属 skill

`cc-baseline`、`cc-backup-restore`、`plugin-refresh`、`usage-alert-setup` 的目标仍是 Claude Code。Codex 可以读取并执行这些流程，但它们操作的是 `~/.claude`、Claude 插件 cache 或 Claude 相关 App，不是 Codex 自身配置。
