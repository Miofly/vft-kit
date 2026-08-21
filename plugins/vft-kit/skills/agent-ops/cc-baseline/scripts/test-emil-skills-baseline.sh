#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$SKILL_DIR/scripts/check.sh"
DOC="$SKILL_DIR/SKILL.md"

grep -Fq 'Emil 动效 skills（必装 3 项）' "$CHECK"
grep -Fq 'Emil 扩展 skills（可选 7 项）' "$CHECK"
grep -Fq 'npx skills add emilkowalski/skills --skill animate --skill review-animations --skill apple-design --agent claude-code --global --yes' "$CHECK"

for skill in animate review-animations apple-design animation-vocabulary ask-sonner emil-design-eng find-animation-opportunities improve-animations pick-ui-library prototype; do
  grep -Fq "$skill" "$DOC"
done

printf 'PASS: cc-baseline Emil skills classification\n'
