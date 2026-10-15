#!/usr/bin/env python3
"""飞书机器人 ↔ 大模型 / 本机编码智能体（长连接，无需公网地址）。

三种后端（BOT_BACKEND）：
  api          纯对话：调 Anthropic Messages API，多轮上下文存内存。依赖 anthropic。
  claude-code  远程操作本机：每条消息交给本机 `claude -p` 执行，按会话 --resume 续接。
  codex        远程操作本机：每条消息交给本机 `codex exec`，按会话 `codex exec resume` 续接。
后两种只响应 BOT_OWNER_OPEN_IDS 里的人在单聊发的消息。

支持文字、图片、富文本（图文混排）消息。图片下载到 BOT_MEDIA_DIR：
api 后端以 base64 图片块发给模型；claude-code 把路径写进提示让它用 Read 查看；codex 用 --image 传入。

依赖：pip install lark-oapi anthropic
通用环境变量（密钥只从环境读取，不接受命令行传入）：
  FEISHU_APP_ID / FEISHU_APP_SECRET   飞书自建应用凭据
  FEISHU_DOMAIN                       可选，默认 https://open.feishu.cn；Lark 国际版填 https://open.larksuite.com
  BOT_BACKEND                         可选，api（默认）/ claude-code / codex
  BOT_MODEL                           可选，模型名；api 默认 claude-sonnet-5，claude-code/codex 默认用各自配置里的模型
  BOT_MEDIA_DIR                       可选，图片下载目录，默认 ~/.feishu-bot-media
api 后端：
  ANTHROPIC_API_KEY / ANTHROPIC_BASE_URL（可选，中转网关，不含 /v1）
  CLAUDE_SYSTEM / BOT_MAX_TURNS（默认 20）/ BOT_MAX_TOKENS（默认 4096）
claude-code / codex 后端（ANTHROPIC_*、CLAUDE_CONFIG_DIR、CODEX_HOME 原样传给子进程，用来与本机主配置隔离）：
  BOT_OWNER_OPEN_IDS   必填，逗号分隔；为空时谁都不执行，并把发送者 open_id 回给对方，便于配置
  BOT_WORKDIR          子进程工作目录，默认当前目录
  BOT_STATE_FILE       chat_id → session_id 持久化文件，默认 ~/.feishu-bot-sessions.json
  BOT_TIMEOUT          单条任务超时秒数，默认 600
  BOT_PERMISSION_MODE  claude-code 用，默认 bypassPermissions；保守可设 default 并配合 BOT_ALLOWED_TOOLS
  BOT_ALLOWED_TOOLS    claude-code 用，可选，传给 --allowedTools
  CLAUDE_BIN / CODEX_BIN  默认 claude / codex

通用行为：发「/reset」或「清空」重置当前会话；回复用卡片 markdown，失败回退纯文本；按 message_id 去重。
自检：python3 feishu_claude_bot.py --selftest   （不联网）
"""
import base64
import json
import os
import re
import subprocess
import sys
import threading
from collections import OrderedDict, defaultdict
from concurrent.futures import ThreadPoolExecutor

RESET_WORDS = {"/reset", "清空", "重置"}
MENTION_RE = re.compile(r"@_user_\d+\s*")
MAX_REPLY_CHARS = 20000  # 卡片内容上限约 30KB，留余量
AGENT_BACKENDS = {"claude-code", "codex"}


def parse_message(message_type: str, raw_content: str):
    """返回 (正文, [image_key])；不支持的类型返回 (None, [])。"""
    try:
        content = json.loads(raw_content)
    except (ValueError, TypeError):
        return None, []
    if message_type == "text":
        return MENTION_RE.sub("", content.get("text", "")).strip(), []
    if message_type == "image":
        return "", [content["image_key"]] if content.get("image_key") else []
    if message_type == "post":
        # 收到的富文本是 {"title","content":[[node,...],...]}，个别场景外面再包一层语言键
        if "content" not in content and content:
            content = next(iter(content.values()))
        lines, images = [content.get("title") or ""], []
        for para in content.get("content") or []:
            parts = []
            for node in para:
                tag = node.get("tag")
                if tag in ("text", "a", "md"):
                    parts.append(node.get("text", ""))
                elif tag == "img" and node.get("image_key"):
                    images.append(node["image_key"])
            lines.append("".join(parts))
        text = MENTION_RE.sub("", "\n".join(l for l in lines if l)).strip()
        return text, images
    return None, []


