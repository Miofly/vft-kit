# Notebook / PAI-DSW Operations

Verified against the domestic ModelScope web application on 2026-08-18.

## Authentication Boundary

| Surface | Authentication | Base path |
|---|---|---|
| Studio deployment | `Authorization: Bearer $MODELSCOPE_API_KEY` | `/openapi/v1/studios` |
| Notebook / PAI-DSW | authenticated ModelScope browser cookie | `/api/v1/notebooks` |

A valid Bearer token does not authenticate Notebook calls. Run them inside the already authenticated browser
session. Do not extract, print, or persist the login cookie.

The ModelScope page session and the PAI-DSW gateway session are separate. `Status=Running` proves only that the
instance is ready; opening `JupyterlabUrl` may still redirect to `account.aliyun.com`. When that happens, hand the
same task space to the user for the gateway login and resume only after explicit confirmation. A
`dsw_gateway_token` is bound to one instance path: never copy or replay it for a new instance, because the gateway
rejects it with `403 Access forbidden`.

### Preferred no-manual-login path: ModelScope Code Workspace

For ModelScope-managed free Notebook instances, open `https://modelscope.cn/code/workspace` and use **连接运行时**.
This ModelScope page uses the authenticated ModelScope session to obtain the current instance bridge information, calls
the platform's internal `gateway-login` handshake, and then connects the editor/runtime. It avoids opening the raw
`JupyterlabUrl`, which is the path that can redirect to `account.aliyun.com`.

- Start or inspect the instance through the normal ModelScope Notebook page first.
- Reuse the same ego-browser task space and ModelScope cookie for Code Workspace.
- Select the existing instance in **连接运行时**; do not manually reconstruct or log the internal token/URL.
- Treat a failed bridge handshake as a platform/session issue and hand the same task space to the user; do not switch
  to an old `JupyterlabUrl` or replay a token from another instance.

### Optional PAI-DSW OpenAPI gateway path

If a RAM/STS credential is available for the same Alibaba Cloud PAI workspace, a non-interactive gateway path may be
used. This is Alibaba Cloud authentication, not a ModelScope or DashScope API key:

1. Use the credential to call PAI-DSW `GetInstance` and confirm the current `dsw-*` instance belongs to the expected
   workspace.
2. Run a read-only `GetToken` probe before any resource mutation. Request `Type=Access`, `Audience=ThirdParty`, and
   a short TTL; use the returned token only for the current instance and never persist or print it.
3. If the probe returns `403` or `NotFound`, treat it as an account/workspace boundary. Fall back to the same-task-space
   browser handoff; do not retry GPU starts or reuse a token from another instance.

The RAM principal should have only the required `paidsw:*` actions. ModelScope's free Notebook may be managed by a
different Alibaba Cloud workspace, so a valid RAM credential is not proof that this path will work.

## Safe Workflow

1. Open `$MODELSCOPE_ENDPOINT/my/mynotebook/preset` in an authenticated browser session.
2. Read specs, images, and current instances before making changes.
3. Confirm accelerator type and whether the resource is free or billable.
4. Start only with a fresh `CaptchaVerify` issued by the page's safety-verification widget.
5. Poll the instance list until it reaches `Running` or a terminal failure state.
6. Return the instance ID, status, image, and opening URL without exposing session credentials.

## Fast Automation Contract

After the user has authorized the task and any resource cost, complete ordinary Notebook operations end to end.
Do not pause for each reversible step.

1. Reuse one named ego-browser task space and its authenticated tab. Do not open parallel login sessions.
2. Use `browserFetch` against the authenticated web APIs for state reads and writes; use the rendered UI only when
   the API contract is unknown or ModelScope requires interactive verification.
3. Batch specs, images, and instance-list reads. Poll transitions every 3-5 seconds instead of repeatedly taking
   full-page snapshots.
4. After a selection or navigation rerenders the page, reacquire the target with a stable selector. Never reuse an
   old snapshot ref. Accelerator radios have stable values such as `input[type="radio"][value="GPU"]`.
5. Verify every mutation from the API or remote filesystem before reporting success.
6. Pause only for a fresh CAPTCHA, explicit paid-resource authorization, or an unclear destructive target.

If a task space was handed to the user, do not seize it back. Resume only after the user confirms completion, then
use the ego-browser takeover flow for that same task space.

Browser-side reads can use the page's existing cookie:

```javascript
const get = (path) => fetch(path, { credentials: "include" }).then((r) => r.json());

const [specs, images, instances] = await Promise.all([
  get("/api/v1/notebooks/specs?Channel=dsw"),
  get("/api/v1/notebooks/image?AcceleratorType=CPU"),
  get("/api/v1/notebooks?Channel=dsw"),
]);
```

