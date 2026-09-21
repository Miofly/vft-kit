# vft-kit

Claude Code / Codex 运维工具箱与通用开发工具。插件主体在 `plugins/vft-kit/`。

这些 Skill 面向需要把 Claude Code / Codex 工作流做成可复用工具的开发者：安装、检查、部署、抓取、文档处理、需求评审和前端质量验证都能在项目里直接复用。账号、域名、数据库和密钥通过环境变量或本地忽略配置提供，仓库不包含个人环境。

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

公开边界和导入规则见 [`docs/public-boundary.md`](docs/public-boundary.md)。改动目录或内容后运行：

```bash
node scripts/validate-skill-catalog.mjs
node scripts/audit-public.mjs
```

## 使用边界

每个 Skill 的完整用法在对应目录的 `SKILL.md`，脚本和参考资料跟随 Skill 发布。需要账号或外部服务时，先阅读该文件中的配置表；不要把 token、Cookie、密码或真实业务数据写入仓库。带有上传、发布、删除、部署等副作用的流程会先要求确认目标，完成后应回读外部状态。
## Skill 分类

运行目录使用 `plugins/vft-kit/skills/<category>/<skill-name>/`。分类清单以 [`catalog/skills.json`](catalog/skills.json) 为唯一来源，目录分类、Claude manifest 和 Codex manifest 必须一致。

| 分类 | 定位 | skills |
|---|---|---|
| Agent 运维 (`agent-ops`) | Claude Code、Codex、CC Switch、插件缓存与工作总结 | `cc-backup-restore` · `cc-baseline` · `cc-switch-add-provider` · `codex-baseline` · `co-work-summary` · `plugin-refresh` |
| 云平台 (`cloud-platforms`) | 云服务、模型托管、部署平台和账号资源 | `aistudio` · `cloudflare-ops` · `huggingface-ops` · `kaggle-ops` · `modelscope-studio` · `vercel-ops` |
| 开发工作流 (`dev-workflow`) | 数据库工具、前端质量、Git、代码托管、UA 解析和 Vue 配置 | `dbx` · `fe-auto-test` · `fe-lint-fix` · `fe-user-agent-resolver` · `git-auto-push` · `git-ops` · `github-ops` · `vue27-vite-config` |
| 设计与内容 (`design-content`) | 代码知识库、信息图、视觉理解、Office 文档和视觉内容 | `co-infographic-generator` · `co-vision-understanding` · `code-wiki` · `mastergo-mcp` · `office-doc-rewrite` · `replicate-web-style` · `wxapkg-unpack` |
| 需求质量 (`requirements`) | 需求文档通用检查和专项质量检查 | `req-check-activity` · `req-check-admin-system` · `req-check-quick-app` · `req-check-scheduled-task` · `req-quality-check` |
| 工作台工具 (`workplace-tools`) | Lark/飞书文档、表格、云盘、任务和知识库 | `lark-cli` |
| Web 与自动化 (`web-automation`) | 浏览器发布、网页抓取、Android 与 macOS 自动化 | `android-ui-automation` · `chrome-web-store-publish` · `keyboard-maestro` · `qr-login` · `web-scrape` · `wechat-mp` |

新增、删除或改名 skill 时同步更新分类，并运行：

```bash
node scripts/validate-skill-catalog.mjs
```

校验器保证每个已跟踪 skill 恰好属于一个分类，并具有有效的 frontmatter `name`。插件 skill 的调用名允许与目录名不同。未跟踪的开发中 skill 只提示，不阻塞验证。

## 规则模块（rules + hooks）

Claude Code 插件不能直接提供 `.claude/rules/`，vft-kit 用钩子实现同等效果，且带自动检查：

| 钩子 | 时机 | 作用 |
|---|---|---|
| `scripts/rules/inject.mjs` | PreToolUse（Read/Edit/Write/MultiEdit） | 文件路径命中规则 `paths` 时，把规则正文注入上下文；同会话每条只注入一次 |
| `scripts/rules/check.mjs` | PostToolUse（Edit/Write/MultiEdit） | 运行规则声明的 `checks`；error 退回模型修复，warn 只提示 |
| `scripts/rules/reset.mjs` | SessionStart（compact/clear） | 上下文压缩后清注入记录，下次命中重新注入 |

插件自带规则在 `plugins/vft-kit/rules/`（目前：`vue-sfc`、`style-layout`、`package-json`）。项目继承与私有规则放在项目根（从被操作文件向上逐级合并，monorepo 根与子项目可各放一份）：

```text
.claude/vft-rules.json        # { "disable": ["vue-sfc"], "checks": { "v-for-needs-key": "off" } }
.claude/vft-rules/*.md        # 私有规则；frontmatter 写 extends: vue-sfc 表示继承并追加
.claude/vft-rules/checks.mjs  # 私有自动检查：export default { id: { level, run({ src, blocks, filePath }) } }
```

Codex 没有对应钩子时用 CLI：`node "$VFT_PLUGIN_ROOT/scripts/rules/check.mjs" <file...>`（有 error 退出码 1）、`node "$VFT_PLUGIN_ROOT/scripts/rules/inject.mjs" <file>`（打印适用规则）。改动后跑 `node plugins/vft-kit/scripts/rules/selftest.mjs`。

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
