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

## UI and Secret Safety

- Codelab is iframe-heavy. Prefer authenticated Jupyter APIs for transfer/execution and semantic UI for lifecycle controls.
- If UI upload is required, the toolbar uses a native file chooser; do not assume a permanent `input[type=file]` exists.
- Model detail pages may render a Git clone command containing the access token. Never log/snapshot the model-introduction panel; navigate directly to `模型空间`, and redact credential-shaped text from all browser output.
- Do not publish a project, attach private datasets/models, start paid resources, or delete a user-owned project without explicit authorization. Test-created artifacts may be deleted after successful verification.

