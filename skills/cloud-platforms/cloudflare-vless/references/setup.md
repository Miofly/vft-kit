# 从零建立一条可用线路

这是主教程。按 G0–G6 顺序做；先用一个域名、一个节点，成功后再读 operations。示例域名只演示格式，工具会拒绝 `example.com`，执行时必须换成自己的域名。

## 1. 准备账号、域名和客户端（G1）

### 1.1 打开这些地址

| 做什么 | 地址 | 新手要看什么 |
|---|---|---|
| 注册 / 登录 Cloudflare | https://dash.cloudflare.com/sign-up | 本人邮箱验证完成；2FA、验证码由本人处理 |
| Cloudflare 控制台 | https://dash.cloudflare.com/ | 左侧账号，右侧 Account ID；不要拿 Zone ID 代替 |
| 免费域名主页 / 注册后台 | https://domain.digitalplat.org/ / https://dash.domain.digitalplat.org/ | 没有域名先按 [免费域名完整教程](free-domain.md) 注册、设置 NS 并核对续期 |
| 托管自己的域名 | https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/ | 注册商把 NS 改为 Cloudflare 分配值，zone 最后显示 Active |
| 隧道上游 | https://github.com/amclubs/am-cf-tunnel | 仅使用 sources 中的固定 commit，不复制搜索引擎上的改版 |
| Clash Verge Rev 安装包 | https://github.com/clash-verge-rev/clash-verge-rev/releases | Windows/macOS/Linux；区分 Intel、Apple Silicon、ARM64 |
| mihomo 内核 | https://github.com/MetaCubeX/mihomo/releases | 需要 VLESS 支持；老版 Clash 不等于 mihomo |
| Node.js LTS | https://nodejs.org/en/download | 脚本要求 Node.js 22+；安装后 `node --version` |
| Wrangler 文档 | https://developers.cloudflare.com/workers/wrangler/install-and-update/ | CLI 路线才需要；控制台路线不需要 |

**域名不是脚本自动赠送的。** 没有域名且想免费试用，先读 [免费域名申请与 Cloudflare 接入](free-domain.md)，里面包含官方地址、注册表、候选名、先取 NS 再提交申请的顺序、Windows/macOS/Linux DNS 验证、失败处理和续期。该分支完成后回到本页第 1.2 节。

已有域名按下面步骤托管。注册、续费和 NS 修改前说明影响。不要宣传“永远免费域名”。Cloudflare 免费托管 DNS 与域名注册费是两件事。

1. Cloudflare 控制台选择 `Add a domain / 添加域`。
2. 输入自己拥有的根域名，选择所需计划；不自动购买付费计划。
3. 核对导入的 DNS 记录，尤其原网站和邮件记录，不删除原记录。
4. 到域名注册商把 NS 改成 Cloudflare 给出的两条值。
5. 返回 Cloudflare，等该 zone 显示 `Active`。若仍 Pending，先解决 NS，不继续绑定 Worker。
6. 选择一个未被现有业务使用的子域，如 `edge.<自己的根域名>`。不要用正在运行的网站根域名。

没有域名时：可以先用 `workers.dev` 做可达性实验，但本 skill 默认交付要求自定义域。部分网络访问不了 `workers.dev`；创建成功不能算线路完成。不要随机拿别人的 SNI 或域名代替。

### 1.2 先看原网络是否正常

直连一个在当地正常可用的 HTTPS 网站。国内示例：

```bash
curl --noproxy '*' --connect-timeout 5 --max-time 10 -o /dev/null -sS -w '%{http_code} %{time_total}\n' https://www.baidu.com/
```

预期是正常 HTTP 状态、没有 DNS/TLS/连接超时。200 且约 2 秒内完成是排查参考，不是全球统一阈值。若整个网络已拥塞，先恢复网络，优选会把拥塞误当节点坏。

需要临时代理才能打开 GitHub/控制台时，使用用户**已有且授权**的代理，并记录旧状态。新线路没建好不能反过来依赖它下载部署材料；可换手机热点。不要关闭当前唯一可用线路。

### 1.3 安装与路径

