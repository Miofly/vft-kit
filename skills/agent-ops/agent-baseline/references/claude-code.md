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

`run.sh` 先保证 RTK 可用（缺失时 Homebrew 安装）并把 RTK 的 `PreToolUse` Bash hook 幂等补进 `~/.claude/settings.json`（`rtk hook claude`，装了才会自动压缩 Bash 输出），再同步 Caveman 风格模式（见下节「Caveman 风格模式」：拉上游最新代码，vendor 成用户级 hook，卸掉插件本体），把 `~/.config/caveman/config.json.defaultMode` 固定为 `full`，再把 codegraph 的 `UserPromptSubmit` hook 包上过滤脚本 `codegraph-prompt-filter.py`（hook timeout 设 10 秒；新逻辑只在提示里有 CamelCase、带扩展名的文件名、≥6 字符 snake_case 或反引号符号时才查，索引库超过 1000 MB 时跳过，codegraph 限时 8 秒，结果里至少一个提示标识符作为完整符号名或文件名出现才注入，注入的是自出的 ≤1.5 KB 摘要；默认 live（2026-10-20 影子期 224 条提示：旧逻辑 49 次注入共 105 KB、大块 6 次里 5 次无关、11 次超时，新逻辑仅 1 次相关注入 975 B），判定照常追加到 `CODEGRAPH_FILTER_SHADOW_LOG`（默认 `~/.cache/vft-kit/codegraph-prompt-filter.jsonl`，只记提示前 80 字和标识符）；`touch ~/.cache/vft-kit/codegraph-prompt-filter.SHADOW` 退回影子运行（输出保持旧逻辑），`CODEGRAPH_FILTER_MODE=shadow|live|legacy` 可临时覆盖；自检 `--selftest`），再安装补丁版 `claude-model-router-hook`（固定 commit + `patches/claude-model-router-hook.patch` + `config/model-router.json`，首次为 advisory 影子模式），再用 `migrate-plugin-hooks.sh` 幂等清掉旧版安装脚本写进 `settings.json` 的 bash-prompt-guard / handoff-nudge / reply-lang-pin 绝对路径条目（只删命令含脚本名且不含 `CLAUDE_PLUGIN_ROOT` 的那条 hook，写前备份 `settings.json.bak-<时间戳>`；`CLAUDE_CONFIG_DIR` 指定实例，`--dry-run` 只预览），最后调用只读的 `check.sh`。这三个 hook 现由 vft-kit 插件自己注册（`hooks/hooks.json`，脚本在插件 `scripts/hooks/`）：`handoff-nudge.py` 挂 `PostToolUse`（读 transcript 最后一条主线程 usage，上下文过 40%、55%、70%、85% 各记一次；默认影子运行，只写 `~/.cache/vft-kit/handoff-nudge.jsonl`，`touch ~/.cache/vft-kit/handoff-nudge.LIVE` 后才注入「写交接」提示），`reply-lang-pin.py` 挂 `UserPromptSubmit`（提问里中文占比低于 30% 时补一句「用简体中文回复」，压过 caveman「跟随用户语言」的默认，caveman 的简短风格不变；目标语言 `VFT_REPLY_LANG`，关闭用 `touch ~/.cache/vft-kit/reply-lang.OFF`），`bash-prompt-guard.py` 挂 `PreToolUse` Bash。退出码为 0 表示必需项齐全，为 1 表示存在必需项缺失；可选项不影响退出码。

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
| npm | `@danielsogl/lighthouse-mcp`（载体保留）                                                                                              | - |
| MCP | codegraph、code-review-graph；lighthouse-mcp 已按需移除注册（2026-10-20，用户定；要用再 `claude mcp add`）                                  | - |
| 插件 | superpowers、skill-creator、code-review、frontend-design、typescript-lsp、jdtls-lsp、context-mode、ponytail、gsap-skills；playwright 已按需禁用（2026-10-20，ego-lite 兜底，要用 `claude plugin enable`） | claude-hud、context7、understand-anything、diagram-design、pm-skills |
| Agent Skills | Emil 的 animate、review-animations、apple-design                                                                                               | AnySearch、Emil 其余 7 项 |
| 系统 | Caveman 风格模式 hook（用户级，默认 full；caveman 插件本体不装）、RTK hook（PreToolUse Bash 自动压缩）、bash-prompt-guard hook（插件注册；拒掉会触发内置确认框的 Bash 写法并给改写提示）、codegraph prompt-hook 过滤、reply-lang-pin hook（插件注册；英文提问也用中文回复）、cc 实例纠偏 hook（插件注册；只在 `CLAUDE_CONFIG_DIR` 不是 `~/.claude` 时生效，主会话不受影响，失败放行）：`stall-continue-hook.py`（Stop：宣布下一步却停下、结尾抛选择题、`claude -p` 挂后台就结束、「理论上更快」、没试替代就说「改不了」、没给次数就说「最优 / 稳定更快」、改完没跑任何验证就说「已修好」，各推一次）、`repeat-error-guard.py`（PostToolUseFailure：同一报错签名在最近 2 次内重复，就提示别再换参数重试、先读报错和对比真实状态）、`converge-guard.py`（PostToolUse：最近 3 段文字空泛或重复时要求写出假设和区分检查，每轮最多一次），状态在 `~/.cache/vft-kit/`、handoff-nudge hook（插件注册；上下文过 40% 提醒写交接，默认影子运行，标记文件 `~/.cache/vft-kit/handoff-nudge.LIVE` 存在才生效；窗口按模型 id 判断，可用 `HANDOFF_NUDGE_WINDOW` 覆盖；`HANDOFF_NUDGE_MODEL_WINDOWS="正则=token数;…"` 按模型设有效窗口，给远没到标称窗口就开始退化的模型用）、model-router（补丁版 claude-model-router-hook：只把机械子 agent 路由到 haiku，其余用 opus；SessionStart 改走 `session_brief.py`：健康时零注入（路由规则在全局 CLAUDE.md parallel-policy），仅缺 routed 变体 agent 时报一行，不再注入上游的「Model Tier Rules」表；routed-* 变体 agent 的 description 由补丁压成 `Router-internal; do not use.`（每会话的 Agent 列表都会列出它们，而 hook 还要能路由过去，`deny Agent(name)` 会直接禁用、hook 的 allow 也压不过 deny，没法隐藏，只能压短描述）；`~/.claude/model-router.json` 的 `subagent_enforcement` 从 `advisory` 改 `on` 才生效；补丁另加 `offload` 配置块 `{"subagent_type", "classes", "marker", "start_command", "prompt_template"}`：marker 文件存在时，把所列类别的通用子 agent 改派给指定 agent（比如一个调用便宜后端的薄载体；放在插件 `agents/` 目录并带 `router-generated: true` 时名字带 `router:` 前缀），marker 路径可以写 `{config_dir}` 让开关只对某个实例生效，删掉 marker 就回到原路由；配了 `start_command` 时由 hook 自己把原任务书经 stdin 交给该命令启动后台作业，命令末行输出 `<handle> [agent]`，子 agent 的 prompt 换成 `prompt_template`（`{handle}` 替换），载体只负责等结果，避免弱载体自己动手做活；可选的 agent 名用来按后端改派（如 `xxx-codex`），启动失败则回到原路由）、bypassPermissions、bypass 警告已接受、`~` 目录已信任、供应链只读检查（`mcp-pin-check.mjs`：MCP 是否钉版本，`@latest`/未写版本/git 分支记 HIGH，env 只报 key 名；`skill-supply-scan.mjs ~/.claude/skills`：隐藏 Unicode、curl\|sh、改 API 端点、读凭据路径、未钉版本的 npx 等，只报不计失败；装第三方 skill 或插件前对其目录单独跑一遍）、CodeGraph 白名单、关闭自动更新、关闭 ponytail 代码地图（`env.PONYTAIL_MAP=0`，只去掉 SessionStart 的 Codebase map，ponytail 规则照常注入）、Codex 自动注入 `OPENAI_API_KEY`、全局 CLAUDE.md、项目 memory 目录 | claude-hud 状态栏、CC Switch |
| 全局规范 | 中文回复、可点短链、压缩取舍、代理兜底、多 Agent 并行、CodeGraph 自动初始化、Code Review Graph 优先、Token 节省、Bash 命令避开内置确认框                                                                                         | context7 / AnySearch / context-mode 已安装时才检查对应调用规则（各 1 项） |

