---
name: codex-baseline
description: 一键核对本机 Codex 是否符合「装配基线」——逐项核对 Codex CLI、Node/npm/git、Codex dangerous full access 基线（等价 `--dangerously-bypass-approvals-and-sandbox`：`sandbox_mode = "danger-full-access"` + `approval_policy = "never"`）、full access 警告隐藏、项目信任、hooks、node_repl MCP、常用插件启用与 cache、系统 skills、全局 AGENTS 规范。缺什么直接打印对应修复命令。用户说"codex-baseline"、"检查 codex 基线"、"codex 体检"、"codex-doctor"、"codex 权限配置对吗"、"dangerously bypass 有没有落实"、"codex 插件/MCP 全不全"、"换机器后核对 codex"等场景时触发。只读检查，不改任何配置。
---

# codex-baseline —— Codex 装配基线核对

对照本机 Codex 装配基线逐项核对安装、配置、插件、MCP 与全局规范状态，缺什么给什么修复命令。**只读**，不改任何配置。

基线里最核心的一项是 dangerous full access：等价于启动参数 `--dangerously-bypass-approvals-and-sandbox`，持久配置写在 `~/.codex/config.toml`：

```toml
approval_policy = "never"
sandbox_mode = "danger-full-access"
```

## 怎么用

直接跑脚本：

```bash
bash ${CODEX_PLUGIN_ROOT:-${VFT_PLUGIN_ROOT:-.}}/skills/codex-baseline/scripts/check.sh
```

输出是分组的 `✓` / `✗` / `○` 清单 + 汇总。退出码：必需项齐全=0，有必需项缺失=1（可选项缺失不影响退出码）。

- `✓` 绿 = 已装/已启用
- `✗` 红 = **必需**项缺失，行尾直接给修复命令
- `○` 黄 = 可选项缺失，不算故障

跑完把结果回报给用户；有 `✗` 就把对应修复命令一并列出，问用户要不要补齐。

## 检查项

| 类别 | 检查项 | 数据来源 |
|---|---|---|
| CLI 工具 | `codex` / `node` / `npm` / `git` / `jq` 可选 | `command -v` |
| dangerous full access | `approval_policy = "never"` / `sandbox_mode = "danger-full-access"` / hide full-access warning | `~/.codex/config.toml` |
| 项目与 hooks | `features.hooks = true` / `/` 或常用代码根已 trust | `~/.codex/config.toml` |
| MCP | `node_repl` server 配置与命令存在 | `~/.codex/config.toml` |
| 插件 | browser / github / documents / pdf / spreadsheets / presentations / template-creator 启用且 cache 存在 | `~/.codex/config.toml` + `~/.codex/plugins/cache` |
| 系统 skills | openai-docs / imagegen / skill-creator / plugin-creator / skill-installer | `~/.codex/skills/.system` |
| 全局规范 | `~/.codex/AGENTS.md` 存在，建议含中文回复 / 可点短链 / 压缩取舍规则 | 文件正文 grep |

## 关键实现细节

- **dangerous full access 是必需项**：脚本把 `approval_policy = "never"` 和 `sandbox_mode = "danger-full-access"` 当作硬失败项。它们是 `--dangerously-bypass-approvals-and-sandbox` 的持久配置等价物。
- **只读检查，不自动修复**：本 skill 不写 `~/.codex/config.toml`，只打印 `codex -c ...` 或可粘贴的配置片段。
- **插件检查分两层**：配置里的 `[plugins."<plugin>@<marketplace>"].enabled = true` 是启用事实；`~/.codex/plugins/cache/<marketplace>/<plugin>/...` 是 cache 落盘事实，两者都要看。
- **Codex 配置是 TOML**：脚本用 `awk`/`grep` 做轻量检查，不引入额外依赖；`jq` 只作为可选工具提示。
- **改完配置要重启 Codex 会话**：当前会话的权限与 system prompt 已经在启动时确定，配置落盘后通常要新开会话才稳定生效。
