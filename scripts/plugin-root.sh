#!/usr/bin/env bash
set -euo pipefail

# Resolve the plugin root in both Claude Code and Codex contexts.
# Prefer explicit environment variables, then fall back to this script location.
if [ -n "${VFT_PLUGIN_ROOT:-}" ]; then
  printf '%s\n' "$VFT_PLUGIN_ROOT"
  exit 0
fi

if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  printf '%s\n' "$CLAUDE_PLUGIN_ROOT"
  exit 0
fi

if [ -n "${CODEX_PLUGIN_ROOT:-}" ]; then
  printf '%s\n' "$CODEX_PLUGIN_ROOT"
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
pwd
