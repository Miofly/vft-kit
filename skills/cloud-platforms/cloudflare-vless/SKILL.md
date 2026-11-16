---
name: cloudflare-vless
description: "Cloudflare 自建代理：从零部署 am-cf Workers 的 VLESS over WebSocket + TLS，接入 Clash Verge Rev/mihomo，配置可选订阅、优选入口、排查断流与恢复旧配置。用户提到 Cloudflare 自建 VPN、搭梯子、Workers 节点、ProxyIP 或 Clash 接入时使用；Cloudflare Tunnel 内网穿透和 WARP 不走此方案。"
compatibility: "配置工具需要 Node.js 22+；部署需要本人 Cloudflare 账号和授权域名；客户端需要支持 VLESS 的 mihomo。可通过浏览器控制台或 Wrangler 操作。"
---

# Cloudflare VLESS 自建代理

给执行模型的逐步操作手册。目标是让别人用自己的账号、域名和电脑建立代理，不依赖作者机器上的任何配置。

## 先明确交付

默认交付 **一个隧道 Worker + 一份本地 Clash 配置 + 逐层验收记录**。用户需要多设备自动更新时，再增加订阅 Worker。服务器代码复用固定版本的 amclubs/am-cf-tunnel，不自己重写代理协议。

这不是 WireGuard/OpenVPN，也不是 Cloudflare Tunnel：

```text
应用 → 本机 mihomo → TLS/WebSocket → 自己的 Worker → 目标网站
                                             → 可选 ProxyIP → 目标网站
```

- Cloudflare Tunnel（cloudflared）把内网服务发布出去，不是本流程的公网代理出口。
- WARP 是 Cloudflare 提供的客户端网络，不等于自己的 VLESS Worker。
- 本路线只交付 TCP 代理。UDP、QUIC、游戏加速和固定住宅 IP 不在保证范围。
- 先核对当地规则、网络管理要求与 Cloudflare 当前服务条款；免费额度不等于允许任意用途，也不保证 SLA。

## 执行顺序：停在第一个没过的关卡

每关写 `PASS / FAIL / BLOCKED / NOT_RUN` 和证据。只有上一关 PASS 才进入下一关。用户只要教程或 skill 时，生成文档和配置示例，不登录账号、不部署、不切换现有代理。

| 关卡 | 操作 | 通过条件 | 失败去向 |
|---|---|---|---|
| G0 输入 | 填下面的输入表，确认写操作授权 | 确认账号、主机域名、客户端、产物绝对路径 | 只问缺失的必需项 |
| G1 基础网络 | 国内直连、Cloudflare 控制台、域名状态 | 直连正常，账号可用，zone 为 Active | setup §1 |
| G2 本地产物 | `init`、下载固定源码、`prepare-worker`、`check` | 文件生成、校验通过、无公开默认凭据 | setup §2–3 |
| G3 服务端 | 创建 KV、设置 secret、部署、绑定域名 | 生产版本可回读，自定义域 HTTPS 证书有效 | setup §4 |
| G4 客户端 | mihomo 校验，作为**新配置**导入 | VLESS/WS/TLS/UUID/Host/SNI 一致 | setup §5 |
| G5 业务 | 显式代理、实际浏览器、出口、负向鉴权 | 按 setup §6 逐项过关 | troubleshooting |
| G6 维护 | 备份、恢复、可选订阅和优选 | 重载后仍可用，旧配置保留，临时进程已停 | operations |

## G0 输入表

先从用户提供的信息和本机**只读**检查填表，不虚构账号、域名、权限或工具。不要读取或复用另一人的凭据。

| 字段 | 示例 / 默认 | 缺失如何处理 |
|---|---|---|
| `OS` | macOS / Windows / Linux | 读取系统信息 |
| `WORK_DIR` | 用户指定的绝对路径，独立于仓库与 skill | 请用户指定或选择其本机私有工作目录 |
| `SKILL_DIR` | 当前加载的本 skill 绝对路径 | 从 skill 元数据读取，不猜插件缓存位置 |
| `ACCOUNT_ID` | 32 位十六进制 | 在本人 Cloudflare 控制台读取；不是 Zone ID |
| `TUNNEL_HOST` | `edge.example.com` | 用户拥有、已托管 Cloudflare 的子域名；示例不可部署 |
| `WORKER_NAME` | `personal-vless` | 新建名称；同名已存在先备份，不覆盖 |
| `ENTRY` | 首次等于 `TUNNEL_HOST` | 域名先通，再优选 IP |
| `PADDR` | 首次为空字符串 | 空表示不使用第三方回退；部分 CF 目标可能不通 |
| `CLIENT` | Clash Verge Rev + mihomo | 记录版本和实际混合端口，不能假定都是 7890 |
| `TEST_URLS` | 用户实际需要的 2–3 个 HTTPS 网站 | 至少一个普通站和一个 CF 托管站 |
| 授权范围 | 只写文档 / 创建测试资源 / 部署并导入 | 对外部署、付费、替换 DNS/配置须有明确授权 |

