# 建通后的订阅、优选与维护

本页只在 setup 的 G5 通过后使用。每次只改一层，先备份，再验证，再决定保留。工具及官方链接集中在 sources。

## 1. 先认清四种地址

| 地址 | 用途 | 是否应保密 |
|---|---|---|
| `edge.<自己的域名>` | 隧道 Worker 主机，客户端 SNI 与 WS Host | 主机名通常公开，UUID 保密 |
| 一个 Cloudflare 入口 IP | 客户端 `server`，帮助改善网络路径 | 不是 UUID，不决定出口国家 |
| `PADDR` / ProxyIP | Worker 出站失败时的中转目标，尤其部分 CF 托管目标 | 供应者和凭据按信任边界管理 |
| `https://sub.<自己的域名>/<订阅token>?clash` | 下载节点配置的订阅 URL | 是；持有者可能取得节点凭据 |

“优选 IP”与“ProxyIP”不能互换。把入口 IP 填 PADDR 不会自动成为可用出口；把 ProxyIP 填成 SNI 会造成 TLS/域路由错误。

## 2. 订阅：先选是否真的需要

### 2.1 最简单：继续本地配置

单台电脑不需要订阅 Worker。`clash.yaml` 作为独立本地配置可以长期使用；改入口后生成新的配置再导入。不要为了“像机场”引入额外转换服务。

另一台受信设备可用安全的本地文件传输导入同一份配置；这不是自动订阅。不要把含 UUID 的文件上传公开 Gist、网盘公开链接或二维码解析网站。

### 2.2 需要自动订阅时：am-cf-tunnel-sub

入口：https://github.com/amclubs/am-cf-tunnel-sub

核对版本：`96703e0b869500a4d3beee3926d13b539b7599a3`。

**当前版本已拆模块。** `_worker.js` 仅是约 504 字节的导入入口，引用 `core/handler.js`。只复制这一份到控制台会报找不到模块。两条可行路径：

- Wrangler：保留整个仓库模块树，入口 `_worker.js`，由 Wrangler 打包。
- 控制台：在审查源码后运行上游自带 `scripts/build-worker.mjs`，它生成单文件 `_worker.src.js`，上传这个生成文件；不要把 `_worker.js` 当单文件包。

POSIX 获取完整固定仓库：

```bash
# WORK_DIR 是 setup 中自己的绝对工作目录。目标目录必须不存在。
git clone https://github.com/amclubs/am-cf-tunnel-sub.git "$WORK_DIR/sub-source"
git -C "$WORK_DIR/sub-source" checkout --detach 96703e0b869500a4d3beee3926d13b539b7599a3
git -C "$WORK_DIR/sub-source" rev-parse HEAD
```

`checkout --detach` 只用于这个新下载的上游源码目录，不用于用户的工作仓库。不自动推送，不把该目录当个人凭据存储。

运行前阅读 `package.json`、`scripts/build-worker.mjs` 与 `core/handler.js`，检查网络上传、凭据记录和默认值。本固定版本的构建脚本只用 Node 标准库，不需要 `npm install`：

```bash
node "$WORK_DIR/sub-source/scripts/build-worker.mjs"
# 输出：$WORK_DIR/sub-source/_worker.src.js
```

Windows 同样可以 `git clone`、固定 checkout 后执行：

```powershell
node "$WorkDir/sub-source/scripts/build-worker.mjs"
```

### 2.3 变量表：两个 Worker 别配反

| 变量 | 隧道 Worker `personal-vless` | 订阅 Worker `personal-vless-sub` |
|---|---|---|
| `ID` | VLESS UUID，客户端认证用 | **另生成的订阅 token**，作为 URL 路径，不等于 UUID |
| `UUID` | 不使用此变量 | 与隧道 `ID` 完全相同 |
| `HOST` | 不需要 | 隧道域名，如 `edge.<自己的域名>`，不是订阅域名 |
| `PADDR` | 可信 ProxyIP；首次为空 | 不使用此变量 |
| `PROXYIP` | 不使用此变量 | 可选，须与自己的隧道中转策略一致 |
| `PROT_TYPE` | `vless` | `vless` |
| `SUB_CONVERTER` | 不需要 | 自己控制或已明确同意使用的转换后端 |
| KV binding | `amclubs`，独立 namespace | 该版本读取 `ips` 或 `KV`，用独立 namespace |

本地生成订阅 token 的命令：

```bash
# 写入私有文件，不把标准输出中的 token 复制进公开报告。
node --input-type=module -e 'import fs from "node:fs"; import {randomBytes} from "node:crypto"; fs.writeFileSync(process.argv[1], randomBytes(32).toString("hex")+"\n", {flag:"wx",mode:0o600});' "$WORK_DIR/sub-token.txt"
```

PowerShell 用双引号变量路径、保留 JS 外层单引号即可。若新版本改变 token 验证规则，以该固定版本源码为准，不套用其他项目的 UUID-only 约束。

### 2.4 控制台逐步部署

