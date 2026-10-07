# 小程序版本发布与提审（mp.weixin.qq.com/wxamp）

开发阶段的 CLI、模拟器自测和广告规则见 `miniprogram-devtools.md`。

小程序后台和公众号后台同域（`mp.weixin.qq.com`），但路径是 `/wxamp/...`，而且是**另一个账号**：同一个微信号下常同时挂着公众号和小程序，扫码时要选「小程序」那个账号。同一个浏览器 profile 同时只能登一个账号，登小程序会把公众号后台挤掉（先访问 `/cgi-bin/logout`，再打开登录页 `/cgi-bin/loginpage?url=%2Fwxamp%2Fwacodepage%2Fgetcodepage`）。

`token` 规则和公众号一样：每次登录都变，从当前 `/wxamp/...?token=` 的 URL 里现取。

## 流程

1. **上传开发版**：**首选 `scripts/mp-ci.mjs`（官方 miniprogram-ci）**，没有上传密钥时才用开发者工具 CLI，不走网页。
   - `MP_APPID=wx… MP_KEY=<上传密钥.key> MP_PROJECT=<含 app.json 的目录> node scripts/mp-ci.mjs upload <版本号> "<描述>"`；生成预览码：`… mp-ci.mjs preview "<描述>" <绝对路径.png> [页面路径] [query]`。
   - 不需要开发者工具，也不用扫码登录，完全在后台跑，不碰用户桌面。效果和开发者工具上传一样，后台多一个开发版。`MP_ROBOT`（1～30）是后台显示的上传者编号，默认 1。
   - 一次性准备：①安装依赖：`mkdir -p ~/.cache/vft-kit/miniprogram-ci && cd $_ && npm i miniprogram-ci`。②在小程序后台「开发管理 → 开发设置 → 小程序代码上传」生成并下载上传密钥（`.key`），放进私有凭据目录，只按路径读取，不打印内容。③在同一处配置 IP 白名单：填本机出口 IP，或者关闭白名单（关闭后密钥一旦泄露，任何人都能上传代码）。
   - 报 `invalid ip` 一类错误时，是出口 IP 不在白名单里。代理会改变出口 IP，上传时要注意。
   - 报 `tunneling socket could not be established ... ETIMEDOUT` 时，是 shell 里的 `http(s)_proxy` 指向了连不上的代理，miniprogram-ci 会照用。用 `env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY node scripts/mp-ci.mjs …` 直连重试（大小写都要清）。
   - 只想验证密钥能不能用时跑 `preview`：它只生成预览码，不占开发版，也不影响线上和体验版。
   - 不能做的：没有模拟器，跑不了 automator 自测（见 `miniprogram-devtools.md`）。
   以下是开发者工具 CLI 兜底：
   ```bash
   /Applications/wechatwebdevtools.app/Contents/MacOS/cli upload --project <项目目录> -v <版本号> -d "<描述>"
   ```
   - 需要开发者工具「设置 → 安全设置 → 服务端口」已开启；没开时 CLI 会交互式询问，可以用 `echo y |` 确认，开启后首次调用可能报 `reading IDE port file`，重试一次即可。
   - 同一开发者覆盖上传后，如果体验版本来就指向该开发者的开发版，体验版自动更新；否则要在「版本管理」里「选为体验版」。
   - 版本号按线上版本递增，不要用日期（审核和回退列表按版本号展示）。
2. **查状态**：`ego-browser nodejs < scripts/wxamp-version-status.mjs`，读线上、审核中、开发版本。
3. **提交审核**：首选接口版 `scripts/wxamp-submit-audit-api.mjs`（参数写在脚本前：`globalThis.ARGS={version,desc,privacy}`，见脚本头注释），它自己回读 `audit_status`。页面版 `wxamp-submit-audit.mjs` 只作兜底。
4. **审核通过后发布**：版本管理里点「发布」（接口待抓）。

## 隐私选项（提审表单「用户隐私保护指引设置」）

- **未采集用户隐私**（`PRIVACY=none`）：会再弹一次确认框，提示代码里实际调用的隐私接口在发布后会被回收权限。`chooseAvatar`、`<input type="nickname">`、定位、相册等都属于隐私接口，选了「未采集」，发布后这些能力可能失效。
- **采集用户隐私**（`PRIVACY=collect`）：要先在「设置 → 服务内容声明 → 用户隐私保护指引」里如实勾选收集项（表单里也有「点击更新」链接 `/wxamp/wadevelopcode/privacy?ver=2&id=<开发者openid>&token=…`），指引内容不合规会影响审核结果。

## 接口（API 化进度）

都在已登录的 `mp.weixin.qq.com` 页面里用 `page.fetch` 调用（带 cookie）。路由型接口的格式是 `/wxamp/cgi/route?path=<urlencode(/wxopen/...)>&token=&lang=zh_CN&random=`。

