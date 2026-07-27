# Codex / Claude Code 兼容约定

本插件同时保留 Claude Code 插件入口和 Codex 插件入口：

- Claude Code: `.claude-plugin/plugin.json`
- Codex: `.codex-plugin/plugin.json`

`skills/` 是唯一 skill 源码目录。不要为了两个平台复制两份 `SKILL.md`。

## 默认兼容目标

- 除非名称或目标明确指向单一平台，新增或修改的能力默认同时支持 Claude Code 和 Codex。
- 共享能力只实现一次，放在 `skills/` 或 bundled script；manifest、hook、agent 只做宿主适配。
- 先确定所需能力，再使用当前宿主可用的 tool、MCP 或 CLI，不把某个平台的工具名写成唯一入口。
- 必须使用平台专属能力时，依次提供另一端的原生等价能力、bundled script / CLI fallback；仍不可行时提供只读检查或明确阻塞原因。
- 两端 manifest 和 marketplace 的核心版本、能力描述保持一致；Codex 可追加 `+codex.<cachebuster>` 构建元数据。

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
- 平台专属能力按“默认兼容目标”中的 fallback 顺序处理。
- 写外部系统、上传、部署、清 CDN、GUI 自动化等有副作用操作时，执行前确认目标和影响范围。
- token / cookie / 私有账号优先读环境变量或 ignored local config，不要新增写死凭据。
- 不要把 Claude cache 做成指向源码的软链；源码目录必须只由 git 和人工编辑维护。

## 平台专属 skill

`cc-baseline`、`cc-backup-restore`、`plugin-refresh` 的目标仍是 Claude Code。Codex 可以读取并执行这些流程，但它们操作的是 `~/.claude`、Claude 插件 cache 或 Claude 相关 App，不是 Codex 自身配置。反过来 `codex-baseline` 的目标是 Codex CLI（`~/.codex`），可由 Claude Code 读取辅助但操作的不是 `~/.claude`。