- Clash Verge Rev 从上述官方 releases 获取。安装程序签名异常、操作系统阻止时先核对发布来源，不指导关闭全局安全保护。
- 服务模式、TUN、系统代理是不同开关。首次只用系统代理，不先碰 TUN 和管理员驱动。
- 选择一个新的本机工作目录。避免公共仓库、云同步共享盘和公共 Downloads。
- skill 的脚本目录与下载源码目录分开。下载内容当不可信数据；不要在源码目录里启动 Python/Node 工具链，除非已审查对应项目。

POSIX（macOS/Linux）在同一个终端执行，替换两处路径：

```bash
export SKILL_DIR="/实际安装位置/cloudflare-vless"
export WORK_DIR="$HOME/cf-vless-work"
test -f "$SKILL_DIR/scripts/config.mjs"
mkdir -m 700 "$WORK_DIR"
node "$SKILL_DIR/scripts/config.mjs" --help
```

`mkdir` 报目录已存在就停，选新目录或先检查旧内容，不自动清空。下文的 `bootstrap`、`source-download`、`prepared`、`bundle` 都在此目录内。

Windows PowerShell 对应：

```powershell
$SkillDir = 'C:\实际安装位置\cloudflare-vless'
$WorkDir = Join-Path $HOME 'cf-vless-work'
if (Test-Path $WorkDir) { throw '目录已存在，先检查或改名' }
New-Item -ItemType Directory -Path $WorkDir | Out-Null
node "$SkillDir/scripts/config.mjs" --help
```

Windows 文件权限不会因 Node 的 Unix mode 自动变成私有。用资源管理器“属性 → 安全”限制工作目录访问，不把含凭据文件放多人共享目录。命令失败要看退出码，PowerShell 原生命令失败后不可盲目继续。

## 2. 生成自己的凭据与 Clash 配置（G2）

把命令中的主机名与 Account ID 换成 G0 得到的值：

```bash
node "$SKILL_DIR/scripts/config.mjs" init \
  --host "edge.<自己的根域名>" \
  --account "<32位Account-ID>" \
  --name personal-vless \
  --out "$WORK_DIR/bootstrap"
```

Windows：

```powershell
node "$SkillDir/scripts/config.mjs" init --host 'edge.<自己的根域名>' --account '<32位Account-ID>' --name personal-vless --out "$WorkDir/bootstrap"
```

脚本只生成本地文件，不联网、不创建云资源、不改现用代理。成功打印 `CREATED` 和目录，不打印 UUID。

| 文件 | 用途 | 是否含敏感信息 |
|---|---|---|
| `connection.json` | 主机、入口、UUID、账号 ID，后续重新生成依据 | 是，不上传公共仓库 |
| `worker-secrets.json` | 隧道 Worker 的 `ID`、`PADDR` | 是，只交给本人 Cloudflare |
| `wrangler.json` | Worker 配置；KV ID 待填 | 不含 UUID，但保留私有 |
| `clash.yaml` | 可直接导入的新本地 profile，内容是 JSON 形式的有效 YAML | 是，包含 UUID |

**字段含义**：`ID` 是隧道 UUID。上游隧道不是读取 `UUID` 变量。初次 `entry=host`，端口 443，WS path 为 `/?PROT_TYPE=vless`，`servername` 与 WS `Host` 都是自己的隧道域名。`PADDR` 默认空，避免悄悄使用上游随机公共中转。

本地先校验：

```bash
node "$SKILL_DIR/scripts/config.mjs" check \
  --config "$WORK_DIR/bootstrap/connection.json" \
  --profile "$WORK_DIR/bootstrap/clash.yaml"
```

预期 `{"status":"PASS","nodes":1}`。这只证明本地字段符合配方，还没证明服务端可用。

## 3. 获取并准备固定版本上游

本教程核对的版本：

```text
仓库：https://github.com/amclubs/am-cf-tunnel
commit：e70a3a7f6923811b0e168339662e60d00bee44f0
文件：_worker.js
SHA-256：e87c3165ff1c985b15b97f9e1fb88331c1be524ad3b8df71e643ced87dae3cbd
固定下载：https://raw.githubusercontent.com/amclubs/am-cf-tunnel/e70a3a7f6923811b0e168339662e60d00bee44f0/_worker.js
```