## 上下文预算：skill 列表与手动调用

- 每个会话常驻：全局 CLAUDE.md、项目 AGENTS/CLAUDE.md、SessionStart hook 注入、MCP instructions、skill 列表（名字 + description）。skill 正文只在调用时加载。
- codegraph MCP 的 server instructions 不处理（2026-10-20 决策）：codegraph 1.6.0 写死约 5.8k 字、没有开关，Claude Code 只取前 2048 字；上游 PR #1529 未合并。不要再调研或打补丁，等上游合并后再看。
- skill 列表预算是上下文窗口的 1%（`skillListingBudgetFraction` 可调），超出时先丢**最少调用** skill 的描述，名字保留；单条 description + when_to_use 上限 1,536 字。`/context` 的 Skills 行是截断后的实际大小，`claude plugin details <插件>` 给出每个插件的常驻估算。
- 写 description：一句做什么 + 用户会说的领域词，控制在 250 字内；实现细节、长触发词表放正文。压缩前后用真实说法做一次路由对照（`claude -p --model haiku` 只给列表让它选 skill），命中率不降才算过。
- 很少用或只手动用的 skill：SKILL.md frontmatter 加 `disable-model-invocation: true`，描述不进上下文，仍可 `/名字` 调用。插件里按本仓 `explicitOnly` 约定：catalog 登记、`commands/<名字>.md` 带该字段、Codex `agents/openai.yaml` 设 `allow_implicit_invocation: false`、Claude plugin.json 的 skills 根排除该目录（`scripts/validate-skill-catalog.mjs` 校验四处一致）。插件 skill 不受 `skillOverrides` 影响；第三方插件的 skill 只能在插件缓存的 SKILL.md 里补这一行，插件升级会还原，需用 SessionStart hook 每次幂等重打。
- 内置 skill（名字无插件前缀，如 `dataviz`、`claude-api`）描述长又用不到：`settings.json` 的 `skillOverrides` 设 `"name-only"`，列表只留名字，仍可手动调用。用不到的插件设 `enabledPlugins=false`（保留安装，如不写 Java 关 `jdtls-lsp`）。用 CC Switch 时两项都要同步写进公共配置，否则切 provider 会被覆盖。
- 全局 CLAUDE.md 瘦身：低频规则的细则下沉到对应 skill，全局只留一行指针，指针里保留硬约束关键词（如「推理只在 X 跑」「先 `command -v ego-browser`」），保证不调 skill 也知道去哪；与常驻风格插件（ponytail、caveman）重复的条目删掉。被本 skill check.sh 按措辞校验的规范（CodeGraph 自动初始化、Code Review Graph 优先、代理兜底标题）保留原措辞，否则 check 会报缺失；全局 CLAUDE.md 若由脚本按标记块生成，改源再生成，手写进生成文件的条目会在下次生成时丢失。
- 插件「enabled」不等于加载成功：缓存目录与 `installed_plugins.json` 记录的版本不一致时会静默失败，`claude --debug` 日志可见 `not cached at`；修复用 uninstall + install。
- skill 正文调用后常驻上下文直到会话结束：SKILL.md 正文宜 ≤6,000 字，只留定位、何时用、硬规则、路由表，细节放 `references/` 按需读取。
- 拆分 SKILL.md 时按原文行区间逐字搬运，并用脚本核对原文每行都落到新文件（覆盖率 100%）；理解后改写会丢内容。同时核对原有 references 文件没被删或覆盖。
- 项目级 CLAUDE.md 过大时，把只对部分文件生效的规则移到 `.claude/rules/*.md`，用 `paths:` frontmatter 限定只在读写匹配文件时加载；子目录规则的 glob 同时写相对项目根与 `**/` 前缀两种（如 `src/api/**` 和 `**/src/api/**`）。

