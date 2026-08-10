#!/usr/bin/env bash
# 往全局 ~/.claude/CLAUDE.md 追加「ruflo 多 Agent 与后台执行」规范。
# 正文是实测校准过的（2026-08 对 @claude-flow/cli 3.34.0 逐条验证），不是照文档抄的：
#   - CLI 可执行名是 claude-flow，`ruflo` 命令不存在
#   - swarm 没有 create 子命令，用 start -o "目标" -s 策略
#   - autopilot 是「持续完成模式」，不是定时巡检
#   - 没有 loop 命令，定时能力是 daemon 的 9 个固定 worker
# 幂等：已有该段则不重复追加。
set -uo pipefail

CLAUDE_MD="$HOME/.claude/CLAUDE.md"
MARK_START='<!-- cc-baseline:ruflo-guidance:start -->'
MARK_END='<!-- cc-baseline:ruflo-guidance:end -->'

[ -f "$CLAUDE_MD" ] || { echo "✗ 全局规范文件不存在：$CLAUDE_MD" >&2; exit 1; }

if grep -Fq "$MARK_START" "$CLAUDE_MD"; then
  # 注意必须写 ${VAR} 带花括号：紧跟全角括号「）」时，bash 会把多字节首字节当成变量名的一部分，
  # 裸 $MARK_START 在 set -u 下报 `MARK_START\xef: unbound variable` 而整脚本以 1 退出。
  echo "✓ ruflo 规范已存在（${MARK_START}），跳过"
  exit 0
fi

# 已有手写版（无标记但有 ruflo 段）时也跳过，别叠两份
if grep -Eq '^## ruflo (多 Agent|swarm)' "$CLAUDE_MD"; then
  echo "✓ 检测到已有 ruflo 规范段（未带标记，可能是手写版），跳过以免重复"
  exit 0
fi

cp "$CLAUDE_MD" "$CLAUDE_MD.bak.$(date +%Y%m%d%H%M%S)"
cat >> "$CLAUDE_MD" <<'RUFLO_GUIDANCE'

<!-- cc-baseline:ruflo-guidance:start -->
## ruflo 多 Agent 与后台执行（CLI 名是 `claude-flow`，不是 `ruflo`）

**命令入口**：装的是 `@claude-flow/cli`（建议 volta 管理），可执行文件叫 **`claude-flow`**。`ruflo` 这个命令不存在，写成 `ruflo xxx` 会 command not found。MCP 注册名同样是 `claude-flow`（工具前缀 `mcp__claude-flow__*`）。

### ruflo swarm — 只在子 agent 需要互看产物时用
分流判据：**子项互不相干走原生 Agent 扇出（一条消息多个 Agent 调用），子项要互相看才用 swarm**。swarm 唯一不可替代之处是共享记忆池——agent A 写入的中间结论，agent B 能读到；原生 subagent 各自上下文独立，看不到对方。

```bash
claude-flow swarm start -o "重构用户模块：前端定接口 → 后端实现 → 测试断言" -s development
claude-flow swarm status          # 看进度
claude-flow swarm stop            # 停
claude-flow swarm coordinate --agents 15   # V3 15-agent 分层网格（大改造才用）
```
子命令只有 `init / start / status / stop / scale / coordinate / pheromone / join / compress-message`。**没有 `create` 子命令**，也不能用 `--agents frontend,backend,test` 指定角色名——角色由 `-s <策略>`（development / research / analysis / testing / optimization / maintenance）决定。

### autopilot — 是「干到全做完」，不是定时监控
真实语义是**持续完成模式**：挂在 stop hook 上，收尾时检查任务是否全部完成，没完成就重新拉起继续干，直到清零或触顶（max iterations / timeout）。**它不做「每 N 分钟巡检生产环境」**，别这么用。

```bash
claude-flow autopilot enable      # 开启持续完成
claude-flow autopilot status      # 看迭代次数与任务进度
claude-flow autopilot config      # 配 max iterations / timeout / 任务来源
claude-flow autopilot disable     # 关
```
适用：一次交代一长串待办、不想反复催「继续」。不适用：健康检查、告警、巡检。

### 定时/后台任务 — 走 daemon 的 worker，**没有 `loop` 命令**
`claude-flow loop ...` 不存在（报 Unknown command）。定时能力的载体是 daemon 的固定 worker，共 9 个、默认启用 7 个：`map / audit / optimize / consolidate / testgaps / backup / harness`（默认开），`predict / document`（默认关）。它们是 ruflo 内置的仓库维护任务，**不接受自定义 shell 命令**。

```bash
claude-flow daemon start          # 起 daemon（TTL 12h 自动退出）
claude-flow daemon status         # 看 9 个 worker 的运行/成功率/下次执行
claude-flow daemon trigger -w audit   # 手动触发某个 worker
claude-flow daemon enable -w predict  # 开关某个 worker
claude-flow daemon install-supervisor # 装 launchd 自动重启（免手动重开）
```
**想跑自定义定时任务（清 CDN、备份库、查配额）**：ruflo 给不了，用 launchd/cron 或既有 skill，别硬套 daemon worker。

### 已知运维坑
- **daemon TTL 12h 自动退出**，机器重启或超时后要重新 `daemon start`；想常驻装 `install-supervisor`。
- **MCP 别配 `npx -y ruflo@latest mcp start`**：每个 CC 会话 spawn `npx → npm exec → node` 三层进程且退出不回收，实测累积到 22 进程 / 603 MB。正确配法指向固定二进制：`claude mcp add claude-flow -s user -- ~/.volta/bin/claude-flow-mcp`。
- `claude-flow init` 只写**项目级** `./.mcp.json`，不注册到 user scope，必须再 `claude mcp add` 一次。
<!-- cc-baseline:ruflo-guidance:end -->
RUFLO_GUIDANCE

echo "✓ 已追加 ruflo 规范骨架到 $CLAUDE_MD"
