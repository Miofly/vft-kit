# 新手申请免费域名并接入 Cloudflare

适用：还没有域名，希望先用 DigitalPlat FreeDomain 申请一个可委托给 Cloudflare 的域名，再继续搭建自己的 Worker。

核对日期：2026-11-16；已阅读官方公开教程，未代替接收者注册账号、申请域名或通过审核。按钮名可能变化，按页面当前功能定位。

## 目录

1. 地址与概念
2. 注册本人账号
3. 选择域名，先取得 Cloudflare NS
4. 提交免费域名申请
5. 检查 NS 委托与 Cloudflare Active
6. 回填 Worker 所需字段
7. 续期、保密与失败处理

## 1. 地址与概念

| 用途 | 官方地址 |
|---|---|
| 项目主页、当前开放后缀 | https://domain.digitalplat.org/ |
| 账号注册、域名申请、管理与续期 | https://dash.domain.digitalplat.org/ |
| 官方教程导航 | https://github.com/DigitalPlatDev/FreeDomain/blob/main/documents/tutorial/index.md |
| 账号注册说明 | https://github.com/DigitalPlatDev/FreeDomain/blob/main/documents/tutorial/platform/1.1-account-registration.md |
| 域名注册说明 | https://github.com/DigitalPlatDev/FreeDomain/blob/main/documents/tutorial/platform/1.2-domain-registration.md |
| NS 接入说明 | https://github.com/DigitalPlatDev/FreeDomain/blob/main/documents/tutorial/platform/1.3-connect-nameservers.md |
| 状态与续期说明 | https://github.com/DigitalPlatDev/FreeDomain/blob/main/documents/tutorial/platform/1.4-status-and-renewal.md |
| Cloudflare 注册 | https://dash.cloudflare.com/sign-up |
| Cloudflare 管理 | https://dash.cloudflare.com/ |

核对时主页列出 `.qzz.io`、`.dpdns.org`、`.us.kg`、`.xx.kg`、`.qd.je`。实际能注册哪种、是否还有名额、是否暂停，以后台公告和申请表为准，不把主页标签当注册成功。

**先分清三个名字：**

```text
选中的完整免费域名：your-name.qzz.io
Cloudflare 添加的 zone：your-name.qzz.io
以后绑定 Worker 的主机：edge.your-name.qzz.io
```

上面仅为教学示例，不代表这些名称空闲，也不是让模型实际注册。`qzz.io` 是平台的上级域；不能把整个 `qzz.io` 添加进自己的 Cloudflare，也不要在这一步把 `edge.your-name.qzz.io` 当注册主域。

**DigitalPlat 管注册和 NS 委托；Cloudflare 管 DNS 记录与 Worker 域名。** NS 是权威服务器的主机名，不是 `1.1.1.1` / `8.8.8.8`，也不是网站 IP。

## 2. 注册本人账号

1. 打开 DigitalPlat 主页，点击 `Register a domain`，应进入 `dash.domain.digitalplat.org`。核对域名，避免搜索广告和仿冒站。
2. 在登录页找 `Register / Sign up / 创建账号`。若当前只开放申请或暂停注册，记录原文并停止，不编造隐藏入口。
3. 准备自己长期可用的邮箱与唯一强密码；使用本人信息完成当前注册表。不要用别人邮箱、临时接码或虚构身份绕过要求。
4. 官方教程说明注册表可能分别收集域名联系资料（WHOIS）和账单资料。页面要求姓名、联系地址等时，让本人填写；先读隐私政策，不能保证所有字段一定不公开。
5. 仔细阅读用户协议、可接受使用政策和当日注册公告。若不允许预期用途，停止这条路线，不让模型替用户勾选虚假同意。
6. 若要求邮箱验证，打开本人邮箱完成验证；要求 CAPTCHA、2FA、GitHub OAuth 或身份审核时交给本人处理。**不预先承诺“一定不需要 GitHub/实名”，也不把当前未看到的要求写成强制条件。**
7. 登录进入 Dashboard，核对邮箱、可用注册名额与当前公告。安全保存恢复码，不发进聊天或公开截图。
8. 尚未提交域名申请，此关只确认账号可用。不要把账号注册成功写成域名已经归用户所有。

**通过条件：**本人能登录 Dashboard，账号信息正确，了解当前名额与审核/费用规则；缺验证则记 `BLOCKED`。