## Caveman 风格模式（用户级 hook）

只保留 caveman 的风格模式，不装插件本体：插件带的二十多个 skill 和 cavecrew agent 每个会话都占上下文。`install-caveman-default.sh` 调用通用脚本 `scripts/vendor-plugin-hooks.mjs`，配置文件是 `config/caveman-hooks.json`，调用方可用 `CAVEMAN_VENDOR_CONFIG` 指向自己的配置。脚本按以下步骤执行：

1. 在 `~/.cache/vft-kit/caveman/upstream` 浅拉上游 `ref`（默认 `main`）。只把 `src/hooks`、`skills/caveman|ultracave|megacave` 和 `.claude-plugin/plugin.json` 复制到暂存目录。
2. 自检：在隔离的 `CLAUDE_CONFIG_DIR` 里依次运行 SessionStart、SubagentStart、UserPromptSubmit，要求退出码为 0，且输出含 `CAVEMAN MODE ACTIVE`。通过后换入 `~/.cache/vft-kit/caveman/current`，上一版留在 `previous`。
3. 按 `current` 中 `plugin.json` 的 hook 定义改写 `settings.json`。命令前加 `export CLAUDE_PLUGIN_ROOT='<vendor>/current';`，命令文本里的 `${CLAUDE_PLUGIN_ROOT}` 换成字面路径。Claude Code 会拒绝运行引用这个变量的非插件 hook，报错 `Hook command references ${CLAUDE_PLUGIN_ROOT} but the hook is not associated with a plugin`。新条目插在各事件数组的最前面，其他 hook 不动。配置里的 `commandOverrides{事件: 命令}` 用来替换该事件上游唯一一个 hook 的命令：caveman 用它让 SubagentStart 先把 `loadRuleset` 置空，再运行上游的 `--subagent`。这样子 agent 只拿到约 0.7KB 的短版规则，主会话仍是约 4.7KB 的全文，模式判断仍走上游。
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

