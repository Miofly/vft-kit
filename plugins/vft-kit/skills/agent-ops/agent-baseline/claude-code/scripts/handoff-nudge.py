#!/usr/bin/env python3
"""PostToolUse hook: nudge the main session to write a handoff doc once context crosses ~40%.

Rule it backs: global CLAUDE.md「交接文档」(or the handoff skill it points to)— when the main session's context exceeds about 40% of the
window, write a handoff doc and /clear (or start a new session). The rule had no trigger; this hook
supplies one from the real token count.

How the context size is measured: the latest non-sidechain assistant record in the transcript tail carries
`message.usage`; input_tokens + cache_read_input_tokens + cache_creation_input_tokens is the prompt size of
that turn, i.e. the live context. Window: HANDOFF_NUDGE_WINDOW (or CLAUDE_CODE_AUTO_COMPACT_WINDOW) env
override → model id containing "[1m]" → known 1M families (transcripts drop the "[1m]" suffix, so the id
alone cannot tell; see KNOWN_1M) → observed tokens > 200k imply 1M → else 200k.

Tiers: 40%, then every +15% (55/70/85). Each session records each tier once.

Shadow by default: writes one jsonl line per (session, tier) to ~/.cache/vft-kit/handoff-nudge.jsonl with
what it would have said. Only when the marker file ~/.cache/vft-kit/handoff-nudge.LIVE exists does it print
`hookSpecificOutput.additionalContext`. Any error/timeout → no output, exit 0.

Self-test: python3 handoff-nudge.py --self-test
Part of the idea adapted from affaan-m/ECC (MIT): scripts/lib/transcript-context.js, skills/strategic-compact.
"""
import json
import os
import re
import sys
import time

STD_WINDOW = 200_000
LARGE_WINDOW = 1_000_000
TAIL_BYTES = 512 * 1024
# Families that run with a 1M window in this setup while their transcript ids carry no "[1m]" marker.
# Override per machine with HANDOFF_NUDGE_1M_MODELS="regex"; HANDOFF_NUDGE_WINDOW wins over everything.
KNOWN_1M = r"claude-(opus-5|fable-5|mythos-5)(?![A-Za-z0-9])(?!-[A-Za-z])"


def cache_dir():
    return os.environ.get("HANDOFF_NUDGE_DIR") or os.path.join(os.path.expanduser("~"), ".cache", "vft-kit")


def thresholds():
    raw = os.environ.get("HANDOFF_NUDGE_TIERS", "0.40,0.55,0.70,0.85")
    out = []
    for p in raw.split(","):
        try:
            v = float(p)
            if 0 < v < 1:
                out.append(v)
        except ValueError:
            pass
    return sorted(out) or [0.40, 0.55, 0.70, 0.85]


def usage_tokens(rec):
    msg = rec.get("message") if isinstance(rec, dict) else None
    u = msg.get("usage") if isinstance(msg, dict) else None
    if not isinstance(u, dict):
        return 0
    t = 0
    for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"):
        v = u.get(k)
        if isinstance(v, (int, float)) and v > 0:
            t += int(v)
    return t


def is_main_assistant(rec):
    return (isinstance(rec, dict) and rec.get("type") == "assistant" and not rec.get("isSidechain")
            and (rec.get("message") or {}).get("model") not in (None, "<synthetic>"))


def resolve_window(model, tokens):
    for key in ("HANDOFF_NUDGE_WINDOW", "CLAUDE_CODE_AUTO_COMPACT_WINDOW"):
        try:
            v = int(os.environ.get(key, ""))
            if v > 0:
                return v
        except ValueError:
            pass
    model = model or ""
    if "[1m]" in model.lower():
        return LARGE_WINDOW
    if re.search(os.environ.get("HANDOFF_NUDGE_1M_MODELS") or KNOWN_1M, model):
        return LARGE_WINDOW
    if tokens > STD_WINDOW:
        return LARGE_WINDOW
    return STD_WINDOW


def judge(tokens, model):
    """Return (ratio, window, tier) — tier is the highest crossed threshold, or None."""
    window = resolve_window(model, tokens)
    ratio = tokens / window if window else 0.0
    tier = None
    for t in thresholds():
        if ratio >= t:
            tier = t
    return ratio, window, tier


def latest_usage(path):
    """(tokens, model, record) from the latest main-thread assistant record in the transcript tail."""
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            if size > TAIL_BYTES:
                f.seek(size - TAIL_BYTES)
            data = f.read().decode("utf-8", "replace")
    except OSError:
        return 0, "", None
    lines = data.split("\n")
    if size > TAIL_BYTES:
        lines = lines[1:]
    for line in reversed(lines):
        line = line.strip()
        if not line or '"usage"' not in line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if not is_main_assistant(rec):
            continue
        t = usage_tokens(rec)
        if t > 0:
            return t, rec["message"].get("model", ""), rec
    return 0, "", None