`UUID` 本地随机生成。Cloudflare API token、UUID、订阅 token、订阅 URL、本地配置均按凭据处理：不发进聊天、截图、公共转换器或公开仓库；文件权限限制为当前用户。API token 和 VLESS UUID 是两种不同的凭据。

## 工具与边界

1. 先读 [references/setup.md](references/setup.md)，按 G1–G5 建立单节点。没有域名且希望免费申请时，先完整执行 [references/free-domain.md](references/free-domain.md)：本人注册 DigitalPlat、查询候选、取得 Cloudflare NS、提交注册、核验 Active 与续期；不能跳过域名注册状态检查。
2. 遇故障读 [references/troubleshooting.md](references/troubleshooting.md)，按层定位，不循环换配方。
3. 已建通后读 [references/operations.md](references/operations.md)：订阅 Worker、入口优选、分流、出口国家、备份与回退。
4. 核对固定上游、变量证据和平台限制读 [references/sources.md](references/sources.md)。更新上游先复核源码和测试，不能把 `main` 当固定版本。
5. 附带工具 `scripts/config.mjs` 只生成/校验本地文件，不联网、不部署、不改系统代理。先运行 `node "$SKILL_DIR/scripts/config.mjs" --help`。
6. 浏览器自动化用宿主已有浏览器工具；有 ego-browser 时优先 ego，否则使用可用浏览器。桌面客户端用后台 GUI 自动化；没有 GUI 工具就给用户精确点击步骤，标记人工待验，不伪称已点击。
7. 命令中的 `SKILL_DIR`、`WORK_DIR` 都是 G0 取得的绝对路径。先断言变量非空，再执行；Windows 使用 PowerShell 对应写法，不能直接复制 POSIX `export`。

## 让低能力模型也能执行的约束

- 每次只处理一关。报告“做了什么、读回什么、是否通过”，不是只报告命令退出码。
- 部署的是**隧道 Worker**还是**订阅 Worker**，先说清楚。两者的 `ID` 含义不同，见 operations 变量表。
- 本地 `server` 是入口，`servername` 和 WS `Host` 是自己的隧道域名。优选只改 `server`，不把另外两个改成 IP。
- 不根据节点名、旗帜、入口 `colo` 推断出口国家。用经代理的公网 IP 查询与 CF 目标 trace 分别验证。
- 不盲改 Trojan 为 VLESS；本路线本来就生成 VLESS。外部订阅协议不符先拒收，核实服务端后重新生成。
- HTTP 200、WebSocket 101、控制台部署成功、mihomo 语法通过，各自只证明一层；都不能单独证明代理能用。
- 不开启 `skip-cert-verify`，不让 controller 监听公网，不开启 LAN 分享，不向网上提交订阅转换。
- 初次导入前保留旧 profile。优选无可用节点、网络拥塞、订阅内容异常时保留上次可用配置。
- 连续两次相同故障无新证据：停止重试，输出具体层、原始错误、一个区分假设的检查。

## 完成报告

```text
目标：单节点 / 含订阅 / 含入口优选
G0–G6：逐项状态和证据路径
产物：绝对路径（不展示 secret 内容和订阅 URL）
服务端：生产版本、域名证书状态、变量名（不含值）
客户端：内核版本、配置校验、实际端口、系统代理/TUN 状态
业务：逐个 URL 结果、三轮成功数、普通/CF 目标出口核验
恢复：旧 profile/备份位置、恢复操作是否实测
未验证：浏览器、UDP、指定国家、下载速度等明确列出
资源：新增 Worker/KV 是否保留；临时 mihomo 是否停止
```

交付 skill 本身时，附离线测试/结构检查结果，明确“未用接收者账号完成在线部署”，不把作者既有环境的历史结果当新用户实测。
