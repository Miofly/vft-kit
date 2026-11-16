# 故障对照：按层检查，不靠换节点猜

## 一次拿到的最小证据

记录：操作系统、Verge/mihomo 版本、实际混合端口、当前 profile 与选中节点、配置校验结果、Worker 生产版本、HTTPS 证书状态、三轮 probe 结果、系统代理/TUN 是否启用。日志原句保存到私有目录，公开报告去掉 UUID、token、订阅 URL、账号标识与完整公网 IP。

检查顺序：原网络 → DNS/证书 → Worker 配置 → 协议 → 本机端口/路由 → 目标站。某层失败只动该层。相同错误连续两次无新证据就停止换配置，写下一个能区分原因的检查。

## 症状表

| 症状 | 先验证 | 操作 | 不能据此宣布成功 |
|---|---|---|---|
| 所有入口都超时 | 直连国内站是否也慢；当前网络是否换了 | 先恢复网络，再低并发优选；保留旧 profile | TCP ping 不等于代理可用 |
| `Connection refused` 到 127.0.0.1 | 实际混合端口与监听进程 | 改为客户端显示端口；确认内核已启动 | 客户端窗口打开不等于核心在监听 |
| TLS 证书错误 | 证书是否 Active；SNI 是否等于自有隧道主机 | 等证书/修 SNI，检查系统时间 | 不开启 `skip-cert-verify` |
| 域名 HTTPS 正常，VLESS 不通 | 入口是否返回 WS；UUID/Host/path/协议 | 对照生成配置；查 Worker 生产日志 | 主页 200 和 WS 101 都不验证 UUID |
| `Service not configured` 503 | 隧道 secret 名是否为 `ID` | 设置本人 UUID，回读生产 secret 名 | 不是改成 `UUID`，也不是删鉴权 |
| `KV not configured` 503 | 绑定名是否 `amclubs`，是否属于生产版本 | 绑定独立 KV 并部署 | KV namespace 已创建不等于绑定成功 |
| `KV identity mismatch` 503 | KV `KV_CONFIG.kv_id` 是否是旧 UUID | 备份后只修改本 Worker 对应键；等传播后复测 | 不删除共用 KV，不绕过入口检查 |
| `KV unavailable` 503 | KV 用量、读取错误、是否绑定错资源 | 看服务端错误/平台限制；先恢复 KV | 不把 503 换成 200 糊弄监控 |
| `Error 1101` | Worker exception 原文、入口及模块 | 修 import、绑定或异常；先在测试 Worker 验证 | 控制台“部署成功”不等于运行成功 |
| `Error 1102` / `exceededResources` | CPU/内存/用量指标 | 降低无意义探测，定位代码；付费先确认 | 免费不是无限并发/流量保证 |
| 522/握手或连接超时 | 自定义域、入口、ProxyIP 分别可达性 | 单变量换入口或中转并三轮复测 | 不能仅凭状态码断言目标封 IP |
| 普通目标通，CF 目标不通 | Worker TCP socket 限制；PADDR 是否为空/失效 | 使用可信兼容中转，分别测两类目标 | 不能删除失败目标后报全通 |
| curl 明确代理通，浏览器不通 | 系统代理、浏览器扩展、TUN 实际状态 | 开正确系统代理并回读，再同 URL 看正文 | 点击开关成功不等于系统已变更 |
| curl 竟然还是直连 | `NO_PROXY`、所选 DIRECT、规则命中 | 用 `--noproxy '' --proxy ...`，固定 VLESS 节点 | IP 查询可达不等于走了隧道 |
| `?clash` 返回 200 但不能导入 | 原始文件字节与内容类型 | 找 HTML、错误 JSON、`No nodes were found!` | 不用“非空/包含 proxies”作为唯一判据 |
| SNI 是 `undefined.xyz` 或多余后缀 | 上游转换响应、本地源配置 | 拒收、保留旧配置，定位转换端 | 不盲目重拉覆盖 |
| 订阅给 Trojan，服务器是 VLESS | 订阅 PROT_TYPE/缓存/实际服务端 | 重新生成正确 VLESS；旧缓存失效再导入 | 不对任何机场订阅一律 Trojan→VLESS |
| 上游 `_worker.js` 只有几行 | 订阅项目是否已模块化 | 完整模块 Wrangler 打包或用上游生成 `_worker.src.js` | 不复制入口文件当单文件包 |
| 延迟 1–5 秒或时好时坏 | 测速 URL 是否 HTTPS；是否随机指纹 | 固定本配方 chrome；三轮同批看波动 | 不把另一订阅组延迟当自建节点结果 |
| 连续三次延迟完全一样 | 每次 history 时间戳是否更新 | 等异步 healthcheck 完成再记下一轮 | 三次读取缓存不是三轮实测 |
| 旗帜是 JP，但网站说美国 | 实际公网 IP、CF trace、业务判区 | 区分入口、执行地、ProxyIP；标国家未通过 | 组名、colo、placement 不能单独证明出口 |
| 国内站打不开/风控 | 实际出站是否国外；是否适合 DIRECT | 用户授权后为该目标加精确直连规则 | 不能据此判断整条代理坏 |
| 所有节点重测后更坏 | 是否在网络拥塞时覆盖了旧数据 | 恢复备份，恢复网络后重测 | 不继续覆盖唯一可用配置 |

