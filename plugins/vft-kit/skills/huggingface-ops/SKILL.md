---
name: huggingface-ops
description: Use when requests involve Hugging Face or HF Hub models, datasets, Spaces/创空间, repositories, files, uploads, downloads, Variables, Secrets, environment variables, logs, runtime, hardware, storage, restarts, duplication, Jobs, Inference Endpoints, sandboxes, buckets, collections, discussions or PRs, papers, webhooks, cache or sync, authentication, or token verification.
---

# Hugging Face Ops

## Run operations

Treat `<skill-dir>` as the directory containing this loaded `SKILL.md`. Always resolve it from the loaded skill path, never from the current working directory.

Prefer the official CLI through the pass-through launcher:

```bash
bash "<skill-dir>/scripts/hf.sh" [--config <credential.json>] <official hf args>
```

Run the relevant `... --help` before choosing current syntax. Pass arbitrary official subcommands through; do not maintain manual wrappers or catalogs.

Resolve credentials in this order: `HF_TOKEN`, explicit `--config <json>` using the first supported field (`token`, `access_token`, `api_token`, or `key`), then the official saved token. Never print token/config contents or secret values.

Use the SDK only when the CLI lacks the operation. Check current official documentation and the `HfApi` method signature first:

```bash
python3 "<skill-dir>/scripts/hf-api.py" [--config <credential.json>] <HfApi method> --kwargs '<JSON object>'
```

## Quick reference

| Need | Start with; inspect help for exact current syntax |
| --- | --- |
| Auth/status | `bash "<skill-dir>/scripts/hf.sh" auth --help`; then inspect `whoami` or token verification |
| Models/datasets/Spaces/repos | Run launcher with `models --help`; likewise `datasets`, `spaces`, `repos`; list first |
| Download/upload/sync | Run launcher with `download --help`, `upload --help`, then inspect cache/sync help |
| Space variables/secrets | Run launcher with `spaces --help`; inspect variable/secret commands and exact Space ID |
| Logs/runtime/settings | Run launcher with `spaces --help`; inspect logs, runtime, restart, duplicate, hardware, storage |
| Jobs/Endpoints/sandbox | Run launcher with `jobs --help`; inspect Inference Endpoint and sandbox help |
| Buckets/collections/discussions/webhooks | Run launcher with `--help`; open the relevant group, including PRs and papers |
| SDK fallback | `python3 "<skill-dir>/scripts/hf-api.py" list_models --kwargs '{"limit": 5}'` |

## Safety

Run read-only inspect/list/log/status/download operations directly. Before delete, move, replace, remote file deletion, paid hardware/storage, or billable Jobs/Endpoints, inspect current state, resolve the exact target, and obtain explicit confirmation unless the current request already names that exact target and action. For every mutation, inspect current state first and verify resulting state afterward; for Secrets, verify key/metadata/restart status only, never value readback.

Warn that Space secret, variable, and hardware changes can restart the Space. Use Variables for non-sensitive values and Secrets for sensitive values. Treat secret listing as key/metadata inspection only; never attempt value readback.

## Common mistakes

- Do not use `--token "$(...)"`; argv can leak credentials.
- Do not hard-code private paths.
- Do not invent CLI syntax; run `--help`.
- Do not use the SDK when the CLI covers the operation.
- Do not reimplement the official clients with raw REST.
