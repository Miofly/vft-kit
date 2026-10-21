# Studio Deployment Troubleshooting

## Common errors

| Error signature | Cause | Fix |
|----------|------|----------|
| `ModuleNotFoundError: No module named 'xxx'` | Missing dependency | Add it to `requirements.txt` |
| `SyntaxError` | Python syntax error | Review and fix the code |
| `MemoryError` / `OOMKilled` | Out of memory | Optimize memory usage or upgrade hardware; if switching to a paid resource, first clearly state the cost risk and obtain explicit authorization from the user |
| `Permission denied` | File permission issue | `chmod +x` or check directory permissions |
| `FileNotFoundError` | Wrong file path | Check whether the file has been committed to Git |
| Variable is empty/None | Plaintext variable or secret not configured | Add it via OpenAPI; use secrets for sensitive information |
| `ImportError: cannot import name` | Version incompatibility | Pin the version in requirements.txt |

## Docker-specific errors

| Error signature | Cause | Fix |
|----------|------|----------|
| `Address already in use` | Port conflict | Make sure you listen on `0.0.0.0:7860` |
| `COPY failed: file not found` | Source file does not exist | Check the COPY path in the Dockerfile |
| `RUN` step fails | Dependency installation error | Check the pip/npm commands and the network |
| Image pull failure | The `FROM` base image is inaccessible | Use a domestic mirror source |
| Build timeout | Too many dependencies or the image is too large | Trim dependencies and use a multi-stage build |
| `exec format error` | Architecture mismatch | Make sure you use an amd64 base image |

## Deployment status

| Status | Meaning | Action |
|------|------|------|
| `Building` | Docker is building | Wait, and check the build logs |
| `Running` | Running | Normal |
| `Stopped` | Stopped | Call deployStudio to restart |
| `Failed` | Startup failed | Check the run logs to troubleshoot |
| `Sleeping` | Sleeping after a long period without access | Visit the URL to wake it automatically |

## Git push issues

| Error | Fix |
|------|------|
| `Authentication failed` | Check whether the Token is correct and not expired |
| `remote rejected` | Check whether the repository exists and whether permissions are sufficient |
| `LFS objects missing` | `git lfs install && git lfs push --all` |
| Merge conflict | `git checkout --ours . && git add . && git commit` |

## Troubleshooting flow

```
Deployment failed
│
├── Check the log type
│   ├── Docker → check the build logs first, then the run logs
│   └── Other → check the run logs directly
│
├── Locate the problem from the logs
│   ├── Missing dependency → update requirements.txt
│   ├── Wrong port → ensure 7860
│   ├── Code error → fix the code
│   └── Variable → check plaintext variable/secret configuration
│
└── After fixing, redeploy
    git add . && git commit -m "fix" && git push modelscope master
    then call deployStudio
```

## Notes

1. The default branch is `master`; force push is prohibited
2. Files over 100MB must use Git LFS
3. The first Docker build takes about 3-5 minutes; other types start faster
4. Free quotas have time limits
5. Switching to paid hardware resources will incur charges on the Alibaba Cloud account bound to the user's ModelScope account; the user's explicit authorization must be obtained first
6. Hardcoding sensitive information in code is prohibited; it must be injected via secrets; non-sensitive configuration may use plaintext variables
7. A Studio **cannot be deleted through a programmatic interface**: OpenAPI `DELETE /openapi/v1/studios/{id}` returns 404; the SDK/CLI `delete_repo` is deprecated and does not support studio. Deletion is only possible via the web console at https://modelscope.cn (which uses a cookie-authenticated internal interface; a Bearer token call returns 401). Programmatically, you can only stop (`stop`).
