# MasterGo MCP Skill 设计

日期：2026-08-10

## 目标

在 `vft-kit` 新增公开、双端兼容的 `mastergo-mcp` skill，同时覆盖 MasterGo 官方两套 MCP：

- Vibe MCP：连接本机 MasterGo 客户端，读取、生成、修改和同步画布。
- Magic MCP：通过 Token 读取远程设计稿的 DSL / D2C 数据。

Skill 必须能判断用户意图、检查本机状态、配置 Claude Code 或 Codex、诊断连接问题，并在实际操作设计稿时执行正确的安全流程。不得写入私有域名、账号或 Token。

## 已选方案

采用“一个 skill + 一个 Node CLI + 一份按需工作流参考”的方案。

对比过的方案：

1. 纯文档 skill：文件最少，但配置 JSON/TOML、双端状态检查和脱敏输出容易漂移。
2. 单一综合 skill（采用）：入口统一，确定性操作由一个无依赖 Node CLI 承担，复杂工作流按需加载参考文件。
3. 拆成 Vibe/Magic 两个 skill：边界清楚，但用户通常只会说“MasterGo MCP”，触发与诊断会被拆散。

## 目录

```text
plugins/vft-kit/skills/mastergo-mcp/
├── SKILL.md
├── agents/openai.yaml
├── references/workflows.md
├── scripts/mastergo-mcp.mjs
└── tests/test-mastergo-mcp.mjs
```

不修改插件 manifest；当前 manifest 已自动发现 `skills/`。不修改已有脏区 `plugins/vft-kit/skills/cc-baseline/**`。

## 路由规则

| 用户意图 | 选择 |
|---|---|
| 生成页面、读取选区、修改/删除节点、同步 HTML、管理变量或组件 | Vibe MCP |
| 给设计稿链接，提取 DSL/D2C、SVG、文本或元数据 | Magic MCP |
| 安装、检查、升级、报错排查 | 同时检查两套，再按实际配置处理 |

Vibe 不可用时不得静默降级到 Magic：两者能力不等价。必须说明本机客户端、文件连接或端口问题。

## CLI 接口

只提供三个非重叠命令，避免额外管理层：

```text
mastergo-mcp.mjs status [--target claude|codex|both]
mastergo-mcp.mjs configure --mode vibe|magic --target claude|codex|both [选项]
mastergo-mcp.mjs doctor [--target claude|codex|both] [--health]
```

### status

只读检查：

- Node >= 18、npm >= 8。
- Claude Code 用户/项目 scope 与 Codex 合并态是否注册 `mastergo`、`mastergo-magic-mcp`。
- 配置使用的官方包、URL、启用状态与本地 npx 缓存版本。
- 输出只显示凭据是否存在，绝不显示 Token、Header 或完整敏感参数。

### configure

- 优先调用宿主原生命令 `claude mcp add` / `codex mcp add`，不手写宿主配置格式。
- Vibe 使用 `@mastergo/vibe-mcp@latest`；默认 URL 取当前官方值 `http://localhost:30678`，允许 `--url` 覆盖。
- Magic 使用 `@mastergo/magic-mcp`；Token 只从 `MG_MCP_TOKEN` 或 `MASTERGO_API_TOKEN` 读取，不接受聊天正文或命令行明文参数。
- Magic 配置前明确告知 Token 将由宿主原生命令写入其用户级 MCP 配置；仅在用户确认后执行，并把目标配置权限收紧为仅当前用户可读写。Skill 不另建第二份凭据文件。
- 已存在且等价时幂等退出；存在但不一致时展示脱敏差异并停止，只有显式 `--force` 才覆盖。
- 默认只配置用户点名的宿主；`both` 必须显式传入。
- 不实现删除命令。卸载属于破坏性操作，实际需要时经确认后使用宿主原生命令。

### doctor

在 `status` 基础上检查：

- npm registry 当前 latest，提示版本漂移但不自动升级。
- Vibe 配置 URL 的本地端口是否监听；端口不通时提示检查 MasterGo 客户端、当前文件 MCP 状态和实际端口。
- Magic 凭据、团队版权限和文件是否位于团队项目的前提。
- `--health` 时复用 `codex-baseline/scripts/check-mcp-health.mjs` 做 stdio initialize，并额外保留 Vibe 端口探测；不复制第二套健康探针。

## 实际操作流程

`SKILL.md` 只保留路由、入口命令与安全原则；详细工具编排放到 `references/workflows.md`，仅在实际操作设计稿时读取。

Vibe 写操作遵循：读取目标 → 明确目标 ID/根节点 → 执行单次最小修改 → 再读或 diff 验证。删除节点、删除变量、全量同步 HTML 必须得到用户明确授权；同步只接受静态 HTML，不直接提交 `.vue` / `.tsx`。

Magic 读取遵循：解析链接 → 先取 meta/section → 按需取 DSL、SVG、文本 → 选择 `json` / `yaml` / `tree` 输出；不为“省事”一次拉取全部大 payload。

## 安全与错误处理

- Token 不进入仓库、日志、测试 fixture、聊天输出或 `agents/openai.yaml`。
- 测试只使用假 Token，并断言 stdout/stderr 不包含它。
- 配置文件损坏、宿主 CLI 缺失、包名不匹配或目标 scope 不明确时停止，不猜测修复。
- 外网 npm/官方文档访问异常时复用代理规则。
- Vibe 端口可变；`30678` 只是默认值，诊断以实际配置和监听状态为准。
- 当前官方事实可能变化；版本检查走 npm registry，skill 不把版本号写成永久真理。

## 测试与验收

实现遵循 skill TDD：

1. 先让无该 skill 的独立 Agent 处理三类场景，记录其混淆 Vibe/Magic、泄露 Token 或误判端口的失败。
2. 写 `tests/test-mastergo-mcp.mjs`，使用临时 HOME 和 fake `claude`/`codex` 覆盖：未安装、Claude-only、Codex-only、both、幂等配置、冲突配置、Vibe 端口失败、Magic 缺 Token、输出脱敏。
3. 实现最小 CLI 使测试通过，再用同样场景 forward-test skill。

最终验收：

- `node --test plugins/vft-kit/skills/mastergo-mcp/tests/test-mastergo-mcp.mjs`
- `quick_validate.py` 校验 frontmatter。
- `vft-ai:skill-validator` 校验公开层无私有特征。
- 刷新 Claude Code 与 Codex 的 `vft-kit` 插件缓存，比较源码与缓存一致。
- 新会话中分别验证“检查 MasterGo MCP”“配置 Vibe MCP”“用链接读取设计稿”能触发本 skill。

## 非目标

- 不把 MasterGo MCP 变成 `codex-baseline` / `cc-baseline` 必需项。
- 不内置任何公司私有域名或凭据。
- 不复制 MasterGo 官方完整文档或实现新的 MCP server。
- 不自动执行删除、全量画布覆盖或变量删除。
