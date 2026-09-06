# vercel-ops

无需 Vercel MCP 的运维 skill。REST 脚本使用 API token，官方 CLI 覆盖 Blob、运行时日志、函数检查和监控，Cron 使用项目配置。

以 [SKILL.md](SKILL.md) 为维护入口；命令以 `node scripts/vercel-ops.js --help` 为准。不要把历史占位命令当成可用 API。

```bash
node scripts/vercel-ops.js --config /private/vercel.json verify --json
node scripts/vercel-ops.js projects list --json
bash scripts/test.sh
```

Node.js 18+；REST 无第三方依赖。官方 CLI 工作流需要已安装且完成认证的 `vercel`。
