# Hugging Face Ops Skill Design

## Goal

Add a public `vft-kit:huggingface-ops` skill that can operate the full Hugging Face Hub surface without embedding private credentials or duplicating the official client.

## Scope

The skill covers every operation exposed by the current `hf` CLI, including authentication, models, datasets, Spaces, repositories, files, buckets, collections, discussions, papers, Jobs, Inference Endpoints, sandboxes, webhooks, cache, sync, extensions, and skills.

For Hub operations not exposed by the CLI, the skill provides an authenticated `huggingface_hub.HfApi` execution path. Space variables, secrets, logs, runtime, hardware, storage, restart, duplication, and repository settings are first-class documented workflows.

## Architecture

Create only these reusable files:

- `plugins/vft-kit/skills/huggingface-ops/SKILL.md`: routing, safety rules, common commands, and CLI-versus-SDK selection.
- `plugins/vft-kit/skills/huggingface-ops/scripts/hf.sh`: credential loading and transparent official CLI execution.
- `plugins/vft-kit/skills/huggingface-ops/scripts/hf-api.py`: narrow generic `HfApi` method invocation for SDK-only methods.
- `plugins/vft-kit/skills/huggingface-ops/tests/test-hf.sh`: credential and forwarding regression checks.
- `plugins/vft-kit/skills/huggingface-ops/agents/openai.yaml`: Codex UI metadata.

The scripts use installed official tools when present and otherwise run `huggingface_hub` through `uvx`/`uv`. No custom Hugging Face REST client is added.

## Credentials

Resolve credentials in this order:

1. `HF_TOKEN` environment variable.
2. Explicit `--config <json>` containing `token`, `access_token`, `api_token`, or `key`.
3. Hugging Face's standard locally saved token.

The private `vft-ai` secret path is supplied explicitly at runtime and never hard-coded into the public `vft-kit` repository. Tokens must not appear in process arguments, command output, or error messages.

## Command Flow

`hf.sh` removes its own `--config` option, exports the resolved token as `HF_TOKEN`, then forwards all remaining arguments unchanged to the official `hf` CLI. This automatically inherits new official subcommands without skill changes.

`hf-api.py` accepts an `HfApi` method name and JSON keyword arguments, resolves the same credential sources, calls the official SDK, and emits JSON-safe output. It exists only for operations missing from the CLI.

## Safety

Read-only listing, inspection, logs, status, and downloads may run directly.

Before deleting or moving repositories, deleting remote files, replacing secrets, changing paid hardware/storage, or starting billable Jobs/Endpoints, resolve the exact target and obtain explicit user confirmation. Never print secret values; secret listings may show keys and metadata only.

## Verification

Follow RED-GREEN-REFACTOR:

1. Record a baseline agent failure without the skill.
2. Add shell tests that fail until token precedence, redaction, `--config` stripping, and argument forwarding exist.
3. Implement the minimum scripts and skill text.
4. Run shell syntax checks, regression tests, `quick_validate.py`, and repository-specific skill checks when available.
5. Run live read-only checks against `vftfnn/wfly-spring` using the stored credential.
6. Refresh Claude Code and Codex plugin caches and compare source/cache hashes.

## Non-goals

- Reimplementing the Hugging Face API.
- Storing credentials in `vft-kit`.
- Adding wrappers for every official subcommand.
- Performing destructive or billable live tests.
