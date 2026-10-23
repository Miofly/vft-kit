#!/bin/bash
# Seed GrowthBook feature flags into a third-party Claude Code instance (CLAUDE_CONFIG_DIR) so it behaves like the
# official main session and gets the native Monitor tool.
#
# Why: an instance on ANTHROPIC_BASE_URL usually sets CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC, which turns GrowthBook
# off, so every flag stays at its built-in default (Monitor's gate tengu_amber_sentinel defaults to false). External
# builds ignore CLAUDE_INTERNAL_FC_OVERRIDES. What works: the launcher exports CLAUDE_CODE_GB_DISK_CACHE_WHEN_TELEMETRY_OFF=1
# (CC then reads flags from <instance>/.claude.json cachedGrowthBookFeatures) and runs this script before `claude`.
# Verified on CC 2.1.280. If Monitor disappears after an upgrade, find the new gate next to
# `userFacingName(){return"Monitor"}` -> `isEnabled` in the claude binary.
#
# The instance cache becomes: source flags (read only) minus CC_FLAGS_EXCLUDE, plus CC_FLAGS_FORCE set to true.
# A missing source leaves just the forced flags. The file is rewritten only when the result differs, through a
# per-process tmp file (parallel launches race here); any failure leaves the file alone and exits 0, so a launcher
# never aborts on it.
#
# Env:
#   CLAUDE_CONFIG_DIR  instance dir (required; the main ~/.claude is refused)
#   CC_FLAGS_SRC       flag source, default $HOME/.claude.json (the official login's cache)
#   CC_FLAGS_EXCLUDE   jq regex of keys not to copy (official-account-only and promo flags)
#   CC_FLAGS_FORCE     space-separated keys forced to true, default tengu_amber_sentinel
# Usage: cc-instance-flags.sh [--dry-run]   (--dry-run prints "<n> flags, changed|unchanged" and writes nothing)
set -u
dir=${CLAUDE_CONFIG_DIR:-}
[ -n "$dir" ] && [ "$dir" != "$HOME/.claude" ] || { echo "cc-instance-flags: set CLAUDE_CONFIG_DIR to an instance dir" >&2; exit 0; }
cfg=$dir/.claude.json
[ -f "$cfg" ] || { echo "cc-instance-flags: $cfg missing, skipped" >&2; exit 0; }
src=${CC_FLAGS_SRC:-$HOME/.claude.json}; [ -f "$src" ] || src=/dev/null
exclude=${CC_FLAGS_EXCLUDE:-'^tengu_(bridge|ccr|chrome|claudeai|cowork|startup_announcements|snug_storm)|upsell'}
force=$(printf '%s\n' ${CC_FLAGS_FORCE:-tengu_amber_sentinel} | jq -R . | jq -sc 'map({(.): true}) | add // {}')
gb='(($m[0].cachedGrowthBookFeatures? // {}) | with_entries(select(.key | test($ex) | not))) + $force'
args=(--slurpfile m "$src" --arg ex "$exclude" --argjson force "$force")
if jq -e "${args[@]}" ".cachedGrowthBookFeatures == ($gb)" "$cfg" >/dev/null 2>&1; then state=unchanged; else state=changed; fi
if [ "${1:-}" = --dry-run ]; then echo "$(jq -n "${args[@]}" "$gb | length") flags, $state"; exit 0; fi
[ $state = changed ] || exit 0
tmp=$cfg.tmp.$$
{ jq "${args[@]}" ".cachedGrowthBookFeatures = ($gb)" "$cfg" > "$tmp" && mv "$tmp" "$cfg"; } 2>/dev/null || { rm -f "$tmp"; echo "cc-instance-flags: write failed, $cfg left as is" >&2; }
exit 0
