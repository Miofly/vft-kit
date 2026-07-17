---
name: cc-helper-setup
description: 一键安装 cc-helper —— 一个常驻 macOS 菜单栏的 Claude Code 助手 App(菜单栏实时用量 5h/7d + 点击看重置倒计时 + 可选刘海显示 + CC 事件自绘毛玻璃通知横幅 + 图形设置面板)。vft-kit 里存的是编译好的成品,安装 = 解压 → 去隔离 → 装进 ~/Applications 并启动(无需源码/工具链)。用户说"安装 cc-helper"、"装那个菜单栏用量 App"、"cc-helper setup"、"菜单栏显示 Claude 用量的软件"、"把用量显示装上"、"通知横幅 App 装一下"等场景时触发。仅 macOS(Apple Silicon 成品)。装完在 App 的设置窗口里点"安装 statusLine wrapper / 通知 hook"接数据。
---

# cc-helper-setup —— 安装 CC 助手 App

把 vft-kit 里预编译好的 `cc-helper.app` 装到 `~/Applications` 并启动。**仅 macOS(成品为 Apple Silicon / arm64),无需 Swift 工具链**。

> 源码是私有的(在 vft-ai/apps/cc-helper),开源的 vft-kit 只放编译好的成品 zip。要 Intel 版或改源码,去私有仓库自行 `swift build`。

## cc-helper 是什么

一个常驻菜单栏的 Claude Code 助手(无 Dock 图标):

- **用量显示**:菜单栏高亮 `5h X% 7d Y%`;点击看「已用% + 重置倒计时」;可选内置屏刘海同宽覆盖 + hover 展开详情。
- **通知**:CC 任务完成/失败/等待输入/对话完成时,弹自绘毛玻璃横幅(仿原生,支持单/双屏),或走系统原生。
- **设置窗口**:通用/用量/通知/数据管道/关于五页,统一开关调参,配置落 `~/.cc-helper/config.json`。

数据链路:用量来自 statusLine 落盘的 `rate_limits` 快照;通知来自 CC hook 事件经 shim 转发到 App 的事件队列。**两条链路都在 App 设置窗口里一键安装**。

## 执行

跑安装脚本(解压成品 → 装 `~/Applications/cc-helper.app` → 启动):

```bash
bash "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/cc-helper-setup/scripts/setup.sh"
```

脚本会:

1. 校验 macOS + 架构(成品是 arm64,Intel 会提示)。
2. 解压 `apps/cc-helper/cc-helper.app.zip`,`xattr` 去掉隔离属性(ad-hoc 成品 Gatekeeper 会拦)。
3. 拷到 `~/Applications/cc-helper.app`,`open` 启动。
4. 打印后续:去菜单栏点 **⚙ 设置… → 数据管道**,装「statusLine wrapper」(接用量)与「通知 hook」(接通知),再重开一个 CC 会话。

## 装完怎么接数据(告诉用户)

1. 菜单栏出现用量项(若被前台 App 的长菜单挤掉,切到菜单短的 App 就会显示)。
2. 点 **⚙ 设置…** → **数据管道** 页 → 「安装 / 更新 statusLine wrapper」+「安装 / 更新 通知 hook」。
3. **重开一个 Claude Code 会话** 生效。之后菜单栏显真实用量、任务事件弹通知横幅。
4. 想开机自启:设置 → 通用 → 勾「开机自启」。

## 排错

- **菜单栏没看到项**:多半是当前前台 App 菜单太长把状态项挤没了(macOS 溢出机制),切个菜单短的 App 即可;不是崩溃。
- **打不开 / 提示已损坏**:ad-hoc 成品被 Gatekeeper 拦,脚本已 `xattr` 去隔离;若手动拷贝的,自己跑 `xattr -dr com.apple.quarantine ~/Applications/cc-helper.app`。
- **Intel Mac 跑不了**:成品是 arm64;去私有 vft-ai/apps/cc-helper 源码自行 `swift build`。
- **通知不弹**:确认设置里「启用通知」开着、且已装通知 hook 并重开会话。