覆盖：`run.sh` 的安装顺序 / 参数转发 / 退出码传播、RTK 二进制与 hook 的幂等安装、Caveman 风格模式 hook（`test-caveman-default.sh`：只卸一次插件、接三条 hook、默认 full；`test-vendor-plugin-hooks.sh`：本地 git 夹具上验证接线幂等、其他 hook 保留、上游坏/拉取失败/自检失败保留旧版、插件在时不接线、用户级命令只覆盖受管文件）、codegraph 与 code-review-graph 与 Emil skills 的基线判定、RTK hook 缺失判为必需项、codegraph prompt-hook 过滤（新旧筛选逻辑、相关性门槛与摘要上限的 `--selftest`、幂等改写 settings 并设 timeout 10、影子与生效两种模式的日志）、handoff-nudge 与 reply-lang-pin（判定、每档只记一次、影子与生效两种输出；脚本在插件 `scripts/hooks/`）、cc 实例纠偏三个 hook 各自的 `--self-test`（含主会话不触发）、`test-migrate-plugin-hooks.sh`（只删旧绝对路径条目、其他 hook 保留、写前备份、幂等、`CLAUDE_CONFIG_DIR` 与 `--dry-run`）。`test-mcp-pin-check.sh` 与 `test-skill-supply-scan.sh` 覆盖供应链两脚本的分类、不泄露 env 值、不写配置。`test-cc-instance-flags.sh` 覆盖开关同步的排除与强制、保留其他配置键、源缺失、没变化不重写、拒绝主目录、并行运行。

## 第三方网关实例：原生 Monitor 与开关同步

用 `CLAUDE_CONFIG_DIR` 隔离、走 `ANTHROPIC_BASE_URL` 的实例，默认没有 Monitor 工具，其他行为也停在 CC 的旧默认值。原因是这类实例通常设 `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`，GrowthBook 被关掉，所有特性开关都取内置默认；Monitor 由开关 `tengu_amber_sentinel` 控制，默认为 false。外部版本不认 `CLAUDE_INTERNAL_FC_OVERRIDES`。

做法：实例的启动器 export `CLAUDE_CODE_GB_DISK_CACHE_WHEN_TELEMETRY_OFF=1`（要求 provider 为 firstParty，走 `ANTHROPIC_BASE_URL` 也算），让 CC 读实例 `.claude.json` 里的 `cachedGrowthBookFeatures`；然后在 `exec claude` 前跑 `claude-code/scripts/cc-instance-flags.sh`。脚本把主 `~/.claude.json` 的开关缓存只读复制过去，排除官方账号专属和推广类（`CC_FLAGS_EXCLUDE`），再把 `CC_FLAGS_FORCE`（默认 `tengu_amber_sentinel`）强制设为 true；源缺失时只写强制项。内容没变化就不写，写入用每个进程独立的 tmp 文件，失败也退出 0，并行启动不会卡住启动器。`--dry-run` 只报数量和是否变化。