1. 新建 `personal-vless-sub`，先保留 Hello World。
2. 生产环境添加 secrets `ID`（新订阅 token）、`UUID`（隧道 ID）、`HOST`（隧道域名）；添加 `PROT_TYPE=vless`。
3. 新建 `personal-vless-sub-kv`，绑定名 `ips`。不要与隧道共用 KV。
4. 配置自己信任的 `SUB_CONVERTER`。本版内置公共默认转换服务；未明确同意使用第三方、或未找到自己控制的兼容转换后端时，**停在本地配置路线**，不要调用 `?clash`。
5. 代码编辑器上传生成的 `_worker.src.js`，设为入口。检查没有未解析的本地模块 import，再 Deploy。
6. 绑定一个新的自定义域 `sub.<自己的根域名>`，等待 HTTPS 生效。
7. 用本地文件中的 token 访问订阅页。只在私有环境处理完整 URL，不截图 URL 栏。
8. 先下载到一个新临时文件，确认内容是 Clash 配置，而不是 HTML、`No nodes were found!` 或错误 JSON。
9. 核对每个 VLESS 节点 `uuid`、SNI、WS Host、port、WS path，之后用 mihomo `-t` 校验。
10. 新建一个 Remote profile 再导入，不直接覆盖现用的本地 profile。下载后首次更新也完整验收。

**转换服务的隐私边界**：即使上游会生成临时假 ID、伪装 UUID 再还原，也不能承诺转换方“完全不知道配置”。它可能回拉订阅、看到域名、节点结构和访问记录。优先本地配置，确需转换时自行审查/控制服务。

### 2.5 订阅更新的接收门槛

本工具 `config.mjs check` 只读自己生成的 JSON YAML，不能直接校验任意外部 YAML。外部订阅使用 mihomo 语法检查，加下列字段核对；需要程序解析时用已安装的可信 YAML 库，不手写正则假解析 YAML。

全部满足才替换：

- HTTP 正常，实际字节数非零，`proxies` 是非空数组。
- 节点类型与实际 Worker 协议相符；本配方是 VLESS + WS + TLS。
- UUID 与自己连接文件相同；SNI、WS Host 都是自己的隧道主机，不含 `undefined`、`.xyz` 误拼后缀。
- 未开启 `skip-cert-verify`；不携带未知 `PADDR=`、SOCKS5 URL、随机 TLS 指纹或额外公网 controller。
- 至少一个隧道节点真实代理通过 G5；只有备份机场节点可用不算自建节点成功。
- 自动组不是只剩 DIRECT/REJECT；`MATCH` 最后落到预期代理组。

拒收时保留上次可用配置、暂停会绕开校验的自动更新，不反复用坏订阅覆盖。

## 3. 优选入口 IP：先少量，再完整代理验证

成熟工具：https://github.com/XIU2/CloudflareSpeedTest

1. 用官方 Releases 获取匹配本机架构的版本，记录版本与 hash。阅读该版本 `-h`，不同版本参数可能不同。
2. 在独立下载目录解压，不覆盖已有程序。`cfst` 不能读取 Worker UUID，不向它传订阅 URL。
3. 原网络健康时运行。先使用低并发，避免公司 Wi-Fi/NAT 被高并发压垮。

确认当前版本支持下列参数后，POSIX 示例：

```bash
# CFST_BIN、IP_FILE 为该工具和官方 IP 列表的绝对路径。
"$CFST_BIN" -h
"$CFST_BIN" -n 50 -t 4 -tl 300 -dd -p 0 -f "$IP_FILE" -o "$WORK_DIR/cfst-result.csv"
```

`-dd` 这一路线只筛 TCP 候选，不下载测速；具体含义以本机 `-h` 为准。结果里的低延迟不能证明 Worker、WebSocket 或目标站可用。

4. 先取少量（如前 5 个）候选，逐个复制 `connection.json` 到新的私有候选文件，只修改 `entry` 为候选 IP。`host`、UUID 不变。
5. 重新生成到**新目录**：

```bash
node "$SKILL_DIR/scripts/config.mjs" render --config "$WORK_DIR/candidate.json" --out "$WORK_DIR/candidate-01"
node "$SKILL_DIR/scripts/config.mjs" check --config "$WORK_DIR/candidate.json" --profile "$WORK_DIR/candidate-01/clash.yaml"
```

6. 内核语法通过后，用独立临时 mihomo（单独工作目录、混合端口如 17890）测；启动前核对端口未占用，不能停现用内核。
7. 每个候选测同一组目标，完整走 TLS、WS、VLESS；三轮成功率优先，再比较延迟中位数。
8. 如果要比较下载速度，使用相同真实目标文件、相同字节数、至少 3 轮，记录服务端是否支持 Range；延迟排名不是带宽排名。
9. 只有候选确实通过才导入新 profile，保留旧 profile。全部失败就不写配置，回到域名入口或原可用线路。
10. 停掉临时进程并核对端口释放。移动城市/运营商后重新优选，不能把另一网络的榜单当永远最佳。

