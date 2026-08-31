#!/usr/bin/env python3
"""Send a text or file notification through ntfy using environment config."""

from __future__ import annotations

import argparse
import mimetypes
import os
import urllib.error
import urllib.parse
import urllib.request
from email.header import Header
from pathlib import Path

MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024


def load_config_from_env() -> dict:
    return {
        "base_url": os.environ.get("NTFY_BASE_URL", ""),
        "topic": os.environ.get("NTFY_TOPIC", ""),
        "token": os.environ.get("NTFY_TOKEN", ""),
        "allow_short_topic": os.environ.get("NTFY_ALLOW_SHORT_TOPIC", "") == "true",
    }


def validate_config(config: dict) -> tuple[str, str, str]:
    base_url = config.get("base_url")
    topic = config.get("topic")
    token = config.get("token", "")
    if not all(isinstance(value, str) for value in (base_url, topic, token)) or not base_url or not topic:
        raise RuntimeError("ntfy 配置缺少 base_url 或 topic")
    if len(topic) < 32 and config.get("allow_short_topic") is not True:
        raise RuntimeError("ntfy 必须使用至少 32 字符的随机 topic")
    parsed = urllib.parse.urlparse(base_url)
    if (
        parsed.scheme != "https"
        or not parsed.netloc
        or parsed.username
        or parsed.password
        or parsed.path not in ("", "/")
        or parsed.params
        or parsed.query
        or parsed.fragment
    ):
        raise RuntimeError("ntfy base_url 必须是无路径和内嵌凭据的 HTTPS 根地址")
    return base_url.rstrip("/"), topic, token


def send_notification(
    config: dict,
    title: str,
    message: str,
    attachment: Path | None = None,
    priority: int = 3,
) -> int:
    base_url, topic, token = validate_config(config)
    if not 1 <= priority <= 5:
        raise RuntimeError("ntfy priority 必须在 1 到 5 之间")
    headers = {
        "Title": Header(title, "utf-8").encode(),
        "Priority": str(priority),
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if attachment is None:
        data = message.encode("utf-8")
        headers["Content-Type"] = "text/plain; charset=utf-8"
    else:
        if not attachment.is_file():
            raise RuntimeError(f"ntfy 附件不存在: {attachment}")
        size = attachment.stat().st_size
        if size <= 0 or size > MAX_ATTACHMENT_BYTES:
            raise RuntimeError("ntfy 附件必须是 1 字节到 10 MiB")
        data = attachment.read_bytes()
        headers.update(
            {
                "Content-Type": mimetypes.guess_type(attachment.name)[0] or "application/octet-stream",
                "Filename": attachment.name,
                "Message": Header(message, "utf-8").encode(),
            }
        )
    request = urllib.request.Request(
        base_url + "/" + urllib.parse.quote(topic, safe=""),
        data=data,
        headers=headers,
        method="PUT",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            status = response.status
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"ntfy 请求失败 (HTTP {exc.code})") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError("ntfy 请求失败") from exc
    except TimeoutError as exc:
        raise RuntimeError("ntfy 请求超时") from exc
    if status != 200:
        raise RuntimeError(f"ntfy 请求失败 (HTTP {status})")
    return status


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--title", required=True)
    parser.add_argument("--message", required=True)
    parser.add_argument("--file", type=Path)
    parser.add_argument("--priority", type=int, default=3)
    args = parser.parse_args()
    status = send_notification(
        load_config_from_env(), args.title, args.message, args.file, args.priority
    )
    print(f"ntfy: ok (HTTP {status})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
