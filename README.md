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

新增或修改非平台专属能力时，必须遵循 `plugins/vft-kit/docs/codex-compat.md`。

### ai-helper（macOS）

插件不会在安装时静默写入 Applications。安装好 `vft-kit` 后，直接对 Claude Code 或 Codex 说：

```text
安装 ai-helper
```

`install-ai-helper` skill 会从本仓库的 `ai-helper-v*` GitHub Release 下载 DMG，依次校验 SHA-256、Bundle ID、Developer ID 签名和 Gatekeeper，再安装并启动。用户不需要克隆或编译 `apps/ai-helper` 源码。

发布资产约定和设计取舍见 [ai-helper 分发方案](docs/ai-helper-distribution.md)。

## 详细文档

每个 skill / hook 的完整用法、踩坑与配置，见博客的逐篇文档（下面「Skill 分类」是速览，想看细节点进去）：

- [vft-kit 总览](https://wflynn.cn/pages/2607131001) —— 定位、安装、全量速查表、FAQ
- **CC 运维**：[cc-baseline](https://wflynn.cn/pages/2607131002) · [cc-backup-restore](https://wflynn.cn/pages/2607131003) · [plugin-refresh](https://wflynn.cn/pages/2607131004)
- **Codex 运维**：[codex-baseline](https://wflynn.cn/pages/2607131010)
- **通用工具**：[fe-auto-test](https://wflynn.cn/pages/2607131005) · [fe-lint-fix](https://wflynn.cn/pages/2607131012) · [co-infographic-generator](https://wflynn.cn/pages/2607131006) · [pr-submit](https://wflynn.cn/pages/2607131013) · [git-auto-push](https://wflynn.cn/pages/2607131007) · [vue-sfc-split](https://wflynn.cn/pages/2607131008) · [office-doc-rewrite](https://wflynn.cn/pages/2607131011)
- **macOS 应用**：[ai-helper 源码与安装说明](apps/ai-helper/README.zh-CN.md)

## Skill 分类

运行目录使用 `plugins/vft-kit/skills/<category>/<skill-name>/`。分类清单以 [`catalog/skills.json`](catalog/skills.json) 为唯一来源，目录分类、Claude manifest 和 Codex manifest 必须一致。

| 分类 | 定位 | skills |
|---|---|---|
| Agent 运维 (`agent-ops`) | Claude Code、Codex、CC Switch 与插件缓存 | `cc-backup-restore` · `cc-baseline` · `cc-switch-add-provider` · `codex-baseline` · `plugin-refresh` |
| 云平台 (`cloud-platforms`) | 云服务、模型托管、部署平台和账号资源 | `aistudio` · `cloudflare-ops` · `huggingface-ops` · `kaggle-ops` · `modelscope-studio` · `vercel-ops` |
| 开发工作流 (`dev-workflow`) | 数据库工具、前端质量、Git、代码托管和 PR 交付 | `dbx` · `fe-auto-test` · `fe-lint-fix` · `git-auto-push` · `github-ops` · `pr-submit` · `vue-sfc-split` |
| 设计与内容 (`design-content`) | 设计还原、信息图、Office 文档和视觉内容 | `co-infographic-generator` · `mastergo-mcp` · `office-doc-rewrite` · `replicate-web-style` |
| Web 与自动化 (`web-automation`) | 浏览器发布、网页抓取和 macOS 自动化 | `chrome-web-store-publish` · `keyboard-maestro` · `web-scrape` · `wechat-mp` |

新增、删除或改名 skill 时同步更新分类，并运行：

```bash
node scripts/validate-skill-catalog.mjs
```

校验器保证每个已跟踪 skill 恰好属于一个分类，并具有有效的 frontmatter `name`。插件 skill 的调用名允许与目录名不同。未跟踪的开发中 skill 只提示，不阻塞验证。

### fe-auto-test 的依赖

它要真实浏览器和 Lighthouse，这些不在插件里。**不用你手动装**——skill 每次跑的第一步会检查并自动补装：

| 装什么 | 何时生效 |
|---|---|
| `playwright` + chromium 内核、`@danielsogl/lighthouse-mcp` | npm 包，装完**立即可用** |
| playwright 插件、lighthouse MCP 注册 | 需**重启会话**才加载 |

CC 的 MCP 新注册后当前会话拿不到工具，所以 skill 不会卡住让你重启：它走**脚本路径**（`lighthouse-audit.mjs` 等直接调库，不经 MCP）把活干完，同时把 MCP 注册好留给下次。两条路能力等价。

想提前检查或只诊断不安装：

```bash
bash ~/.claude/plugins/cache/vft-kit/vft-kit/*/skills/dev-workflow/fe-auto-test/scripts/check-deps.sh --no-install
```

## 许可

MIT
