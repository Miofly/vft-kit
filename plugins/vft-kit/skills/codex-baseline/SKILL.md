---
name: codex-baseline
description: Use when 用户要求核对本机 Codex CLI 装配基线，例如“codex-baseline”“codex-doctor”“Codex 体检”“权限配置对吗”“插件/MCP 全不全”“换机器后核对”，或检查 dangerous full access、项目信任、hooks、Memories、multi-agent、MCP、插件、Agent Skills、图片生成 CLI 与全局 AGENTS 规范。支持 --health 实连 stdio MCP。
---

# codex-baseline

核对 Codex CLI 的本机装配状态。`scripts/check.sh` 是检查项和修复命令的唯一真相来源；不要在本文复制脚本实现细节。

## 执行

统一从 `run.sh` 进入：

```bash
bash ${CODEX_PLUGIN_ROOT:-${VFT_PLUGIN_ROOT:-.}}/skills/codex-baseline/scripts/run.sh
```

需要验证 MCP 初始化握手时：

```bash
bash ${CODEX_PLUGIN_ROOT:-${VFT_PLUGIN_ROOT:-.}}/skills/codex-baseline/scripts/run.sh --health
```

`run.sh` 会执行已授权的常设维护：同步 CC-Switch 认证、准备 imagegen CLI、维护 imagegen 与 Caveman 默认 full 的全局 AGENTS 托管块。Caveman 规则写入当前实际生效文件：存在 `~/.codex/AGENTS.override.md` 时写 override，否则写 `~/.codex/AGENTS.md`。不得输出完整 Key。其余检查只读。

输出含 `✓` 已满足、`✗` 必需项缺失、`○` 可选提醒、`⊘` 通过 `CODEX_BASELINE_SKIP` 声明的刻意不装。只有必需项缺失时退出码为 1。

## 回报与修复

- 用“项 | 作用”表格回报缺失项，不向用户倾倒长修复命令。
- 用户确认补齐后，执行对应检查行给出的命令并重跑。
- Ponytail 缺失已获长期授权，可直接分两步补齐 marketplace 和插件；其他项目先回报。
- 配置、MCP、插件或全局规范变更后提醒用户新开 Codex 会话。
- 只有必需项与既有方案明确互斥时才使用 `CODEX_BASELINE_SKIP`。

## 基线

| 类别 | 必需 | 可选 |
|---|---|---|
| CLI | codex、node、npm、git、codegraph | brew、jq、gh、vercel、RTK |
| 权限与项目 | dangerous full access、隐藏警告、hooks、Memories、multi_agent、信任目录 | 关闭启动更新检查 |
| MCP | Playwright、CodeGraph、Lighthouse、OpenAI Developer Docs | Context7、Vercel |
| 插件 | GitHub、Build Web Apps、Ponytail、Context Mode | Superpowers、Diagram Design |
| Agent Skills | Caveman + 默认 full、GSAP 8 项、Emil 3 项 | AnySearch、Grill-me、Understand Anything、PM Skills、Emil 其余 7 项 |
| 系统 skills | openai-docs、imagegen、skill-creator、plugin-creator、skill-installer | - |
| 图片生成 | imagegen 脚本、专用 venv、依赖、`codex-imagegen`、认证注入源 | - |
| 全局 AGENTS | `AGENTS.md` 中的中文回复、可点短链、压缩取舍、代理兜底、多 Agent 并行、生图规则；Caveman 额外检查实际生效文件 | Context7 / AnySearch 已安装时才检查对应调用规则 |

Codex 原生 `features.memories = true` 已承担跨会话回忆，不叠加 agentmemory MCP。

## 可选安装

只在用户明确选择时安装：

```bash
# Diagram Design：原生 Codex 插件
codex plugin marketplace add cathrynlavery/diagram-design
codex plugin add diagram-design@diagram-design

# Understand Anything：陌生大仓知识图谱；首次全量分析耗 token
curl -fsSL https://raw.githubusercontent.com/Egonex-AI/Understand-Anything/main/install.sh | bash -s codex

# PM Skills：68 个产品工作流 skill；可用 --skill 单独选择
npx skills add phuryn/pm-skills --agent codex --global --yes

# AnySearch：同时配置 API key 和全局调用规则
bash ${CODEX_PLUGIN_ROOT:-${VFT_PLUGIN_ROOT:-.}}/skills/codex-baseline/scripts/install-anysearch.sh
```

Emil 动效 skills：

```bash
npx skills add emilkowalski/skills \
  --skill animate \
  --skill review-animations \
  --skill apple-design \
  --agent codex --global --yes
```

`animation-vocabulary`、`ask-sonner`、`emil-design-eng`、`find-animation-opportunities`、`improve-animations`、`pick-ui-library`、`prototype` 按项目安装，不自动补齐。

## 约束

- dangerous full access 必须同时满足 `approval_policy = "never"` 和 `sandbox_mode = "danger-full-access"`。
- MCP 与插件优先读取 Codex 合并后的真实状态，覆盖 user、project、local 和 runtime scope；文件检查只是命令不可用时的回退。
- Claude 专属的 statusLine、permissions 白名单、LSP 插件和 RTK Claude hook 不迁移。
- Claude 插件优先映射到 Codex 原生能力：remember 对应 Memories，code-review 对应 `codex review` + GitHub，frontend-design 对应 Build Web Apps。
- CodeGraph 新项目用 `codegraph init`，增量刷新用 `codegraph sync`，完整重建用 `codegraph index -f`。
- `--health` 只对已启用的 stdio MCP 做真实 `initialize` 握手，并回收子进程。
