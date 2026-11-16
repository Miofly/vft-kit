# 地址索引、版本证据与适用边界

资料核对日期：2026-11-16。下面的“源码核对”不是接收者账号上的部署实测。平台配额、界面和服务条款会变化，执行时再看官方页面。

## 官方入口

| 类别 | 地址 | 目的 |
|---|---|---|
| DigitalPlat 主页 | https://domain.digitalplat.org/ | 免费域名项目、当前展示后缀；开放情况以后台为准 |
| DigitalPlat 注册后台 | https://dash.domain.digitalplat.org/ | 本人账号、域名申请、NS 与续期 |
| DigitalPlat 官方教程 | https://github.com/DigitalPlatDev/FreeDomain/blob/main/documents/tutorial/index.md | 账号注册、申请、NS 委托、状态与续期；本地详解见 [free-domain.md](free-domain.md) |
| Cloudflare 注册 | https://dash.cloudflare.com/sign-up | 本人注册账号 |
| 控制台 | https://dash.cloudflare.com/ | 账号、域名、Workers、KV、日志 |
| 域名完整托管 | https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/ | NS 与 Active zone |
| Worker 自定义域 | https://developers.cloudflare.com/workers/configuration/routing/custom-domains/ | 域名路由、证书与已有记录冲突 |
| Wrangler 安装 | https://developers.cloudflare.com/workers/wrangler/install-and-update/ | CLI 版本和安装 |
| Wrangler 命令 | https://developers.cloudflare.com/workers/wrangler/commands/ | deploy、secret、kv、deployments |
| Secrets | https://developers.cloudflare.com/workers/configuration/secrets/ | 不把 UUID 写普通公开配置 |
| KV bindings | https://developers.cloudflare.com/kv/concepts/kv-bindings/ | namespace 与变量名区别 |
| TCP sockets | https://developers.cloudflare.com/workers/runtime-apis/tcp-sockets/ | 出站限制，不能直接连 Cloudflare IP ranges |
| WebSocket | https://developers.cloudflare.com/workers/runtime-apis/websockets/ | Upgrade 与连接处理 |
| Placement | https://developers.cloudflare.com/workers/configuration/placement/ | 位置提示，不等于固定国家出口 |
| Workers 价格 | https://developers.cloudflare.com/workers/platform/pricing/ | 费用、WebSocket 初始握手计费 |
| Workers 限额 | https://developers.cloudflare.com/workers/platform/limits/ | 请求、CPU、连接数等 |
| KV 限额 | https://developers.cloudflare.com/kv/platform/limits/ | 入口每次读取 KV，也会消耗 KV 额度 |
| 服务条款 | https://www.cloudflare.com/terms/ | 执行者自行确认用途与规则 |
| 服务状态 | https://www.cloudflarestatus.com/ | 排除平台故障 |

核对当日官方文档：Workers Free 为每日 100,000 请求、每次 10ms CPU。WebSocket 初始 Upgrade 计一次请求，消息不按每条请求计；不能据此推出无限带宽、无限连接或永不中断。该包装入口读取 KV，因此还受 KV 独立配额约束。

## 使用的成熟项目

