# codex-baseline CC-Switch Auth Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `codex-baseline` automatically synchronize the active CC-Switch Codex API key and base URL into macOS Keychain and new zsh sessions.

**Architecture:** Keep `check.sh` read-only. Add a deterministic synchronization script plus a `run.sh` orchestrator that attempts synchronization and always runs the existing checker. Store secrets only in Keychain and maintain a marker-delimited `.zshrc` lookup block.

**Tech Stack:** Bash, Node.js JSON parsing, SQLite fallback, macOS `security`, Codex plugin CLI.

---

### Task 1: Add RED integration coverage

**Files:**
- Create: `plugins/vft-kit/skills/codex-baseline/tests/test-sync-cc-switch-openai-env.sh`
- Test: `plugins/vft-kit/skills/codex-baseline/scripts/sync-cc-switch-openai-env.sh`

- [x] Create a Bash test that builds a temporary `HOME`/`CODEX_HOME`, installs a PATH-local `security` stub, writes `auth.json` and `config.toml`, then invokes the missing sync script.
- [x] Assert that the first run writes both Keychain service values, creates exactly one managed zsh block, and never writes the raw key to `.zshrc` or stdout.
- [x] Invoke the script again and assert idempotency; change the active values and assert the stored values update.
- [x] Remove the key and assert a warning with exit code zero and no secret output.
- [x] Run `bash plugins/vft-kit/skills/codex-baseline/tests/test-sync-cc-switch-openai-env.sh` and verify RED fails because the sync script does not exist.

### Task 2: Implement synchronization and orchestration

**Files:**
- Create: `plugins/vft-kit/skills/codex-baseline/scripts/sync-cc-switch-openai-env.sh`
- Create: `plugins/vft-kit/skills/codex-baseline/scripts/run.sh`
- Modify: `plugins/vft-kit/skills/codex-baseline/SKILL.md`

- [x] Parse `OPENAI_API_KEY` from `${CODEX_HOME}/auth.json` with Node.js and resolve the selected `base_url` from `${CODEX_HOME}/config.toml`; use the active CC-Switch SQLite row only as a missing-field fallback.
- [x] On Darwin with complete values, call `security add-generic-password -U` for `CC_SWITCH_CODEX_API_KEY` and `CC_SWITCH_CODEX_BASE_URL` without printing either value.
- [x] Replace legacy/unmanaged lines and any existing marker block with exactly one block containing dynamic `security find-generic-password` exports.
- [x] Return zero with a warning for unsupported systems or incomplete values; return nonzero only for unexpected write failures.
- [x] Make `run.sh` attempt synchronization, report a warning on unexpected sync failure, then run `check.sh` and return only the checker status.
- [x] Update `SKILL.md` to call `run.sh`, document the permanent authorization and remove the blanket read-only claim while retaining read-only behavior for all other checks.
- [x] Run the Task 1 test and `bash -n` on all three scripts; expect all checks to pass.

### Task 3: Validate and deploy the local plugin update

**Files:**
- Modify: `plugins/vft-kit/.codex-plugin/plugin.json`
- Verify: Codex plugin cache under `~/.codex/plugins/cache/vft-kit/vft-kit/`

- [x] Run the skill validator and plugin validator against the source tree.
- [x] Run the new `run.sh` on the real machine; verify the Keychain values match the active CC-Switch files, `.zshrc` contains one managed block, and no plaintext key exists in `.zshrc`.
- [x] Run `update_plugin_cachebuster.py plugins/vft-kit` to replace the Codex cachebuster suffix.
- [x] Run `codex plugin add vft-kit@vft-kit` and verify `codex plugin list` reports the new version.
- [x] Compare source and installed-cache `SKILL.md`, sync script, and orchestrator checksums.
- [x] Run the installed-cache `run.sh` and repeat the secret-safe verification.
- [x] Commit only the planned source, test, documentation, and manifest changes; leave unrelated user changes untouched.
