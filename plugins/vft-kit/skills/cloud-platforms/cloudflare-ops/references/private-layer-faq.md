# 与私有 skill 的关系与常见问题

## 与私有 skill 的关系

本 skill 是**通用基础**,不知道你的私有配置(zone ID/域名/业务场景)。私有项目应:
1. 创建私有 skill(如 `my-project-cdn`)
2. 在私有 skill 的 config.json 里定义 zone ID/域名
3. 私有 skill 的 SKILL.md 说明触发场景 + 如何调用本 skill

示例:私有 skill 说"清缓存",它读自己的 config.json 拿到 zone ID,从 `.secrets` 读 token,export 成环境变量,再调本 skill 的 `purge` 子命令。

## 常见问题

**Q: Token 放哪最安全?**
A: 环境变量(临时) > 配置文件在 `.secrets/` 并 gitignore(持久)。不要 hardcode 在脚本里。

**Q: 多账号怎么管理?**
A: 一账号一配置文件,`--profile <name>` 切换。文件名 = profile 名。

**Q: 为什么不用官方 Cloudflare MCP plugin?**
A: 官方 plugin 是通用 API 透传,本 skill 封装了"缓存规则 CRUD"这类高频操作的便利层,减少重复代码。两者可共存。

**Q: known_zones 必须配吗?**
A: 不必须。如果没配,脚本会调 API 自动解析域名 → zone ID(需 Zone Read 权限)。配了能减少 API 调用。
