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
