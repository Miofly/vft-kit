#!/bin/bash
# Claude 用量阈值告警：5 小时窗口 / 7 天窗口越过阈值时发 macOS 通知。
#
# 数据来源说明（重要）：
# 官方 hook 事件的 payload 不含任何用量数据，唯一能拿到 rate_limits 的是 statusline。
# 因此本 hook 不直接读用量，而是读 claude-hud 落盘的快照——需要在
# ~/.claude/plugins/claude-hud/config.json 里开启：
#   { "display": { "externalUsageWritePath": "<$HOME>/.claude/usage-snapshot.json" } }
# 未开启 / 非订阅账号（API key 无限额窗口）时，本脚本静默退出，不影响会话。
#
# 自定义（阈值 / 声音 / 新鲜度 / 快照路径）：编辑 ~/.claude/vft-kit/usage-alert-config.json
#   { "thresholds": [70,90], "sound": "Glass", "maxAgeSeconds": 600,
#     "snapshotPath": "~/.claude/usage-snapshot.json" }
# 取值优先级：环境变量（CLAUDE_USAGE_THRESHOLDS / CLAUDE_USAGE_SNAPSHOT） > 配置文件 > 内建默认。
# 配置模板由 usage-alert-setup skill 幂等落盘，也可手建。

CONFIG="$HOME/.claude/vft-kit/usage-alert-config.json"
STATE="$HOME/.claude/usage-alert-state"
DEFAULT_SNAPSHOT="$HOME/.claude/usage-snapshot.json"
DEFAULT_THRESHOLDS="70 75 80 85 90 95 100"
DEFAULT_MAX_AGE=600     # 快照比这更旧就不信（statusline 每个 turn 刷新，正常远低于此）
DEFAULT_SOUND="Glass"

cat >/dev/null 2>&1   # 丢弃 hook payload，本脚本不需要

# jq 是读快照与配置的硬依赖；没有就静默退出
command -v jq >/dev/null 2>&1 || exit 0

# 读配置文件（存在且合法 JSON 才读）
cfg_thresholds=""; cfg_sound=""; cfg_maxage=""; cfg_snapshot=""
if [ -r "$CONFIG" ] && jq empty "$CONFIG" >/dev/null 2>&1; then
  cfg_thresholds="$(jq -r 'if (.thresholds|type)=="array" then (.thresholds|map(tostring)|join(" ")) else empty end' "$CONFIG" 2>/dev/null)"
  cfg_sound="$(jq -r '.sound // empty' "$CONFIG" 2>/dev/null)"
  cfg_maxage="$(jq -r '.maxAgeSeconds // empty' "$CONFIG" 2>/dev/null)"
  cfg_snapshot="$(jq -r '.snapshotPath // empty' "$CONFIG" 2>/dev/null)"
fi

# 优先级：环境变量 > 配置文件 > 内建默认
SNAPSHOT="${CLAUDE_USAGE_SNAPSHOT:-${cfg_snapshot:-$DEFAULT_SNAPSHOT}}"
THRESHOLDS="${CLAUDE_USAGE_THRESHOLDS:-${cfg_thresholds:-$DEFAULT_THRESHOLDS}}"
SOUND="${cfg_sound:-$DEFAULT_SOUND}"
MAX_AGE_SEC="${cfg_maxage:-$DEFAULT_MAX_AGE}"

# 展开 snapshotPath 里的 ~（配置文件可能写 ~/…）
case "$SNAPSHOT" in "~/"*) SNAPSHOT="$HOME/${SNAPSHOT#\~/}" ;; esac
# 容错：非数字 maxAge 回落默认，避免下面算术报错
case "$MAX_AGE_SEC" in ''|*[!0-9]*) MAX_AGE_SEC="$DEFAULT_MAX_AGE" ;; esac
# 容错：阈值只允许数字与空格，否则回落默认（防 awk 把垃圾当 0 误报）
case "$THRESHOLDS" in *[!0-9\ ]*) THRESHOLDS="$DEFAULT_THRESHOLDS" ;; esac
# 容错：声音名去掉双引号，避免注入 osascript 字符串
SOUND="${SOUND//\"/}"

[ -r "$SNAPSHOT" ] || exit 0

age=$(( $(date +%s) - $(stat -f %m "$SNAPSHOT" 2>/dev/null || echo 0) ))
[ "$age" -gt "$MAX_AGE_SEC" ] && exit 0

touch "$STATE" 2>/dev/null
fired=""

for win in five_hour seven_day; do
  read -r pct resets <<<"$(jq -r --arg w "$win" \
    '(.[$w].used_percentage // empty | tostring) + " " + (.[$w].resets_at // "none")' \
    "$SNAPSHOT" 2>/dev/null)"
  [ -z "$pct" ] || [ "$pct" = "null" ] && continue

  case "$win" in
    five_hour) label="5 小时" ;;
    seven_day) label="7 天" ;;
  esac

  # 只就当前达到的最高阈值告警一次，避免 92% 同时触发 70 和 90 两条通知
  hit=""
  for th in $THRESHOLDS; do
    awk -v p="$pct" -v t="$th" 'BEGIN{exit !(p >= t)}' && \
      { [ -z "$hit" ] || [ "$th" -gt "$hit" ]; } && hit="$th"
  done
  [ -z "$hit" ] && continue

  # 去重键含 resets_at：限额窗口一翻新，同阈值可再次告警
  key="${win}:${hit}:${resets}"
  grep -qxF "$key" "$STATE" 2>/dev/null && continue
  echo "$key" >>"$STATE"

  pct_disp=$(printf '%.0f' "$pct" 2>/dev/null || echo "$pct")
  msg="${label}用量已达 ${pct_disp}%"
  osascript -e "display notification \"${msg}（阈值 ${hit}%）\" with title \"Claude 用量告警\" sound name \"${SOUND}\"" >/dev/null 2>&1
  fired="${fired}${fired:+；}${msg}"
done

# state 文件不无限增长
if [ "$(wc -l <"$STATE" 2>/dev/null || echo 0)" -gt 50 ]; then
  tail -20 "$STATE" >"$STATE.tmp" && mv "$STATE.tmp" "$STATE"
fi

[ -n "$fired" ] && printf '{"systemMessage": "⚠️ %s"}\n' "$fired"
exit 0
