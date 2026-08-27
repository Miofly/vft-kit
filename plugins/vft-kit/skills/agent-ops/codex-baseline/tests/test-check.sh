#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$BASH_SOURCE")/.." && pwd)"
CHECK_SCRIPT="$SKILL_DIR/scripts/check.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
REAL_NODE="$(node -p 'process.execPath')"

TEST_HOME="$TMP_ROOT/home"
TEST_CODEX_HOME="$TEST_HOME/.codex"
FAKE_BIN="$TMP_ROOT/bin"
NPM_ROOT_FIXTURE="$TMP_ROOT/npm-root"
CC_SWITCH_FIXTURE="$TMP_ROOT/CC Switch.app"
mkdir -p "$TEST_CODEX_HOME" "$FAKE_BIN" "$NPM_ROOT_FIXTURE" "$CC_SWITCH_FIXTURE"

cat > "$FAKE_BIN/codex" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "--version" ] && { printf 'codex-cli 1.0.0\n'; exit 0; }
if [ "$1" = "features" ] && [ "$2" = "list" ]; then
  printf 'multi_agent                          stable             %s\n' "${TEST_MULTI_AGENT_ENABLED:-true}"
  exit 0
fi
if [ "$1" = "plugin" ] && [ "$2" = "list" ] && [ "$3" = "--json" ] && [ -f "${TEST_PLUGIN_LIST_JSON:-}" ]; then
  cat "$TEST_PLUGIN_LIST_JSON"
  exit 0
fi
if [ "$1" = "mcp" ] && [ "$2" = "get" ] && [ -f "${TEST_MCP_JSON_DIR:-}/$3.json" ]; then
  cat "$TEST_MCP_JSON_DIR/$3.json"
  exit 0
fi
exit 2
EOF
cat > "$FAKE_BIN/node" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "-v" ] && { printf 'v22.0.0\n'; exit 0; }
exit 2
EOF
cat > "$FAKE_BIN/npm" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  -v) printf '10.0.0\n' ;;
  root) [ "$2" = "-g" ] && printf '%s\n' "$TEST_NPM_ROOT" ;;
  *) exit 2 ;;
esac
EOF
cat > "$FAKE_BIN/git" <<'EOF'
#!/usr/bin/env bash
printf 'git version 2.50.0\n'
EOF
cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "--version" ] && { printf 'gh version 2.0.0\n'; exit 0; }
if [ "$1" = "auth" ] && [ "$2" = "token" ] && [ "${TEST_GH_TOKEN_AVAILABLE:-true}" = "true" ]; then
  printf 'fixture-gh-token-must-not-leak\n'
  exit 0
fi
exit 2
EOF
cat > "$FAKE_BIN/codegraph" <<'EOF'
#!/usr/bin/env bash
printf 'codegraph 1.0.0\n'
EOF
cat > "$FAKE_BIN/code-review-graph" <<'EOF'
#!/usr/bin/env bash
printf 'code-review-graph 2.3.7\n'
EOF
cat > "$FAKE_BIN/volta" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
cat > "$FAKE_BIN/rtk" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "--version" ] && printf 'rtk 1.0.0\n'
EOF
for command_name in brew jq; do
  cat > "$FAKE_BIN/$command_name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
