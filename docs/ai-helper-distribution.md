# ai-helper 分发方案

ai-helper 的源码位于 `apps/ai-helper/`，但最终用户只需要安装 `vft-kit` 插件和正式发布的 macOS 应用，不需要拉取或编译源码。

## 为什么不在插件安装时直接装 App

Codex 插件清单没有 `postinstall` 事件。插件 hook 属于会话生命周期，只会在插件启用并经用户审查信任后，于 `SessionStart`、`Stop` 等事件运行；它不适合作为软件包安装器。npm 来源的 Codex 插件也不会执行 npm lifecycle scripts。

因此采用显式 skill：用户安装插件后说“安装 ai-helper”，`install-ai-helper` 才执行应用安装。这个动作有清晰的用户意图，也能把下载、校验和失败信息展示出来。

官方参考：

- [Build plugins](https://developers.openai.com/codex/plugins/build)
- [Hooks](https://learn.chatgpt.com/docs/hooks)

## 发布契约

ai-helper Release 使用独立标签，避免和 vft-kit 插件版本冲突：

```text
ai-helper-v<CFBundleShortVersionString>
```

每个正式 Release 至少包含：

```text
AIHelper-<version>.dmg
AIHelper-<version>.dmg.sha256
```

`apps/ai-helper/scripts/create-release.sh` 还会在存在时上传 ZIP、`appcast.xml` 和 release notes。安装器只接受非 draft、非 prerelease 的 `ai-helper-v*` Release，并验证：

- DMG SHA-256
- Bundle ID `com.wfly.ai-helper`
- Developer Team ID `K46RM9974S`
- `codesign --verify --deep --strict`
- Gatekeeper `spctl --assess`

## 发布步骤

在 `apps/ai-helper/` 配好 Developer ID、notarytool 与 Sparkle 密钥后运行：

```bash
./scripts/create-release.sh
```

首次发布后，用插件中的只读检查验证 Release 可发现：

```bash
node plugins/vft-kit/skills/install-ai-helper/scripts/install-ai-helper.mjs --check
```

## 用户流程

1. 安装 `vft-kit` 插件。
2. 对 Claude Code 或 Codex 说“安装 ai-helper”。
3. Agent 调用 `install-ai-helper` skill。
4. 安装器下载、校验并安装到 `/Applications`；该目录不可写时使用 `~/Applications`。
5. ai-helper 启动后自行管理 Agent hooks、用量展示、会话状态和通知。

不要恢复旧 `usage-alert` Stop hook。用量与桌面通知只保留 ai-helper 一条实现链路，避免重复通知和两套配置漂移。