def clean_text(raw_content: str) -> str:
    return parse_message("text", raw_content)[0] or ""


def with_image_paths(text: str, paths: list) -> str:
    """给 claude-code 的提示：正文 + 本地图片路径。"""
    if not paths:
        return text
    listing = "\n".join(f"- {p}" for p in paths)
    return f"{text or '请看图片。'}\n\n用户在飞书里附带了图片，已保存到本机，先用 Read 工具查看：\n{listing}"


def trim_history(history: list, max_turns: int) -> list:
    """保留最近 max_turns 轮，并保证首条是 user（Messages API 要求）。"""
    history = history[-max_turns * 2:]
    while history and history[0]["role"] != "user":
        history = history[1:]
    return history


def card_content(markdown: str) -> str:
    if len(markdown) > MAX_REPLY_CHARS:
        markdown = markdown[:MAX_REPLY_CHARS] + "\n\n…（已截断）"
    return json.dumps({
        "schema": "2.0",
        "body": {"elements": [{"tag": "markdown", "content": markdown}]},
    }, ensure_ascii=False)


def parse_owners(raw: str) -> set:
    return {x.strip() for x in raw.split(",") if x.strip()}


def build_claude_cmd(text: str, session_id, model: str, permission_mode: str, allowed_tools: str) -> list:
    cmd = [os.environ.get("CLAUDE_BIN", "claude"), "-p", text, "--output-format", "json",
           "--permission-mode", permission_mode]
    if model:  # 空则用 Claude Code 自身配置的默认模型
        cmd += ["--model", model]
    if allowed_tools:
        cmd += ["--allowedTools", allowed_tools]
    if session_id:
        cmd += ["--resume", session_id]
    return cmd


def parse_claude_output(stdout: str) -> dict:
    """claude -p --output-format json 的最后一行 JSON；解析失败时把原文当错误。"""
    for line in reversed(stdout.strip().splitlines()):
        try:
            data = json.loads(line)
        except ValueError:
            continue
        if isinstance(data, dict) and ("result" in data or "is_error" in data):
            return data
    return {"is_error": True, "result": stdout.strip()[-2000:] or "（无输出）"}


def build_codex_cmd(session_id, model: str, images: list) -> list:
    """提示词走 stdin（末尾的 "-"），避免被 --image 的多值参数吞掉。"""
    cmd = [os.environ.get("CODEX_BIN", "codex"), "exec"]
    if session_id:
        cmd += ["resume", session_id]
    cmd += ["--json", "--skip-git-repo-check", "--dangerously-bypass-approvals-and-sandbox"]
    if model:
        cmd += ["--model", model]
    cmd += [f"--image={p}" for p in images]
    return cmd + ["-"]


def parse_codex_output(stdout: str) -> dict:
    """codex exec --json 的 JSONL 事件流 → 与 claude 输出同形的 dict。"""
    out = {"is_error": False, "result": "", "session_id": None}
    messages, errors = [], []
    for line in stdout.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        t, item = e.get("type"), e.get("item") or {}
        if t == "thread.started":
            out["session_id"] = e.get("thread_id")
        elif t == "item.completed" and item.get("type") == "agent_message":
            messages.append(item.get("text", ""))
        elif t in ("turn.failed", "error"):
            errors.append(str(e.get("message") or e.get("error") or e))
        elif t == "turn.completed":
            out["usage"] = e.get("usage")
    if messages:
        out["result"] = messages[-1]
    else:
        out["is_error"] = True
        out["result"] = "\n".join(errors[-3:]) or stdout.strip()[-2000:] or "（无输出）"
    return out


