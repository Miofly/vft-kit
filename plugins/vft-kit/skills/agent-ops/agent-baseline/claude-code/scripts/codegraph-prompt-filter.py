#!/usr/bin/env python3
"""Gate for `codegraph prompt-hook` (UserPromptSubmit).

Two generations of logic live here:

legacy  Old wide gate: skip task notifications, strip URLs, then pass any prompt
        that looks vaguely code-ish (extensions, a/b paths, camel/snake case,
        Chinese words such as 实现/修复) to `codegraph prompt-hook` and forward its
        ~15-18 KB output unchanged. Claude Code cuts that to a 2 KB preview, which
        was often unrelated to the question.
new     1. Trigger only on explicit identifiers: CamelCase/camelCase names,
           file names with a code extension, snake_case of >= 6 chars, or
           `backticked` symbols. Plain Chinese text never triggers.
        2. Skip when the nearest .codegraph/codegraph.db is larger than
           CODEGRAPH_FILTER_MAX_DB_MB (default 1000). Measured on this machine:
           546 MB index 2.3 s, 1.2 GB 8-9 s, 1.4 GB 12 s; the big mixed indexes
           would always hit the timeout.
        3. Run codegraph with an 8 s timeout (CODEGRAPH_FILTER_TIMEOUT); on
           timeout inject nothing.
        4. Relevance gate: at least one prompt identifier must appear in the
           result as a complete symbol name or as a file basename/stem.
        5. Inject our own summary instead of the raw output: `Found N ...` plus
           one line per file "path — first 5 symbols", <= 1500 bytes.

Mode switch (env var wins over marker files):
  CODEGRAPH_FILTER_MODE=shadow|live|legacy
  touch ~/.cache/vft-kit/codegraph-prompt-filter.SHADOW  -> shadow
  touch ~/.cache/vft-kit/codegraph-prompt-filter.LEGACY  -> legacy (no log)
  neither                                                -> live (default)
shadow: behave exactly like legacy (output unchanged), and append what the new
        logic would have done to the decision log.
live:   use the new logic; still append the decision to the log.
Live became the default on 2026-10-20 after shadow data (224 prompts): legacy
injected 105 KB over 49 prompts (5 of 6 large ones irrelevant, 11 timeouts),
new gate 975 B over 1 relevant prompt.

Decision log: CODEGRAPH_FILTER_SHADOW_LOG (default
~/.cache/vft-kit/codegraph-prompt-filter.jsonl). One JSON line per prompt; only
the first 80 characters of the prompt and the extracted identifiers are kept.

Failure policy: any exception in the new logic falls back to the legacy logic
(shadow/legacy) or to silence (live); the exit code is always 0. Legacy
codegraph calls are capped at 9 s so Claude Code's 10 s hook timeout never
fires on us.
Self-test: python3 codegraph-prompt-filter.py --selftest
"""
import json, os, re, subprocess, sys, time

HOME = os.path.expanduser("~")
FLAG_DIR = os.path.join(HOME, ".cache", "vft-kit")
SHADOW_FLAG = os.path.join(FLAG_DIR, "codegraph-prompt-filter.SHADOW")
LEGACY_FLAG = os.path.join(FLAG_DIR, "codegraph-prompt-filter.LEGACY")
DEFAULT_LOG = os.path.join(FLAG_DIR, "codegraph-prompt-filter.jsonl")
NEW_TIMEOUT = float(os.environ.get("CODEGRAPH_FILTER_TIMEOUT", "8"))
LEGACY_TIMEOUT = 9.0
MAX_DB_MB = float(os.environ.get("CODEGRAPH_FILTER_MAX_DB_MB", "1000"))
SUMMARY_MAX = 1500

# ---------------------------------------------------------------- legacy gate
CODE_HINT = re.compile(
    r"(\.(java|ts|tsx|js|mjs|vue|py|go|rs|kt|sql|yaml|yml|json|sh)\b)"  # file extensions
    r"|([A-Za-z_]+/[A-Za-z_./-]+)"                                      # paths
    r"|(\b[a-z]+[A-Z][A-Za-z]+\b)|(\b[A-Z][a-z]+[A-Z][A-Za-z]+\b)"      # camelCase / PascalCase
    r"|(\b[a-z]+_[a-z_]+\b)"                                            # snake_case
    r"|(函数|代码|报错|异常|接口|类名|方法|组件|编译|单测|测试用例|重构|实现|修复|bug|Bug|BUG|stack|trace)"
)