- 不依赖官方账号：开关在本地缓存里，Monitor 在本机跑 shell，模型请求走网关。主 CC 如果换成未登录身份重新拉开关，缓存会变，实例下次启动也会跟着变，只有强制项不受影响。
- 验收：`claude -p 'say ok' --output-format stream-json --verbose` 的 init 事件里 `tools` 包含 `Monitor`；交互模式下 Monitor 运行时状态栏显示 `1 monitor`。实例的 CLAUDE.md 如果写过「没有 Monitor」，要一起删掉，否则模型会拒绝调用。
- CC 升级后 Monitor 消失：到 claude 二进制里搜 `userFacingName(){return"Monitor"}`，看旁边 `isEnabled` 用的新开关名，再改 `CC_FLAGS_FORCE`（2.1.280 实测）。

## 第三方网关实例：多模型切换与规范继承

一个实例经本地 LiteLLM 接多个后端，在会话里用 `/model` 切换。以下是 Claude Code 2.1.280 和 LiteLLM 1.106 上实测的通用做法和坑。个人的 key、端口、模型清单放在私有层。

- **上下文窗口**：走第三方 `ANTHROPIC_BASE_URL` 时，不管是未知模型名还是 `claude-*`，Claude Code 都按 200k 算，这是客户端保守的默认值。模型名加 `[1m]` 后缀（如 `glm[1m]`、`claude-opus-5-5[1m]`）才按 1M 算，Claude Code 发请求前会去掉这个后缀。先实测网关能不能处理 200k 以上的输入，再开 1M。`[1m]` 在 zsh 里会被当成通配符，写进启动命令要加引号。
- **`/model` 菜单**：user settings 里的 `modelPicker.options` 是 `[{model, label, description, behavesAs}]` 的数组。Claude Code 不认识的模型必须写 `behavesAs`（填一个它认识的模型 id），否则不会出现在菜单里。`replaceBuiltInOptions: true` 时菜单只剩 Default 和这些行，顺序按数组来。如果用同步脚本从主配置覆盖实例的 settings，要保留 `modelPicker`、`effortLevel` 这类实例自己的键。
- **启动时的默认模型**：settings env 里的 `ANTHROPIC_MODEL` 优先于在菜单里按 Enter 存下的 `model`。要换开局模型，用 `--model`。
- **LiteLLM fallback**：`router_settings.fallbacks` 的键按请求里的确切模型名匹配，写成 `claude-*` 这种通配键不生效（`router_utils/fallback_event_handlers.py`）。每个名字都要单独列一条，可以用 YAML 锚点复用后备列表。`CustomLogger.async_filter_deployments` 返回空列表时会触发 fallback。
- **按 key 路由、记录 key**：同名部署有多个时，`async_filter_deployments` 可以按自定义请求头（Claude Code 用 `ANTHROPIC_CUSTOM_HEADERS` 发）挑出指定 key；冷却中的 key 不在候选里，会自动换另一个。`async_log_success_event` 里用 `kwargs['litellm_params']['proxy_server_request']['headers']` 拿 `x-claude-code-session-id`，用 `model_info.id` 拿实际部署 id，就能让状态栏显示本会话实际在用的 key。`session_affinity` 的绑定存在内存里，代理重启就丢。
- **只回 SSE 的 OpenAI 中转**：有的中转不管是否流式，`/v1/responses` 都回 SSE。`openai/` 会走 Responses API，非流式请求解析失败，还会被 fallback 悄悄换成别的模型回答。改用 `hosted_vllm/` 走 chat completions。
- **重启代理**：按端口找监听进程来杀（`lsof -tiTCP:<port> -sTCP:LISTEN`），不要按 pid 文件。启动失败的那次也会写 pid 文件，之后旧代理一直杀不掉，改了配置也不生效。
- **记忆不共享**：实例读的是 `<CLAUDE_CONFIG_DIR>/projects/<cwd>/memory`，主配置的记忆不会自动过去。要单向同步：主配置的文件更新过才覆盖，实例自己写的不删，`MEMORY.md` 把实例自己的索引行合并在后面。`utimes` 只保留到毫秒，比较修改时间时留 1 ms 容差，否则每次都判定为有改动。
- **本地目录插件是缓存副本**：`plugins/cache/<marketplace>/<plugin>/<version>` 是安装时复制的，版本号不变时 `claude plugin update` 认为已是最新，新加的 hook 不会生效。要在对应的 `CLAUDE_CONFIG_DIR` 下先 uninstall 再 install，然后检查缓存里的 `hooks/hooks.json`。
- **按模型区分的规则**：只写在很长的 CLAUDE.md 末尾，模型容易套错，比如 Sonnet 把「Opus 自己做」套到自己身上，还认为自己是主会话。规则开头要写明「你就是这里说的实例，不管当前是什么模型」，再用 UserPromptSubmit hook 每轮注入当前模型和对应做法。当前模型可以从状态栏 stdin 的 `model.id` 记下来，也可以取会话记录里最后一条回复的 `message.model`，或者父进程的 `--model`。实测提醒之后 spark、gpt、glm 会照做，Sonnet 3/3 次仍不照做，这类模型不建议放进实例里。

