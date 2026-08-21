# Codex 默认自主闭环规范实施计划

> **执行要求：** 使用 `superpowers:subagent-driven-development` 持续执行，不把内部计划或 spec 当成人工审批门槛。

**目标：** 让 vft-ai `codex-baseline-private` 每次运行都幂等同步“默认自主规划、直接实施、测试验证闭环”的 Codex 全局规范；只有用户明确要求先规划或存在真实阻塞时才暂停。

**架构：** 规范正文以私有 skill 的受控 marker 块为唯一源，`sync-agents.mjs` 提取并原子更新 `~/.codex/AGENTS.md` 的独立 marker，不影响目录、数据库和临时目录块。

**技术栈：** Node.js 18+ ESM、`node:test`、现有 `replaceBlock` 同步机制、Codex 私有基线。

---

### 任务 1：先写同步回归测试

**文件：**
- 新建：`skills/agent-ops/codex-baseline-private/tests/test-sync-agents.mjs`

1. 构造临时 vft-ai、数据库 YAML 与 AGENTS 文件，写入 sentinel 和旧 autonomy 块。
2. 连续运行同步两次，断言内容字节一致、marker 仅一对、旧正文被替换、sentinel 与其他块保留。
3. 构造残缺 marker，断言脚本非零且文件内容不变。
4. 运行测试并确认因生产代码尚未同步新块而失败。

### 任务 2：实现规范源与幂等同步

**文件：**
- 修改：`skills/agent-ops/codex-baseline-private/SKILL.md`
- 修改：`skills/agent-ops/codex-baseline-private/scripts/sync-agents.mjs`
- 修改：`skills/agent-ops/codex-baseline-private/scripts/check.sh`

1. 在 SKILL 内新增 `autonomy-policy:start/end` 源块，规定默认内部规划后直接实施、测试、验证和交付。
2. 明确仅用户说“先规划/只要方案/先别实施”，或缺权限、关键输入、高风险不可逆操作时暂停；安全默认值可继续时直接继续并在结果说明假设。
3. 在同步脚本提取该块，写入 `codex-baseline-private:autonomy-policy` 独立目标块，并保持损坏 marker 时先失败后写入。
4. 更新基线文案和检查项，运行单测直至全绿。

### 任务 3：写入真实全局配置并验证

**文件：**
- 生成态：`/Users/wfly/.codex/AGENTS.md`

1. 运行私有同步脚本，再次运行确认幂等。
2. 回读全局 AGENTS，确认自主规范、目录、DB 与临时目录块共存且各 marker 唯一。
3. 刷新 vft-ai 的 Claude/Codex 插件缓存，在 Codex 缓存副本重跑同步测试。
4. 运行 `codex-baseline-private` 完整检查；若外部健康项与本改动无关，单独报告而不误判实现失败。
