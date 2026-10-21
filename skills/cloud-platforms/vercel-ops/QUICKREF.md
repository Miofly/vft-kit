# Vercel 运维速查

从 skill 目录运行，认证与安全边界见 [SKILL.md](SKILL.md)。

```bash
node scripts/vercel-ops.js verify --json
node scripts/vercel-ops.js projects list --json
node scripts/vercel-ops.js deployments create prj_xxx --target production --json
node scripts/vercel-ops.js deployments wait dpl_xxx --timeout 1800 --json
node scripts/vercel-ops.js logs get dpl_xxx --since 1h --json
node scripts/vercel-ops.js env import prj_xxx --file /private/env.json --target production --json
node scripts/vercel-ops.js domains verify example.com --project prj_xxx --json
node scripts/vercel-ops.js edge-config get ecfg_xxx
node scripts/vercel-ops.js webhooks list
```

部署等待必须使用创建响应中的 ID。脚本默认 preview；只读 JSON 环境变量清单不会导出 value。

Blob、运行时日志、监控、函数与 Cron 按 [官方工作流](references/examples.md) 操作。
