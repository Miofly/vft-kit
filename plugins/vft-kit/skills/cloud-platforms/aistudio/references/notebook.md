# Notebook Operations

Verified against AI Studio BML Codelab on 2026-08-18. Notebook lifecycle uses the authenticated website session, not `AISTUDIO_ACCESS_TOKEN`.

## Lifecycle

1. Reuse one ego-browser task space and open `https://aistudio.baidu.com/my/project`.
2. Choose `创建项目` -> `Notebook`, enter a name, select JupyterLab or VS Code, and create it. Verify the resulting project ID, name, IDE, and privacy state.
3. Open `专业开发`, inspect the current resource tabs, price/points, quota, and balance. The basic CPU item is safe only when the current UI shows `0.0 点/小时`. GPU consumes points even under `免费资源`; require the user's GPU authorization and report the displayed rate.
4. Start the selected environment and wait for the project state to reach running or for navigation to a Codelab URL. Treat failure/insufficient quota as terminal.
5. Transfer files, execute the requested work, and verify output as below.
6. Return to `我的项目`, open the running-state menu, choose `停止运行`, and poll until `未运行`. Closing the browser is not a stop operation.

Project IDs, region prefixes, Codelab URLs, and runtime state are dynamic. Never store them in a skill.

## Codelab Base URL

Derive the Jupyter server base from the active Codelab URL. A current example is:

```text
https://aistudio.baidu.com/<region>/user/<owner>/<project-id>/home#codelab
```

The base is everything through `<project-id>/`. Use `browserFetch` so the existing browser session supplies authentication. Never extract or persist cookies.

## Workspace Transfer

List files with `GET <base>api/contents/`. Upload through the standard Jupyter Contents API:

```javascript
import fs from 'node:fs'
import crypto from 'node:crypto'

const local = fs.readFileSync('/absolute/local/file')
await browserFetch(base + 'api/contents/target-dir', {
  method: 'PUT',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({type: 'directory'}),
})
await browserFetch(base + 'api/contents/target-dir/file', {
  method: 'PUT',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({type: 'file', format: 'base64', content: local.toString('base64')}),
})
const remote = JSON.parse(await browserFetch(base + 'api/contents/target-dir/file?content=1'))
const bytes = Buffer.from(remote.content, remote.format === 'base64' ? 'base64' : 'utf8')
if (!local.equals(bytes)) throw new Error('workspace upload verification failed')
cliLog(JSON.stringify({path: remote.path, size: remote.size, sha256: crypto.createHash('sha256').update(bytes).digest('hex')}))
```

Use `GET ...?content=1` for downloads and compare byte count or SHA-256. Use `DELETE <base>api/contents/<path>` only for an exact task-owned target.

## Terminal Execution

Create a terminal with `POST <base>api/terminals`, connect to `<base>terminals/websocket/<name>` using `wss`, send `['stdin', '<command>\r']`, and wait for a unique completion marker. The terminal echoes the command, so require the marker twice before treating it as completed. Delete the terminal with `DELETE <base>api/terminals/<name>` afterward.

Run `scripts/gpu_probe.py` after transfer. Verify Python, GPU/CPU, CUDA, Paddle/PyTorch, network, working directory, and the completion marker. Keep durable files under `/home/aistudio`; `/home/aistudio/data` is mounted data and may reset.

## Long-running Commands

Terminal websockets live in the page: a navigation or new heredoc round drops the `window` globals, and one `js()` call must not block for minutes. For anything long (pip installs, weight downloads) launch detached and poll the log instead of holding the socket:

1. Upload the script via Contents API.
2. `nohup bash <script> > <script>.log 2>&1 & echo MARK` — require MARK twice (terminal echoes the command).
3. Poll `GET <base>api/contents/<script>.log?content=1`; branch on phase/DONE/FATAL lines.

Contents API GET may return `format: "text"` even when the upload used base64 — always decode with the returned `format`, or byte-equality upload verification false-fails.

If `pageInfo()` reports a 0×0 viewport (coordinate clicks and screenshots die), fix with `cdp('Emulation.setDeviceMetricsOverride', {width: 1680, height: 1050, deviceScaleFactor: 1, mobile: false})`.