POSIX：

```bash
mkdir -m 700 "$WORK_DIR/source-download"
curl --fail --show-error --location --max-time 60 \
  'https://raw.githubusercontent.com/amclubs/am-cf-tunnel/e70a3a7f6923811b0e168339662e60d00bee44f0/_worker.js' \
  --output "$WORK_DIR/source-download/upstream.js"
```

Windows：

```powershell
New-Item -ItemType Directory -Path "$WorkDir/source-download" | Out-Null
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/amclubs/am-cf-tunnel/e70a3a7f6923811b0e168339662e60d00bee44f0/_worker.js' -OutFile "$WorkDir/source-download/upstream.js"
```

超时或 TLS 失败时先确认当前网络和已有代理，不能改成下载搜索结果中的“不知名加速脚本”。组织禁止直连下载时用其批准镜像，并仍校验相同 hash。

```bash
node "$SKILL_DIR/scripts/config.mjs" prepare-worker \
  --config "$WORK_DIR/bootstrap/connection.json" \
  --source "$WORK_DIR/source-download/upstream.js" \
  --out "$WORK_DIR/prepared"
```

Windows：

```powershell
node "$SkillDir/scripts/config.mjs" prepare-worker --config "$WorkDir/bootstrap/connection.json" --source "$WorkDir/source-download/upstream.js" --out "$WorkDir/prepared"
```

脚本检查原始 SHA-256，只对**已核对版本**做两个小改动：把公开默认 UUID 换成自己的 UUID；强制关闭可能打印 UUID 的上游调试开关。另生成 `worker.mjs` 入口，缺 secret/KV、或 KV 旧 ID 与 secret 不一致时返回 503。原始下载文件保留不改。

输出 `worker.mjs`、`upstream.mjs`、`source-lock.json`。不要只上传原始 `upstream.js`：它包含公开默认 ID。准备目录也含私有 UUID，按密钥文件保护。

## 4. 部署隧道 Worker（G3）

先确认用户授权向**所选账号**创建 Worker、KV、自定义域和 secrets。本任务只是编写教程时不执行这里。

### 4.1 推荐：Cloudflare 控制台，逐项点击

1. 进入 https://dash.cloudflare.com/ ，选择目标账号。
2. `Workers & Pages → Create application → Worker → Start with Hello World`。UI 名称可能变化，按功能定位，不猜旧坐标。
3. 名称填 `personal-vless`，核对没有同名生产 Worker。先部署无代理功能的 Hello World。
4. 打开该 Worker → `Settings → Variables and Secrets`。
5. 新增 **Secret** `ID`：值从本地 `worker-secrets.json` 的 `ID` 复制，不发到聊天。
6. 新增 **Secret** `PADDR`：首次为空字符串。控制台若不接受空 secret，先留空不添加，并在第 11 步使用下述空值兜底。
7. 新增 Text 变量 `PROT_TYPE=vless`。不要设置字符串 `ENABLE_LOG=false`：在这版 JS 中非空字符串仍是真值。
8. 账号左侧 `Storage & databases → KV → Create namespace`，新建 `personal-vless-kv`。不要复用别的应用 KV。
9. 回到 Worker → `Bindings → Add binding → KV namespace`，变量名严格填 `amclubs`，选新建的 namespace。
10. Worker → `Edit code`。上传/新建两个 ES Module 文件：`worker.mjs` 与 `upstream.mjs`，内容来自 `prepared`。入口指定 `worker.mjs`。不是把两个文件拼在一起，也不是上传成静态 assets。
11. 核对上传的是生成后的 `worker.mjs`。它已用 `PADDR: env.PADDR ?? ''` 保证缺值也不回退到公共 ProxyIP，不需要手改；后续要中转时再设置本人确认的 `PADDR`。
12. 点击 Deploy。回读最新生产版本，确认两个文件、`ID/PADDR` 名称、KV 绑定都在该生产版本；不要只看编辑器草稿。
13. `Settings → Domains & Routes → Add → Custom Domain`，填自己的隧道子域 `edge.<根域名>`。已有同名 DNS/业务时先停，不替换。
14. 等自定义域与 HTTPS 证书状态为 Active。自定义域由 Cloudflare 管理记录和证书，不额外手工 CNAME 到 IP。
15. 已启用自定义域后关闭不需要的 `workers.dev` 与 preview URL，减少额外入口。先核实自定义域可用，再关闭备用入口。

