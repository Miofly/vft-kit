# 创建飞书机器人并接入大模型

## 选型

| 需求 | 用哪种 |
|---|---|
| 只往一个群推通知 | 群自定义机器人（群设置 → 群机器人 → 自定义机器人），拿 Webhook 地址即可；不能收消息，lark-cli 用不了 |
| 私聊/群聊对话、接大模型、调 OpenAPI | 企业自建应用 + 机器人能力（下文） |

## 一键创建智能体应用（推荐）

开放平台首页 `https://open.feishu.cn/app` 顶部有「创建飞书智能体应用 → 立即创建」，
入口 URL 是 `https://open.feishu.cn/page/launcher?from=backend_oneclick`。
只填头像和名称，平台按模板一次性完成：

1. 创建应用并开启机器人能力；
2. 预置权限：收发单聊/群聊消息、卡片 `cardkit:card:read|write`、机器人菜单、Slash Command、通讯录基本信息、云文档评论等；
3. 事件订阅方式设为**长连接**，预置 `im.message.receive_v1`、`im.chat.member.bot.added_v1/deleted_v1`、`im.message.reaction.*`、`drive.notice.comment_add_v1`；
4. 自动建版本并提交发布（个人版或自己是管理员时直接生效）。

页面背后的写请求（只记方法和路径，需开放平台登录态和 CSRF，不适合脱离浏览器调用）：

```
POST /developers/v1/app/upload/image             # 头像
POST /developers/v1/manifest/upsert_by_template  # 按模板建应用
POST /developers/v1/secret/<app_id>              # 生成 App Secret
POST /developers/v1/app_version/create/<app_id>  # 建版本
POST /developers/v1/publish/commit/<app_id>/<version_id>  # 提交发布
```

完成页显示 App ID 和打码的 App Secret；点眼睛图标后读 `.secret-code__code` 文本，
直接写入凭据存储，不打印、不截图。

## 手动创建（无一键入口时）

1. 开发者后台 → 创建企业自建应用 → 添加应用能力「机器人」；
2. 权限管理开 `im:message`、`im:message:send_as_bot`、`im:message.p2p_msg:readonly`、`im:message.group_at_msg:readonly`；
3. 事件与回调 → 订阅方式选「使用长连接接收事件」，添加 `im.message.receive_v1`；
4. 版本管理与发布 → 创建版本 → 申请发布。

## 集成到已有群聊

- 先确认目标租户、群名和成员数；同名群不能仅凭名称选取。复用现有登录态和用户已授权的操作范围。
- 区分「所有群成员都能 @问答、写代码和方案」与「远程执行本机命令」。前者使用脚本的 `BOT_BACKEND=api`；后者保留执行者白名单，不能为了支持群聊而删除现有单聊授权检查。
- 群问答只需 `im:message:send_as_bot` 和 `im:message.group_at_msg:readonly`，并订阅 `im.message.receive_v1`；图片处理再开 `im:resource`。不为接收 @消息申请敏感的「获取群组中所有消息」。
- 发布后，在电脑端目标群的 `设置 > 群机器人 > 添加机器人` 中加入应用机器人。找不到时检查应用发布状态、用户可用范围和群管理员限制。
- 应用创建、配置保存、提交审核、审核通过、已入群、模型调用成功、群内实际回复是不同状态，分别验证。审核未通过时报告待审核，不声称已接通。

## HTTP 回调（后台没有长连接选项时）

兼容部署的文档可能引用公有云新版能力；以当前后台选项及真实接口结果为准。没有长连接入口、或对应服务端接口不可用时，使用 HTTP 回调，不重复重试 WebSocket。

现有 `scripts/feishu_claude_bot.py` 同时支持两种接收方式；默认仍为长连接。HTTP 模式额外配置：

```bash
# 以下值由凭据文件或进程环境注入，不能把真实凭据写进命令历史。
export BOT_HTTP_PORT=18762
export BOT_VERIFICATION_TOKEN="<平台 Verification Token>"
export BOT_ENCRYPT_KEY="<平台 Encrypt Key；未启用则留空>"
export BOT_SHADOW=1
```

- 服务只监听 `127.0.0.1`，提供 `GET /health`、`POST /events`；通过已有反向代理或固定域名的隧道提供 HTTPS。临时隧道地址不适合无人值守运行。
- SDK 负责 URL challenge、Token 校验和平台已启用的解密验签；HTTP 模式缺少 Verification Token 时直接退出。模型调用和下载在线程池处理，回调及时返回。
- 先以 `BOT_SHADOW=1` 启动，由实际调度器运行。验证正确 Token 的 challenge、错误 Token 拒绝，以及消息事件确实进入影子日志后，再切到 `BOT_SHADOW=0`。影子模式不调用模型、不回复群消息。
- 平台「事件与回调」填写 `https://<固定域名>/events`；保存并通过 URL 校验后，添加接收消息事件，再发布应用。
- 兼容部署必须设置 `FEISHU_DOMAIN` 为其开放平台域名，不沿用公网飞书网关。浏览器或 CLI 的用户连接器可用，不代表它的应用机器人能力已启用。
- 验证结束发送一条明确标记的集成测试 @消息，并从群内回读机器人的实际回复；HTTP 200、进程存在或模型单独调用通过都不能替代此步骤。
- 平台校验 URL 超时时，以平台发起的请求做对照：只测试用户拥有或授权的接收端，使用一次性占位 Token，避免把真实应用 Token 发给诊断目标。平台收到非 JSON 响应说明网络已通，仍不等于业务校验成功；平台访问自身正常而其他目标均超时时，保留请求编号，请平台运维确认执行节点的路由、DNS 和出站策略，不继续盲目叠加中转。