## Endpoints

| Operation | Method | Path |
|---|---|---|
| List resource specs and quota | GET | `/api/v1/notebooks/specs?Channel=dsw` |
| List images | GET | `/api/v1/notebooks/image?AcceleratorType={CPU|GPU|AMD}` |
| List current/history instances | GET | `/api/v1/notebooks?Channel=dsw` |
| Start an instance | POST | `/api/v1/notebooks` |
| Stop an instance | PUT | `/api/v1/notebooks/stop` |

Do not guess mutation request bodies. Read the current frontend request or let the UI submit the operation, then
poll `GET /api/v1/notebooks?Channel=dsw` by instance ID. Instance IDs and image versions are runtime state and must
not be stored in a skill.

The web application currently sends this start payload:

```json
{
  "Channel": "dsw",
  "AcceleratorType": "CPU",
  "Image": "<Version returned by the image API>",
  "CaptchaVerify": "<fresh platform-issued verification result>"
}
```

`CaptchaVerify` is a security control, not reusable configuration. Never omit, forge, replay, log, save, or
commit it. If verification appears, hand the same browser session to the user. After they finish, resume in that
session so the page can submit the fresh result normally.

## States

Treat `Running` as ready. Continue polling transitional states such as `Creating`, `Starting`, or `Pending`.
Treat `Failed`, `Stopped`, and `Deleted` as terminal for the current attempt and report the API's error details.

Do not start a paid resource without explicit user authorization. A displayed quota does not prove the next
instance is free; trust the current spec response and page labels.

## CPU Prepare, GPU Run

Use the cheapest suitable resource for each stage:

- CPU: dependency checks, source upload, model download, preprocessing, config generation, syntax checks, and
  persistent-cache preparation.
- GPU: CUDA-only model loading, inference, training, and GPU result verification.

Put all cross-stage artifacts under `/mnt/workspace`. Before stopping CPU, verify the script, required model config
and weight shards, log completion marker, and hashes where a local source file is available. Then stop CPU, select a
currently available free GPU, start it, run only the GPU stage, verify the output, and stop GPU unless the user asks
to keep it running. Never start GPU for a CPU-only task.

Do not trust `df -h /mnt/workspace` as an account-quota check. The mount can advertise a very large shared
filesystem while a small real write fails with `Disk quota exceeded`. Probe an actual task-owned file before large
downloads. If the account quota is exhausted, stage on instance-local `/tmp`, store durable inputs/results in a
private Dataset, verify the uploaded bytes, and remove only the task-owned zero-byte placeholders or temporary
copies.

Make stages explicit and rerunnable, for example `JOB_STAGE=prepare` and `JOB_STAGE=run`. A rerun must resume or
skip completed downloads rather than duplicate them.

Before switching to GPU, require all applicable gates:

- source model/code revisions are immutable and recorded;
- the requested model scope is complete (see below), with no `.incomplete` or temporary shards;
- weight indexes resolve to non-empty files and safetensors headers parse;
- source and destination size/SHA-256 manifests match;
- code compiles, runner syntax passes, and required input assets exist;
- dependencies for the GPU image's actual Python ABI are cached without replacing its Torch/Triton build;
- a tiny device/backend preflight runs before model weights are loaded;
- the runner treats a missing output artifact as failure even when upstream code catches exceptions and exits zero.

## Workspace File Transfer

ModelScope has two distinct file surfaces:

- `/mnt/workspace`: the persistent filesystem mounted into the active DSW instance.
- ModelScope Workspace gallery files: managed by `/api/v1/gallery/editor/files*`; uploading here does not prove the
  file exists under `/mnt/workspace`.

The authenticated gallery upload flow is:

1. `POST /api/v1/gallery/editor/files/upload` with `{"FileNames":["name"]}`.
2. Read `Data.Urls[0].Url` without printing it.
3. `PUT` bytes to that signed URL as `application/octet-stream`.

The download flow is `POST /api/v1/gallery/editor/files/download?Channel=dsw` with the same `FileNames` body, then
fetch the returned signed URL. Signed URLs are temporary credentials: never log or persist them.

For a small script that must exist in `/mnt/workspace`, writing base64-decoded bytes through the DSW terminal is
more reliable than pasting into Monaco. For larger artifacts, use a short-lived signed transfer. Always compare
byte count or SHA-256 after transfer.

## Terminal Automation

Code Workspace is a virtualized IDE. Treat its terminal/editor surface as visual UI:

- If the iframe viewport is `0x0`, set CDP device metrics and verify dimensions before coordinate input.
- Do not paste substantial source into Monaco without a tiny write/readback probe.
- Redirect diagnostics to a uniquely named text file when terminal canvas output is hard to inspect.
- Start long CPU work with a detached command:

