---
name: mastergo-mcp
description: 配置、检查、诊断和使用 MasterGo 官方 Vibe MCP 与 Magic MCP，并可通过浏览器 window.mg 提取 Canvas 原型。用户提到 MasterGo MCP、设计稿链接转代码/DSL、读取或修改 MasterGo 画布、原型文案/便签/尺寸提取、导出切图或图标素材、needsCanvasVisit 拿不到图层、同步 HTML、变量/组件操作、未找到活跃连接、50678 端口、MG_MCP_TOKEN，或要给 Claude Code/Codex 安装 MasterGo 时使用。
---

# MasterGo MCP

用一套入口处理两种能力，但不要混淆或静默互相降级：

| 模式 | 用途 | 前提 |
|---|---|---|
| Vibe MCP | 连接本机 MasterGo，读取选区、生成/修改画布、变量与组件、HTML 双向同步 | MasterGo 客户端打开目标文件并启用 MCP；默认 `http://localhost:50678`，端口可变 |
| Magic MCP | 从 MasterGo 链接读取远程 DSL/D2C、SVG、文本和元数据 | `MG_MCP_TOKEN` 或 `MASTERGO_API_TOKEN`；团队版及团队项目文件 |

## 执行入口

先定位脚本：

```bash
SKILL_DIR="${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/design-content/mastergo-mcp"
node "$SKILL_DIR/scripts/mastergo-mcp.mjs" status
```

如果宿主根变量不可用，从当前 `SKILL.md` 所在目录解析 `SKILL_DIR`，不要猜缓存路径。

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
- Vibe 使用 `@mastergo/vibe-mcp@latest`；端口变化时传 `--url http://localhost:<实际端口>`。
- Magic 使用 `@mastergo/magic-mcp@latest`；公网默认 API 是 `https://mastergo.com`，私有部署必须由用户或现有配置给出 `--url`。
- Magic Token 只能从环境变量读取。不要让用户把 Token 发到聊天，不接受 `--token`，不输出明文，不写仓库。
- 上述安装授权允许宿主原生命令写用户级 MCP 配置；写入后脚本收紧已存在的宿主配置权限。
- 等价配置幂等退出；冲突默认停止并报告脱敏差异。只有用户明确要求覆盖或已接受该影响时使用 `--force`。
- 不提供删除命令。确需卸载时，先确认精确宿主和 server 名，再用宿主原生命令。

## 设计操作

实际读取、生成、修改或同步设计稿前，完整读取 [workflows.md](references/workflows.md)，按其中对应模式执行。

通用边界：

1. 先读取并锁定文件、页面、选区或节点 ID，再执行最小操作，最后回读或 diff 验证。
2. 删除节点、删除变量、全量 HTML 同步会覆盖或移除设计数据，必须有明确授权。用户在当前请求已明确要求该动作时，不要重复确认。
3. Vibe 同步接收静态 HTML；先把 Vue/React 页面运行或导出为静态 HTML，不把 `.vue`、`.tsx` 源码直接交给 MCP。
4. Magic 先取 meta/section，再按需获取 DSL、SVG、文本；避免一次拉完整大 payload。
5. Vibe 连接失败时停止写操作并修复连接，不得降级为 Magic 假装完成画布修改。
6. MCP 不适合当前目标，或按上节安装仍不可用但页面已在浏览器加载时，按工作流使用 `window.mg` 只读回退脚本；普通 DOM 抓取无法读取 Canvas 画板。
7. `getPageLayers` 返回 `totalLayers: 0 / needsCanvasVisit: true` 是图层缓存为空，不是没权限。不要空转重试，也不要把定位退回给用户——按工作流的「链接没有 layer_id 时」用浏览器枚举拿到 layerId 再调 `getDsl`。

## 完成标准

- 配置任务：宿主回读显示正确包、URL、启用状态和凭据存在性，输出无敏感值。
- Vibe 操作：目标画布回读或 `get_design_diff` 证明改动落地。
- Magic 操作：链接、file/layer 定位正确，返回所需范围和格式，并说明团队权限或草稿箱限制。
- 安装或配置变更后提醒用户新开/重启对应宿主会话，使 MCP 注册生效。

涉及当前包参数或工具变化时，以 [MasterGo MCP 帮助](https://mastergo.com/help/MG/MCP)、[配置指南](https://mastergo.com/help/MG/MCP/CONFIG) 和 [Magic MCP 官方仓库](https://github.com/mastergo-design/mastergo-magic-mcp) 为准，并用 `npm view` 核对 latest；不要把本文中的版本快照当作永久事实。
