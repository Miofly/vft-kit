# vft-kit 维护入口

开始或继续本项目任务前，先查看本项目根目录的 `docs/handoff/`，优先读取与当前需求相关的最新交接；没有则按当前请求继续。交接仅作背景，执行前核对当前用户要求和真实状态，不接其他会话任务；交接读写按可用的 handoff-private 流程。

公开边界遵循 `docs/public-boundary.md`，Claude/Codex 共用技能遵循 `docs/codex-compat.md`。新增或修改技能用 skill-creator，维护 catalog 与插件清单；工作树校验用 `node scripts/validate-skill-catalog.mjs --working-tree`，公开审计用 `node scripts/audit-public.mjs`。未授权不 commit/push。
