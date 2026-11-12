#!/usr/bin/env python3
"""在指定绝对临时目录下运行本技能全部离线测试，不调用模型或网络。"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--temp-dir", type=Path, required=True)
    args = parser.parse_args()
    if not args.temp_dir.is_absolute():
        parser.error("--temp-dir 必须是绝对路径")
    args.temp_dir.mkdir(parents=True, exist_ok=True)
    scripts = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory(dir=args.temp_dir) as temp:
        env = dict(os.environ, TMPDIR=temp, PYTHONDONTWRITEBYTECODE="1")
        for name in ("test_check_evidence.py", "test_check_manuscript.py", "test_check_delivery.py"):
            result = subprocess.run([sys.executable, "-B", "-I", str(scripts / name)], env=env)
            if result.returncode:
                return result.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
