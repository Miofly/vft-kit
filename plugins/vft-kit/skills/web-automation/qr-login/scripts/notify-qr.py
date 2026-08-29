#!/usr/bin/env python3
"""Send a temporary QR image via PushPlus and an optional ntfy reminder.

Secrets come from environment variables (supply-bridge convention: the caller
exports them from its own secret store; this public script never reads repo
secret files):
  PUSHPLUS_TOKEN          required, PushPlus message token
  PUSHPLUS_TOPIC          group topic code, default "me"
  PUSHPLUS_SEND_URL       default https://www.pushplus.plus/send
  BEEIMG_TOKEN            optional; when set, BeeImg is the primary image host
  BEEIMG_UPLOAD_URL       default https://img.beeimg.cn/api/v2/upload
  BEEIMG_STORAGE_ID       default 3
  UGUU_UPLOAD_URL         fallback anonymous host, default https://uguu.se/upload
  NTFY_BASE_URL/NTFY_TOPIC/NTFY_TOKEN/NTFY_ALLOW_SHORT_TOPIC  optional reminder
"""

from __future__ import annotations

import argparse
import html
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from email.header import Header
from pathlib import Path

MAX_IMAGE_BYTES = 10 * 1024 * 1024


def validate_image_file(image_file: Path) -> str:
    if not image_file.is_file():
        raise RuntimeError(f"二维码文件不存在: {image_file}")
    size = image_file.stat().st_size
    if size <= 0 or size > MAX_IMAGE_BYTES:
        raise RuntimeError("二维码文件必须是 1 字节到 10 MiB 的图片")
    with image_file.open("rb") as stream:
        signature = stream.read(12)
    if signature.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if signature.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    raise RuntimeError("二维码文件只支持 JPEG 或 PNG")


def validate_https_endpoint(url: str, label: str) -> str:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password or parsed.fragment:
        raise RuntimeError(f"{label} 必须是无内嵌凭据的 HTTPS 地址")
    return url


def load_ntfy_config_from_env() -> dict:
    return {
        "base_url": os.environ.get("NTFY_BASE_URL", ""),
        "topic": os.environ.get("NTFY_TOPIC", ""),
        "token": os.environ.get("NTFY_TOKEN", ""),
        "allow_short_topic": os.environ.get("NTFY_ALLOW_SHORT_TOPIC", "") == "true",
    }


def validate_image_url(image_url: str, provider: str) -> str:
    parsed = urllib.parse.urlparse(image_url)
    host = (parsed.hostname or "").lower().rstrip(".")
    if parsed.scheme != "https" or parsed.username or parsed.password:
        raise RuntimeError(f"{provider} 返回了非 HTTPS 图片地址")
    if provider == "beeimg":
        allowed = host == "img.beeimg.cn" or host.endswith(".imglnk.cn")
    else:
        allowed = host == "uguu.se" or host.endswith(".uguu.se")
    if not allowed:
        raise RuntimeError(f"{provider} 返回了非预期图片地址")
    return image_url


