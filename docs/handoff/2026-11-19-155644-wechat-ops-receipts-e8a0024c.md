# 微信后台发送桥交接

## 在做什么

用户要求研究 `wechat-use` 的技术思路并独立实现。已完成文本发送桥的单次提交与回执，以及基于后台界面的文件助手 CLI；未复刻上游原生发送器。

## 当前状态

`wechat_bridge.py self-test` 130 项通过。`receipt` CLI 只读核对 3 笔真实回执，文件字节不变。`desktop` 接上 Swift 文件助手的文本、1–4 张 JPEG、可见历史和四种导出。副本从 `ax_window_unresolved` 恢复后，9 个 HTTP 只读场景真机通过，四种导出各对齐 2 条标签；本机只读 MCP 四个工具也用真实副本数据验证。新文本 POST 11.308 秒，独立回读未找到标记，回执未知。新四图首次被剪贴板门禁拒绝，未提交；前置恢复后单次提交 4 张标记图（152,213 字节，5.997 秒），发送侧有新记录，截图确认第 3、4 张，手机未验。实际重启桥后两笔旧回执仍可查；原始四图共 6,951,175 字节，同号同内容只返回原 `status_unknown`，逆序返回 409，未补发。官方 v1.19.29 CLI 仍未激活；只读 MCP 握手及 9 个工具的清单通过，业务查询缺 daemon；Hermes 鉴权通过但业务报 `missing_activation`；Wechaty 缺 `.wx-rs` 时启动失败；隔离 HOME 建父目录后启动与协议鉴权通过，但微信业务仍未激活。入口已补启动前检查。

新增 `verify_desktop.py`：窗口不可读时明确阻塞，恢复后真机对照 3 条可见标签，9 个 HTTP 场景、4 个 MCP 工具和四种导出通过；无发送。

新增 `verify_release.py`：官方 v1.19.29 八组件离线核验通过，5 种异常包拒绝；未安装或升级。

## 决策

先登记 `request_id`，再提交。同号同内容返回已有回执，不同内容返回 409。`desktop` 走 Swift 私有持久回执，其他桥后端仅进程内回执。结果未知只查原回执，不重发。默认 `noop` 不发送。保留上游激活与版本前置，不复刻进程注入。

## 指针

- `skills/web-automation/wechat-ops/scripts/wechat_bridge.py`、`SKILL.md`
- 博客同步：`${BLOG_ROOT}/docs/handoff/2026-11-19-155644-wechat-ops-docs-e8a0024c.md`
- 本机 REA 证据：`${WFLY_BOLIERPLATE_DIR}/other/temp/research/wechat-use-download-v1.19.29/technical-notes.md`

## 下一步

用户明确要求独立实现，不以官方激活为前置，已停止激活监控。`desktop` 的会话显示名称列表和精确名称匹配已真机通过（9 条快照记录），不返回 wxid，不改变发送范围。不补发已知未知请求；照片仅在预检与发送时都通过剪贴板门禁时测试。官方网页版仍停在扫码页。上游业务须先满足激活、受支持副本和 daemon 就绪；Wechaty 还须通过本机上传目录前置检查。好友、群、原文件、真实 SSE 和手机接收未验。

## 回查

由本机定位 `WECHAT_OPS_TRANSCRIPT`（会话标识 `e8a0024c-541f-4b92-8cbe-fb444e53f014`）。`rg -n '技术思路|receipt-test|CLI 模拟验证|31 protocol checks' "$WECHAT_OPS_TRANSCRIPT"`。