| 项目 | 地址 | 用途 |
|---|---|---|
| 隧道 | https://github.com/amclubs/am-cf-tunnel | VLESS/WS 到 Workers TCP sockets |
| 隧道固定源码 | https://github.com/amclubs/am-cf-tunnel/blob/e70a3a7f6923811b0e168339662e60d00bee44f0/_worker.js | 可复查版本 |
| 隧道固定 raw | https://raw.githubusercontent.com/amclubs/am-cf-tunnel/e70a3a7f6923811b0e168339662e60d00bee44f0/_worker.js | 配套工具只接受此文件 hash |
| 可选订阅 | https://github.com/amclubs/am-cf-tunnel-sub | 节点与订阅生成，存在转换服务信任边界 |
| 订阅固定版本 | https://github.com/amclubs/am-cf-tunnel-sub/tree/96703e0b869500a4d3beee3926d13b539b7599a3 | 当前为多模块入口，构建生成 `_worker.src.js` |
| CloudflareSpeedTest | https://github.com/XIU2/CloudflareSpeedTest | 筛入口候选，不代替 VLESS 验证 |
| cfst Releases | https://github.com/XIU2/CloudflareSpeedTest/releases | 按系统与架构获取 |
| Clash Verge Rev | https://github.com/clash-verge-rev/clash-verge-rev | GUI 客户端 |
| Verge Releases | https://github.com/clash-verge-rev/clash-verge-rev/releases | 安装包，不用来源不明镜像 |
| Verge 文档 | https://www.clashverge.dev/ | 客户端当前设置方式 |
| mihomo | https://github.com/MetaCubeX/mihomo | 解析/运行 Clash 配置的内核 |
| mihomo VLESS | https://wiki.metacubex.one/config/proxies/vless/ | 客户端 VLESS 字段 |
| mihomo WS | https://wiki.metacubex.one/config/proxies/transport/ | ws-opts 与 Host/path |
| Node.js | https://nodejs.org/en/download | 本地脚本运行时 |

仓库公开不代表本 skill 对其全部代码做了安全审计。这里不复制和再分发上游协议实现，执行时下载固定版本，保留上游原有许可与声明。

## 固定源码核对结果

隧道原始 `_worker.js` SHA-256：

```text
e87c3165ff1c985b15b97f9e1fb88331c1be524ad3b8df71e643ced87dae3cbd
```

- `fetch` 从 `env.ID` 读取隧道凭据，但 KV `kv_id` 优先于它；包装入口检查 `KV_CONFIG.kv_id`，避免旧值悄悄覆盖新 secret。
- 上游原文件有公开默认 UUID；工具替换初始化值，且包装入口无 ID 时 503。
- `PADDR` 的 URL 参数优先于环境变量，所以客户端 path 不写 `PADDR=`。默认空值由包装入口明确传入，不走随机公共地址。
- `ENABLE_LOG` 的字符串 `"false"` 仍可能为真值。工具只在固定 hash 上关闭该赋值，不声称关闭所有第三方代码的所有日志。
- KV 绑定名为 `amclubs`；订阅项目读取 `ips` 或 `KV`，不是同一绑定。
- 上游 WebSocket 接入不靠 HTTP 主页证明鉴权；真正有效性以 mihomo 发起的 VLESS 请求为准。

订阅固定版本的 `_worker.js` SHA-256：

```text
a28bfa8c02c10abfea5538bdb9238a26e605a326d0e7b7aa63c71c7734a89a45
```

这个 hash **只标识 504 字节入口**，不代表整个仓库校验。完整版本以 commit 为准；完整模块需要打包，不能只上传该入口。`core/handler.js` 明确区分 `ID`（订阅 token）、`UUID`（隧道凭据）、`HOST`（隧道主机），Clash 转换会调用 `SUB_CONVERTER`。

## 配套脚本索引

| 脚本 | 功能 | 安全边界 |
|---|---|---|
| `scripts/config.mjs init` | 本地生成 UUID、连接数据、Clash 与 Wrangler 配置 | 无网络，拒绝已存在输出目录，文件 mode 0600 |
| `scripts/config.mjs prepare-worker` | 校验固定上游、替换默认 ID、生成安全入口 | 不部署，hash/补丁位置不符就失败 |
| `scripts/config.mjs render` | 修改入口后生成新的一套配置 | 不改现用 profile；输入不接受 URL 充当主机 |
| `scripts/config.mjs check` | 校验本工具生成的 JSON YAML | 不解析任意 YAML、不证明网络可用 |
| `scripts/probe.mjs` | 指定 loopback HTTP proxy，3 轮目标检查 | 不切节点、不改系统代理；不代表浏览器验收 |
| `scripts/config.test.mjs` | Node 内置离线测试 | 含错误输入、覆盖保护、配置坏值、probe 格式 |

所有命令参数与完整示例在 setup/operations，先 `--help`。本 skill 不携带作者账号、域名、profile UID、密钥目录或本机运行路径。
