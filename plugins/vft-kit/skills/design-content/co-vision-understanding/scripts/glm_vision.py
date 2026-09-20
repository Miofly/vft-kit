#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
glm_vision.py — 智谱 GLM-4.6V-Flash 免费多模态模型命令行封装。

仅依赖 Python 3 标准库（无需 pip install）。
支持：图片理解（本地文件自动 Base64）、视频理解（需公网 URL）、
文件/文档理解（需公网 URL）、思考模式开关、流式输出、目标检测坐标。

API Key 读取顺序：--key 参数 > 本地 .env 文件（先当前工作目录，后 skill 根目录）> 环境变量 ZHIPU_API_KEY。
"""

import argparse
import base64
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.request

API_URL = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
DEFAULT_MODEL = "glm-4.6v-flash"
DEFAULT_PROMPT = "请描述并总结这个内容的关键信息。"

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff", ".ico"}
VIDEO_EXTS = {".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v", ".flv"}

# 常见错误码 → 人话
ERROR_HINTS = {
    1002: "API Key 无效或为空，请检查 --key / .env / ZHIPU_API_KEY",
    1302: "触发速率限制：并发请求过多，请稍后重试或降低并发",
    1305: "平台服务过载：模型当前访问量过大，稍后重试",
    1102: "请求参数有误，请检查输入内容格式",
    1301: "输入内容可能违反内容安全政策",
}


def die(msg, code=1):
    print(f"[glm-4.6v-flash] {msg}", file=sys.stderr)
    sys.exit(code)


def is_url(s):
    return s.startswith("http://") or s.startswith("https://")


def read_env_file_key(path):
    """从 .env 文件提取 ZHIPU_API_KEY 的值（标准库实现）；不存在/读不到返回 None。"""
    try:
        with open(path, "r", encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                key = key.strip()
                if key.startswith("export "):
                    key = key[len("export "):].strip()
                if key != "ZHIPU_API_KEY":
                    continue
                value = value.strip().strip("'\"")
                if value:
                    return value
    except OSError:
        pass
    return None


def resolve_api_key(cli_key):
    """API Key 查找顺序：--key 参数 > 本地 .env（先 cwd，后 skill 根目录）> 环境变量。"""
    if cli_key:
        return cli_key
    env_paths = [
        os.path.join(os.getcwd(), ".env"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".env"),
    ]
    for path in env_paths:
        key = read_env_file_key(path)
        if key:
            return key
    return os.environ.get("ZHIPU_API_KEY")


def local_image_to_data_url(path):
    """本地图片转 data URI（data:image/...;base64,...）。"""
    if not os.path.isfile(path):
        die(f"图片文件不存在: {path}")
    mime = mimetypes.guess_type(path)[0]
    if not mime or not mime.startswith("image/"):
        ext = os.path.splitext(path)[1].lower()
        mime = "image/png" if ext not in VIDEO_EXTS else None
        if mime is None:
            die(f"不支持的图片格式: {path}")
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("utf-8")
    return f"data:{mime};base64,{b64}"


def build_content(images, videos, files, text):
    content = []
    for img in images:
        url = img if is_url(img) else local_image_to_data_url(img)
        content.append({"type": "image_url", "image_url": {"url": url}})
    for vid in videos:
        if not is_url(vid):
            die(
                f"视频理解只支持公网 URL，本地视频请先上传换取链接"
                f"（可考虑 fe-file-uploader 等上传手段）: {vid}"
            )
        content.append({"type": "video_url", "video_url": {"url": vid}})
    for f in files:
        if not is_url(f):
            die(
                f"文件理解只支持公网 URL，本地文件请先上传换取链接"
                f"（可考虑 fe-file-uploader 等上传手段）: {f}"
            )
        content.append({"type": "file_url", "file_url": {"url": f}})
    content.append({"type": "text", "text": text})
    return content


def call_api(payload, api_key, stream):
    req = urllib.request.Request(
        API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        return urllib.request.urlopen(req, timeout=600)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        try:
            data = json.loads(body)
            err = data.get("error", {})
            code = err.get("code", "")
            msg = err.get("message", body)
            hint = ERROR_HINTS.get(code, "")
            die(f"HTTP {e.code} 错误码 {code}: {msg}" + (f"\n提示: {hint}" if hint else ""))
        except json.JSONDecodeError:
            die(f"HTTP {e.code}: {body[:500]}")
    except urllib.error.URLError as e:
        die(f"网络错误: {e.reason}")


def run_stream(resp):
    """解析 SSE 流，分别打印思考过程与正文。"""
    reasoning_started = False
    content_started = False
    for raw_line in resp:
        line = raw_line.decode("utf-8", errors="replace").strip()
        if not line.startswith("data:"):
            continue
        data = line[5:].strip()
        if data == "[DONE]":
            break
        try:
            chunk = json.loads(data)
        except json.JSONDecodeError:
            continue
        if not chunk.get("choices"):
            continue
        delta = chunk["choices"][0].get("delta", {})
        rc = delta.get("reasoning_content")
        c = delta.get("content")
        if rc:
            if not reasoning_started:
                print("[思考过程]", file=sys.stderr)
                reasoning_started = True
            print(rc, end="", flush=True, file=sys.stderr)
        if c:
            if reasoning_started and not content_started:
                print("", file=sys.stderr)  # 思考结束换行
                content_started = True
            print(c, end="", flush=True)
    print()


def main():
    p = argparse.ArgumentParser(
        description="GLM-4.6V-Flash 免费多模态模型 CLI（图片/视频/文件理解）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例:\n"
            "  python3 glm_vision.py '提取这张发票的金额和抬头' -i invoice.jpg\n"
            "  python3 glm_vision.py -i a.png -i b.png '对比这两张图的差异'\n"
            "  python3 glm_vision.py --video https://example.com/v.mp4 '总结视频内容'\n"
            "  python3 glm_vision.py '定位图中所有瓶子，输出 [[xmin,ymin,xmax,ymax]]' -i img.png\n"
        ),
    )
    p.add_argument("prompt", nargs="?", default=None, help="提问内容（缺省为通用描述提示）")
    p.add_argument("-i", "--image", action="append", default=[], metavar="PATH_OR_URL",
                   help="图片，本地路径或 URL，可多次传入")
    p.add_argument("--video", action="append", default=[], metavar="URL",
                   help="视频，仅支持公网 URL，可多次传入")
    p.add_argument("--file", action="append", default=[], metavar="URL",
                   help="文件（pdf/doc/txt 等），仅支持公网 URL，可多次传入")
    p.add_argument("--think", choices=["enabled", "disabled"], default="disabled",
                   help="思考模式：enabled 开启深度推理（更准但更慢），默认 disabled")
    p.add_argument("--stream", action="store_true", help="流式输出")
    p.add_argument("--system", default=None, help="system 提示词")
    p.add_argument("--max-tokens", type=int, default=None, help="最大输出 tokens（上限 32K）")
    p.add_argument("--temperature", type=float, default=None, help="采样温度")
    p.add_argument("--top-p", type=float, default=None, help="top-p 采样")
    p.add_argument("--model", default=DEFAULT_MODEL, help=f"模型名（默认 {DEFAULT_MODEL}）")
    p.add_argument("--key", default=None, help="API Key（默认依次读本地 .env、环境变量 ZHIPU_API_KEY）")
    p.add_argument("--json", action="store_true", help="输出完整响应 JSON 而非纯文本")
    p.add_argument("--dry-run", action="store_true", help="只打印请求体，不实际调用 API")
    args = p.parse_args()

    media_kinds = sum(1 for group in (args.image, args.video, args.file) if group)
    if media_kinds > 1:
        die("GLM-4.6V-Flash 单次请求不支持同时理解图片、视频、文件，请拆成多次调用")
    if media_kinds == 0 and not args.prompt:
        p.print_help()
        sys.exit(0)

    prompt = args.prompt or DEFAULT_PROMPT
    content = build_content(args.image, args.video, args.file, prompt)

    messages = []
    if args.system:
        messages.append({"role": "system", "content": args.system})
    messages.append({"role": "user", "content": content})

    payload = {
        "model": args.model,
        "messages": messages,
        "thinking": {"type": args.think},
    }
    if args.stream:
        payload["stream"] = True
    if args.max_tokens is not None:
        payload["max_tokens"] = args.max_tokens
    if args.temperature is not None:
        payload["temperature"] = args.temperature
    if args.top_p is not None:
        payload["top_p"] = args.top_p

    if args.dry_run:
        preview = json.dumps(payload, ensure_ascii=False, indent=2)
        # 避免超长 base64 刷屏
        if len(preview) > 8000:
            preview = preview[:8000] + "\n... (base64 内容已截断)"
        print(preview)
        return

    api_key = resolve_api_key(args.key)
    if not api_key:
        die("未找到 API Key：请在 .env 文件（当前工作目录或 skill 根目录）写入 ZHIPU_API_KEY=...，\n"
            "或设置环境变量 ZHIPU_API_KEY，或使用 --key 传入\n"
            "获取方式: https://bigmodel.cn 控制台 → API Keys（该模型免费）")

    resp = call_api(payload, api_key, args.stream)

    if args.stream and not args.json:
        run_stream(resp)
        return

    body = resp.read().decode("utf-8", errors="replace")
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        die(f"响应不是合法 JSON: {body[:500]}")

    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return

    if not data.get("choices"):
        die(f"响应中没有 choices: {json.dumps(data, ensure_ascii=False)[:500]}")
    msg = data["choices"][0].get("message", {})
    if msg.get("reasoning_content"):
        print("[思考过程]", file=sys.stderr)
        print(msg["reasoning_content"], file=sys.stderr)
    print(msg.get("content", ""))


if __name__ == "__main__":
    main()
