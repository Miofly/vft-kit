# Mac 桌面微信静默复刻交接

## 1. 目标

对标 `wechat-use` 的公开功能：独立 Mac 桌面微信副本，不抢焦点、不用网页登录、不依赖 ADB。界面可见标签和离线归档只算分项，不等于无窗口的真实数据源。一次性的置前验收授权不延伸到日常操作。

## 2. 当前状态

- `WeChat-4.2.0-Test`（270390，`com.tencent.xinWeChat420Test`）已登录，与主微信不同 PID 和容器。4.1.9 副本扫码后提示版本过低。新版接入只读，拒绝发送和旧回执查询；主微信不在允许列表。
- 新版 `--sessions-only` 最后通过 11 条会话名称，CLI、HTTP、MCP、终端一致。此前通讯录 11 条和朋友圈 1 条可见标签在页面先打开后通过后台对账。不代表完整通讯录或朋友圈。
- 文件助手历史、搜索、统计、导出与发送预检解耦。读取仍要求标题、消息列表及可验证标签；截断、错会话或无标签不报空历史。Swift 自检通过。真机 `--filehelper-only` 返回 `503`：当前并未选中文件助手，不是发送输入框缺失。视觉精确命中、后台点按回执和原生搜索菜单均未验证会话切换；不重复这些路径。未发送。
- 桥 190 项协议回归；归档 70 次 CLI、37 次回环 HTTP 检查通过，含四格式导出、JSON 导回和导入流。合成数据不算微信实时接收。`--readiness-only` 通过的是状态、鉴权和参数校验，不表示全部可读。

## 3. 决策

继续使用独立副本；不改主微信、不降沙盒、不取密钥、不注入、不对外开放。实际收发与原文件送达分别验；结果未知永不补发。网页版任务此前停在扫码，已排除出本目标，不要求用户扫码。

## 4. 指针

- `skills/web-automation/wechat-ops/scripts/desktop_sender.swift`：`verifiedFilehelperLabels`、`visibleFilehelperLabels`、`readVisible`。
- `skills/web-automation/wechat-ops/scripts/verify_desktop.py`：`--readiness-only`、`--sessions-only`、`--filehelper-only`。
- `skills/web-automation/wechat-ops/references/capability-scope.md`：缺口和真机证据；本机会话产物目录名 `history-final.0fyboA`，二进制可按 `SKILL.md` 重编。

## 5. 下一步

文件助手已选中且副本可读时，后台跑 `--filehelper-only`，逐验历史、搜索、统计、四种导出；不把手动打开页面算成自动导航通过。无窗口的采集、全量历史、完整通讯录、群成员、逐会话未读、实时接收和新版发送仍未打通；只有获得支持的真实数据入口后才验窗口隐藏时的新增消息。不要再用增加协议外壳来替代该验收。

## 6. 回查

在本机会话记录中定位会话 `cac2fee7-b3a3-4b2f-ba63-ba3569db0242`，将日志绝对路径设为 `WECHAT_OPS_TRANSCRIPT`。`rg -n 'filehelper_title|verifiedFilehelperLabels|session_names|background snapshot unavailable' "$WECHAT_OPS_TRANSCRIPT"`。