```bash
nohup env JOB_STAGE=prepare python /mnt/workspace/job.py \
  > /mnt/workspace/job-prepare.log 2>&1 < /dev/null &
echo $! > /mnt/workspace/job-prepare.pid
```

Immediately verify both the PID file and `pgrep -af`. Before retrying, confirm the prior PID is gone; duplicate
downloaders can corrupt or waste the same target. Monitor a completion marker plus artifact growth, not progress-bar
text alone. Remove only task-owned probes and failed partial artifacts after the final verification.

## Model Downloads In DSW

Prefer ModelScope's native downloader inside DSW. External Hugging Face endpoints may be unreachable even when
the matching ModelScope repository is available.

### Freeze the requested scope first

Do not silently reinterpret "complete/full/all files/no omissions" as a minimal inference download.

- **Complete archive:** recursively enumerate every source `blob` at a pinned revision. That exact path, size, and
  SHA-256 set is the acceptance criterion, including dotfiles, root metadata, training/ODE checkpoints, and files
  not used by the first inference command.
- **Runtime closure:** download only what a named entry point actually loads. Record the excluded prefixes and keep
  this separate from the complete archive.

If the complete archive exceeds the Workspace quota, use a private Dataset as durable storage and process one
prefix at a time: download to the final staging path, reject partial files, verify against the source API, upload
with resumable cache, verify the Dataset API, then delete only that verified local prefix. After the archive is
complete, materialize just the runtime closure locally for GPU use. Never compress safetensors merely to fit them;
it removes per-shard resume and normally saves little space.

Repository tree endpoints differ:

- model/studio files: `GET /api/v1/models/{owner}/{repo}/repo/files`;
- Dataset files: `GET /api/v1/datasets/{owner}/{repo}/repo/tree`.

Use `Revision`, `Root`, and `Recursive=true`. Dataset tree responses can stop at 100 entries even with
`Recursive=true`; query each top-level root and merge the results. Compare source and Dataset `blob` entries, not
directory/tree entries. A successful upload command alone is not the final verification.

If one invalid file makes a folder commit fail with `commit rejected by repository policy`, remove generated
metadata such as `.git` and `__pycache__`, then retry by root or individual file to isolate the rejected path. Finish
with a fresh download into an empty directory and compare content, not only the upload report.

For runtime closure mode, a Diffusers pipeline usually needs its component directories but not every root-level
checkpoint:

```python
from modelscope import snapshot_download

snapshot_download(
    model_id="<modelscope-owner>/<model>",
    local_dir="/mnt/workspace/models/<model>",
    allow_patterns=[
        "model_index.json",
        "scheduler/*",
        "text_encoder/*",
        "tokenizer/*",
        "transformer/*",
        "vae/*",
    ],
)
```

Keep model files under `/mnt/workspace` so CPU preparation can be reused after switching the instance to GPU.
Verify the model config and required weight shards before stopping the CPU instance.

### Dependency cache across CPU and GPU images

Check `python3 -V`, `torch.__version__`, and `torch.version.{cuda,hip}` inside each actual instance; image labels
are not proof of the runtime ABI. If CPU and GPU Python ABIs differ, do not carry a CPU-created venv across the
switch. Download wheels for the GPU ABI on CPU (`pip download --python-version ... --only-binary=:all:`), then
create a `--system-site-packages` venv on GPU and install from that wheelhouse.

Never install PyPI `torch`, `torchvision`, `torchaudio`, or generic `triton` over the GPU image's vendor build. For
ROCm, require `torch.version.hip`, exclude NVIDIA-only helpers from the inference dependency set, and validate a
tiny PyTorch attention/kernel operation before loading the model. Keep optional training/evaluation dependencies
in the complete source requirements even when they are not part of the inference wheelhouse.

With `--system-site-packages`, an optional package already present in the image can activate an integration that the
project never uses and conflict with its pinned dependencies. Test the project's real top-level imports in a fresh
venv, not only `pip install`. Prefer a project-scoped compatibility shim or clean environment over changing the
vendor Torch/CUDA stack or globally uninstalling image packages.

## Browser Handoff

With ego-browser, keep one named task space for the operation. Use `handOffTaskSpace` when ModelScope presents
interactive verification, then `takeOverTaskSpace` after the user confirms completion. Do not open a second
session because the verification result belongs to the original authenticated page.

After the Code Workspace opens, select its exact tab before terminal automation. The wrapper page contains the
same-origin `iframe[title="notebook-ide"]`; terminal elements live inside that document, not the outer page. If the
user opened a workspace outside the assigned task space, do not seize it during a handoff. Resume only after the
user explicitly asks the agent to continue, then work in the confirmed workspace session.