> 测试靠环境变量注入 mock（`RTK_SCRIPT` / `CAVEMAN_SCRIPT` / `CHECK_SCRIPT`），所以 `run.sh` 里这些路径变量（含 `CG_FILTER_SCRIPT`、`MR_SCRIPT`、`MIGRATE_SCRIPT`）**必须保持 `${VAR:-默认值}` 形式**；写成硬编码会让 mock 注入失效、测试报出误导性的「exit code not propagated」。

## 约束

### 改动纪律

- 发现更简单且等价的方案时，明确提出并采用。
- 只修改与请求或必要联动直接相关的文件，保持现有风格。
- 不重构未损坏的代码；不要顺手整理相邻注释、格式或死代码。
- 只清理本次修改造成的孤儿 import、变量、函数、测试和引用。

- CodeGraph 以 CLI 可执行为准；新项目用 `codegraph init`，增量刷新用 `codegraph sync`，完整重建用 `codegraph index -f`。
- 多实例（`CLAUDE_CONFIG_DIR` 隔离的第三方网关实例）对主 `~/.claude` **只读**：`CLAUDE_CONFIG_DIR` 只隔离 Claude Code 自身，不隔离实例会话里跑的命令。会写 `settings.json` 的工具（CC Switch 本地路由接管、改 env 的安装器）必须在目标实例的 `CLAUDE_CONFIG_DIR` 下执行，否则该实例的 provider env 会写进主配置，所有新会话被切走。主 `settings.json` 的 `env` 出现 `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_MODEL` / `ANTHROPIC_DEFAULT_*_MODEL` 即泄漏（主配置走官方登录，本不该有），备份后删除；私有层 `sync-cc-profiles.mjs --check` 自带该检测。
- 图工具分工：读代码、改代码、查调用链用 codegraph；代码审查用 code-review-graph。
- 所有代码审查优先通过 code-review-graph MCP 获取最小上下文、影响半径和相关测试，再按结果读取源码；图谱首次建立或完整重建用 `code-review-graph build`，日常刷新用 `code-review-graph update`，状态检查用 `code-review-graph status`。
- 插件检查读取 `installed_plugins.json`，覆盖 user、project 和 local scope；已装插件同时显示 `~/.claude/settings.json` 的 `enabledPlugins` 状态（已启用 / 已禁用 / 未登记），刻意禁用的插件仍记 ✓，看括号确认开关。
- `--health` 只实连 codegraph、code-review-graph、lighthouse 和 Playwright，不启动额外常驻服务。
- 装了 context-mode 时，发 HTTP 一律走 `ctx_execute` / `ctx_fetch_and_index`。它的 PreToolUse hook 会拦下「响应体打到 stdout」的 curl/wget 并渲染成红色 Error——那是设计好的路由提示，不是故障，插件也没有静默开关；被拦一次就白费一轮工具调用。非要用 Bash curl 就写成 hook 放行的形态：`-s`（wget `-q`）+ 输出落文件，且不能是 `-o -` / `/dev/stdout`，不能带 `-v`。
- 文本检索一律走 `rg` 或 `/usr/bin/grep`（绝对路径）。裸 `grep` 会被 Claude Code shell 快照注入的 `grep` shell 函数劫持（转发 claude 二进制内置 ugrep，本机派发坏，报 `error: unknown option '-G'`）；与 rtk 无关——rtk hook 不改写 grep。例：`(rg -l "关键字" dir 2>/dev/null || /usr/bin/grep -rl "关键字" dir)`。`scripts/*.sh` 内部 grep 跑在子 shell，不受该函数影响。
