> 运行资源目录：`<plugin-root>/skills/agent-ops/agent-baseline/claude-code`；命令中的 `scripts/`、`tests/` 相对此目录解析。

# Agent baseline / Claude Code

> **浏览器/API 边界**：遵守 [浏览器到 API 强制演进](../../../BROWSER_API_EVOLUTION.md)。本机装配、视觉、兼容性或浏览器本身的验证可保留浏览器；认证后的远端业务读写必须探索实际接口、写后独立回读，并在确认后更新本 skill，后续默认 API。

核对 Claude Code 的本机装配状态。`scripts/check.sh` 是检查项和修复命令的唯一真相来源；不要在本文复制脚本实现细节。

## 执行

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/agent-ops/agent-baseline/claude-code/scripts/run.sh
```

需要验证 MCP 实际连接时：

```bash

bash ${CLAUDE_PLUGIN_ROOT}/skills/agent-ops/agent-baseline/claude-code/scripts/run.sh --health
```

`run.sh` 先保证 RTK 可用（缺失时 Homebrew 安装）并把 RTK 的 `PreToolUse` Bash hook 幂等补进 `~/.claude/settings.json`（`rtk hook claude`，装了才会自动压缩 Bash 输出），再同步 Caveman 风格模式（见下节「Caveman 风格模式」：拉上游最新代码，vendor 成用户级 hook，卸掉插件本体），把 `~/.config/caveman/config.json.defaultMode` 固定为 `full`，再把 codegraph 的 `UserPromptSubmit` hook 包上过滤脚本 `codegraph-prompt-filter.py`（hook timeout 设 10 秒；新逻辑只在提示里有 CamelCase、带扩展名的文件名、≥6 字符 snake_case 或反引号符号时才查，索引库超过 1000 MB 时跳过，codegraph 限时 8 秒，结果里至少一个提示标识符作为完整符号名或文件名出现才注入，注入的是自出的 ≤1.5 KB 摘要；默认影子运行：输出保持旧逻辑，只把新逻辑的判定追加到 `CODEGRAPH_FILTER_SHADOW_LOG`（默认 `~/.cache/vft-kit/codegraph-prompt-filter.jsonl`，只记提示前 80 字和标识符），`touch ~/.cache/vft-kit/codegraph-prompt-filter.LIVE` 后才生效，`CODEGRAPH_FILTER_MODE=shadow|live|legacy` 可临时覆盖；自检 `--selftest`），再安装补丁版 `claude-model-router-hook`（固定 commit + `patches/claude-model-router-hook.patch` + `config/model-router.json`，首次为 advisory 影子模式），再把 `handoff-nudge.py` 注册为 `PostToolUse` hook（读 transcript 最后一条主线程 usage，上下文过 40%、55%、70%、85% 各记一次；默认影子运行，只写 `~/.cache/vft-kit/handoff-nudge.jsonl`，`touch ~/.cache/vft-kit/handoff-nudge.LIVE` 后才注入「写交接」提示），再把 `reply-lang-pin.py` 注册为 `UserPromptSubmit` hook（提问里中文占比低于 30% 时补一句「用简体中文回复」，压过 caveman「跟随用户语言」的默认，caveman 的简短风格不变；目标语言 `VFT_REPLY_LANG`，关闭用 `touch ~/.cache/vft-kit/reply-lang.OFF`），最后调用只读的 `check.sh`。退出码为 0 表示必需项齐全，为 1 表示存在必需项缺失；可选项不影响退出码。

启动 skill 后立即新建一个子 Agent，与主线程的 baseline 检查并行。子 Agent 只读比较 `claude --version` 与 `npm view @anthropic-ai/claude-code version --registry=https://registry.npmjs.org`，按 SemVer 数字段（禁止字符串排序）判断 Claude Code CLI 是否有新版本；**不核对插件版本**（用户明确不需要，也不提示）。主线程完成检查后收集其结果：CLI 有新版本时列出“Claude Code｜当前版本｜最新版本”，询问用户是否更新；无新版本时只报告已是最新。本地或上游命令失败、输出为空、版本无法解析时必须报告“无法判断”，不得当作已是最新。子 Agent 不可用时由主线程完成同一只读检查，不阻塞 baseline。

## 回报与修复