| 动作 | 方法与路径 | 状态 |
|---|---|---|
| 版本状态 | `GET /wxamp/cgi/route?path=/wxopen/wacodepage?action=getcodepage&f=json&token=…`。返回的 `code_data` 是 JSON 字符串，内含 `online_info`、`experience_info`（提审后承载审核版本：`audit_status`、`fail_reason`、`audit_id`）、`develop_info.info_list[]`（`is_exper` 表示是否为体验版）；外层的 `can_submit_check` 表示能否提审 | ✅ 已实测 |
| 提审预检 | 点「提交审核」后依次调用：`aiability/evaluation/getAuditStatus`、`category/getMajorCategory`、`category/selfCheck`（带 version、describe）、`route path=/wxopen/wacodepage?action=check_domain`、`route path=/wxopen/waexperiencecode?action=check_plugin_version`、`version/CheckPrivacyApiAuth`（`ret:0, data.taskStatus:1` 即通过） | 仅抓到 |
| 隐私声明 | `GET /wxamp/cgi/version/updatePrivacyCollectMgr?is_not_collect=1&version_openid=<开发者openid>`；`is_not_collect=1` 表示未采集 | 仅抓到 |
| 隐私接口清单 | `POST /wxamp/cgi/version/getWxaDevPrivacyApiList`，body `openid=<开发者openid>`，返回代码里用到的隐私接口；`GET /wxamp/cgi/version/getMpPrivacyMetaMsg` | 仅抓到 |
| **提交审核** | ①`GET route path=/wxopen/wadevelopcode?action=get_class&openid=<开发版 open_id>&user_name=<上传者昵称>`：返回 `public_key_info`（JSON 字符串，取 `auto_id`）、`class_info`（`remark`、`speedup_type`）、`online_order_path`。②`GET /wxamp/cgi/version/updatePrivacyCollectMgr?is_not_collect=1|0&version_openid=<open_id>`。③`POST route path=/wxopen/wadevelopcode?action=submit_check`，`x-www-form-urlencoded`：`ticket=qrcheckTicket`、`openid`、`auto_id`、`version_desc`、`speedup_audit=0`、`speedup_type`（空时用「修复漏洞」）、`speedup_desc`、`encrypted_username`、`encrypted_password`（无需登录时留空）、`remark`、`order_path`、`feedback_info`、`feedback_status=1`、`only_run_wxwork=0`、`argue_item`、`preview_info={"pic_id_list":[],"video_id_list":[]}`、`feedback_stuff`；成功 `ret=0`。开发版的 `open_id`、`nick_name` 在 getcodepage 的 `develop_info.info_list[].basic_info` 里，同一版本号可能有多条（开发者工具和 ci 机器人各一条） | ✅ 2026-10-06 用接口独立提交成功，回读 `audit_status=1`；脚本 `scripts/wxamp-submit-audit-api.mjs` |
| 发布 | 待抓 | — |
| 订阅消息：我的模板 | `GET /wxamp/cgi/newtmpl/get_pritmpllist?token=…&lang=zh_CN&random=`，返回 `list[]`：`title`、`tid`、`priTmplId`（即前端 `requestSubscribeMessage` 和后端发送用的模板 ID）、`content`（字段占位如 `{{thing5.DATA}}`）、`sceneDesc` | ✅ 2026-10-07 已实测（只读） |
| 订阅消息：搜公共模板库 | `POST /wxamp/cgi/newtmpl/get_pubtmpllist?token=…`，`x-www-form-urlencoded` body `keyword=<urlencode>&start=0&limit=30`，返回 `pubTmplList.list[]`：`tid`、`title`、`type`（2=一次性）、`refCnt`、`keywordList.list[]`（`kid`、`name`、`rule`） | ✅ 2026-10-07 已实测（只读） |
| 订阅消息：选用模板 | 页面 `/wxamp/newtmpl/tmplselect?tid=<tid>&token=…`：按顺序点关键词 chip（DOM `.click()`，ego 的 `page.mouse.click` 在这页会卡死）→ 场景说明输入框（placeholder 含「场景」，≤15 字，用原生 value setter + `input` 事件）→ 点「提交」，成功后跳回 `mytmpl`，用「我的模板」接口回读 `priTmplId`。提交请求因整页跳转没抓到 | 仅页面流程（2026-10-07 用它选用了 YourTools「油价调整提醒」tid 1103） |

开放平台接口（`api.weixin.qq.com/wxaapi/newtmpl/*`、`cgi-bin/stable_token`）需要调用方 IP 在小程序「API IP 白名单」里，本机直连报 `40164 invalid ip`；后台页面内的 `/wxamp/cgi/newtmpl/*` 走登录 cookie，不受白名单限制，优先用它。换 token 时用 `stable_token`（`force_refresh:false`），不要用 `cgi-bin/token`，后者会让线上后端缓存的 token 5 分钟后失效。

下次推进：①抓「发布」接口（审核通过后版本管理里的「发布」按钮）；②抓订阅消息「选用」的提交接口（在 tmplselect 页提交前先 `performance.setResourceTimingBufferSize` 并挂 XHR 钩子到 `window.top` 或用 CDP `Network.requestWillBeSent`，整页跳转前把请求写进 `sessionStorage`）。

## 坑

- **点了「继续提交」没反应**：后台在 `CheckPrivacyApiAuth` 之后用 `window.open` 打开提审表单，必须用真实鼠标点击（`page.mouse.click`）。`element.click()` 不算用户手势，会被弹窗拦截。
- **页面里预先放着十几个隐藏的弹窗模板**：读弹窗或点按钮前，先过滤出 `.weui-desktop-dialog` 中 `offsetParent !== null` 的那个。
- **点「提交审核」后要等几秒**：先跑完预检接口才弹「须知」，立刻去找弹窗会找不到。
- **判断是否已登录别看整串 URL**：登录页 `loginpage?url=%2Fwxamp%2F…` 的参数里也带 `wxamp`，要看路径部分是不是 `/wxamp/...?token=`。
- **开了原始 CDP 之后**（如 `Network.enable`），之前 snapshot 拿到的 `@ref` 会失效，要改用文字或选择器定位。
- **开发者工具的模拟器别用模拟鼠标去点**：改用 miniprogram-automator，见 `miniprogram-devtools.md`。