## 逐层命令

以下变量先按 setup 设置为自己的绝对路径与端口。

### 本地配置与语法

```bash
node "$SKILL_DIR/scripts/config.mjs" check --config "$WORK_DIR/bootstrap/connection.json" --profile "$WORK_DIR/bootstrap/clash.yaml"
"$MIHOMO_BIN" -t -f "$WORK_DIR/bootstrap/clash.yaml"
```

第一条验证本配方的字段；第二条验证真实内核。两条不是在线验收。

### 域名 TLS：入口域名与优选 IP 要分开

```bash
# 只检查域名直连 HTTPS。失败时可能是当前网络问题，不能单独断言 Worker 坏。
curl --noproxy '*' --connect-timeout 8 --max-time 20 -I "https://$TUNNEL_HOST/"
# 将 HTTPS 入口固定到候选 IP，但保持 SNI 和 Host 是自己的隧道主机。
curl --noproxy '*' --resolve "$TUNNEL_HOST:443:$CANDIDATE_IP" --connect-timeout 8 --max-time 20 -I "https://$TUNNEL_HOST/"
```

不加 `-k`。`--resolve` 成功只证明候选入口的 HTTPS；还要用配置中的 VLESS 真正出站。

### 完整代理业务

```bash
node "$SKILL_DIR/scripts/probe.mjs" --proxy "$LOCAL_PROXY" --out "$WORK_DIR/diagnose-new.json" --url https://github.com/
```

文件必须新建，防止旧记录被覆盖。probe 报告仅检查 HTTP 状态及 trace/IP 结构；普通网页 200 仍可能是登录墙/验证页，必须浏览器补验真实正文。301/302 记录的是重定向，不等于最终页可用。

### Cloudflare 服务端

控制台 Worker → Observability/Logs 与 Metrics，按时间窗核对异常状态和用量。没有实时日志不等于没有报错；部分网络的 `wrangler tail` 链路不可达，改用控制台日志/指标，不反复等待。禁止为了排错开启含 UUID 的上游 `ENABLE_LOG`。

如果控制台出现验证码或登录失效，交给本人完成，不能借用其他账号的 Cookie/API token。

## 恢复顺序

1. 停止自动刷新坏订阅，保留错误响应的去密版本。
2. 选择原先备份的可用 profile。
3. 恢复系统代理/TUN 的原状态并回读。
4. 显式代理与浏览器同 URL 复验。
5. 仅按 PID 停止本次临时核心；不全局杀进程。
6. 用户确认后才回滚/删除本次新云资源。日志保留私有，公共产物不带凭据。