URL = re.compile(r"(https?://|www\.)\S+|\b[\w-]+(\.[\w-]+)*\.(com|org|io|net|ai|cn|dev|app)(/\S*)?")


def is_notification(prompt: str) -> bool:
    return "<task-notification>" in prompt or "[SYSTEM NOTIFICATION" in prompt


def should_run(prompt: str) -> bool:
    if is_notification(prompt):
        return False
    return bool(CODE_HINT.search(URL.sub(" ", prompt)))


# ------------------------------------------------------------- new extraction
EXT = ("java|ts|tsx|js|jsx|mjs|cjs|vue|py|go|rs|kt|kts|sql|yaml|yml|json|sh|bash|zsh|"
       "rb|php|swift|c|cc|cpp|h|hpp|cs|scala|dart|lua|toml|xml|gradle")
BACKTICK = re.compile(r"`([^`\n]{2,120})`")
FILE_NAME = re.compile(r"(?<![\w.-])([A-Za-z0-9_][\w.-]*\.(?:%s))(?![\w-])" % EXT)
CAMEL = re.compile(r"(?<![\w$])([a-z][a-z0-9]*(?:[A-Z][a-z0-9]+)+|[A-Z][a-z0-9]+(?:[A-Z][A-Za-z0-9]*)+)(?![\w$])")
SNAKE = re.compile(r"(?<![\w$])([A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)+)(?![\w$])")
MEMBER = re.compile(r"(?<![\w$])([A-Za-z_$][\w$]*)\.([A-Za-z_$][\w$]*)(?![\w$])")
SYMBOLISH = re.compile(r"[\w$./:-]+(?:\(\))?")
# Product / brand names that look like CamelCase but are never local symbols.
STOP = {
    "GitHub", "GitLab", "JavaScript", "TypeScript", "YouTube", "OpenAI", "ChatGPT", "DeepSeek",
    "PowerShell", "WeChat", "iPhone", "iPad", "iCloud", "macOS", "iOS", "LinkedIn", "PayPal",
    "WordPress", "PostgreSQL", "MySQL", "MongoDB", "ModelScope", "HuggingFace", "AiStudio",
    "ClaudeCode", "CodeGraph", "LaTeX", "FastAPI", "NodeJS", "VSCode", "IntelliJ", "PyTorch",
    "TensorFlow", "OpenI", "MiniMax", "LoRA", "ComfyUI", "SpringBoot", "CloudFlare", "GitHubActions",
    "QQMusic", "BiliBili", "ByteDance", "DingTalk", "WeCom", "TikTok", "OneDrive", "DropBox",
}
STOP_FILES = {"node.js", "vue.js", "next.js", "nuxt.js", "three.js", "d3.js", "chart.js", "express.js",
              "react.js", "p5.js", "moment.js", "lame.js"}


def extract_idents(prompt: str) -> list:
    """Explicit code identifiers in the prompt, in first-seen order."""
    if is_notification(prompt):
        return []
    text = URL.sub(" ", prompt)
    found = []

    def add(tok):
        tok = tok.strip(".-:")
        if tok and tok not in found and tok not in STOP and tok.lower() not in STOP_FILES:
            found.append(tok)

    # `symbol` / `path/to/file.ext` / `Cls.method()` / `Cls::method`; commands with spaces don't count.
    for m in BACKTICK.finditer(text):
        body = m.group(1).strip()
        if not SYMBOLISH.fullmatch(body) or not re.search(r"[A-Za-z]", body):
            continue
        base = body.rstrip("()").rstrip("/").rsplit("/", 1)[-1].replace("::", ".")
        if FILE_NAME.fullmatch(base) or "." not in base:
            if len(base) >= 3:
                add(base)
        else:
            for part in base.split("."):
                if len(part) >= 3:
                    add(part)
    for m in FILE_NAME.finditer(text):
        add(m.group(1))
    for m in CAMEL.finditer(text):
        add(m.group(1))
    for m in SNAKE.finditer(text):
        if len(m.group(1)) >= 6:
            add(m.group(1))
    # `Foo.bar` member access: also look for `bar` once `Foo` already counts.
    for m in MEMBER.finditer(text):
        left, right = m.group(1), m.group(2)
        if left in found and not re.fullmatch(EXT, right) and len(right) >= 3:
            add(right)
    return found