## 3. 选择域名，先取得 Cloudflare 的两条 NS

部分申请表在首次提交时就要求 NS，所以顺序是：**查询候选名 → Cloudflare 添加完整候选域名取 NS → 回 DigitalPlat 提交注册**，不是等注册完才发现缺必填值。

1. Dashboard 找 `Register Domain / Domain Registration / 注册域名`。先阅读公告，核对名额、后缀、是否需要审核、是否免费。
2. 选择当前开放后缀，输入想要的前缀，点击检查可用性。只使用页面允许的字符和长度；名字已占用就换前缀，不提交重复申请。
3. 记下完整候选名，例如 `your-name.qzz.io`。页面若分为 `Name` 和 `Suffix` 两栏，只在 Name 填 `your-name`，不要把后缀重复填两次。
4. 暂不确认最终注册。另开 Cloudflare 标签页，登录本人账号。
5. Cloudflare 选择 `Add a domain / Onboard a domain / 添加域名`，输入**完整候选名**，不带 `https://`、路径或 `edge.` 前缀。
6. 选择 Free 计划。扫描出来为空可用于新域名；已有网站/邮件则先核对原记录，不删除。添加 zone 可能暂时 Pending，获取 NS 阶段属预期。
7. 进入该 zone 的激活流程/Overview，复制 Cloudflare **分配给这个 zone** 的全部权威 NS，通常是两条 `*.ns.cloudflare.com`。
8. 两条值分别保存到本机私有记录。不要抄教程示例，不借用另一个域名分配到的 NS，不把 Account ID 当 NS。

如果 Cloudflare 拒绝该后缀/完整名称、无法添加 zone，保留错误原文，先核对拼写、平台委托和 Cloudflare 的 zone 支持。不能强加整个共享后缀，也不能保证所有免费后缀始终能托管；换当前受支持的候选，或请用户决定是否用付费域名。

**通过条件：**候选名目前可申请，Cloudflare 已为同一个完整名称创建 zone，分配的 NS 可在该 zone 回读。此时仍不代表域名已经注册。

## 4. 提交免费域名申请

1. 回到 DigitalPlat 申请页，重新检查候选仍可用；避免停留太久后名称已被占用。
2. 再核对完整名称、后缀与名额。名字要更换时，Cloudflare zone 与 NS 也重新对应，不能串用旧候选。
3. 在 `Nameserver 1 / Nameserver 2` 或对应列表填入 Cloudflare 分配的两条主机名；每项只填主机名，不带 `https://`、端口、IP 或空格。
4. 若是一个多行文本框，按页面要求每行一条；若是两个输入框分别填。不要盲目用逗号拼接。
5. 核对所示费用、有效期、续期规则和条款。写着收费、消耗付费名额或需要付款时，**先停下来让用户决定**，不能因为叫 FreeDomain 就默认接受收费。
6. 确认用户授权注册这个准确名称后，只提交一次。遇超时先查 `Domain List` 和申请状态，确认未成功再重试，避免重复申请。
7. 到 `Domain List / My Domains / 域名列表` 找到相同完整名称，查看状态、到期时间、NS 值与申请编号（如有）。审核中/失败都按原状态报告。
8. 保存不含密码/恢复码的私有记录：完整域名、归属账号提示、当前状态、到期日期、两条 NS。截图避免联系人地址与账号资料。

已注册成功但 NS 未填对时，在域名管理的 nameserver 编辑入口更正，不必重新注册域名。若平台当前不提供编辑入口，按官方支持流程处理，不删除后抢注同名。

**通过条件：**域名列表确有本人申请的完整域名，状态显示注册有效，NS 与 Cloudflare 分配值一致。仅弹出“提交成功”不算。

## 5. 检查 NS 委托与 Cloudflare Active

### 5.1 看平台状态

1. DigitalPlat 域名详情的 NS 已保存为正确值。
2. Cloudflare 返回该 zone 的 Overview，使用 `Check nameservers / 检查名称服务器`（若页面提供）。
3. 等 Cloudflare 显示 **Active**；不要在 Pending 状态继续绑定 Worker。
4. NS 缓存更新可能需要时间，不能保证固定 5 分钟生效；按页面提示等待。超过平台提示的等待时间仍不变，再按下表排查，不重复点注册。

### 5.2 命令核对（可选，但推荐）

