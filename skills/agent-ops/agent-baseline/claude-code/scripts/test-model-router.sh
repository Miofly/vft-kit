#!/usr/bin/env bash
# Offline test of the vft-kit micro-patch on the pinned claude-model-router-hook source:
# patch applies cleanly; upstream's own suites (tests/test-hook.sh, unittest) still pass;
# Chinese mechanical work routes to haiku, reasoning stays opus; named agents with a pinned
# model are left alone, other named agents are only ever downgraded to haiku; the
# prompt-blocking UserPromptSubmit hook is gone; SessionStart injects nothing when
# healthy (rules live in global CLAUDE.md) and only reports missing router variants.
# Needs the source cache from install-model-router.sh; prints SKIP when it is missing.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${MODEL_ROUTER_DIR:-$HOME/.cache/vft-kit/claude-model-router-hook}"
REV="$(sed -n 's/^REV="\(.*\)"$/\1/p' "$DIR/install-model-router.sh")"
[ -d "$SRC/.git" ] || { echo 'SKIP: router source not cached (run install-model-router.sh)'; exit 0; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
git -C "$SRC" archive "$REV" | tar -x -C "$tmp"
git -C "$tmp" init -q && git -C "$tmp" apply "$DIR/../patches/claude-model-router-hook.patch"
H="$tmp/plugins/claude-model-router-hook/hooks"
! grep -q UserPromptSubmit "$H/hooks.json"
grep -q 'hooks/session_brief.py' "$H/hooks.json" && ! grep -q 'hooks/session_init.py' "$H/hooks.json"
# variant agents (router:haiku ...) show up in every session's agent list: one short line each, still generated.
[ "$(grep -h '^description:' "$tmp"/plugins/claude-model-router-hook/agents/*.md | sort -u)" = 'description: Router-internal; do not use.' ]
( cd "$tmp" && python3 scripts/generate_variants.py --check >/dev/null )
mkdir -p "$tmp/home/.claude"; cp "$DIR/../config/model-router.json" "$tmp/home/.claude/model-router.json"
# healthy config: SessionStart injects nothing (rules live in global CLAUDE.md);
# a broken config still reports the missing routed variants in one short line.
out="$(echo '{"cwd":"/x"}' | HOME="$tmp/home" CLAUDE_PLUGIN_ROOT="$tmp/plugins/claude-model-router-hook" python3 "$H/session_brief.py")"
[ -z "$out" ]
rm -f "$tmp/plugins/claude-model-router-hook/agents/haiku.md"
out="$(echo '{"cwd":"/x"}' | HOME="$tmp/home" CLAUDE_PLUGIN_ROOT="$tmp/plugins/claude-model-router-hook" python3 "$H/session_brief.py" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])')"
[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && [ "${#out}" -lt 200 ]
printf '%s' "$out" | grep -q '缺少路由变体' && ! printf '%s' "$out" | grep -Eq 'Model Tier|MANDATORY'
( cd "$tmp" && python3 scripts/generate_variants.py >/dev/null )   # restore haiku.md for the upstream suites
python3 - "$H" "$DIR/../config/model-router.json" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from router import taxonomy, config, policy
cfg = config.load_config(global_path=sys.argv[2])
def route(t):
    k, _ = taxonomy.classify_heuristic(t, cfg)
    return k and policy.apply_gates(t, policy.target_for_class(k, cfg), cfg).model
cases = {
    "下载 3 个 LoRA 到 Kaggle 并校验 sha256，列出大小": "haiku",
    "清理 other/temp 下的旧截图": "haiku",
    "评审执行者报告并写结论": "opus",
    "排查 kernel 报错根因": "opus",
    "实现 VideoTaskService 的重试逻辑": "opus",
}
bad = {t: (route(t), want) for t, want in cases.items() if route(t) != want}
assert not bad, bad
assert all(v["target"]["model"] in ("haiku", "opus") for v in cfg["classes"].values()), "only haiku/opus targets"
assert cfg["classifier"]["cli_fallback"] is False
PY
bash "$tmp/tests/test-hook.sh" >/dev/null
( cd "$tmp" && python3 -m unittest discover -s tests -q 2>/dev/null )
pre(){ printf '%s' "{\"tool_input\":{\"subagent_type\":\"$1\",\"prompt\":\"$2\"},\"cwd\":\"/x\"}" | HOME="$tmp/home" python3 "$H/pre_tool_use.py"; }
mkdir -p "$tmp/home/.claude/agents"
sed -i.bak 's/"advisory"/"on"/' "$tmp/home/.claude/model-router.json"
printf -- '---\nname: carrier\nmodel: haiku\n---\n' > "$tmp/home/.claude/agents/carrier.md"
[ -z "$(pre carrier '下载 LoRA 并校验 sha256')" ]          # pinned model: untouched
[ -z "$(pre fork '下载 LoRA 并校验 sha256')" ]             # fork: untouched
[ -z "$(pre custom '评审执行者报告并写结论')" ]            # named + reasoning: never upgraded
pre custom '下载 LoRA 并校验 sha256，列出大小' | grep -q '"model": "haiku"'   # named + mechanical: downgraded
pre general-purpose '清理 other/temp 下的旧截图' | grep -q '"model": "haiku"'
CLAUDE_PLUGIN_ROOT="$tmp/plugins/claude-model-router-hook" pre general-purpose '清理 other/temp 下的旧截图' | grep -q '"subagent_type": "router:haiku"'
echo 'PASS: model router patch'