# ----------------------------------------------------------- result parsing
HEADER = re.compile(r"^\*\*`([^`]+)`\*\*(?:\s+—\s+(.*))?$")
BLAST = re.compile(r"^- `([^`]+)` \(([^:)]+):\d+\)")
SYM = re.compile(r"([A-Za-z_$][\w$.]*)\(([a-z_ ]+)\)")
FOUND = re.compile(r"Found (\d+) symbols? across (\d+) files?")
EDGE_KINDS = {"calls", "references", "imports", "instantiates", "extends", "implements"}


def parse_result(out: str):
    """-> (found_line, {path: [symbols]}, all_names)"""
    files, names = {}, set()
    m = FOUND.search(out)
    found_line = m.group(0) + "." if m else ""
    for line in out.splitlines():
        h = HEADER.match(line.strip())
        if h:
            path = h.group(1)
            syms = files.setdefault(path, [])
            for s, kind in SYM.findall(h.group(2) or ""):
                names.add(s)
                if kind.strip() not in EDGE_KINDS and s not in syms:
                    syms.append(s)
            continue
        b = BLAST.match(line.strip())
        if b:
            sym, path = b.group(1), b.group(2)
            names.add(sym)
            syms = files.setdefault(path, [])
            if sym not in syms:
                syms.insert(0, sym)
    return found_line, files, names


def relevance(idents, files, names):
    keys = set(names)
    for p in files:
        base = p.rsplit("/", 1)[-1]
        keys.add(base)
        keys.add(base.rsplit(".", 1)[0])
    return [i for i in idents if i in keys]


def short_path(p, limit=90):
    if len(p) <= limit:
        return p
    # Keep the first segment (module / package root) and as many trailing segments as fit.
    parts = p.split("/")
    head, tail = parts[0], [parts[-1]]
    for seg in reversed(parts[1:-1]):
        if len(head) + len("/…/") + len("/".join([seg] + tail)) > limit:
            break
        tail.insert(0, seg)
    out = head + "/…/" + "/".join(tail)
    return out if len(out) <= limit + 20 else "…/" + parts[-1]


def build_summary(found_line, files, matched):
    head = ('<codegraph_context note="CodeGraph 摘要，命中 %s；要源码再调 codegraph_explore">'
            % ", ".join(matched[:5]))
    tail = "</codegraph_context>"
    lines = [head, found_line or "Found %d files." % len(files)]

    def hit(item):
        path, syms = item
        base = path.rsplit("/", 1)[-1]
        return not (base in matched or base.rsplit(".", 1)[0] in matched or any(s in matched for s in syms))

    for path, syms in sorted(files.items(), key=hit):
        ordered = [s for s in syms if s in matched] + [s for s in syms if s not in matched]
        line = "- " + short_path(path) + (" — " + ", ".join(ordered[:5]) if ordered else "")
        if len("\n".join(lines + [line, tail]).encode()) > SUMMARY_MAX:
            break
        lines.append(line)
    return "\n".join(lines + [tail]) + "\n"


# --------------------------------------------------------------- runtime bits
def mode():
    env = os.environ.get("CODEGRAPH_FILTER_MODE", "").strip().lower()
    if env in ("shadow", "live", "legacy"):
        return env
    if os.path.exists(SHADOW_FLAG):
        return "shadow"
    if os.path.exists(LEGACY_FLAG):
        return "legacy"
    return "live"