class SessionStore:
    """chat_id → session_id，写文件以便服务重启后续接。"""

    def __init__(self, path: str):
        self.path = path
        self.lock = threading.Lock()
        try:
            with open(path) as f:
                self.data = json.load(f)
        except (OSError, ValueError):
            self.data = {}

    def get(self, chat_id: str):
        return self.data.get(chat_id)

    def set(self, chat_id: str, session_id) -> None:
        with self.lock:
            if session_id:
                self.data[chat_id] = session_id
            else:
                self.data.pop(chat_id, None)
            tmp = self.path + ".tmp"
            with open(tmp, "w") as f:
                json.dump(self.data, f)
            os.replace(tmp, self.path)


def selftest() -> None:
    import tempfile
    assert clean_text('{"text":"@_user_1 你好"}') == "你好"
    assert parse_message("text", "not json") == (None, [])
    assert parse_message("image", '{"image_key":"img_1"}') == ("", ["img_1"])
    post = {"title": "", "content": [[{"tag": "img", "image_key": "img_2"}], [{"tag": "text", "text": "有啊"}]]}
    assert parse_message("post", json.dumps(post)) == ("有啊", ["img_2"])
    assert parse_message("post", json.dumps({"zh_cn": post})) == ("有啊", ["img_2"])
    assert parse_message("file", '{"file_key":"f"}') == (None, [])
    assert "/a.png" in with_image_paths("", ["/a.png"]) and with_image_paths("hi", []) == "hi"
    h = [{"role": "assistant", "content": "x"}] + [
        {"role": r, "content": str(i)} for i in range(5) for r in ("user", "assistant")
    ]
    t = trim_history(h, 2)
    assert len(t) == 4 and t[0]["role"] == "user"
    assert json.loads(card_content("**a**"))["body"]["elements"][0]["content"] == "**a**"
    assert "已截断" in card_content("x" * (MAX_REPLY_CHARS + 1))
    assert parse_owners(" ou_a, ,ou_b") == {"ou_a", "ou_b"}
    cmd = build_claude_cmd("hi", "s1", "m", "bypassPermissions", "")
    assert cmd[-2:] == ["--resume", "s1"] and "--allowedTools" not in cmd and cmd[cmd.index("--model") + 1] == "m"
    assert "--model" not in build_claude_cmd("hi", None, "", "default", "")
    assert parse_claude_output('noise\n{"result":"ok","session_id":"s2"}\n')["session_id"] == "s2"
    assert parse_claude_output("boom")["is_error"] is True
    c = build_codex_cmd("t1", "", ["/a.png"])
    assert c[1:4] == ["exec", "resume", "t1"] and c[-2:] == ["--image=/a.png", "-"]
    assert build_codex_cmd(None, "m", [])[1:3] == ["exec", "--json"]
    jsonl = "\n".join([
        "Reading additional input from stdin...",
        '{"type":"thread.started","thread_id":"t9"}',
        '{"type":"item.completed","item":{"type":"agent_message","text":"ok"}}',
        '{"type":"turn.completed","usage":{"input_tokens":1}}',
    ])
    o = parse_codex_output(jsonl)
    assert o == {"is_error": False, "result": "ok", "session_id": "t9", "usage": {"input_tokens": 1}}
    assert parse_codex_output('{"type":"turn.failed","error":"x"}')["is_error"] is True
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "s.json")
        SessionStore(p).set("c1", "s9")
        assert SessionStore(p).get("c1") == "s9"
    print("selftest ok")