- 用“项 | 作用”表格回报缺失必需项；**未安装的可选项也必须一并列出**（项 | 作用 | 适合场景），让用户知道还有哪些可装，装不装由用户选。不向用户倾倒脚本中的长修复命令。
- 用户确认补齐后，执行对应检查行给出的命令并重跑检查。
- RTK（含其 PreToolUse hook）、Ponytail、Caveman 风格模式 hook（含卸载 caveman 插件本体）和 codegraph prompt-hook 过滤缺失已获长期授权，可直接补齐；其他项目先回报。
- MCP、插件或全局规范变更后提醒用户新开 Claude Code 会话。

## 基线

> 下表是**概览**，具体项以 `check.sh` 实际输出为准（新增检查项时它会先于本表变化）。

| 类别 | 必需                                                                                                                                          | 可选 |
|---|---------------------------------------------------------------------------------------------------------------------------------------------|---|
| CLI | node、npm、claude、rtk、codegraph、code-review-graph                                                                                             | brew、jq、gh |
| npm | `@danielsogl/lighthouse-mcp`                                                                                                                | - |
| MCP | codegraph、code-review-graph、lighthouse-mcp                                                                                                  | - |
| 插件 | superpowers、skill-creator、code-review、frontend-design、playwright、typescript-lsp、jdtls-lsp、context-mode、ponytail、gsap-skills | claude-hud、context7、grill-me、understand-anything、diagram-design、pm-skills |
| Agent Skills | Emil 的 animate、review-animations、apple-design                                                                                               | AnySearch、Emil 其余 7 项 |
| 系统 | Caveman 风格模式 hook（用户级，默认 full；caveman 插件本体不装）、RTK hook（PreToolUse Bash 自动压缩）、bash-prompt-guard hook（拒掉会触发内置确认框的 Bash 写法并给改写提示）、codegraph prompt-hook 过滤、reply-lang-pin hook（英文提问也用中文回复）、handoff-nudge hook（上下文过 40% 提醒写交接，默认影子运行，标记文件 `~/.cache/vft-kit/handoff-nudge.LIVE` 存在才生效；窗口按模型 id 判断，可用 `HANDOFF_NUDGE_WINDOW` 覆盖）、model-router（补丁版 claude-model-router-hook：只把机械子 agent 路由到 haiku；`~/.claude/model-router.json` 的 `subagent_enforcement` 从 `advisory` 改 `on` 才生效）、bypassPermissions、bypass 警告已接受、`~` 目录已信任、供应链只读检查（`mcp-pin-check.mjs`：MCP 是否钉版本，`@latest`/未写版本/git 分支记 HIGH，env 只报 key 名；`skill-supply-scan.mjs ~/.claude/skills`：隐藏 Unicode、curl\|sh、改 API 端点、读凭据路径、未钉版本的 npx 等，只报不计失败；装第三方 skill 或插件前对其目录单独跑一遍）、CodeGraph 白名单、关闭自动更新、Codex 自动注入 `OPENAI_API_KEY`、全局 CLAUDE.md、项目 memory 目录 | claude-hud 状态栏、CC Switch |
| 全局规范 | 中文回复、可点短链、压缩取舍、代理兜底、多 Agent 并行、CodeGraph 自动初始化、Code Review Graph 优先、Token 节省、Bash 命令避开内置确认框                                                                                         | context7 / AnySearch / context-mode 已安装时才检查对应调用规则（各 1 项） |

## 上下文预算：skill 列表与手动调用

- 每个会话常驻：全局 CLAUDE.md、项目 AGENTS/CLAUDE.md、SessionStart hook 注入、MCP instructions、skill 列表（名字 + description）。skill 正文只在调用时加载。
- skill 列表预算是上下文窗口的 1%（`skillListingBudgetFraction` 可调），超出时先丢**最少调用** skill 的描述，名字保留；单条 description + when_to_use 上限 1,536 字。`/context` 的 Skills 行是截断后的实际大小，`claude plugin details <插件>` 给出每个插件的常驻估算。
- 写 description：一句做什么 + 用户会说的领域词，控制在 250 字内；实现细节、长触发词表放正文。压缩前后用真实说法做一次路由对照（`claude -p --model haiku` 只给列表让它选 skill），命中率不降才算过。
- 很少用或只手动用的 skill：SKILL.md frontmatter 加 `disable-model-invocation: true`，描述不进上下文，仍可 `/名字` 调用。插件里按本仓 `explicitOnly` 约定：catalog 登记、`commands/<名字>.md` 带该字段、Codex `agents/openai.yaml` 设 `allow_implicit_invocation: false`、Claude plugin.json 的 skills 根排除该目录（`scripts/validate-skill-catalog.mjs` 校验四处一致）。插件 skill 不受 `skillOverrides` 影响。
- 插件「enabled」不等于加载成功：缓存目录与 `installed_plugins.json` 记录的版本不一致时会静默失败，`claude --debug` 日志可见 `not cached at`；修复用 uninstall + install。