def index_db(cwd):
    d = os.path.abspath(cwd or os.getcwd())
    while True:
        db = os.path.join(d, ".codegraph", "codegraph.db")
        if os.path.isfile(db):
            return db
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def run_codegraph(raw, cwd, timeout):
    t = time.time()
    try:
        r = subprocess.run(["codegraph", "prompt-hook"], input=raw, text=True, capture_output=True,
                           timeout=timeout, cwd=cwd if cwd and os.path.isdir(cwd) else None)
        return r.stdout or "", round((time.time() - t) * 1000), None
    except subprocess.TimeoutExpired:
        return None, round((time.time() - t) * 1000), "timeout"
    except Exception as e:  # codegraph missing etc.
        return None, round((time.time() - t) * 1000), type(e).__name__


def new_decide(prompt, cwd, idents, cached=None, allow_call=True):
    """New-logic decision. cached=(out, ms, err) reuses a legacy codegraph run."""
    d = {"trigger": bool(idents), "inject": False, "summary_bytes": 0}
    if not idents:
        d["reason"] = "no_identifier"
        return d, None
    db = index_db(cwd)
    if db is None:
        d["reason"] = "no_index"
        return d, None
    size_mb = round(os.path.getsize(db) / 1048576)
    d["db_mb"] = size_mb
    if size_mb > MAX_DB_MB:
        d["reason"] = "index_too_big"
        return d, None
    if cached is not None:
        out, ms, err = cached
        if err is None and ms > NEW_TIMEOUT * 1000:
            out, err = None, "timeout"
    elif allow_call:
        out, ms, err = run_codegraph(json.dumps({"prompt": prompt, "cwd": cwd}), cwd, NEW_TIMEOUT)
    else:
        d["reason"] = "not_evaluated"
        return d, None
    d["codegraph_ms"] = ms
    if err:
        d["reason"] = err
        return d, None
    if not out.strip():
        d["reason"] = "empty_result"
        return d, None
    found_line, files, names = parse_result(out)
    matched = relevance(idents, files, names)
    d["result_files"] = len(files)
    d["matched"] = matched
    if not matched:
        d["reason"] = "irrelevant"
        return d, None
    summary = build_summary(found_line, files, matched)
    d.update(inject=True, reason="relevant", summary_bytes=len(summary.encode()))
    return d, summary


def log(entry):
    try:
        path = os.environ.get("CODEGRAPH_FILTER_SHADOW_LOG") or DEFAULT_LOG
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        pass


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
        prompt = data.get("prompt", "") or ""
        cwd = data.get("cwd") or os.getcwd()
    except Exception:
        prompt, cwd = raw, os.getcwd()
    m = mode()
    t0 = time.time()
    entry = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "mode": m, "cwd": cwd,
             "prompt_head": prompt[:80]}

    if m == "live":
        try:
            idents = extract_idents(prompt)
            entry["idents"] = idents[:20]
            d, summary = new_decide(prompt, cwd, idents)
            if summary:
                sys.stdout.write(summary)
        except Exception as e:  # live failure -> silent
            d = {"error": type(e).__name__, "inject": False}
        d["total_ms"] = round((time.time() - t0) * 1000)
        entry["new"] = d
        log(entry)
        return 0

    # shadow / legacy: legacy behaviour, unchanged output.
    old_run = should_run(prompt)
    cached = None
    if old_run:
        cached = run_codegraph(raw, cwd, LEGACY_TIMEOUT)
        if cached[0]:
            sys.stdout.write(cached[0])
            sys.stdout.flush()
    if m == "legacy":
        return 0
    entry["old"] = {"run": old_run, "bytes": len((cached[0] or "").encode()) if cached else 0,
                    "ms": cached[1] if cached else 0, "err": cached[2] if cached else None}
    try:
        t1 = time.time()
        idents = extract_idents(prompt)
        entry["idents"] = idents[:20]
        d, _ = new_decide(prompt, cwd, idents, cached=cached, allow_call=False)
        # Estimated new-mode latency: own overhead + the codegraph call it would make.
        d["total_ms"] = round((time.time() - t1) * 1000) + (d.get("codegraph_ms") or 0)
    except Exception as e:
        d = {"error": type(e).__name__}
    entry["new"] = d
    log(entry)
    return 0