不附全网大并发扫描器。CloudflareSpeedTest 已完成候选筛选；本 skill 的 probe 完成真正代理目标检查，避免重复造工具。

## 4. ProxyIP：解决一部分目标的出站限制

官方限制：Workers `connect()` 不能直接连 Cloudflare IP 范围，不能把 Worker 当无条件任意 TCP 出口。`PADDR` 是上游尝试中转的回退地址，不是官方稳定服务。

- 首选本人控制、来源明确且兼容此隧道协议的中转。普通 HTTPS 网站 IP 不会因为填进 PADDR 就变成中转。
- 社区地址只是候选，例如 `ProxyIP.US.CMLiussss.net`；供应者可能改变、记录或停止服务，不能保证隐私/国家/可用率。目录源见 https://github.com/cmliu/CF-Workers-docker.io ，先核对其当前说明，不把别人的公益服务写成默认依赖。
- 本生成器首版只接受主机/IP、固定 443，不支持 URL、账号密码和自定义端口。需要带端口/认证时先核对上游格式并扩展测试，不绕过校验。
- 在 Cloudflare 将隧道 Worker 的 `PADDR` secret 改为确认的地址；本地 `connection.json.paddr` 同步记录，重新生成 secret 文件到新目录。
- 客户端 WS path 不写 `PADDR=`，否则 URL 参数可能覆盖服务端配置。
- 使用同一固定入口，对普通目标和 CF 目标分别测试 3 轮，记录失败率与两个出口查询。目标不同可能走不同出口。

## 5. 指定国家：Placement 是提示，不是固定出口承诺

官方说明：https://developers.cloudflare.com/workers/configuration/placement/

可用配置形态（只选一个，不同时填 `mode` 和 `region`）：

```json
{"placement":{"region":"aws:ap-northeast-1"}}
```

`aws:ap-northeast-1` 是东京邻近计算位置提示，`aws:eu-west-2` 是伦敦，`aws:ap-southeast-1` 是新加坡。账户功能与支持地域以当日官方文档为准。

需要时复制已通过验收的隧道到**新的 Worker、新的自定义域、新的 KV**，设置所需 placement 与经核验的 PADDR；先不修改主线路。优选入口可能在别处，普通 TCP 目标和 CF 目标还可能走不同出站路径。

分别核验经代理的公网 IP 国家、CF 目标 trace、用户实际业务的地区判定。三者不一致就写“指定国家未通过”。不要把 `placement.region` 的设置成功写成固定国家/解锁成功。

## 6. 分流与系统代理

- 初始 `MATCH,PROXY` 便于验收，日常添加国内/内网 DIRECT 规则时，放在 MATCH 前；保留原有规则顺序与用户选择。
- 只加用户实际需要的精确域名或后缀，不把故障网站一股脑 DIRECT。若原网络本来打不开目标，DIRECT 只会掩盖隧道问题。
- 更换订阅会覆盖 profile 本体。采用客户端的 per-profile Merge/Script 增强机制保存自定义规则；先查当前 Verge 版本的格式，不把作者的 profile UID、组名或路径写死。
- 应用通常按系统代理工作；终端需要显式 `--proxy` 或环境变量。`NO_PROXY` 和大小写环境变量都可能导致目标绕过代理。
- TUN 是另一条影响全机路由的路线，首次不需要；若用户授权使用，先备份 DNS/路由/驱动状态，再按当前客户端官方文档配置并实测回退。

## 7. 备份、轮换、升级、卸载

### 备份

备份本地 profile、连接文件、源码锁、Worker 当前版本、bindings 名称与 KV 归属；secret 不能指望控制台导出明文，要保留本地私有原件。记录系统代理/TUN、当前选中 profile 和混合端口。

### 轮换 UUID

在维护窗口执行：本地生成新 UUID → 备份旧凭据 → 准备新源码和 secret → 核对/清理**本 Worker 的** KV 中旧 `kv_id` → 更新隧道 `ID` → 更新订阅 `UUID` → 更新所有设备 → 正向新凭据成功、负向旧凭据失败。此过程可能短暂断网，先有备用线路。

生成源码里的初始 UUID 与 secret 都维护同步；入口以 secret 为权威且缺失时 503。KV 更新有传播延迟，出现 `KV identity mismatch` 先等并回读，不取消鉴权闸门。

### 升级

不直接跟 main。下载新 commit 到新目录 → 审查 `ID/PADDR/KV/日志/协议` 变更 → 更新源码 hash 与补丁断言及测试 → dry-run → 新测试 Worker 实测 → 用户授权后替换生产。订阅项目拆模块、变量优先级改变都属于升级验收项。

### 回退 / 卸载

回退先切回已知可用 profile、恢复原系统代理/TUN状态并实测网络。卸载云资源须明确确认，只删除本任务新建且已核对归属的 Worker、域名绑定和独立 KV，不删根域 DNS、不撤销共用 token、不影响其他业务。删除后回读资源不存在并确认其他应用仍正常。