## Caveman 风格模式（用户级 hook）

只保留 caveman 的风格模式，不装插件本体：插件带的二十多个 skill 和 cavecrew agent 每个会话都占上下文。`install-caveman-default.sh` 调用通用脚本 `scripts/vendor-plugin-hooks.mjs`，配置文件是 `config/caveman-hooks.json`，调用方可用 `CAVEMAN_VENDOR_CONFIG` 指向自己的配置。脚本按以下步骤执行：

1. 在 `~/.cache/vft-kit/caveman/upstream` 浅拉上游 `ref`（默认 `main`）。只把 `src/hooks`、`skills/caveman|ultracave|megacave` 和 `.claude-plugin/plugin.json` 复制到暂存目录。
2. 自检：在隔离的 `CLAUDE_CONFIG_DIR` 里依次运行 SessionStart、SubagentStart、UserPromptSubmit，要求退出码为 0，且输出含 `CAVEMAN MODE ACTIVE`。通过后换入 `~/.cache/vft-kit/caveman/current`，上一版留在 `previous`。
3. 按 `current` 中 `plugin.json` 的 hook 定义改写 `settings.json`。命令前加 `export CLAUDE_PLUGIN_ROOT='<vendor>/current';`，命令文本里的 `${CLAUDE_PLUGIN_ROOT}` 换成字面路径。Claude Code 会拒绝运行引用这个变量的非插件 hook，报错 `Hook command references ${CLAUDE_PLUGIN_ROOT} but the hook is not associated with a plugin`。新条目插在各事件数组的最前面，其他 hook 不动。
4. 装用户级命令 `~/.claude/commands/caveman.md`（来源 `config/caveman-command.md`，设了 `disable-model-invocation`，不占模型上下文）。插件卸载后，交互式会话里输入 `/caveman ultra` 会报 `Unknown command` 且不发送，hook 也收不到；有了这个命令，hook 才能完成切换。
5. caveman 插件仍装着时，脚本只 vendor 不接线，避免同一套规则注入两次；`--check` 通过后才卸载插件，卸载后再接线。

拉取失败、上游缺文件或缺事件、自检失败时，保留旧的 `current`，打印告警，退出码为 0。只有 `--check` 会以 1 退出，供 `check.sh` 使用。手动执行：`node scripts/vendor-plugin-hooks.mjs --config config/caveman-hooks.json`；只核对时加 `--check`，不联网时加 `--offline`。

上游 4.x 起，档位从 lite/full/ultra/wenyan-* 合并为 `caveman`、`ultracave`、`megacave`，旧名自动映射，用 `/caveman`、`/caveman ultra`、`/caveman wenyan` 切换，用 `stop caveman` 或 `normal mode` 关闭。`claude -p` 等 SDK 入口默认不启用；需要启用时设置环境变量 `CAVEMAN_DEFAULT_MODE=full`。要固定在某个版本，把配置里的 `ref` 改成对应的 tag 或 commit。

Claude Code 2.1.59 起默认提供 auto memory，项目记忆位于 `~/.claude/projects/<project>/memory/`。不要再叠加第三方记忆插件或记忆类 MCP；只有用户明确需要外部向量检索服务时才单独评估。

## 可选安装

只在用户明确选择时安装：

```bash
# AnySearch：同时配置 API key 和全局调用规则
bash ${CLAUDE_PLUGIN_ROOT}/skills/agent-ops/agent-baseline/claude-code/scripts/install-anysearch.sh

# PM 工作流：9 个插件，适合 PRD、产品发现、战略与上线规划
bash ${CLAUDE_PLUGIN_ROOT}/skills/agent-ops/agent-baseline/claude-code/scripts/install-pm-skills.sh

# Understand Anything：首次全量分析耗 token，适合陌生大仓和新人导览
claude plugin marketplace add Egonex-AI/Understand-Anything
claude plugin install understand-anything@understand-anything

# Diagram Design：专业架构图、流程图和时序图
claude plugin marketplace add cathrynlavery/diagram-design
claude plugin install diagram-design@diagram-design
```

Claude Code 会话中执行 marketplace 和 install 时分开发送，避免前一条配置尚未刷新。

