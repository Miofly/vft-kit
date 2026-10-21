# 模式、检查与配置

用一套入口处理两种能力，但不要混淆或静默互相降级：

| 模式 | 用途 | 前提 |
|---|---|---|
| Vibe MCP | 连接本机 MasterGo，读取选区、生成/修改画布、变量与组件、HTML 双向同步 | MasterGo 客户端打开目标文件并启用 MCP；默认 `http://localhost:50678`，端口可变 |
| Magic MCP | 从 MasterGo 链接读取远程 DSL/D2C、SVG、文本和元数据 | `MG_MCP_TOKEN` 或 `MASTERGO_API_TOKEN`；团队版及团队项目文件 |

## 执行入口

### 第 0 步：status，缺就装（不可跳过）

任何 MasterGo 任务——包括只读画布、导切图、走浏览器回退——的**第一条命令**都是 `status`，不是打开浏览器：

```bash
SKILL_DIR="${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/design-content/mastergo-mcp"
node "$SKILL_DIR/scripts/mastergo-mcp.mjs" status
```

如果宿主根变量不可用，从当前 `SKILL.md` 所在目录解析 `SKILL_DIR`，不要猜缓存路径。

读当前宿主那两行（`claude` 或 `codex`）：

- 任一行是 `missing` → **默认直接装，不要问、不要绕过**。用户请求执行实际设计任务即视为安装授权（见下节「配置」）。Magic 和 Vibe 两套都要补齐，不能只装当前任务直接用到的那套。
- Magic 缺 Token 时仍先把 Vibe 装上，再请用户从安全来源提供 `MG_MCP_TOKEN`。
- 装完提醒用户：MCP 在**新开会话**才注册，当前会话仍然用不上，本轮按浏览器回退路径继续。

有浏览器回退脚本**不是**跳过这步的理由：回退只解决 MCP 覆盖不到的部分（拿 layerId、导位图切图），不替代 DSL / 文本 / 变量 / 组件那些只有 MCP 能给的读取能力。直接开浏览器等于把宿主长期留在没装的状态，下次还得重来。

### 检查和诊断

```bash
node "$SKILL_DIR/scripts/mastergo-mcp.mjs" status --target codex
node "$SKILL_DIR/scripts/mastergo-mcp.mjs" doctor --target both
node "$SKILL_DIR/scripts/mastergo-mcp.mjs" doctor --target codex --health
```

- `status` 是只读检查；默认同时检查 Claude Code 和 Codex。
- `doctor` 额外查 npm latest、Vibe 实际端口、Magic 权限前提；`--health` 才启动 MCP 做 initialize。
- “未找到活跃连接”属于 Vibe：以配置中的实际 URL 查端口，再检查 MasterGo 客户端、当前文件 MCP 开关和重新连接；不要改查 Magic 的远程 API。

### 配置

只修改用户点名的宿主；同时配置必须显式传 `both`：

```bash
node "$SKILL_DIR/scripts/mastergo-mcp.mjs" configure --mode vibe --target codex
MG_MCP_TOKEN='从安全来源注入' node "$SKILL_DIR/scripts/mastergo-mcp.mjs" configure --mode magic --target claude
```

- 用户请求使用 MasterGo MCP 执行实际设计任务，视为允许为当前宿主安装 Magic 和 Vibe 两套官方 MCP；仅问能力、状态或诊断时保持只读。
- 实际任务开始前先检查当前宿主；Magic 或 Vibe 任一缺失时，分别运行对应的 `configure --mode ... --target <当前宿主>` 补齐两套，不得只安装当前任务直接用到的一套。
- Magic 从环境变量或现有安全配置取得 Token 和实际 URL；缺少 Token 时仍先补齐 Vibe，再请用户从安全来源配置 Magic，不要让用户把 Token 发到聊天。
- Vibe 优先使用客户端实际端口；客户端未启动、无法探测时按官方默认 `http://localhost:50678` 安装，并明确报告连接仍待客户端启用。
- Vibe 使用钉死的 `@mastergo/vibe-mcp@1.0.31`（版本写在 `scripts/mastergo-mcp.mjs` 的 `MODES`，不用 `@latest`：未审查的新发布会直接执行；`doctor` 会报告与 registry 的版本漂移，审过再升）；端口变化时传 `--url http://localhost:<实际端口>`。
- Magic 使用钉死的 `@mastergo/magic-mcp@0.2.10`；公网默认 API 是 `https://mastergo.com`，私有部署必须由用户或现有配置给出 `--url`。
- Magic Token 只能从环境变量读取。不要让用户把 Token 发到聊天，不接受 `--token`，不输出明文，不写仓库。
- **Token 必须和域匹配。** 内网 token 打公网 `mastergo.com` 返回 `401 {"code":"10002"}`，反之亦然。一套 token 只能读它自己那个实例的稿。
- **需要出网代理的机器要把代理写进 MCP 配置。** MCP server 是 `npx` 拉起的独立进程，**不继承 shell 的 `https_proxy`**；缺了就报 `Client network socket disconnected before secure TLS connection was established` 或 `ECONNRESET`，看起来像 Token 或权限问题。在宿主配置的 `env` 里补 `HTTPS_PROXY` / `https_proxy` / `NO_PROXY=localhost,127.0.0.1`，**新开会话才生效**。
- 上述安装授权允许宿主原生命令写用户级 MCP 配置；写入后脚本收紧已存在的宿主配置权限。
- 等价配置幂等退出；冲突默认停止并报告脱敏差异。只有用户明确要求覆盖或已接受该影响时使用 `--force`。
- 不提供删除命令。确需卸载时，先确认精确宿主和 server 名，再用宿主原生命令。
