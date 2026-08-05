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

[plugins."codex-security@openai-api-curated"]
enabled = true

[plugins."ponytail@ponytail"]
enabled = true
EOF

for key in github superpowers build-web-apps codex-security; do
  mkdir -p "$TEST_CODEX_HOME/plugins/cache/openai-api-curated/$key/v1"
done
mkdir -p "$TEST_CODEX_HOME/plugins/cache/ponytail/ponytail/v1"
for skill in openai-docs imagegen skill-creator plugin-creator skill-installer; do
  mkdir -p "$TEST_CODEX_HOME/skills/.system/$skill"
  : > "$TEST_CODEX_HOME/skills/.system/$skill/SKILL.md"
done
mkdir -p "$TEST_CODEX_HOME/skills/anysearch"
: > "$TEST_CODEX_HOME/skills/anysearch/SKILL.md"
for skill in caveman gsap-core gsap-frameworks gsap-performance gsap-plugins gsap-react gsap-scrolltrigger gsap-timeline gsap-utils; do
  mkdir -p "$TEST_CODEX_HOME/skills/$skill"
  : > "$TEST_CODEX_HOME/skills/$skill/SKILL.md"
done

mkdir -p \
  "$NPM_ROOT_FIXTURE/@colbymchenry/codegraph" \
  "$NPM_ROOT_FIXTURE/@danielsogl/lighthouse-mcp" \
  "$TEST_HOME/Library/Caches/ms-playwright/chromium-fixture" \
  "$TEST_CODEX_HOME/venvs/imagegen-cli/bin"
mkdir -p "$TMP_ROOT/mcp-json"
cat > "$TMP_ROOT/mcp-json/vercel.json" <<'EOF'
{"name":"vercel","enabled":true,"transport":{"type":"streamable_http","url":"https://mcp.vercel.com"}}
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
      '- codegraph 新项目自动建立索引。' \
      '- context7 查询最新官方文档。' \
      '- anysearch 联网搜索优先。' \
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
    CC_SWITCH_APP_PATH="$CC_SWITCH_FIXTURE" \
    CODEX_IMAGEGEN_CLI="$TEST_CODEX_HOME/image-gen.py" \
    CODEX_IMAGEGEN_VENV="$TEST_CODEX_HOME/venvs/imagegen-cli" \
    CODEX_IMAGEGEN_WRAPPER="$TEST_HOME/codex-imagegen" \
    GITHUB_PAT_TOKEN="${TEST_GITHUB_PAT_TOKEN-fixture-token}" \
    OPENAI_API_KEY="fixture-key" \
    PATH="$FAKE_BIN:/usr/bin:/bin" \
    bash "$CHECK_SCRIPT"
}

write_agents yes
output="$(run_check)"
grep -Fq '@danielsogl/lighthouse-mcp' <<< "$output" || { printf 'FAIL: npm package check missing\n' >&2; exit 1; }
grep -Fq 'CodeGraph 自动初始化' <<< "$output" || { printf 'FAIL: CodeGraph AGENTS check missing\n' >&2; exit 1; }
grep -Fq 'context7 官方文档优先' <<< "$output" || { printf 'FAIL: context7 AGENTS check missing\n' >&2; exit 1; }
grep -Fq 'anysearch 联网搜索优先' <<< "$output" || { printf 'FAIL: anysearch AGENTS check missing\n' >&2; exit 1; }
grep -Fq 'grill-me skill' <<< "$output" || { printf 'FAIL: optional grill-me skill check missing\n' >&2; exit 1; }
grep -Fq 'npx skills add mattpocock/skills --skill grill-me --agent codex --global --yes' <<< "$output" || { printf 'FAIL: grill-me Codex install command missing\n' >&2; exit 1; }
grep -Fq 'Codex Memories' <<< "$output" && { printf 'FAIL: enabled memories reported missing\n' >&2; exit 1; }
grep -Fq 'Codex multi_agent' <<< "$output" && { printf 'FAIL: enabled multi_agent reported missing\n' >&2; exit 1; }
grep -Fq 'OpenAI Developer Docs MCP 已配置' <<< "$output" || { printf 'FAIL: docs MCP check missing\n' >&2; exit 1; }
grep -Fq 'Vercel MCP 已配置' <<< "$output" || { printf 'FAIL: resolved project-scope MCP state not used\n' >&2; exit 1; }
grep -Fq 'GITHUB_PAT_TOKEN 已注入' <<< "$output" || { printf 'FAIL: injected GitHub token not detected\n' >&2; exit 1; }
grep -Fq 'node_repl command 不存在' <<< "$output" && { printf 'FAIL: disabled node_repl should be ignored\n' >&2; exit 1; }

set +e
output="$(TEST_GITHUB_PAT_TOKEN= TEST_GH_TOKEN_AVAILABLE=true run_check 2>&1)"
status=$?
set -e
[ "$status" -eq 1 ] || { printf 'FAIL: enabled GitHub plugin without env token should fail\n' >&2; exit 1; }
grep -Fq 'GITHUB_PAT_TOKEN 未注入（gh 已登录）' <<< "$output" || { printf 'FAIL: missing GitHub token not reported\n' >&2; exit 1; }
grep -Fq 'export GITHUB_PAT_TOKEN="$(gh auth token 2>/dev/null)"' <<< "$output" || { printf 'FAIL: safe GitHub token fix missing\n' >&2; exit 1; }
grep -Fq 'fixture-gh-token-must-not-leak' <<< "$output" && { printf 'FAIL: gh token leaked to output\n' >&2; exit 1; }

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
  {"pluginId":"codex-security@openai-api-curated","installed":true,"enabled":true},
  {"pluginId":"ponytail@ponytail","installed":true,"enabled":true}
]}
EOF
rm -rf "$TEST_CODEX_HOME/plugins/cache"
output="$(run_check)"
grep -Fq 'ponytail@ponytail（installed + enabled）' <<< "$output" || { printf 'FAIL: resolved plugin state not used\n' >&2; exit 1; }
rm "$TMP_ROOT/plugin-list.json"
for key in github superpowers build-web-apps codex-security; do
  mkdir -p "$TEST_CODEX_HOME/plugins/cache/openai-api-curated/$key/v1"
done
mkdir -p "$TEST_CODEX_HOME/plugins/cache/ponytail/ponytail/v1"

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
[ "$status" -eq 1 ] || { printf 'FAIL: missing plugin cache should fail\n' >&2; exit 1; }
[ "$(grep -Fc 'superpowers@openai-api-curated' <<< "$output")" -eq 1 ] || { printf 'FAIL: plugin failure should be counted once\n' >&2; exit 1; }

printf 'PASS: codex baseline checks\n'