Emil 动效 skills：

```bash
npx skills add emilkowalski/skills \
  --skill animate \
  --skill review-animations \
  --skill apple-design \
  --agent claude-code --global --yes
```

`animation-vocabulary`、`ask-sonner`、`emil-design-eng`、`find-animation-opportunities`、`improve-animations`、`pick-ui-library`、`prototype` 按项目安装，不自动补齐。

## 自检测试

`scripts/test-*.sh`，全部用 `mktemp` 造隔离的假 `HOME` 与假 `PATH` 运行，**不碰真实环境、不装任何东西**。改动 `check.sh` / `run.sh` 后必跑：

```bash
cd ${CLAUDE_PLUGIN_ROOT}/skills/agent-ops/agent-baseline/claude-code/scripts
for t in test-*.sh; do bash "$t" >/dev/null 2>&1 && echo "✓ $t" || echo "✗ $t"; done
```

覆盖：`run.sh` 的安装顺序 / 参数转发 / 退出码传播、RTK 二进制与 hook 的幂等安装、Caveman 风格模式 hook（`test-caveman-default.sh`：只卸一次插件、接三条 hook、默认 full；`test-vendor-plugin-hooks.sh`：本地 git 夹具上验证接线幂等、其他 hook 保留、上游坏/拉取失败/自检失败保留旧版、插件在时不接线、用户级命令只覆盖受管文件）、codegraph 与 code-review-graph 与 Emil skills 的基线判定、RTK hook 缺失判为必需项、codegraph prompt-hook 过滤（新旧筛选逻辑、相关性门槛与摘要上限的 `--selftest`、幂等改写 settings 并设 timeout 10、影子与生效两种模式的日志）、handoff-nudge（判定、每档只记一次、影子与生效两种输出、幂等注册）。`test-mcp-pin-check.sh` 与 `test-skill-supply-scan.sh` 覆盖供应链两脚本的分类、不泄露 env 值、不写配置。

> 测试靠环境变量注入 mock（`RTK_SCRIPT` / `CAVEMAN_SCRIPT` / `CHECK_SCRIPT`），所以 `run.sh` 里这些路径变量（含 `CG_FILTER_SCRIPT`、`MR_SCRIPT`、`HN_SCRIPT`）**必须保持 `${VAR:-默认值}` 形式**；写成硬编码会让 mock 注入失效、测试报出误导性的「exit code not propagated」。

## 约束

### 改动纪律

- 发现更简单且等价的方案时，明确提出并采用。
- 只修改与请求或必要联动直接相关的文件，保持现有风格。
- 不重构未损坏的代码；不要顺手整理相邻注释、格式或死代码。
- 只清理本次修改造成的孤儿 import、变量、函数、测试和引用。

- CodeGraph 以 CLI 可执行为准；新项目用 `codegraph init`，增量刷新用 `codegraph sync`，完整重建用 `codegraph index -f`。
- 所有代码审查优先通过 code-review-graph MCP 获取最小上下文、影响半径和相关测试，再按结果读取源码；图谱首次建立或完整重建用 `code-review-graph build`，日常刷新用 `code-review-graph update`，状态检查用 `code-review-graph status`。
- 插件检查读取 `installed_plugins.json`，覆盖 user、project 和 local scope。
- `--health` 只实连 codegraph、code-review-graph、lighthouse 和 Playwright，不启动额外常驻服务。
- 装了 context-mode 时，发 HTTP 一律走 `ctx_execute` / `ctx_fetch_and_index`。它的 PreToolUse hook 会拦下「响应体打到 stdout」的 curl/wget 并渲染成红色 Error——那是设计好的路由提示，不是故障，插件也没有静默开关；被拦一次就白费一轮工具调用。非要用 Bash curl 就写成 hook 放行的形态：`-s`（wget `-q`）+ 输出落文件，且不能是 `-o -` / `/dev/stdout`，不能带 `-v`。
- 文本检索一律走 `rg` 或 `/usr/bin/grep`（绝对路径）。裸 `grep` 会被 Claude Code shell 快照注入的 `grep` shell 函数劫持（转发 claude 二进制内置 ugrep，本机派发坏，报 `error: unknown option '-G'`）；与 rtk 无关——rtk hook 不改写 grep。例：`(rg -l "关键字" dir 2>/dev/null || /usr/bin/grep -rl "关键字" dir)`。`scripts/*.sh` 内部 grep 跑在子 shell，不受该函数影响。