done
chmod +x "$FAKE_BIN"/*

cat > "$TEST_CODEX_HOME/config.toml" <<'EOF'
approval_policy = "never"
sandbox_mode = "danger-full-access"

[notice]
hide_full_access_warning = true

[features]
hooks = true
memories = true

[projects."/"]
trust_level = "trusted"

[mcp_servers.playwright]
command = "fixture-playwright"

[mcp_servers.codegraph]
command = "codegraph"

[mcp_servers.code-review-graph]
command = "code-review-graph"
args = ["serve"]
type = "stdio"
enabled = true

[mcp_servers.lighthouse-mcp]
command = "node"

[mcp_servers.context7]
url = "https://context7.example/mcp"

[mcp_servers.openaiDeveloperDocs]
url = "https://developers.openai.com/mcp"

[mcp_servers.node_repl]
enabled = false
command = "/missing/Codex.app/node_repl"

[plugins."github@openai-api-curated"]
enabled = true

[plugins."superpowers@openai-api-curated"]
enabled = true

[plugins."build-web-apps@openai-api-curated"]
enabled = true

[plugins."ponytail@ponytail"]
enabled = true

[plugins."context-mode@context-mode"]
enabled = true
EOF

for key in github superpowers build-web-apps; do
  mkdir -p "$TEST_CODEX_HOME/plugins/cache/openai-api-curated/$key/v1"
done
mkdir -p "$TEST_CODEX_HOME/plugins/cache/ponytail/ponytail/v1"
mkdir -p "$TEST_CODEX_HOME/plugins/cache/context-mode/context-mode/v1"
for skill in openai-docs imagegen skill-creator plugin-creator skill-installer; do
  mkdir -p "$TEST_CODEX_HOME/skills/.system/$skill"
  : > "$TEST_CODEX_HOME/skills/.system/$skill/SKILL.md"
done
mkdir -p "$TEST_CODEX_HOME/skills/anysearch"
: > "$TEST_CODEX_HOME/skills/anysearch/SKILL.md"
for skill in caveman gsap-core gsap-frameworks gsap-performance gsap-plugins gsap-react gsap-scrolltrigger gsap-timeline gsap-utils animate review-animations apple-design; do
  mkdir -p "$TEST_CODEX_HOME/skills/$skill"
  : > "$TEST_CODEX_HOME/skills/$skill/SKILL.md"
done

mkdir -p \
  "$NPM_ROOT_FIXTURE/@danielsogl/lighthouse-mcp" \
  "$TEST_HOME/Library/Caches/ms-playwright/chromium-fixture" \
  "$TEST_CODEX_HOME/venvs/imagegen-cli/bin"
mkdir -p "$TMP_ROOT/mcp-json"
cat > "$TMP_ROOT/mcp-json/playwright.json" <<'EOF'
{"name":"playwright","enabled":true,"transport":{"type":"stdio","command":"fixture-playwright","args":[]}}
EOF
cat > "$TMP_ROOT/mcp-json/codegraph.json" <<'EOF'
{"name":"codegraph","enabled":true,"transport":{"type":"stdio","command":"codegraph","args":["serve","--mcp"]}}
EOF
cat > "$TMP_ROOT/mcp-json/code-review-graph.json" <<'EOF'
{"name":"code-review-graph","enabled":true,"transport":{"type":"stdio","command":"code-review-graph","args":["serve"]}}
EOF
cat > "$TMP_ROOT/mcp-json/lighthouse-mcp.json" <<'EOF'
{"name":"lighthouse-mcp","enabled":true,"transport":{"type":"stdio","command":"node","args":["fixture-lighthouse.js"]}}
EOF
cat > "$TMP_ROOT/mcp-health.mjs" <<'EOF'
import { appendFileSync } from 'node:fs';

let input = '';
for await (const chunk of process.stdin) input += chunk;
appendFileSync(process.env.TEST_MCP_HEALTH_LOG, `${JSON.parse(input).name}\n`);
EOF
: > "$TEST_CODEX_HOME/image-gen.py"
cat > "$TEST_CODEX_HOME/venvs/imagegen-cli/bin/python" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TEST_HOME/codex-imagegen" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TEST_CODEX_HOME/venvs/imagegen-cli/bin/python" "$TEST_HOME/codex-imagegen"

write_agents() {
  local include_parallel="$1"
  {
    printf '%s\n' \
      '- 始终使用简体中文回复。' \
      '- 引用代码位置使用 markdown 可点短链。' \
      '- 上下文压缩时保留决策和状态。' \
      '- 外网操作启用代理兜底并复用 https_proxy。'
    if [ "$include_parallel" = "yes" ]; then
      printf '%s\n' \
        '- 默认并行：有 ≥2 个独立工作流时立即用 spawn_agent 启动多个 Agent。' \
        '- 子 Agent 共享工作区，文件所有权必须互不重叠，不能同时修改同一文件。' \
        '- 主 Agent 汇总结论、整合改动并运行最终验证。'
    elif [ "$include_parallel" = "weak" ]; then
      printf '%s\n' '- 多个 subagent 可以并行执行互不依赖的任务。'
    fi
    printf '%s\n' \
      '- codegraph 新项目自动执行 codegraph init；已有索引执行 codegraph sync，完整重建执行 codegraph index -f。' \
      '- 所有 code review 必须先用 code-review-graph 获取最小审查上下文、影响半径和相关测试，再按需读取源码。' \
      '- code-review-graph 新项目执行 code-review-graph build，索引更新执行 code-review-graph update，检查状态执行 code-review-graph status。' \
      '- context7 查询最新官方文档。' \
      '- anysearch 联网搜索优先。' \
      '- Caveman 默认 full 自动启用，每个新会话直接使用极简表达。' \
      '- 生图使用 codex-imagegen generate。'
  } > "$TEST_CODEX_HOME/AGENTS.md"
}

run_check() {
  env \
    HOME="$TEST_HOME" \
    CODEX_HOME="$TEST_CODEX_HOME" \
    TEST_NPM_ROOT="$NPM_ROOT_FIXTURE" \
    TEST_PLUGIN_LIST_JSON="$TMP_ROOT/plugin-list.json" \
    TEST_MCP_JSON_DIR="$TMP_ROOT/mcp-json" \
    TEST_MULTI_AGENT_ENABLED="${TEST_MULTI_AGENT_ENABLED:-true}" \
    TEST_GH_TOKEN_AVAILABLE="${TEST_GH_TOKEN_AVAILABLE:-true}" \
    CODEX_STATE_NODE="$REAL_NODE" \
    MCP_HEALTH_SCRIPT="$TMP_ROOT/mcp-health.mjs" \
    TEST_MCP_HEALTH_LOG="$TMP_ROOT/mcp-health.log" \
    CC_SWITCH_APP_PATH="$CC_SWITCH_FIXTURE" \
    CODEX_IMAGEGEN_CLI="$TEST_CODEX_HOME/image-gen.py" \
    CODEX_IMAGEGEN_VENV="$TEST_CODEX_HOME/venvs/imagegen-cli" \
    CODEX_IMAGEGEN_WRAPPER="$TEST_HOME/codex-imagegen" \
    GITHUB_PAT_TOKEN="${TEST_GITHUB_PAT_TOKEN-fixture-token}" \
    OPENAI_API_KEY="fixture-key" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    bash "$CHECK_SCRIPT" "$@"
}

write_agents yes
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 0 ] || { printf 'FAIL: complete baseline fixture should pass\n' >&2; exit 1; }
grep -Fq '@danielsogl/lighthouse-mcp' <<< "$output" || { printf 'FAIL: npm package check missing\n' >&2; exit 1; }
grep -Fq 'CodeGraph 自动初始化' <<< "$output" || { printf 'FAIL: CodeGraph AGENTS check missing\n' >&2; exit 1; }
grep -Fq 'code-review-graph CLI' <<< "$output" || { printf 'FAIL: code-review-graph CLI check missing\n' >&2; exit 1; }
grep -Fq 'code-review-graph MCP 已配置' <<< "$output" || { printf 'FAIL: code-review-graph MCP check missing\n' >&2; exit 1; }
grep -Fq 'code-review-graph MCP 已启用' <<< "$output" || { printf 'FAIL: code-review-graph MCP enabled check missing\n' >&2; exit 1; }
grep -Fq 'code-review-graph MCP 命令正确' <<< "$output" || { printf 'FAIL: code-review-graph MCP command check missing\n' >&2; exit 1; }
grep -Fq 'code-review-graph code-review-first' <<< "$output" || { printf 'FAIL: code-review-graph AGENTS review policy check missing\n' >&2; exit 1; }
grep -Fq 'code-review-graph 索引维护规范' <<< "$output" || { printf 'FAIL: code-review-graph AGENTS lifecycle policy check missing\n' >&2; exit 1; }
grep -Fq 'context7 官方文档优先' <<< "$output" || { printf 'FAIL: context7 AGENTS check missing\n' >&2; exit 1; }
grep -Fq 'anysearch 联网搜索优先' <<< "$output" || { printf 'FAIL: anysearch AGENTS check missing\n' >&2; exit 1; }
grep -Fq 'Caveman 默认 full 自动启用' <<< "$output" || { printf 'FAIL: Caveman default activation check missing\n' >&2; exit 1; }
grep -Fq 'grill-me skill' <<< "$output" || { printf 'FAIL: optional grill-me skill check missing\n' >&2; exit 1; }
grep -Fq 'diagram-design@diagram-design' <<< "$output" || { printf 'FAIL: optional diagram-design plugin check missing\n' >&2; exit 1; }
grep -Fq 'understand-anything skills' <<< "$output" || { printf 'FAIL: optional understand-anything check missing\n' >&2; exit 1; }
grep -Fq 'pm-skills' <<< "$output" || { printf 'FAIL: optional pm-skills check missing\n' >&2; exit 1; }
grep -Fq 'Emil 动效 skills（必装 3 项）' <<< "$output" || { printf 'FAIL: required Emil skills check missing\n' >&2; exit 1; }
grep -Fq 'Emil 扩展 skills' <<< "$output" || { printf 'FAIL: optional Emil skills check missing\n' >&2; exit 1; }
grep -Fq 'context-mode@context-mode' <<< "$output" || { printf 'FAIL: required context-mode plugin check missing\n' >&2; exit 1; }
grep -Fq 'npx skills add mattpocock/skills --skill grill-me --agent codex --global --yes' <<< "$output" || { printf 'FAIL: grill-me Codex install command missing\n' >&2; exit 1; }
grep -Fq 'Codex Memories' <<< "$output" && { printf 'FAIL: enabled memories reported missing\n' >&2; exit 1; }
grep -Fq 'Codex multi_agent' <<< "$output" && { printf 'FAIL: enabled multi_agent reported missing\n' >&2; exit 1; }
grep -Fq 'OpenAI Developer Docs MCP 已配置' <<< "$output" || { printf 'FAIL: docs MCP check missing\n' >&2; exit 1; }
grep -Fiq 'vercel' <<< "$output" && { printf 'FAIL: Vercel should not be managed by the baseline\n' >&2; exit 1; }
grep -Fq 'GITHUB_PAT_TOKEN 已注入' <<< "$output" || { printf 'FAIL: injected GitHub token not detected\n' >&2; exit 1; }
grep -Fq 'node_repl command 不存在' <<< "$output" && { printf 'FAIL: disabled node_repl should be ignored\n' >&2; exit 1; }

: > "$TMP_ROOT/mcp-health.log"
output="$(run_check --health)"
grep -Fq 'code-review-graph MCP 已连接' <<< "$output" || { printf 'FAIL: code-review-graph health handshake missing\n' >&2; exit 1; }
grep -Fxq 'code-review-graph' "$TMP_ROOT/mcp-health.log" || { printf 'FAIL: code-review-graph health helper not called\n' >&2; exit 1; }

cp "$TEST_CODEX_HOME/AGENTS.md" "$TEST_CODEX_HOME/AGENTS.override.md"
sed -i.bak '/Caveman 默认 full 自动启用/d' "$TEST_CODEX_HOME/AGENTS.override.md"
rm "$TEST_CODEX_HOME/AGENTS.override.md.bak"
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: active AGENTS.override.md without Caveman rule should fail\n' >&2; exit 1; }
grep -Fq 'Caveman 默认 full 自动启用' <<< "$output" || { printf 'FAIL: active override Caveman gap not reported\n' >&2; exit 1; }
cp "$TEST_CODEX_HOME/AGENTS.md" "$TEST_CODEX_HOME/AGENTS.override.md"
output="$(run_check)"
grep -Fq 'Caveman 默认 full 自动启用' <<< "$output" || { printf 'FAIL: active override Caveman rule not detected\n' >&2; exit 1; }
rm "$TEST_CODEX_HOME/AGENTS.override.md"

mkdir -p "$TEST_HOME/.agents/skills/understand"
: > "$TEST_HOME/.agents/skills/understand/SKILL.md"
cat > "$TEST_HOME/.agents/.skill-lock.json" <<'EOF'
{"version":1,"skills":{"create-prd":{"source":"phuryn/pm-skills"}}}
EOF
output="$(run_check)"
grep -F 'understand-anything skills（代码知识图谱）' <<< "$output" | grep -Fq '✓' || { printf 'FAIL: installed understand-anything not detected\n' >&2; exit 1; }
grep -F 'pm-skills（产品工作流）' <<< "$output" | grep -Fq '✓' || { printf 'FAIL: installed pm-skills source not detected\n' >&2; exit 1; }
rm -rf "$TEST_HOME/.agents"

mkdir -p "$TEST_HOME/.agents/skills"
for skill in caveman gsap-core gsap-frameworks gsap-performance gsap-plugins gsap-react gsap-scrolltrigger gsap-timeline gsap-utils animate review-animations apple-design; do
  mv "$TEST_CODEX_HOME/skills/$skill" "$TEST_HOME/.agents/skills/$skill"
done
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 0 ] || { printf 'FAIL: compatible skills under ~/.agents/skills should pass\n' >&2; exit 1; }
for skill in caveman gsap-core gsap-frameworks gsap-performance gsap-plugins gsap-react gsap-scrolltrigger gsap-timeline gsap-utils animate review-animations apple-design; do
  mv "$TEST_HOME/.agents/skills/$skill" "$TEST_CODEX_HOME/skills/$skill"
done

sed -i.bak 's#^- codegraph.*#- 进入代码项目时，没有 .codegraph 就执行 codegraph init；已有陈旧索引用 codegraph update。#' "$TEST_CODEX_HOME/AGENTS.md"
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: obsolete CodeGraph update policy should fail\n' >&2; exit 1; }
grep -Fq 'CodeGraph 索引刷新规范' <<< "$output" || { printf 'FAIL: obsolete CodeGraph policy not reported\n' >&2; exit 1; }
grep -Fq "sed -i.bak -e 's/codegraph update/codegraph sync/g'" <<< "$output" || { printf 'FAIL: executable CodeGraph policy repair missing\n' >&2; exit 1; }
grep -Fq 'codegraph index -f' <<< "$output" || { printf 'FAIL: full CodeGraph rebuild command missing\n' >&2; exit 1; }
mv "$TEST_CODEX_HOME/AGENTS.md.bak" "$TEST_CODEX_HOME/AGENTS.md"

mv "$FAKE_BIN/codegraph" "$TMP_ROOT/codegraph.disabled"
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: missing CodeGraph CLI should fail\n' >&2; exit 1; }
grep -Fq 'curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh' <<< "$output" || { printf 'FAIL: CodeGraph repair should use the official installer\n' >&2; exit 1; }
grep -Fq 'volta install @colbymchenry/codegraph' <<< "$output" && { printf 'FAIL: CodeGraph repair should not require Volta\n' >&2; exit 1; }
mv "$TMP_ROOT/codegraph.disabled" "$FAKE_BIN/codegraph"

mv "$FAKE_BIN/code-review-graph" "$TMP_ROOT/code-review-graph.disabled"
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: missing code-review-graph CLI should fail\n' >&2; exit 1; }
grep -Fq 'pipx install code-review-graph' <<< "$output" || { printf 'FAIL: code-review-graph repair should use pipx\n' >&2; exit 1; }
mv "$TMP_ROOT/code-review-graph.disabled" "$FAKE_BIN/code-review-graph"

sed -i.bak '/所有 code review 必须先用 code-review-graph/d' "$TEST_CODEX_HOME/AGENTS.md"
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: missing code-review-first policy should fail\n' >&2; exit 1; }
grep -Fq 'code-review-graph code-review-first' <<< "$output" || { printf 'FAIL: missing code-review-first policy not reported\n' >&2; exit 1; }
grep -Fq '最小审查上下文' <<< "$output" || { printf 'FAIL: executable code-review-first repair missing\n' >&2; exit 1; }
mv "$TEST_CODEX_HOME/AGENTS.md.bak" "$TEST_CODEX_HOME/AGENTS.md"

sed -i.bak '/^command = "code-review-graph"$/s/code-review-graph/wrong-review-command/' "$TEST_CODEX_HOME/config.toml"
mv "$TMP_ROOT/mcp-json/code-review-graph.json" "$TMP_ROOT/code-review-graph.json.disabled"
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: wrong code-review-graph MCP command should fail\n' >&2; exit 1; }
grep -Fq 'code-review-graph MCP 命令错误' <<< "$output" || { printf 'FAIL: wrong code-review-graph MCP command not reported\n' >&2; exit 1; }
grep -Fq 'codex mcp add code-review-graph -- code-review-graph serve' <<< "$output" || { printf 'FAIL: code-review-graph MCP repair should only register the user MCP\n' >&2; exit 1; }
mv "$TEST_CODEX_HOME/config.toml.bak" "$TEST_CODEX_HOME/config.toml"
mv "$TMP_ROOT/code-review-graph.json.disabled" "$TMP_ROOT/mcp-json/code-review-graph.json"

sed -i.bak 's/"command":"code-review-graph"/"command":"wrong-review-command"/' "$TMP_ROOT/mcp-json/code-review-graph.json"
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: resolved MCP state with wrong code-review-graph command should fail\n' >&2; exit 1; }
grep -Fq 'code-review-graph MCP 命令错误' <<< "$output" || { printf 'FAIL: wrong resolved code-review-graph MCP command not reported\n' >&2; exit 1; }
mv "$TMP_ROOT/mcp-json/code-review-graph.json.bak" "$TMP_ROOT/mcp-json/code-review-graph.json"

sed -i.bak 's#"command":"code-review-graph","args":\["serve"\]#"command":"/bin/echo","args":["code-review-graph","serve"]#' "$TMP_ROOT/mcp-json/code-review-graph.json"
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: arbitrary MCP runner with CRG-like args should fail\n' >&2; exit 1; }
grep -Fq 'code-review-graph MCP 命令错误' <<< "$output" || { printf 'FAIL: arbitrary code-review-graph MCP runner not reported\n' >&2; exit 1; }
mv "$TMP_ROOT/mcp-json/code-review-graph.json.bak" "$TMP_ROOT/mcp-json/code-review-graph.json"

sed -i.bak '/^\[mcp_servers.code-review-graph\]/,/^\[mcp_servers.lighthouse-mcp\]/ s/^enabled = true$/enabled = false/' "$TEST_CODEX_HOME/config.toml"
mv "$TMP_ROOT/mcp-json/code-review-graph.json" "$TMP_ROOT/code-review-graph.json.disabled"
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: disabled code-review-graph MCP should fail\n' >&2; exit 1; }
grep -Fq 'code-review-graph MCP 已禁用' <<< "$output" || { printf 'FAIL: disabled code-review-graph MCP not reported\n' >&2; exit 1; }
mv "$TEST_CODEX_HOME/config.toml.bak" "$TEST_CODEX_HOME/config.toml"
mv "$TMP_ROOT/code-review-graph.json.disabled" "$TMP_ROOT/mcp-json/code-review-graph.json"

set +e
output="$(TEST_GITHUB_PAT_TOKEN= TEST_GH_TOKEN_AVAILABLE=true run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: enabled GitHub plugin without env token should fail\n' >&2; exit 1; }
grep -Fq 'GITHUB_PAT_TOKEN 未注入（gh 已登录）' <<< "$output" || { printf 'FAIL: missing GitHub token not reported\n' >&2; exit 1; }
grep -Fq 'export GITHUB_PAT_TOKEN="$(gh auth token 2>/dev/null)"' <<< "$output" || { printf 'FAIL: safe GitHub token fix missing\n' >&2; exit 1; }
grep -Fq 'fixture-gh-token-must-not-leak' <<< "$output" && { printf 'FAIL: gh token leaked to output\n' >&2; exit 1; }

sed -i.bak '/^\[plugins\."github@openai-api-curated"\]/,/^\[plugins\./ s/^enabled = true$/enabled = false/' "$TEST_CODEX_HOME/config.toml"
rm -rf "$TEST_CODEX_HOME/plugins/cache/openai-api-curated/github"
output="$(TEST_GITHUB_PAT_TOKEN= TEST_GH_TOKEN_AVAILABLE=true run_check)"
grep -Fq 'GitHub 能力（gh 已登录；API curated 当前未提供插件）' <<< "$output" || { printf 'FAIL: authenticated gh fallback not accepted\n' >&2; exit 1; }
mv "$TEST_CODEX_HOME/config.toml.bak" "$TEST_CODEX_HOME/config.toml"
mkdir -p "$TEST_CODEX_HOME/plugins/cache/openai-api-curated/github/v1"

sed -i.bak 's/^enabled = false$/enabled = true/' "$TEST_CODEX_HOME/config.toml"
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 0 ] || { printf 'FAIL: missing node_repl command should remain optional\n' >&2; exit 1; }
grep -Fq 'node_repl command 不存在' <<< "$output" || { printf 'FAIL: enabled node_repl missing command not reported\n' >&2; exit 1; }
mv "$TEST_CODEX_HOME/config.toml.bak" "$TEST_CODEX_HOME/config.toml"

mv "$NPM_ROOT_FIXTURE/@danielsogl/lighthouse-mcp" "$TMP_ROOT/lighthouse-mcp.disabled"
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: configured MCP without package should fail\n' >&2; exit 1; }
grep -Fq 'lighthouse-mcp 载体缺失' <<< "$output" || { printf 'FAIL: missing MCP carrier not reported\n' >&2; exit 1; }
mv "$TMP_ROOT/lighthouse-mcp.disabled" "$NPM_ROOT_FIXTURE/@danielsogl/lighthouse-mcp"

cat > "$TMP_ROOT/plugin-list.json" <<'EOF'
{"installed":[
  {"pluginId":"github@openai-api-curated","installed":true,"enabled":true},
  {"pluginId":"superpowers@openai-api-curated","installed":true,"enabled":true},
  {"pluginId":"build-web-apps@openai-api-curated","installed":true,"enabled":true},
  {"pluginId":"ponytail@ponytail","installed":true,"enabled":true},
  {"pluginId":"context-mode@context-mode","installed":true,"enabled":true}
]}
EOF
rm -rf "$TEST_CODEX_HOME/plugins/cache"
output="$(run_check)"
grep -Fq 'ponytail@ponytail（installed + enabled）' <<< "$output" || { printf 'FAIL: resolved plugin state not used\n' >&2; exit 1; }
rm "$TMP_ROOT/plugin-list.json"
for key in github superpowers build-web-apps; do
  mkdir -p "$TEST_CODEX_HOME/plugins/cache/openai-api-curated/$key/v1"
done
mkdir -p "$TEST_CODEX_HOME/plugins/cache/ponytail/ponytail/v1"
mkdir -p "$TEST_CODEX_HOME/plugins/cache/context-mode/context-mode/v1"

write_agents weak
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: weak parallel rule should fail\n' >&2; exit 1; }
grep -Fq '多 Agent 并行规范' <<< "$output" || { printf 'FAIL: weak parallel rule not reported\n' >&2; exit 1; }

write_agents yes
set +e
output="$(TEST_MULTI_AGENT_ENABLED=false run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: disabled multi_agent should fail\n' >&2; exit 1; }
grep -Fq 'Codex multi_agent' <<< "$output" || { printf 'FAIL: disabled multi_agent not reported\n' >&2; exit 1; }

write_agents yes
rm -rf "$TEST_CODEX_HOME/plugins/cache/openai-api-curated/superpowers"
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 0 ] || { printf 'FAIL: missing optional superpowers plugin should not fail\n' >&2; exit 1; }
grep -Fq 'superpowers@openai-api-curated' <<< "$output" || { printf 'FAIL: optional superpowers plugin should be reported\n' >&2; exit 1; }
grep -Fq '可选' <<< "$output" || { printf 'FAIL: superpowers plugin should be marked optional\n' >&2; exit 1; }

mkdir -p "$TEST_CODEX_HOME/plugins/cache/openai-api-curated/superpowers/v1"
rm -rf "$TEST_CODEX_HOME/plugins/cache/context-mode/context-mode"
set +e
output="$(run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: missing required context-mode plugin should fail\n' >&2; exit 1; }
[ "$(grep -Fc 'context-mode@context-mode' <<< "$output")" -eq 1 ] || { printf 'FAIL: context-mode failure should be counted once\n' >&2; exit 1; }

set +e
output="$(CODEX_BASELINE_SKIP='unused, context-mode@context-mode ' run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 0 ] || { printf 'FAIL: intentionally skipped required item should not fail\n' >&2; exit 1; }
grep -Fq '刻意不装' <<< "$output" || { printf 'FAIL: skipped item should be reported neutrally\n' >&2; exit 1; }
grep -Fq '1 刻意不装' <<< "$output" || { printf 'FAIL: skipped item should be included in summary\n' >&2; exit 1; }

printf 'PASS: codex baseline checks\n'