**通过标志**：自己的域名 HTTPS 无证书错误，出现上游登录页；缺配置时返回 503 是正确拒绝，不是部署成功。登录页只能证明 HTTP 层，后面还要用真正 VLESS 客户端验证。

### 4.2 可选：Wrangler CLI

已经能用控制台的新人可以跳过本节。CLI 首先 `wrangler --version`、`wrangler deploy --help`，按官方文档装好且固定该版本；不使用不明“一键安装代理”脚本。

```bash
wrangler login
wrangler whoami
wrangler kv namespace create personal-vless-kv
```

OAuth 登录由本人完成；token 路线最少需要目标账号 Workers Scripts Edit、Workers KV Storage Edit，以及目标 zone 的 Workers Routes/DNS 所需权限。不要为省事用 Global API Key。确认 whoami 是目标账号。

1. 把 `bootstrap/wrangler.json` **复制**到 `prepared/wrangler.json`。
2. 用编辑器把 `kv_namespaces[0].id` 的占位符换成刚创建的 namespace ID。绑定名保留 `amclubs`。
3. Wrangler 的 `main: worker.mjs` 是相对该配置文件的资源路径，这是 Wrangler 格式，不是让模型跨 skill 目录找文件。

```bash
wrangler deploy --config "$WORK_DIR/prepared/wrangler.json" --dry-run --outdir "$WORK_DIR/bundle"
```

先看打包是否成功。`--dry-run` 不上传，但也不能证明云端权限、KV 和域名已正确。

```bash
wrangler deploy --config "$WORK_DIR/prepared/wrangler.json"
wrangler secret bulk "$WORK_DIR/bootstrap/worker-secrets.json" --config "$WORK_DIR/prepared/wrangler.json"
wrangler deployments list --config "$WORK_DIR/prepared/wrangler.json"
wrangler secret list --config "$WORK_DIR/prepared/wrangler.json"
```

初次 deploy 到 secret 写入前入口会返回 503，不使用公开默认 UUID。回读绑定/域名和生产版本。若中途失败，先查资源是否已创建再重试；不能重复创建同名 namespace。CLI 输出若包含 secret 或订阅 URL，保存在私有日志，不贴公开 issue。

## 5. 导入 Clash Verge Rev（G4）

### 5.1 先离线验证内核语法

找到实际的 mihomo 可执行文件。Verge 内置核心可能名为 `verge-mihomo`；在客户端“设置 → 内核”核对，不要求所有系统有同一路径。

```bash
"$MIHOMO_BIN" -t -f "$WORK_DIR/bootstrap/clash.yaml"
```

`MIHOMO_BIN` 要先设为本机绝对路径。Windows：`& $MihomoBin -t -f "$WorkDir/bootstrap/clash.yaml"`。若找不到内核，使用客户端配置校验入口，标明没有独立 CLI 检查。不得把缺核心当成配置成功。

### 5.2 作为新配置导入，不覆盖旧订阅

1. 打开 Clash Verge Rev → Profiles/订阅。
2. 记录当前选中的 profile、系统代理/TUN 状态与实际混合端口，导出或备份旧配置。
3. 创建 Local/本地配置，导入 `bootstrap/clash.yaml`；给它起名 `CF 新建测试`。
4. 不填写网络订阅 URL；这是本地配置，首次不需要订阅转换器。
5. 查看配置校验无错后选中它。
6. 在 Proxies/代理中把 `PROXY` 选为 `CF-VLESS`，不是 `DIRECT`。
7. 看 Settings/设置的实际 Mixed Port。生成文件使用 7890，但 Verge 的全局配置可能覆盖端口，记录实际值。
8. 首次保持 TUN 关闭。先做显式 HTTP 代理验收，再开启系统代理。

配置含 `MATCH,PROXY`，测试阶段除私网地址外都进代理；国内流量也可能出国。这是便于验收的最小规则，不宣称成熟国内分流。日常规则见 operations。

## 6. 验证真正业务（G5）

