import os
import re
import subprocess
import sys


def run(*command: str) -> str:
    try:
        return subprocess.run(command, text=True, capture_output=True, timeout=20).stdout.strip()
    except (OSError, subprocess.SubprocessError) as exc:
        return f"unavailable: {exc}"


print("=== AI Studio GPU probe ===", flush=True)
print("python:", sys.version.split()[0], flush=True)
smi = run("nvidia-smi", "--query-gpu=name,memory.total,driver_version", "--format=csv,noheader")
print("gpu:", smi or "unavailable", flush=True)
full_smi = run("nvidia-smi")
cuda = re.search(r"CUDA Version:\s*([\d.]+)", full_smi)
print("cuda-driver:", cuda.group(1) if cuda else "unknown", flush=True)

try:
    import paddle

    print("paddle:", paddle.__version__, "cuda:", paddle.version.cuda(), "devices:", paddle.device.cuda.device_count())
except Exception as exc:
    print("paddle: unavailable:", exc)

try:
    import torch

    print("torch:", torch.__version__, "cuda:", torch.version.cuda, "available:", torch.cuda.is_available())
except Exception as exc:
    print("torch: unavailable:", exc)

print("network:", run("curl", "-sI", "--max-time", "10", "https://github.com").splitlines()[:1])
print("workspace:", os.getcwd())
print("=== done ===")