## 验收

```bash
# 换 tenant_access_token，再查机器人状态；activate_status=2 表示已激活
POST https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal  {app_id, app_secret}
GET  https://open.feishu.cn/open-apis/bot/v3/info   Authorization: Bearer <tenant_access_token>
```

- 长连接模式下，后台「事件配置」页需要先有 SDK 客户端连上，才能点按钮验证连接状态。
- 改权限或事件后要重新发版才生效；页面顶部显示「当前修改均已发布」才算完成。
- 用应用身份读写文档时，先把应用加为文档协作者，否则 403。

## 接大模型

长连接只需一个常驻进程，不需要公网地址：官方 SDK 建立 WebSocket 收
`im.message.receive_v1`，调用大模型，再用 `im/v1/messages/:message_id/reply` 回复。
大模型的 API Key 和飞书 App Secret 一样只从环境变量或凭据文件读取。

现成脚本 [scripts/feishu_claude_bot.py](../scripts/feishu_claude_bot.py)：长连接收消息，按会话保留多轮上下文，调 Claude 后用卡片 markdown 回复。

```bash
pip install lark-oapi anthropic
export FEISHU_APP_ID=... FEISHU_APP_SECRET=... ANTHROPIC_API_KEY=...
export ANTHROPIC_BASE_URL=https://<中转网关>   # 可选，one-api/new-api 类网关填到 /v1 之前
python3 scripts/feishu_claude_bot.py            # --selftest 只测文本处理，不联网
```

- 日志出现 `connected to wss://msg-frontier.feishu.cn` 才算连上。连上之前发的消息会丢失，要重新发。
- 要常驻就交给 launchd/systemd 并设置 `KeepAlive`。SDK 在 DNS 失败后可能停止重连而进程不退出，所以只看进程是否在跑不够，要靠日志判断。
- 支持文字、图片和富文本（图文混排）消息，下载图片需要 `im:resource` 权限。图片会下载到 `BOT_MEDIA_DIR`：api 后端以 base64 图片块发给模型，claude-code 后端把路径写进提示、让它用 Read 查看，codex 后端用 `--image` 传入。
- 纯 API 对话没有工具，模型做不了「打开某某」「改文件」这类事。要在飞书里远程操作本机，有两种后端：
  - `BOT_BACKEND=claude-code`：每条消息交给本机 `claude -p` 执行，用 `--resume` 续接会话。
  - `BOT_BACKEND=codex`：每条消息交给 `codex exec` 执行，用 `codex exec resume` 续接会话。
  
  `claude -p` 接任何 Anthropic 兼容接口都能用，比如百炼的 `https://dashscope.aliyuncs.com/apps/anthropic` 加 Qwen 模型。这时要把 `ANTHROPIC_DEFAULT_{HAIKU,SONNET,OPUS}_MODEL` 都设成同一个模型，否则 Claude Code 的后台任务会去请求对方没有的 haiku。
- `codex exec` 必须关掉 stdin，否则会卡在 `Reading additional input from stdin`。脚本的做法是把提示词通过 stdin 传入，命令末尾写 `-`。另外，代理不通时 codex 只会反复报 `Reconnecting... waiting for network`，不会直接失败。
- 远程操作本机的两种后端都要设白名单，下面的规则对两者都适用。这个后端必须设 `BOT_OWNER_OPEN_IDS`，只接受白名单里的人在单聊发的消息；白名单为空时，机器人会把发送者的 open_id 回给对方，方便配置。open_id 按应用区分。
- 不想影响本机原有的 Codex 时，给机器人设一个独立的 `CODEX_HOME`，里面只放 provider 配置和 `auth.json`。
- 不想影响本机原有的 Claude Code（比如它是官方登录）时，只给机器人进程设置 `CLAUDE_CONFIG_DIR=<独立目录>`、`ANTHROPIC_BASE_URL` 和 `ANTHROPIC_AUTH_TOKEN`。这样登录态、设置、会话和计费都与主配置隔离。需要共用全局规则和 skill 时，把它们软链进独立目录。
- 选现成项目前先比较：cc-connect（Go）、OpenClaw 飞书插件、Claude-to-IM-skill 都偏向桥接 Claude Code 会话，流式卡片也有未修的问题。只需要 API 多轮对话时，用这个脚本更简单。
