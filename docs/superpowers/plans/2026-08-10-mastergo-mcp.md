# MasterGo MCP Skill 实施计划

> **执行要求：** 使用 `superpowers:subagent-driven-development` 持续执行，不在任务之间等待用户确认。

**目标：** 在 vft-kit 交付同时覆盖 MasterGo Vibe 与 Magic MCP 的公开 skill、确定性 CLI、测试与双端缓存。

**架构：** `SKILL.md` 负责意图路由和安全边界，`references/workflows.md` 承载按需读取的设计操作流程，单个无依赖 Node CLI 通过 Claude/Codex 原生命令执行状态检查、配置和诊断。所有宿主与网络行为由 fake CLI 或本地临时环境测试，生产代码不直写宿主配置。

**技术栈：** Node.js 18+ ESM、`node:test`、Claude/Codex MCP CLI、vft-kit skill 规范。

---

### 任务 1：建立失败测试和 skill 骨架

**文件：**
- 新建：`plugins/vft-kit/skills/design-content/mastergo-mcp/tests/test-mastergo-mcp.mjs`
- 新建：`plugins/vft-kit/skills/design-content/mastergo-mcp/SKILL.md`
- 新建：`plugins/vft-kit/skills/design-content/mastergo-mcp/agents/openai.yaml`
- 新建：`plugins/vft-kit/skills/design-content/mastergo-mcp/references/workflows.md`
- 新建：`plugins/vft-kit/skills/design-content/mastergo-mcp/scripts/mastergo-mcp.mjs`

1. 使用 `init_skill.py` 生成 `scripts,references` 骨架和 `openai.yaml`。
2. 用临时 HOME、fake `claude`/`codex` 编写测试，覆盖 status、target、幂等配置、冲突、`--force`、默认 30678、Magic 缺 Token、凭据脱敏和 doctor 端口失败。
3. 运行 `node --test .../test-mastergo-mcp.mjs`，确认因 CLI 尚未实现而失败。

### 任务 2：实现最小 CLI

**文件：**
- 修改：`plugins/vft-kit/skills/design-content/mastergo-mcp/scripts/mastergo-mcp.mjs`
- 测试：`plugins/vft-kit/skills/design-content/mastergo-mcp/tests/test-mastergo-mcp.mjs`

1. 实现严格参数解析，仅接受 `status`、`configure`、`doctor` 及设计内选项。
2. 实现宿主状态读取与规范化，输出任何命令结果前统一递归脱敏 Token、Header 和 env 值。
3. 实现 Vibe/Magic 等价判断、冲突停止和显式 `--force` 重注册；调用宿主原生 MCP 命令。
4. 实现 doctor 的 registry latest、Vibe URL 端口和可选通用 health 探针。
5. 循环运行单测直至全绿，并补齐发现的边界用例。

### 任务 3：完成 skill 指令与按需参考

**文件：**
- 修改：`plugins/vft-kit/skills/design-content/mastergo-mcp/SKILL.md`
- 修改：`plugins/vft-kit/skills/design-content/mastergo-mcp/references/workflows.md`
- 修改：`plugins/vft-kit/skills/design-content/mastergo-mcp/agents/openai.yaml`

1. 写清 Vibe=本机画布读写、Magic=远程链接 DSL/D2C 的路由，不固化版本号和私有域名。
2. 写清默认自主诊断/配置流程、仅 Vibe 破坏性设计写操作需明确授权，以及用户已明确授权时不重复确认。
3. 写清 Token 仅从环境变量进入宿主原生用户配置，CLI 参数和输出均不得出现明文。
4. 在 workflows 中编排读取、最小写入、diff/回读、HTML 同步与 Magic 渐进取数流程。

### 任务 4：校验与发布到本机缓存

**文件：**
- 校验：`plugins/vft-kit/skills/design-content/mastergo-mcp/**`

1. 运行 Node 单测、`quick_validate.py`、skill-validator 的 `validate.mjs` 和 `check-files.mjs`。
2. 用无 skill/有 skill 的相同提示做 forward-test，确认路由、端口和授权判断已纠正。
3. 刷新 Claude Code 与 Codex 的 vft-kit 插件缓存，校验缓存为真实目录且与源码一致。
4. 在新缓存路径重跑测试和校验，记录最终证据。