### 6.1 显式代理，不能被 DIRECT 假通过

POSIX 的 `<实际端口>` 要换成客户端显示的值：

```bash
export LOCAL_PROXY="http://127.0.0.1:<实际端口>"
curl --noproxy '' --proxy "$LOCAL_PROXY" --connect-timeout 8 --max-time 25 -sS -o /dev/null -w '%{http_code} %{time_total}\n' https://www.google.com/generate_204
curl --noproxy '' --proxy "$LOCAL_PROXY" --connect-timeout 8 --max-time 25 -sS https://www.cloudflare.com/cdn-cgi/trace
curl --noproxy '' --proxy "$LOCAL_PROXY" --connect-timeout 8 --max-time 25 -sS https://ipinfo.io/json
```

Windows 用 `curl.exe`，不是旧 PowerShell 的 `curl` alias：

```powershell
$LocalProxy = 'http://127.0.0.1:<实际端口>'
curl.exe --noproxy '' --proxy $LocalProxy --connect-timeout 8 --max-time 25 -sS https://www.cloudflare.com/cdn-cgi/trace
```

- 第一个预期 204。第二个预期有 `ip=`、`loc=`、`colo=`。第三个应有公网 IP 与国家字段；被限流就记失败并用另一独立查询服务复核，不编国家。
- 查询返回自己的直连出口不一定立刻能断言失效，但要检查客户端是否选错 DIRECT、规则是否直连该查询站点。
- 同一固定节点连续做 3 轮，每轮记录时间与结果。三次都通才能记“本轮稳定通过”；不要保证长期稳定。
- 运行附带的 `scripts/probe.mjs` 可做这三轮与用户站点检查。它不切节点、不改系统代理，只经指定本地 HTTP proxy 请求。

```bash
node "$SKILL_DIR/scripts/probe.mjs" --proxy "$LOCAL_PROXY" --out "$WORK_DIR/probe.json"
# 追加真正使用的网站；URL 不带登录 token，不把敏感业务 URL 发给第三方诊断服务。
node "$SKILL_DIR/scripts/probe.mjs" --proxy "$LOCAL_PROXY" --out "$WORK_DIR/probe-with-sites.json" --url https://github.com/
```

首次不配置 PADDR 时，普通目标能通但 CF 托管站不通是可能的。按 troubleshooting 的 ProxyIP 一节配置**自己信任且验证过**的中转，再完整复测；不能只删掉失败站点就宣布通过。

### 6.2 浏览器确实走代理

1. 开启 Verge 的 System Proxy/系统代理；等待系统回读显示启用，不把点击成功当开关生效。
2. macOS：`scutil --proxy`；Windows：系统“代理”设置；Linux：当前桌面代理设置。记录真实状态。
3. 用新标签打开同样的用户目标站点，确认有真实正文、必要交互可用，不是证书页/验证码页/空壳。
4. 浏览器有自己代理扩展时，先核对它是否覆盖系统代理，不能擅自卸载或修改。
5. 没有浏览器工具就列 `NOT_RUN` 并给用户这几步，不能把 curl 结果写成浏览器通过。

### 6.3 负向鉴权与恢复

1. 复制本地配置到新的测试文件，只把该副本 UUID 换成另一个随机 UUID；不要改服务器和主配置。
2. 用**独立临时 mihomo**、不同混合端口（如 17890）验证同样目标，应失败；此时主配置应仍成功。
3. 负向副本不能调用本工具 `check` 宣称通过；它本来就用于故意制造鉴权失败。
4. 临时进程只按实际 PID 停止，不 `pkill` 所有 mihomo，不动当前生产客户端。
5. 切回之前保存的旧 profile，确认恢复正常；再切回新 profile 复测，用户要求维持旧线路则停在旧线路。

没有独立内核/进程隔离条件时负向测试记 `NOT_RUN`，不可通过修改现用 UUID 让用户整机断网。

## 7. 完成与下一步（G6）

保存 `connection.json`、配置、源码锁、服务端版本和验收结果到用户私有目录。备份要能恢复，不自动上传。单节点通过后，再读 operations：增加订阅、优化入口、细化分流；不要同时改三层使故障无法定位。
