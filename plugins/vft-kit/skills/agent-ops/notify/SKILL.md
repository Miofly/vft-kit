---
name: notify
description: 提供通用 ntfy 通知发送，以及 macOS ntfy-macos 接收端、登录自启和订阅看门狗。用户要求发送 ntfy 通知、给其他 skill 接入公共通知、安装或配置 ntfy-macos、Mac 接收 ntfy 通知、自启常驻或排查订阅假活时使用。
---

# 通用通知

当前只封装已经实际复用的 ntfy 能力，不抽象 PushPlus、图床或业务消息格式。

## 发送 ntfy

调用方通过环境变量供给配置，公共脚本不读仓库密钥文件：

| 环境变量 | 含义 | 默认 |
|---|---|---|
| `NTFY_BASE_URL` | ntfy HTTPS 根地址 | 无 |
| `NTFY_TOPIC` | topic；默认要求至少 32 字符 | 无 |
| `NTFY_TOKEN` | 可选 Bearer token | 无 |
| `NTFY_ALLOW_SHORT_TOPIC` | 明确允许短 topic | `false` |

```bash
python3 "<本 SKILL.md 所在目录的绝对路径>/scripts/send_ntfy.py" \
  --title '任务完成' --message '构建与验证已通过'
```

可用 `--file <绝对路径>` 附带一个不超过 10 MiB 的文件，用 `--priority 1..5` 设置优先级。token 只能从环境变量读取，不放进参数、日志或输出。成功时脚本只输出 `ntfy: ok (HTTP 200)`。

安全边界：`NTFY_BASE_URL` 必须是无路径、查询、片段和内嵌凭据的 HTTPS 根地址；短 topic 只有调用方显式设置 `NTFY_ALLOW_SHORT_TOPIC=true` 才允许。

## ntfy-macos 接收端

macOS 可用 [ntfy-macos](https://github.com/laurentftech/ntfy-macos) 订阅相同的 server/topic，把消息显示到系统通知中心。

- 从上游 Release、Homebrew 或源码安装与本机架构匹配的应用；校验签名和实际二进制架构，不静默删除 quarantine 或绕过 Gatekeeper。
- 最小配置只写 server/topic，文件权限设为 `0600`；token 用 `ntfy-macos auth add` 写入 macOS Keychain，不写 YAML、命令输出或日志。
- 首次启动必须由用户在系统提示或“系统设置 -> 通知 -> ntfy-macos”开启通知。权限为 `denied` 时应用可能主动退出，自动拉起不能替代用户授权，也不得修改系统数据库绕过 TCC。
- 直接安装 `.app` 时，可把 `scripts/ntfy-watchdog.sh` 复制到 TCC 保护目录之外，再由用户级 LaunchAgent 以 `RunAtLoad=true`、`StartInterval=300` 执行。脚本支持 `NTFY_MACOS_APP`、`NTFY_MACOS_BIN`、`NTFY_MACOS_GRACE_SECONDS` 覆盖，默认应用为 `/Applications/ntfy-macos.app`、启动宽限期为 120 秒。
- 看门狗按周期执行后退出，所以 `launchctl print` 的 `state = not running` 且 `last exit code = 0` 正常；需要常驻的是 ntfy-macos 进程。进程存在不代表订阅健康，超过宽限期后还必须存在 ESTABLISHED 订阅连接。
- 安装或升级后验证：应用签名/架构、通知授权、`test-notify` 退出 `0`、进程常驻、宽限期后订阅连接，以及用 `send_ntfy.py` 发布测试消息得到 HTTP `200` 并在本机真实收到通知。验证不得打印 server、topic 或 token。