def message(ratio, tokens, window):
    return (f"[handoff-nudge] 主会话上下文已 {ratio:.0%}（约 {tokens // 1000}k / {window // 1000}k tokens）。"
            "按交接规范（全局 CLAUDE.md「交接文档」或其指向的 handoff skill）：基于完整对话写交接（五节＋回查），再 /clear 或新开会话；"
            "正处在实施中途就先做完当前一步再交接。")


def run(payload, now=None):
    """Hook core. Returns (log_entry or None, stdout_text or "")."""
    sid = str(payload.get("session_id") or "")
    path = payload.get("transcript_path") or ""
    if not sid or not path or not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", sid):
        return None, ""
    tokens, model, rec = latest_usage(path)
    if not tokens:
        return None, ""
    ratio, window, tier = judge(tokens, model)
    if tier is None:
        return None, ""
    d = cache_dir()
    state_dir = os.path.join(d, "handoff-nudge-state")
    os.makedirs(state_dir, exist_ok=True)
    state_f = os.path.join(state_dir, sid + ".json")
    try:
        done = json.load(open(state_f)).get("tiers", [])
    except (OSError, ValueError):
        done = []
    key = f"{tier:.2f}"
    if key in done:
        return None, ""
    done.append(key)
    live = os.path.exists(os.path.join(d, "handoff-nudge.LIVE"))
    text = message(ratio, tokens, window)
    entry = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now or time.time())), "session_id": sid,
             "tier": key, "ratio": round(ratio, 4), "tokens": tokens, "window": window, "model": model,
             "cwd": payload.get("cwd") or (rec or {}).get("cwd", ""), "event": payload.get("hook_event_name", ""),
             "mode": "live" if live else "shadow", "would_say": text}
    with open(os.path.join(d, "handoff-nudge.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    with open(state_f, "w") as f:
        json.dump({"tiers": done}, f)
    out = ""
    if live:
        out = json.dumps({"hookSpecificOutput": {"hookEventName": payload.get("hook_event_name") or "PostToolUse",
                                                 "additionalContext": text}}, ensure_ascii=False)
    return entry, out


def self_test():
    import tempfile
    tmp = tempfile.mkdtemp()
    os.environ["HANDOFF_NUDGE_DIR"] = tmp
    for k in ("HANDOFF_NUDGE_WINDOW", "CLAUDE_CODE_AUTO_COMPACT_WINDOW", "HANDOFF_NUDGE_TIERS", "HANDOFF_NUDGE_1M_MODELS"):
        os.environ.pop(k, None)
    tr = os.path.join(tmp, "t.jsonl")

    def write(tokens, model, side=False):
        with open(tr, "a") as f:
            f.write(json.dumps({"type": "assistant", "isSidechain": side, "message": {"model": model, "usage": {
                "input_tokens": 10, "cache_read_input_tokens": tokens - 10, "cache_creation_input_tokens": 0}}}) + "\n")

    assert resolve_window("claude-opus-5-5", 1000) == LARGE_WINDOW
    assert resolve_window("claude-opus-5-mini", 1000) == STD_WINDOW
    assert resolve_window("claude-sonnet-5", 1000) == STD_WINDOW
    assert resolve_window("claude-sonnet-5[1m]", 1000) == LARGE_WINDOW
    assert resolve_window("claude-sonnet-5", 250_000) == LARGE_WINDOW
    os.environ["HANDOFF_NUDGE_WINDOW"] = "400000"
    assert resolve_window("claude-opus-5-5", 1) == 400_000
    os.environ.pop("HANDOFF_NUDGE_WINDOW")
    p = {"session_id": "s1", "transcript_path": tr, "hook_event_name": "PostToolUse"}
    write(70_000, "claude-sonnet-5")
    assert run(p) == (None, "")                       # 35% → nothing
    write(90_000, "claude-sonnet-5")
    e, out = run(p)
    assert e and e["tier"] == "0.40" and e["mode"] == "shadow" and out == "", e   # 45% shadow
    assert run(p) == (None, "")                       # same tier once only
    write(190_000, "claude-sonnet-5", side=True)      # sidechain ignored
    assert run(p) == (None, "")
    open(os.path.join(tmp, "handoff-nudge.LIVE"), "w").close()
    write(120_000, "claude-sonnet-5")                 # 60% live
    e, out = run(p)
    assert e["tier"] == "0.55" and json.loads(out)["hookSpecificOutput"]["additionalContext"].startswith("[handoff-nudge]")
    assert run({"session_id": "../x", "transcript_path": tr}) == (None, "")
    lines = open(os.path.join(tmp, "handoff-nudge.jsonl")).read().splitlines()
    assert len(lines) == 2
    print("self-test ok")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        self_test()
        return
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        _, out = run(payload)
        if out:
            sys.stdout.write(out)
    except Exception:
        pass
    sys.exit(0)


if __name__ == "__main__":
    main()