def main() -> None:
    import lark_oapi as lark
    from lark_oapi.api.im.v1 import (GetMessageResourceRequest, ReplyMessageRequest,
                                     ReplyMessageRequestBody)

    app_id = os.environ["FEISHU_APP_ID"]
    app_secret = os.environ["FEISHU_APP_SECRET"]
    domain = os.environ.get("FEISHU_DOMAIN", lark.FEISHU_DOMAIN)
    backend = os.environ.get("BOT_BACKEND", "api")
    # api 必须给模型；claude-code / codex 不给则用各自配置里的默认模型。BOT_MODEL=default 显式表示不指定
    default_model = "claude-sonnet-5" if backend == "api" else ""
    model = os.environ.get("BOT_MODEL") or os.environ.get("CLAUDE_MODEL") or default_model
    if model == "default":
        model = ""
    media_dir = os.environ.get("BOT_MEDIA_DIR", os.path.expanduser("~/.feishu-bot-media"))
    api = lark.Client.builder().app_id(app_id).app_secret(app_secret).domain(domain).build()

    locks: dict = defaultdict(threading.Lock)
    seen: OrderedDict = OrderedDict()
    seen_lock = threading.Lock()
    pool = ThreadPoolExecutor(max_workers=8)

    def reply(message_id: str, msg_type: str, content: str) -> bool:
        req = ReplyMessageRequest.builder().message_id(message_id).request_body(
            ReplyMessageRequestBody.builder().msg_type(msg_type).content(content).build()
        ).build()
        resp = api.im.v1.message.reply(req)
        if not resp.success():
            lark.logger.error(f"reply {msg_type} failed: code={resp.code} msg={resp.msg}")
        return resp.success()

    def send(message_id: str, markdown: str) -> None:
        if not reply(message_id, "interactive", card_content(markdown)):
            reply(message_id, "text", json.dumps({"text": markdown[:MAX_REPLY_CHARS]}, ensure_ascii=False))

    def download_images(message_id: str, image_keys: list) -> list:
        """下载消息里的图片，返回本地路径；单张失败只记日志。需要 im:resource 权限。"""
        os.makedirs(media_dir, exist_ok=True)
        paths = []
        for key in image_keys:
            req = GetMessageResourceRequest.builder().message_id(message_id) \
                .file_key(key).type("image").build()
            resp = api.im.v1.message_resource.get(req)
            if not resp.success():
                lark.logger.error(f"download image failed: code={resp.code} msg={resp.msg}")
                continue
            ext = os.path.splitext(resp.file_name or "")[1] or ".png"
            path = os.path.join(media_dir, f"{message_id}_{len(paths)}{ext}")
            with open(path, "wb") as f:
                f.write(resp.file.read())
            paths.append(path)
        return paths

    if backend in AGENT_BACKENDS:
        owners = parse_owners(os.environ.get("BOT_OWNER_OPEN_IDS", ""))
        workdir = os.environ.get("BOT_WORKDIR", os.getcwd())
        timeout = int(os.environ.get("BOT_TIMEOUT", "600"))
        permission_mode = os.environ.get("BOT_PERMISSION_MODE", "bypassPermissions")
        allowed_tools = os.environ.get("BOT_ALLOWED_TOOLS", "")
        sessions = SessionStore(os.environ.get(
            "BOT_STATE_FILE", os.path.expanduser("~/.feishu-bot-sessions.json")))

        def run_agent(text: str, images: list, session_id) -> dict:
            if backend == "codex":
                proc = subprocess.run(build_codex_cmd(session_id, model, images), cwd=workdir,
                                      input=text or "请看图片。", capture_output=True, text=True,
                                      timeout=timeout)
                return parse_codex_output(proc.stdout + "\n" + proc.stderr)
            cmd = build_claude_cmd(with_image_paths(text, images), session_id, model,
                                   permission_mode, allowed_tools)
            proc = subprocess.run(cmd, cwd=workdir, capture_output=True, text=True,
                                  timeout=timeout, stdin=subprocess.DEVNULL)
            return parse_claude_output(proc.stdout or proc.stderr)

        def handle(msg, sender: str, text: str, image_keys: list) -> None:
            if msg.chat_type != "p2p" or sender not in owners:
                send(msg.message_id, f"未授权执行。你的 open_id：`{sender}`")
                lark.logger.warning(f"rejected sender={sender} chat_type={msg.chat_type}")
                return
            with locks[msg.chat_id]:
                if text in RESET_WORDS and not image_keys:
                    sessions.set(msg.chat_id, None)
                    send(msg.message_id, "会话已重置，下一条消息开启新会话。")
                    return
                send(msg.message_id, "处理中…")
                images = download_images(msg.message_id, image_keys)
                sid = sessions.get(msg.chat_id)
                try:
                    out = run_agent(text, images, sid)
                    # 会话丢失时续接会报错，去掉续接重试一次
                    if sid and out.get("is_error") and re.search(r"session|thread|conversation",
                                                                  str(out.get("result", "")), re.I):
                        out = run_agent(text, images, None)
                except subprocess.TimeoutExpired:
                    send(msg.message_id, f"超过 {timeout} 秒未完成，已终止。")
                    return
                if out.get("session_id"):
                    sessions.set(msg.chat_id, out["session_id"])
                cost = out.get("total_cost_usd")
                parts = []
                if out.get("duration_ms"):
                    parts.append(f"耗时 {out['duration_ms'] / 1000:.0f}s")
                if isinstance(cost, (int, float)):
                    parts.append(f"${cost:.3f}")
                if out.get("usage"):
                    u = out["usage"]
                    parts.append(f"tokens in {u.get('input_tokens', 0)} / out {u.get('output_tokens', 0)}")
                footer = ("\n\n---\n" + " · ".join(parts)) if parts else ""
                prefix = "执行出错：\n" if out.get("is_error") else ""
                send(msg.message_id, prefix + (str(out.get("result") or "（空回复）")) + footer)
                lark.logger.info(f"done chat={msg.chat_id[:10]} err={out.get('is_error')} cost={cost}")
    else:
        import anthropic
        system = os.environ.get("CLAUDE_SYSTEM", "你是飞书里的 AI 助手，用简体中文简洁回答，可以使用 Markdown。")
        max_turns = int(os.environ.get("BOT_MAX_TURNS", "20"))
        max_tokens = int(os.environ.get("BOT_MAX_TOKENS", "4096"))
        claude = anthropic.Anthropic(
            api_key=os.environ["ANTHROPIC_API_KEY"],
            base_url=os.environ.get("ANTHROPIC_BASE_URL") or None,
            timeout=300,
        )
        histories: dict = defaultdict(list)

        def image_block(path: str) -> dict:
            ext = os.path.splitext(path)[1].lower().lstrip(".")
            media = {"jpg": "jpeg", "jpeg": "jpeg", "gif": "gif", "webp": "webp"}.get(ext, "png")
            with open(path, "rb") as f:
                data = base64.b64encode(f.read()).decode()
            return {"type": "image", "source": {"type": "base64", "media_type": f"image/{media}", "data": data}}

        def handle(msg, sender: str, text: str, image_keys: list) -> None:
            chat_id = msg.chat_id
            with locks[chat_id]:
                if text in RESET_WORDS and not image_keys:
                    histories[chat_id].clear()
                    send(msg.message_id, "上下文已清空。")
                    return
                images = download_images(msg.message_id, image_keys)
                if images:
                    content = [image_block(p) for p in images] + [{"type": "text", "text": text or "请描述这张图片。"}]
                else:
                    content = text
                history = trim_history(histories[chat_id] + [{"role": "user", "content": content}], max_turns)
                try:
                    resp = claude.messages.create(
                        model=model, max_tokens=max_tokens, system=system, messages=history,
                    )
                    answer = "".join(b.text for b in resp.content if b.type == "text").strip() or "（空回复）"
                except Exception as e:  # 网关错误时告诉用户，不丢上下文里的旧轮次
                    lark.logger.error(f"claude error: {e!r}")
                    send(msg.message_id, f"调用模型失败：{type(e).__name__}，稍后再试。")
                    return
                histories[chat_id] = history + [{"role": "assistant", "content": answer}]
                send(msg.message_id, answer)

    def on_message(data) -> None:
        msg = data.event.message
        sender = data.event.sender.sender_id.open_id
        with seen_lock:
            if msg.message_id in seen:
                return
            seen[msg.message_id] = True
            if len(seen) > 2000:
                seen.popitem(last=False)
        text, image_keys = parse_message(msg.message_type, msg.content)
        if text is None:
            pool.submit(send, msg.message_id, "目前支持文字、图片和图文消息。")
            return
        if text or image_keys:
            # 事件回调要尽快返回，下载和模型调用放到线程池
            pool.submit(handle, msg, sender, text, image_keys)

    handler = lark.EventDispatcherHandler.builder("", "") \
        .register_p2_im_message_receive_v1(on_message) \
        .build()
    ws = lark.ws.Client(app_id, app_secret, event_handler=handler, domain=domain, log_level=lark.LogLevel.INFO)
    lark.logger.info(f"feishu bot starting, backend={backend}, model={model or 'default'}")
    ws.start()


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    else:
        main()
