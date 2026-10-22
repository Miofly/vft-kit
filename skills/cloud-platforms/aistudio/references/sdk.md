# SDK operations and official references

## SDK operations

Require `AISTUDIO_ACCESS_TOKEN` in the environment. Never accept or print a token in argv, logs, prompts, or output. For ERNIE SDK compatibility, callers may additionally set `EB_API_TYPE=aistudio` and `EB_ACCESS_TOKEN`.

Run through `uv` so the repository does not gain a dependency:

```bash
uv run --with aistudio-sdk python3 "<skill-dir>/scripts/aistudio.py" credential-status
uv run --with aistudio-sdk python3 "<skill-dir>/scripts/aistudio.py" create-model NAME
uv run --with aistudio-sdk python3 "<skill-dir>/scripts/aistudio.py" create-app NAME --app-sdk gradio --version 4.26.0
uv run --with aistudio-sdk python3 "<skill-dir>/scripts/aistudio.py" upload-file OWNER/REPO /ABSOLUTE/FILE PATH_IN_REPO
uv run --with aistudio-sdk python3 "<skill-dir>/scripts/aistudio.py" file-exists OWNER/REPO PATH_IN_REPO
uv run --with aistudio-sdk python3 "<skill-dir>/scripts/aistudio.py" download-file OWNER/REPO PATH_IN_REPO /ABSOLUTE/DIR
uv run --with aistudio-sdk python3 "<skill-dir>/scripts/aistudio.py" download-repo OWNER/REPO /ABSOLUTE/DIR
```

Set `AISTUDIO_OWNER` to allow short repo names; otherwise transfers require `OWNER/REPO`. Repository creation is private by default. Require `--public` for a public repository. Downloads reject collisions unless `--force` is explicit. Before mutations, inspect the target and local source; afterward verify the returned result and remote state. A request timeout has unknown outcome: inspect the remote account before retrying.

2026-10-21 compatibility: newer BOS SDKs renamed `put_super_obejct_from_file` to `put_super_object_from_file`, while AI Studio still calls the legacy name. The launcher adds the alias only when the old method is absent; existing implementations remain unchanged. `self-check` covers both cases. Upload logs and a Git commit are insufficient: download the actual object and compare bytes/SHA-256. Use a recognized LFS extension such as `.bin` for large snapshot parts; `.part00` was classified as a normal file and hit the 500MB limit. `download-file` now fails if the SDK returns no file.

Official references:

- Access token: <https://ai.baidu.com/ai-doc/AISTUDIO/slmkadt9z>
- SDK quick start: <https://ai.baidu.com/ai-doc/AISTUDIO/jltzsszyq>
- Hub API: <https://ai.baidu.com/ai-doc/AISTUDIO/xltzsucwk>
- Model upload: <https://ai.baidu.com/ai-doc/AISTUDIO/lmc4vuarp>
- Model download: <https://ai.baidu.com/ai-doc/AISTUDIO/zlisofwng>
- Notebook projects: <https://ai.baidu.com/ai-doc/AISTUDIO/Dk3e2vxg9>
- BML Codelab and Notebook background tasks: <https://ai.baidu.com/ai-doc/AISTUDIO/Gktuwqf1x#%E4%BB%BB%E5%8A%A1>
- Script tasks: <https://ai.baidu.com/ai-doc/AISTUDIO/Ik3e3g4lt>
- Model-pipeline jobs through AI Studio CLI: <https://ai.baidu.com/ai-doc/AISTUDIO/lluckgp2n>
- Compute cards: <https://ai.baidu.com/ai-doc/AISTUDIO/nk39v9kec>
- Points rules: <https://ai.baidu.com/ai-doc/AISTUDIO/jk4mcntxf>
