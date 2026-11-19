# 微信后台发送桥交接

## 在做什么

用户要求研究 `wechat-use` 的技术思路并独立实现。已完成文本发送桥的单次提交与回执，以及基于后台界面的文件助手 CLI；未复刻上游原生发送器。

## 当前状态

`wechat_bridge.py self-test` 31 项通过，另有 CLI 模拟检查 3 项通过。独立 `desktop_sender.swift` 已编译，离线自检及真实窗口只读预检通过；CLI 的原请求回执能跨进程读取。真机四图首次回读过早，在提交前停止；核对 4 张已在草稿后只回车一次。草稿随后清空，但无法区分本批与旧图片条目，原回执保留 `status_unknown`，没有补发。已补草稿和发送记录的限时只读回验及回归测试；成功发送总耗时、手机逐张接收未确认。未安装上游工具。

## 决策

先登记 `request_id`，再调用后端。同请求号同正文返回已有回执，不同内容 409。后端超时记 `status_unknown`，查原回执，不重发。回执只在当前桥进程内保留。默认 `noop` 不发送。保留上游激活与版本前置，不复刻进程注入。

## 指针

- `skills/web-automation/wechat-ops/scripts/wechat_bridge.py`、`SKILL.md`
- 博客同步：`${BLOG_ROOT}/docs/handoff/2026-11-19-155644-wechat-ops-docs-e8a0024c.md`
- 本机 REA 证据：`${WFLY_BOLIERPLATE_DIR}/other/temp/research/wechat-use-download-v1.19.29/technical-notes.md`

## 下一步

先只读核对四图原回执，结果未知不补发。要摆脱桌面窗口依赖，可验证官方网页版文件助手的后台上传与回读；目前停在扫码页，只覆盖发给自己。桌面 CLI 的本地回执可跨进程查询，HTTP 桥仍不保留跨重启回执。任意好友、群、HTTP 媒体及手机接收均未实现或未验。

## 回查

由本机定位 `WECHAT_OPS_TRANSCRIPT`（会话标识 `e8a0024c-541f-4b92-8cbe-fb444e53f014`）。`rg -n '技术思路|receipt-test|CLI 模拟验证|31 protocol checks' "$WECHAT_OPS_TRANSCRIPT"`。