# ------------------------------------------------------------------ selftest
FAKE_OUT = """<codegraph_context note="x">
**Exploration: q**

Found 55 symbols across 3 files.

**Blast radius — what depends on these (update/verify before editing)**

- `AiArticlePipeline` (wfly-module-aiarticle/src/main/java/cn/wfly/aiarticle/AiArticlePipeline.java:12) — 9 callers
- `humanize` (wfly-module-aiarticle/src/main/java/cn/wfly/aiarticle/AiArticlePipeline.java:88) — 2 callers

**Source Code**

**`wfly-module-aiarticle/src/main/java/cn/wfly/aiarticle/AiArticlePipeline.java`** — ⚠ changed on disk
**`wfly-module-aiarticle/src/main/java/cn/wfly/aiarticle/AiArticleBudget.java`** — callText(method), AiArticleBudget(class)
**`claude-code/scripts/dispatch-review-gate-hook.sh`** — main(function), list_pending(function)
**`wfly-module-social/src/main/java/ArticlePublisherController.java`** — success(calls), CommonResult(references), article(method)
</codegraph_context>
"""
FAKE_IRRELEVANT = """Found 40 symbols across 2 files.
**`wfly-framework/src/main/java/cn/wfly/Scope.java`** — Scope(class), of(method)
**`project/blog/src/lame/lamejs.js`** — Mp3Encoder(class), encodeBuffer(method)
"""