def upload_to_beeimg(image_file: Path, upload_url: str, storage_id: int, token: str) -> str:
    validate_image_file(image_file)
    validate_https_endpoint(upload_url, "BeeImg 上传地址")

    def config_value(value: object) -> str:
        text = str(value)
        if any(char in text for char in "\r\n\0"):
            raise RuntimeError("BeeImg curl 配置包含非法控制字符")
        return text.replace("\\", "\\\\").replace('"', '\\"')

    curl_config = "\n".join(
        (
            'header = "Authorization: Bearer ' + config_value(token) + '"',
            'form = "file=@' + config_value(image_file) + '"',
            'form = "storage_id=' + config_value(storage_id) + '"',
            'url = "' + config_value(upload_url) + '"',
        )
    )
    try:
        completed = subprocess.run(
            [
                "/usr/bin/curl",
                "-4",
                "--silent",
                "--show-error",
                "--fail-with-body",
                "--connect-timeout",
                "10",
                "--max-time",
                "30",
                "--config",
                "-",
            ],
            check=True,
            capture_output=True,
            text=True,
            input=curl_config,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        code = getattr(exc, "returncode", "unavailable")
        raise RuntimeError(f"BeeImg 上传失败 (curl exit {code})") from exc

    try:
        result = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError("BeeImg 返回格式异常") from exc

    def find_url(value: object) -> str | None:
        if isinstance(value, dict):
            for key in ("public_url", "url", "link"):
                candidate = value.get(key)
                if isinstance(candidate, str) and candidate:
                    return candidate
            for child in value.values():
                found = find_url(child)
                if found:
                    return found
        elif isinstance(value, list):
            for child in value:
                found = find_url(child)
                if found:
                    return found
        return None

    image_url = find_url(result)
    if not image_url:
        raise RuntimeError("BeeImg 返回中没有图片地址")
    return validate_image_url(image_url, "beeimg")


def upload_to_uguu(image_file: Path, upload_url: str) -> str:
    validate_image_file(image_file)
    validate_https_endpoint(upload_url, "Uguu 上传地址")
    try:
        completed = subprocess.run(
            [
                "/usr/bin/curl",
                "-4",
                "--silent",
                "--show-error",
                "--fail-with-body",
                "--connect-timeout",
                "10",
                "--max-time",
                "30",
                "--form",
                f"files[]=@{image_file}",
                upload_url,
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        body = completed.stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        code = getattr(exc, "returncode", "unavailable")
        raise RuntimeError(f"Uguu 上传失败 (curl exit {code})") from exc

    try:
        result = json.loads(body)
        image_url = result["files"][0]["url"]
    except (json.JSONDecodeError, KeyError, IndexError, TypeError) as exc:
        raise RuntimeError("Uguu 返回格式异常") from exc

    return validate_image_url(image_url, "uguu")


def build_notification(action: str, subject: str, message: str | None, title_prefix: str = "") -> tuple[str, str]:
    action = action.strip()
    subject = subject.strip()
    if not action or not subject:
        raise RuntimeError("通知必须提供具体的 action 和 subject")
    title = f"{title_prefix}{action}｜{subject}"
    content = message or f"请使用微信扫描下方二维码，完成「{subject}」的{action}。"
    return title, content


def send_ntfy_notification(config: dict, title: str, message: str, image_file: Path) -> None:
    base_url = config.get("base_url")
    topic = config.get("topic")
    token = config.get("token", "")
    if not all(isinstance(value, str) for value in (base_url, topic, token)) or not base_url or not topic:
        raise RuntimeError("ntfy 配置缺少 base_url 或 topic")
    if len(topic) < 32 and config.get("allow_short_topic") is not True:
        raise RuntimeError("ntfy 必须使用至少 32 字符的随机 topic")
    content_type = validate_image_file(image_file)

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

    headers = {
        "Content-Type": content_type,
        "Filename": "qr.png" if content_type == "image/png" else "qr.jpg",
        "Title": Header(title, "utf-8").encode(),
        "Message": Header(message, "utf-8").encode(),
        "Priority": "4",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        base_url.rstrip("/") + "/" + urllib.parse.quote(topic, safe=""),
        data=image_file.read_bytes(),
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image-file", required=True, type=Path, help="待上传的本地二维码图片")
    parser.add_argument("--action", required=True, help="当前扫码动作，例如：登录、群发验证、授权")
    parser.add_argument("--subject", required=True, help="当前操作对象，例如：平台名、文章标题或授权应用")
    parser.add_argument("--message", help="可选的补充说明；默认由 action 和 subject 生成")
    parser.add_argument("--title-prefix", default="", help="标题前缀，例如公众号流程传「公众号」")
    args = parser.parse_args()
    title, message = build_notification(args.action, args.subject, args.message, args.title_prefix)

    token = os.environ.get("PUSHPLUS_TOKEN", "")
    if not token:
        raise SystemExit("缺少环境变量 PUSHPLUS_TOKEN")
    beeimg_error = ""
    beeimg_token = os.environ.get("BEEIMG_TOKEN", "")
    beeimg_upload_url = os.environ.get("BEEIMG_UPLOAD_URL", "https://img.beeimg.cn/api/v2/upload")
    try:
        beeimg_storage_id = int(os.environ.get("BEEIMG_STORAGE_ID", "3"))
    except ValueError:
        beeimg_storage_id = 0
    upload_url = os.environ.get("UGUU_UPLOAD_URL", "https://uguu.se/upload")
    topic = os.environ.get("PUSHPLUS_TOPIC", "me")
    send_url = os.environ.get("PUSHPLUS_SEND_URL", "https://www.pushplus.plus/send")
    validate_image_file(args.image_file)
    validate_https_endpoint(send_url, "PushPlus 发送地址")
    provider = "beeimg"
    beeimg_ready = bool(beeimg_token) and bool(beeimg_upload_url) and beeimg_storage_id > 0
    if beeimg_ready:
        try:
            image_url = upload_to_beeimg(args.image_file, beeimg_upload_url, beeimg_storage_id, beeimg_token)
        except RuntimeError as exc:
            beeimg_error = str(exc)
    else:
        beeimg_error = "BeeImg 配置不完整（缺少 BEEIMG_TOKEN）"
    if beeimg_error:
        provider = "uguu-fallback"
        print(f"BeeImg 上传失败，回退 Uguu: {beeimg_error}", file=sys.stderr)
        image_url = upload_to_uguu(args.image_file, upload_url)

    content = (
        f"{html.escape(message)}<br/>"
        f'<img src="{html.escape(image_url, quote=True)}" '
        f'alt="{html.escape(args.action, quote=True)}二维码" style="max-width:300px;" />'
    )
    payload = json.dumps(
        {"token": token, "title": title, "content": content, "template": "html", "topic": topic},
        ensure_ascii=False,
    ).encode("utf-8")
    request = urllib.request.Request(
        send_url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            body = response.read().decode("utf-8", "replace")
            status = response.status
    except urllib.error.URLError as exc:
        raise SystemExit(f"PushPlus 请求失败: {exc.reason}") from exc

    try:
        result = json.loads(body)
    except json.JSONDecodeError:
        raise SystemExit(f"PushPlus 返回非 JSON 响应 (HTTP {status})")
    pushplus_ok = status == 200 and result.get("code") == 200
    ntfy_status = "skipped"
    ntfy_config = load_ntfy_config_from_env()
    ntfy_requested = any(ntfy_config[key] for key in ("base_url", "topic", "token"))
    if pushplus_ok and ntfy_requested:
        try:
            send_ntfy_notification(ntfy_config, title, message, args.image_file)
            ntfy_status = "ok"
        except RuntimeError as exc:
            ntfy_status = "failed"
            print(str(exc), file=sys.stderr)

    print(
        json.dumps(
            {
                "upload": "ok",
                "provider": provider,
                "http_status": status,
                "code": result.get("code"),
                "msg": result.get("msg"),
                "ntfy": ntfy_status,
            },
            ensure_ascii=False,
        )
    )
    return 0 if pushplus_ok else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