先把变量替换成自己的真实完整域名和 Cloudflare 分配的 NS。这里只读 DNS，不修改系统设置。

macOS/Linux（装有 `dig`）：

```bash
export DOMAIN="<自己的完整免费域名>"
export CF_NS1="<Cloudflare分配的第一条NS>"
dig NS "$DOMAIN" +short
dig +trace NS "$DOMAIN"
dig @"$CF_NS1" SOA "$DOMAIN" +short
```

Windows PowerShell：

```powershell
$Domain = '<自己的完整免费域名>'
$CfNs1 = '<Cloudflare分配的第一条NS>'
Resolve-DnsName -Name $Domain -Type NS
Resolve-DnsName -Name $Domain -Type SOA -Server $CfNs1
# 若该环境没有 Resolve-DnsName：
nslookup -type=ns $Domain
```

判断：NS 查询应包含分配的相同服务器；SOA 查询检查该服务器是否在服务对应 zone。递归查询可能缓存旧结果，`dig +trace` 可进一步检查父级委托。一个 DNS 查询成功不替代 Cloudflare 的 Active 状态。

**暂时没有 A/AAAA 记录并不等于域名没注册成功。**此时还没发布网站，浏览器访问根域可能打不开；不要为让根域“看着能开”随便填一个陌生 IP。

### 5.3 常见错误

| 看到什么 | 先核对 | 怎么处理 |
|---|---|---|
| 名字不可注册/无名额 | 当日公告、后缀、账号额度 | 换可用名称或等待开放，不绕审核、不保证免费额度 |
| 注册时要求 NS | 是否已为同一完整域名建 Cloudflare zone | 按第 3 节先取两条 NS，再提交 |
| 填了 `1.1.1.1` / `8.8.8.8` | 把递归 DNS 当权威 NS | 改成 Cloudflare 分配的 `*.ns.cloudflare.com` |
| Cloudflare 一直 Pending | 完整域名、父级委托、两条 NS 是否同一 zone | 修 DigitalPlat NS，核对缓存与平台提示 |
| 域名显示 Active，网站仍打不开 | 是否创建网站记录或 Worker 绑定 | 注册已过关，接着走 setup，不乱改 NS |
| Cloudflare 不接受免费域名 | 拼写、后缀支持、是否误加共享上级域 | 保存原始错误，换受支持候选；不保证全部后缀可用 |
| 要求验证码/身份/邮箱验证 | 页面真实要求 | 本人完成后续做，不让模型绕过 |
| 域名注册状态失效/被暂停 | DigitalPlat 域名列表与通知 | 按官方续期/申诉流程；改 A/CNAME 修不了注册层失效 |

## 6. 回填 Worker 所需字段

```text
Cloudflare zone / DOMAIN：本人注册的完整免费域名
TUNNEL_HOST：edge.<DOMAIN>
可选 SUB_HOST：sub.<DOMAIN>
ACCOUNT_ID：Cloudflare 账号的 32 位 ID，不是 Zone ID
```

回到 [setup.md](setup.md) 第 1.2 节，继续基础网络检查、本地生成与部署。绑定 `edge.<DOMAIN>` 用 Worker 的 `Custom Domain` 流程，不需要回 DigitalPlat 添加普通 A/CNAME。DigitalPlat 只负责把整个注册域名委托给 Cloudflare。

## 7. 续期、保密与退路

- 注册当场记录**实际到期日期和续期窗口**，设本人能收到的提醒。建议到期前 90/60/30/7 天检查，仍以当前可续期窗口为准。
- 后台 `Domain List` 找到对应名称 → 查看详情 → 当前允许时选择续期 → 确认费用/条款 → 提交一次 → **重新读取到期日期确实延长**。不能把按钮返回成功当续期完成。
- 当前免费注册不保证永久持有、永久免费续期或未来永不审核；不要写死旧教程里的名额、费用和有效期。
- 到期或暂停可能同时打断隧道和订阅。保留原可用线路作为恢复路径，不把免费域名当唯一关键基础设施。
- 本页不提供自动注册/绕验证码脚本；账号身份、条款、付费与域名占用属于本人确认的边界。后续仍可用配套配置生成和业务探测脚本。
- 放弃域名前移除相关账号恢复地址、OAuth 回调和可信白名单，防止域名被别人重新取得后带来风险。删除/释放域名另行确认，不能为“重试”随便释放。
