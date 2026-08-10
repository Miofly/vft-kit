#!/usr/bin/env bash
# 装 ruflo daemon 的 launchd supervisor（macOS），让后台 worker 常驻、开机自启、崩溃重启。
#
# 为什么需要它（实测 2026-08，@claude-flow/cli 3.34.0）：
#   1. 裸 `claude-flow daemon start` 默认 TTL 43200s（12h）到点 graceful 自退，每天要手动重开。
#   2. 裸启动不随开机启动。
#   3. `daemon install-supervisor` 生成的 unit **不带 --ttl**，而 KeepAlive 只配了
#      SuccessfulExit=false + Crashed=true —— TTL 到点算「正常退出」，launchd 不会拉起它，
#      等于装了 supervisor 仍然 12h 后停摆。所以本脚本装完必须补 `--ttl 0`（永不自退）。
#   4. unit 的 WorkingDirectory / 日志路径取执行时的 cwd。若在 skills/scripts 等子目录下执行，
#      会把 .claude-flow/logs/ 写进插件仓库，污染版本库 —— 所以本脚本强制切到仓库根再装。
set -uo pipefail

LABEL="io.ruv.ruflo.daemon"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
# 装 unit 的工作目录：优先用户显式指定，否则用家目录（推荐：daemon 全局共享，不污染项目根）
# 旧版默认 $HOME/Documents/code/wfly 是历史原因，现已改为 $HOME
WORKDIR="${RUFLO_SUPERVISOR_WORKDIR:-$HOME}"

case "$(uname -s)" in
  Darwin) ;;
  *) echo "本脚本只处理 macOS(launchd)；Linux 请用 claude-flow daemon install-supervisor（systemd-user）" >&2; exit 1 ;;
esac

command -v claude-flow >/dev/null 2>&1 || {
  echo "✗ 找不到 claude-flow CLI。先装：volta install @claude-flow/cli" >&2; exit 1; }
[ -d "$WORKDIR" ] || { echo "✗ 工作目录不存在：${WORKDIR}（可用 RUFLO_SUPERVISOR_WORKDIR 覆盖）" >&2; exit 1; }

echo "→ 停掉手动起的 daemon（避免与 launchd 托管的实例并存）"
claude-flow daemon stop >/dev/null 2>&1 || true
sleep 2

echo "→ 在 $WORKDIR 下写 launchd unit"
( cd "$WORKDIR" && claude-flow daemon install-supervisor --force ) 2>&1 | grep -Ev '^Unload failed|bootout' || true
[ -f "$PLIST" ] || { echo "✗ unit 未生成：$PLIST" >&2; exit 1; }

# 补 --ttl 0：注意不能用 `grep ttl "$PLIST"` 判断（plist 别处含这三字母会误命中），
# 必须精确匹配 ProgramArguments 里的独立 `--ttl` 项。
if /usr/libexec/PlistBuddy -c 'Print :ProgramArguments' "$PLIST" 2>/dev/null | tr -d ' ' | grep -qx -- '--ttl'; then
  echo "✓ unit 已带 --ttl，跳过"
else
  echo "→ 补 --ttl 0（否则 12h 后正常退出，KeepAlive 不会拉起）"
  n=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments' "$PLIST" 2>/dev/null | grep -c '^ ')
  /usr/libexec/PlistBuddy -c "Add :ProgramArguments:$n string --ttl" -c "Add :ProgramArguments:$((n+1)) string 0" "$PLIST" >/dev/null
fi

echo "→ 重载 unit"
launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
sleep 1

echo "→ 清理可能残留的 daemon 状态文件（避免陈旧 PID 误判占位）"
rm -f "$WORKDIR/.claude-flow/daemon.pid" 2>/dev/null || true
if [ -f "$WORKDIR/.claude-flow/daemon-state.json" ]; then
  node -e 'const f=process.argv[1];const j=require(f);j.running=false;j.pid=undefined;j.daemonPid=undefined;require("fs").writeFileSync(f,JSON.stringify(j,null,2))' \
    "$WORKDIR/.claude-flow/daemon-state.json" 2>/dev/null || true
fi

launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>&1 | grep -v '^$' || true
sleep 5

# bootstrap 后实例可能因「已有 daemon 实例 / state 残留 running:false」立刻 exit 0 而起不来
# （launchctl 显示 runs=1 但 state = not running）。用 kickstart -k 强制拉一次，幂等。
if ! launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -q '^	state = running'; then
  echo "→ 实例未在运行，kickstart 强拉"
  launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
  sleep 6
fi

if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  pid=$(launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | awk '/^\tpid =/{print $3}')
  echo "✓ supervisor 已就位（launchd pid=${pid:-?}），daemon 将常驻、开机自启、崩溃重启"
  echo "  注意：\`claude-flow daemon status\` 认不出 launchd 实例会误报 STOPPED，看 .claude-flow/daemon-state.json 的 worker runCount 才准"
  echo "  日志：$WORKDIR/.claude-flow/logs/supervisor.{out,err}.log"
  echo "  卸载：launchctl bootout gui/\$(id -u)/$LABEL && rm $PLIST"
else
  echo "✗ unit 未成功 load，检查 $PLIST" >&2; exit 1
fi
