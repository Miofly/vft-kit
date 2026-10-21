# 入口与认证

## 入口与认证

Node.js 18+，REST 脚本无第三方依赖。将下文 `$SKILL_DIR` 设为本 skill 的实际绝对目录：

```bash
node "$SKILL_DIR/scripts/vercel-ops.js" --help
node "$SKILL_DIR/scripts/vercel-ops.js" --config /absolute/private/vercel.json verify --json
```

Token 优先级：`VERCEL_TOKEN` > 配置中选定 profile 的 `access_token`。
配置路径：显式 `--config` > 当前目录 `vercel-config.json` > `~/.config/vercel/config.json`。
显式路径不存在、JSON 非法或 profile 不存在时直接失败，不能静默换账号。
即使环境变量提供 token，仍读取所选配置的 team scope；`--team-id` 最后覆盖。

配置可用 `config.example.json` 的单账号结构，或 `{"default": {...}, "work": {...}}` 多 profile 结构。私有凭证留在用户现有保险库，不复制到 skill。诊断只检查字段是否存在、调用是否成功，不打印 token 或整个配置。