## BML Environment Gotchas

Verified 2026-08-19 on CPU 基础版 (2C/8G, overlay ~888G free, conda python3.10):

- pip bakes `user=true`; every venv install dies with "Can not perform a '--user' install" → `export PIP_USER=0`.
- Pin `huggingface_hub==0.25.2` for old stacks: 1.x removed `huggingface-cli` and breaks `transformers==4.42` import.
- CPU torch wheels do not pull triton; repos with top-level `import triton` need explicit `pip install triton==3.0.0`.
- Egress: huggingface.co and hf-mirror.com dead; `hf-api.gitee.com` (HF-compatible API) works but mirrors can be stale — compare the repo `lastModified` against the target files' release date before trusting it; modelscope.cn reachable but may lack the repo; kaggle.com reachable.
- Stop runtime from the my/project card: dropdown arrow beside the 运行中 status → 停止运行. The edit page exposes no stop control; poll the card until 未运行. The arrow is an `.anticon` inside the status container — coordinate clicks hit the card link instead, dispatch a bubbling click on the icon via DOM.
- Environment stop/start/switch snapshots the persistent home: a venv (tens of thousands of files) or pip cache (~2.3G per torch round) alone trips 「文件过多过大，无法切换」. Use `pip --no-cache-dir` everywhere and clean venv/cache/weights before switching; keep everything re-downloadable. Template: `java/wfly-spring/aistudio/magi1/clean_for_switch.sh`.

## Weight Relay for Blocked Egress

When the instance cannot reach HF and no fresh mirror carries the files: relay through a Kaggle VM (GCP reaches HF fast). Private kernel loops `hf_hub_download` per file → `aistudio_sdk.hub.upload_file` into a **public** Baidu model repo → delete local file; the notebook then `snapshot_download`s the public repo anonymously at intranet speed (~400MB/s). Keep the Baidu token as a placeholder in the repo copy, inject into the push copy only, delete the kernel right after the relay. Working template: `java/wfly-spring/aistudio/magi1/relay/`.

## V100 (SM70) Model Porting Gotchas

Verified 2026-08-19 running MAGI-1 4.5B-distill on V100 32GB (driver 570, cu124 OK). Newer-model repos target Hopper/Ampere; on V100 expect all of these:

- No flash-attn/flashinfer wheels for SM70. Replace via PYTHONPATH shim package with the same module layout (`flash_attn/__init__.py` etc.) using `F.scaled_dot_product_attention`. SDPA 2.4 lacks `enable_gqa` → GQA models (q heads > kv heads) need manual `repeat_interleave` on kv; varlen variants loop over `cu_seqlens`; rotary must implement rotate-half with cos/sin aligned to q's -3 dim. Template: `java/wfly-spring/aistudio/magi1/gpu/gpu_shim/`.
- Checkpoints ship bf16; V100 has no bf16 tensor cores. Cast state_dict `.half()` at load, sed `torch.bfloat16` literals → fp16, and hunt hardcoded `.bfloat16()` casts + `torch.autocast(..., dtype=torch.bfloat16)` blocks (VAE decoders love both) → fp32 for the VAE side.
- cuDNN fp16/bf16 conv3d fails "too many resources requested for launch" on SM70 — and so does native fp16 conv3d under autocast. Wrap `F.conv2d/conv3d` globally to compute fp32 and set `torch.backends.cudnn.enabled = False` if needed.
- Dtype salad is inevitable after mixed patches: add global `Linear.forward` / `LayerNorm.forward` guards casting input to weight dtype, and cast text-encoder outputs to the DiT dtype at the handoff.
- pip routing: pure `download.pytorch.org` index crawls (nvidia-* dep chain ~100KB/s). Use tsinghua as `--index-url` (nvidia wheels ~4MB/s) + cu124 as `--extra-index-url` for the torch wheel itself, `--timeout 600 --retries 20`.
- Instances have no `rg` — scripts must use grep, or patch steps silently no-op (costs ~30min of GPU billing to notice; assert patch markers in logs).
- Killed demo processes hold MASTER_PORT; `pkill -9 -f entry.py && fuser -k <port>/tcp` before relaunch.
- **HTTP 492 / Jupyter unreachable right after boot is usually NOT a dead container — it is snapshot restore.** On every start the platform re-downloads the persistent `/home/aistudio` snapshot into the fresh container; until that finishes, Jupyter answers 492 / 「数据未下载完，请稍后重试」. Read the platform's literal status text before acting. Restarting interrupts and resets the restore, so a restart-loop on 492 bills points for zero progress (lost ~1-2 points this way on 2026-08-20). Paid-GPU discipline: after starting, observe ≥10 min before touching anything; max 2 restarts per session, each with a one-line justification; quote the platform's exact status text in reports before acting on it. A multi-GB persistent home (tars/weights) makes every boot's restore slow and is the predisposing cause — keep big artifacts in the Baidu library and delete local copies; keep home small. Liveness truth source stays the my/project list card, never the edit-page chip. Separately real: the 16GB「限时池」is preempted after ~10 min — that IS a true death; fit jobs inside the window instead of fighting it.
- Region host prefixes are meaningless: a V100 container was served under `bj-cpu-01`. Discover the real base by clicking 专业开发 and reading the navigation URL.
- Fresh GPU containers may boot with an EMPTY /home/aistudio (snapshot per env-switch): be ready to re-upload the whole script tree. Contents API PUT can 405 on some containers — fall back to terminal stdin `echo <base64> | base64 -d > file`.
- Pool reality 2026-08-20: V100 32GB option greyed out (pool gone); V100 16GB selectable but flaky; 异构算力 DCU unsupported for Notebook projects (tooltip); BI-V150S 32GB is Iluvatar (天数智芯) — needs vendor torch, NVIDIA cu124 venv/stack NOT portable, treat as last resort.
- Pool reality 2026-08-20 evening recheck: V100-32GB AND 异构算力-16GB both `.disable`; V100-16GB / BI-V150S selectable; 基础版 active. CPU 基础版 dialog says RAM 8GB but host `free` shows ~470GB — 8GB is a cgroup cap (process hit 6.9GB RSS without OOM).
- H3 GGUF load-path verdict (2026-08-20, CPU 基础版): mmap of an 18GB file-backed file, all pages touched in 4GB chunks, peak VmHWM 6.85GB — kernel reclaims file pages under pressure, so 8GB cgroup does NOT OOM the mmap streaming load. VERDICT PASS. Overlay 2.9T (~1.6T free), 18GB write 39s. Spike script: `java/wfly-spring/aistudio/h3/h3_load_test.py`.

Full idempotent patch chain template: `java/wfly-spring/aistudio/magi1/gpu/apply_v100_full.sh`.

SDK upload gotcha (>5GB files): `hub.upload_file` routes <5GB through HTTP PUT but >5GB through STS/BOS multipart, and that path is broken in aistudio-sdk (`MyBosClient.put_super_obejct_from_file` calls a `super()` method the bce-python-sdk parent lacks; and `hub.py` judges success by `res is True`). Files >5GB silently fail with "upload lfs file failed / nothing to commit". Fix: monkey-patch multipart via parent primitives and return literal `True` — ready-made patch at `java/wfly-spring/aistudio/magi1/relay/bos_multipart_patch.py` (import before uploading). Alternatively upload >5GB files **from the instance itself** (BOS internal ~300MB/s) instead of the relay VM.

## UI and Secret Safety

- Codelab is iframe-heavy. Prefer authenticated Jupyter APIs for transfer/execution and semantic UI for lifecycle controls.
- If UI upload is required, the toolbar uses a native file chooser; do not assume a permanent `input[type=file]` exists.
- Model detail pages may render a Git clone command containing the access token. Never log/snapshot the model-introduction panel; navigate directly to `模型空间`, and redact credential-shaped text from all browser output.
- Do not publish a project, attach private datasets/models, start paid resources, or delete a user-owned project without explicit authorization. Test-created artifacts may be deleted after successful verification.

