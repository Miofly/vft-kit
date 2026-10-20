---
name: aistudio
description: "Operate Baidu AI Studio repositories, files, points, courses, contests and Notebook CPU/GPU sessions via SDK or browser; includes project startup and background jobs."
---

# Baidu AI Studio

Operate AI Studio repositories through the official SDK, and website-only work (login, points, projects, Notebook, GPU, tasks) through one ego-lite task space.

## When to use

- Model/app creation, model/dataset upload, download or file check on AI Studio.
- Login, projects, Fork, courses, contests, daily points, Notebook CPU/GPU, model-pipeline jobs, script tasks, Notebook background tasks.

## 浏览器到 API 的强制演进

本 skill 只要以浏览器执行远端业务动作，就必须先读并遵守 [浏览器到 API 强制演进](../../BROWSER_API_EVOLUTION.md)。登录、验证码、2FA、纯视觉验收可保留浏览器；认证后的可接口化动作仍须抓取、复现、独立回验，并在同一任务自更新本 skill 与脚本。

## Core flow

1. Read [policies.md](references/policies.md): API first, ego-lite before Playwright, safety.
2. Route the request with the table below; read the referenced file completely before acting.
3. Inspect the target (remote repo, live page, hardware, price, balance) before any mutation.
4. Act through the script or API; use the browser only for login, captcha/2FA handoff, unknown steps and final checks.
5. Verify business state after the action, not just the transport result.
6. Stop runtimes and close the task space with `keep: false` unless the user asks otherwise.

## Hard rules

- Require `AISTUDIO_ACCESS_TOKEN` in env; never accept or print it in argv, logs, prompts or output.
- Never treat an access token as a website login credential, and never use it to bypass web login.
- Never ask for, read, store, inject or replay cookies or passwords.
- If `ego-browser` exists, use one dedicated ego-lite task space; never use Playwright while ego-lite exists.
- Isolate a second account by ego-lite profile, not by task space.
- Repository creation is private by default; require `--public` for public.
- A request timeout has unknown outcome: inspect the remote account before retrying.
- A `免费资源` GPU still consumes points; paid resources need explicit confirmation of the displayed cost.
- Stop the runtime after the task and verify `未运行`; closing the browser does not stop billing.
- Require confirmation before commenting, publishing, contest registration with terms, or destructive changes.
- Never mass-create, duplicate or perform activity whose main purpose is gaming points.
- Daily acceptance reads today's live points panel after reload; historical state or exit=0 is not proof.

## Routing table

| Task | References | Script |
|---|---|---|
| API-first rules, browser choice, safety | [policies.md](references/policies.md) | — |
| Model/app creation, model/dataset upload, download, file check | [sdk.md](references/sdk.md) | `uv run --with aistudio-sdk python3 scripts/aistudio.py` |
| App code upload | [sdk.md](references/sdk.md) (SDK 0.3.9 transfers only `model`/`dataset`; use web/Git) | — |
| Login, second account, dedicated scheduled space | [browser-login.md](references/browser-login.md) | ego-lite task space |
| Sign-in, Fork, courses, contests, daily points acceptance | [points.md](references/points.md) | ego-lite task space |
| Notebook lifecycle, transfer, terminal, GPU, paid cold start | [notebook.md](references/notebook.md) | `scripts/notebook_api.mjs`, `scripts/gpu_probe.py` |
| Model-pipeline jobs, script-task projects, Notebook background tasks | [tasks.md](references/tasks.md) (+ [notebook.md](references/notebook.md) when starting from a Notebook) | official AI Studio CLI / website session |

