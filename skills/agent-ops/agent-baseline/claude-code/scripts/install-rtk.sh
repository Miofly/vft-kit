#!/usr/bin/env bash
# 保证 RTK 已装，并把「Bash 命令自动走 rtk 压缩」的 PreToolUse hook 幂等装进全局 settings.json。
# 只有装了 hook，rtk 才会自动生效；否则它只是个躺在 PATH 里没人调的二进制。
set -euo pipefail

SETTINGS="${SETTINGS:-$HOME/.claude/settings.json}"
RTK_MD="${RTK_MD:-$HOME/.claude/RTK.md}"

if ! command -v rtk >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    printf '  ✗ RTK 缺失且 Homebrew 不可用，无法自动安装\n' >&2
    exit 1
  fi
  brew install rtk
  command -v rtk >/dev/null 2>&1 || {
    printf '  ✗ Homebrew 执行完成，但仍未找到 RTK\n' >&2
    exit 1
  }
fi
printf '  ✓ RTK 已安装（%s）\n' "$(rtk --version 2>/dev/null)"

# `rtk init -g` 负责写 ~/.claude/RTK.md 和 CLAUDE.md 里的 @RTK.md 引用；
# settings.json 的 hook 补丁它要交互确认（非交互默认拒绝），所以下面自己补。
[ -f "$RTK_MD" ] || rtk init -g >/dev/null 2>&1 || printf '  ○ rtk init -g 执行异常，继续补 hook\n' >&2

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"

# 退出码：0=本来就有；10=已补上；1=失败。整份读改写 + 原子 mv，不动其它 hook（如 context-mode 的）。
set +e
node -e '
const fs=require("fs"),p=process.argv[1];
let s;try{s=JSON.parse(fs.readFileSync(p,"utf8")||"{}")}catch(e){process.exit(1)}
s.hooks=s.hooks||{};const pre=s.hooks.PreToolUse=s.hooks.PreToolUse||[];
if(JSON.stringify(pre).includes("rtk hook"))process.exit(0);
pre.push({matcher:"Bash",hooks:[{type:"command",command:"rtk hook claude"}]});
fs.writeFileSync(p+".tmp",JSON.stringify(s,null,2)+"\n");fs.renameSync(p+".tmp",p);
process.exit(10);
' "$SETTINGS"
rc=$?
set -e
case "$rc" in
  0)  printf '  ✓ RTK hook 已启用（PreToolUse Bash → rtk hook claude）\n' ;;
  10) printf '  ✓ 已补上 RTK hook（PreToolUse Bash → rtk hook claude）；新开会话生效\n' ;;
  *)  printf '  ✗ RTK hook 写入失败，手动加 PreToolUse Bash → `rtk hook claude`\n' >&2; exit 1 ;;
esac
