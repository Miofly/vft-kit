# vft-kit

Claude Code / Codex 运维工具箱、通用开发工具，以及 macOS 菜单栏应用 [ai-helper](apps/ai-helper/)。插件主体在 `plugins/vft-kit/`，ai-helper 源码在 `apps/ai-helper/`。

做这个的起因很实际：Claude Code 用久了，配置、插件、登录态会散落在本机各处，换电脑或者插件坏掉时没人救你。官方文档在这块写得很薄，社区踩的坑倒是不少。这些 skill 是踩坑之后沉淀下来的。

## 装

### Claude Code

```bash
claude plugin marketplace add Miofly/vft-kit
claude plugin install vft-kit@vft-kit
```

### Codex

```bash
codex plugin marketplace add Miofly/vft-kit
codex plugin add vft-kit@vft-kit
```

Codex 入口在 `plugins/vft-kit/.codex-plugin/plugin.json`，skill 目录仍是 `plugins/vft-kit/skills/`。

跨平台兼容规则见 `plugins/vft-kit/docs/codex-compat.md`。新增或维护 skill 时，命令示例优先使用 `VFT_PLUGIN_ROOT`，并兼容 `CLAUDE_PLUGIN_ROOT` / `CODEX_PLUGIN_ROOT`。

### ai-helper（macOS）

插件不会在安装时静默写入 Applications。安装好 `vft-kit` 后，直接对 Claude Code 或 Codex 说：

```text
安装 ai-helper
```

`install-ai-helper` skill 会从本仓库的 `ai-helper-v*` GitHub Release 下载 DMG，依次校验 SHA-256、Bundle ID、Developer ID 签名和 Gatekeeper，再安装并启动。用户不需要克隆或编译 `apps/ai-helper` 源码。

发布资产约定和设计取舍见 [ai-helper 分发方案](docs/ai-helper-distribution.md)。

## 详细文档

每个 skill / hook 的完整用法、踩坑与配置，见博客的逐篇文档（下面「有什么」是速览，想看细节点进去）：

- [vft-kit 总览](https://wflynn.cn/pages/2607131001) —— 定位、安装、全量速查表、FAQ
- **CC 运维**：[cc-baseline](https://wflynn.cn/pages/2607131002) · [cc-backup-restore](https://wflynn.cn/pages/2607131003) · [plugin-refresh](https://wflynn.cn/pages/2607131004)
- **Codex 运维**：[codex-baseline](https://wflynn.cn/pages/2607131010)
- **通用工具**：[fe-auto-test](https://wflynn.cn/pages/2607131005) · [fe-lint-fix](https://wflynn.cn/pages/2607131012) · [co-infographic-generator](https://wflynn.cn/pages/2607131006) · [pr-submit](https://wflynn.cn/pages/2607131013) · [git-auto-push](https://wflynn.cn/pages/2607131007) · [vue-sfc-split](https://wflynn.cn/pages/2607131008) · [office-doc-rewrite](https://wflynn.cn/pages/2607131011)
- **macOS 应用**：[ai-helper 源码与安装说明](apps/ai-helper/README.zh-CN.md)

## 有什么

### Claude Code 运维

这些 skill 的目标仍是 Claude Code。Codex 可以读取并辅助执行，但它们操作的是 `~/.claude`、Claude 插件 cache 或 claude-hud，不是 Codex 自身配置。

| skill | 干什么 |
|---|---|
| `cc-baseline` | 核对本机 CC 是否符合装配基线（CLI / npm / MCP / 插件 / 权限），缺什么给修复命令（只读，仅 `ponytail` 缺失时自动补齐） |
| `cc-backup-restore` | 备份 / 恢复配置与数据（CLAUDE.md、settings.json、插件、skill） |
| `plugin-refresh` | 刷新插件 cache——改了本地插件源却不生效时用它 |

### Codex 运维

`codex-baseline` 的目标是 Codex CLI（`~/.codex`），不是 Claude Code。

| skill | 干什么 |
|---|---|
| `codex-baseline` | 核对本机 Codex CLI 装配基线（dangerous full access / hooks / Playwright MCP / 插件 / 系统 skills / 全局 AGENTS / 生图 CLI），缺什么给修复命令 |

### ai-helper

旧版 `Stop` 用量告警 hook 已移除。用量展示、会话状态和桌面通知统一由 ai-helper 承担，避免插件 hook 与菜单栏应用重复通知。

| skill | 干什么 |
|---|---|
| `install-ai-helper` | 检查、安装或更新正式发布的 ai-helper macOS 应用；不从源码构建，不绕过签名或 Gatekeeper |

### 通用工具

| skill | 干什么 |
|---|---|
| `fe-auto-test` | Playwright 真实浏览器验证前端页面 + Lighthouse 全维度体检（依赖会自动补装，见下） |
| `fe-lint-fix` | 前端代码质量一键修复：Prettier → Stylelint → ESLint + TypeScript 校验（自动探测包管理器 / 脚本） |
| `co-infographic-generator` | 结构化文字 → 信息图（HTML+CSS 排版，puppeteer 截图成 PNG） |
| `pr-submit` | 全自动 PR 工作流：分析改动 → 建分支 → 提交 → 创建 PR（GitHub/GitLab/Gitee） |
| `vue-sfc-split` | 拆分过大的 Vue SFC，规避文件路由 / 自动导入的坑 |
| `git-auto-push` | 绕过 git hooks 提交（husky 卡住时的逃生通道） |
| `office-doc-rewrite` | 改 Office 文档（xlsx/doc/docx）文字但保留图片/样式/布局——拿模板换内容（zip 层改文字，非整体重存） |

#### fe-auto-test 的依赖

它要真实浏览器和 Lighthouse，这些不在插件里。**不用你手动装**——skill 每次跑的第一步会检查并自动补装：

| 装什么 | 何时生效 |
|---|---|
| `playwright` + chromium 内核、`@danielsogl/lighthouse-mcp` | npm 包，装完**立即可用** |
| playwright 插件、lighthouse MCP 注册 | 需**重启会话**才加载 |

CC 的 MCP 新注册后当前会话拿不到工具，所以 skill 不会卡住让你重启：它走**脚本路径**（`lighthouse-audit.mjs` 等直接调库，不经 MCP）把活干完，同时把 MCP 注册好留给下次。两条路能力等价。

想提前检查或只诊断不安装：

```bash
bash ~/.claude/plugins/cache/vft-kit/vft-kit/*/skills/fe-auto-test/scripts/check-deps.sh --no-install
```

## 许可

MIT