def selftest():
    bad = []

    def check(name, cond):
        if not cond:
            bad.append(name)

    # 1. legacy gate unchanged
    legacy = {
        "<task-notification><task-id>x</task-id></task-notification>": False,
        "帮我思考怎么减少token消耗": False,
        "aistudio现在什么进展": False,
        "修复 VideoTaskServiceImpl 的空指针": True,
        "看下 src/views/tools/index.vue 为什么报错": True,
        "lease_account_db 脚本续租": True,
        "https://github.com/tamaratran/fast-jev-compaction\n\n这个项目对我现在的工作流有用吗": False,
        "github.com/jaredpalmer/kev 这个呢 也看看": False,
        "https://github.com/a/b 参考它修复 src/utils/date.ts 的报错": True,
    }
    for p, want in legacy.items():
        check("legacy:" + p[:20], should_run(p) == want)

    # 2. new trigger: negatives
    pasted_plan = ("方案：1. 把 skill 拆成公有和私有两层，私有层只放账号配置；2. 触发词写进 description；"
                   "3. 实现时先影子运行，记录 a/b 对比，再切生效；修复旧逻辑里 hook 超时的问题，"
                   "参考 https://github.com/foo/bar_baz_qux/blob/main/SomeThing.java")
    for p in ["把 GPU 监控挂上", "实现一下这个需求", pasted_plan, "修复一下这个 bug",
              "<task-notification>AiArticlePipeline</task-notification>", "看看 GitHub 和 OpenAI 的新闻",
              "看下 a/b 目录", "改下 SKILL.md 的说明"]:
        check("neg:" + p[:16], extract_idents(p) == [])
    # 3. new trigger: positives
    check("pos:sh", "dispatch-review-gate-hook.sh" in extract_idents("`dispatch-review-gate-hook.sh` 每轮刷旧任务"))
    check("pos:sh-bare", "dispatch-review-gate-hook.sh" in extract_idents("dispatch-review-gate-hook.sh 每轮刷旧任务"))
    ids = extract_idents("AiArticlePipeline.humanize 为什么慢")
    check("pos:member", ids[:2] == ["AiArticlePipeline", "humanize"])
    check("pos:snake", extract_idents("lease_account_db 续租") == ["lease_account_db"])
    check("neg:short-snake", extract_idents("a_b 续租") == [])
    check("pos:backtick", "humanize" in extract_idents("看下 `humanize` 函数"))
    check("pos:backtick-path", extract_idents("看 `src/utils/date.ts`") == ["date.ts"])
    check("pos:backtick-member", extract_idents("`Foo.bar()` 呢") == ["Foo", "bar"])
    check("neg:backtick-cmd", extract_idents("跑一下 `git status` 和 `npm run dev`") == [])
    check("neg:node.js", extract_idents("Node.js 和 Vue.js 选哪个") == [])
    check("neg:bare-url", extract_idents("github.com/foo/some_thing_long 这个呢") == [])
    check("pos:camel", extract_idents("看 VideoTaskServiceImpl 和 getUserInfo") == ["VideoTaskServiceImpl", "getUserInfo"])

    # 4. relevance gate on fake codegraph output
    f_line, files, names = parse_result(FAKE_OUT)
    check("parse:found", f_line == "Found 55 symbols across 3 files.")
    check("rel:member", relevance(["AiArticlePipeline", "humanize"], files, names) == ["AiArticlePipeline", "humanize"])
    check("rel:file", relevance(["dispatch-review-gate-hook.sh"], files, names) == ["dispatch-review-gate-hook.sh"])
    check("rel:none", relevance(["GpuWatcher"], files, names) == [])
    _, f2, n2 = parse_result(FAKE_IRRELEVANT)
    check("rel:irrelevant", relevance(["SkillPlan", "agent_baseline"], f2, n2) == [])
    s = build_summary(f_line, files, ["AiArticlePipeline", "humanize"])
    check("sum:size", len(s.encode()) <= SUMMARY_MAX)
    check("sum:first", s.splitlines()[2].startswith("- wfly-module-aiarticle/src/main/java/cn/wfly/aiarticle/AiArticlePipeline.java — humanize, AiArticlePipeline"))
    check("sum:edge-kinds", "success" not in s and "article" in s)
    sp = short_path("wfly-module-aiarticle/src/main/java/cn/wfly/module/aiarticle/service/AiArticlePipelineVeryLongName.java", 60)
    check("sum:short-path", sp.startswith("wfly-module-aiarticle/…/") and sp.endswith("/AiArticlePipelineVeryLongName.java"))
    big = {"dir%02d/%s/File%02d.java" % (i, "x" * 60, i): ["sym%d" % j for j in range(9)] for i in range(40)}
    check("sum:cap", len(build_summary("Found 999 symbols across 40 files.", big, ["File01"]).encode()) <= SUMMARY_MAX)

    # 5. new_decide end to end with cached output (no codegraph call)
    tmp = os.path.join(os.environ.get("TMPDIR", "/tmp"), "cgf-selftest-%d" % os.getpid())
    os.makedirs(os.path.join(tmp, ".codegraph"), exist_ok=True)
    open(os.path.join(tmp, ".codegraph", "codegraph.db"), "w").close()
    try:
        d, summ = new_decide("q", tmp, ["AiArticlePipeline", "humanize"], cached=(FAKE_OUT, 100, None))
        check("dec:inject", d["inject"] and summ and d["summary_bytes"] <= SUMMARY_MAX)
        d, summ = new_decide("q", tmp, ["SkillPlan"], cached=(FAKE_IRRELEVANT, 100, None))
        check("dec:irrelevant", not d["inject"] and d["reason"] == "irrelevant" and summ is None)
        d, _ = new_decide("q", tmp, ["AiArticlePipeline"], cached=(FAKE_OUT, 9000, None))
        check("dec:slow", d["reason"] == "timeout" and not d["inject"])
        d, _ = new_decide("q", tmp, ["X1Y"], cached=(None, 8000, "timeout"))
        check("dec:timeout", d["reason"] == "timeout")
        d, _ = new_decide("q", tmp, [], cached=(FAKE_OUT, 100, None))
        check("dec:noident", d["reason"] == "no_identifier")
        d, _ = new_decide("q", "/", ["AiArticlePipeline"], cached=(FAKE_OUT, 100, None))
        check("dec:noindex", d["reason"] == "no_index")
    finally:
        for p in (os.path.join(tmp, ".codegraph", "codegraph.db"),):
            os.remove(p)
        os.rmdir(os.path.join(tmp, ".codegraph"))
        os.rmdir(tmp)

    print("selftest", "FAIL " + repr(bad) if bad else "ok")
    return 1 if bad else 0


if __name__ == "__main__":
    if "--selftest" in sys.argv or "--self-test" in sys.argv:
        sys.exit(selftest())
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
