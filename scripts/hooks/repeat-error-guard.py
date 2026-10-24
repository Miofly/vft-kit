#!/usr/bin/env python3
"""PostToolUseFailure hook (cc-* instances only): the same error twice in a row -> stop retrying, find the cause.

Third-party models (xf-spark, glm) answer a failed tool call by changing a flag and retrying: glm hit the same
context-mode block on mvn 3 times, swapping run_in_background / nohup / dangerouslyDisableSandbox (bd49f9e1);
xf resubmitted a 3-71 min OpenI job 38 times, one shim tweak each, never reproducing locally (936561bc).
This hook keeps the last few error signatures per session and, when the new failure matches one of the last two,
adds context telling the model to read the error, check real state / reproduce locally, and change approach.
Signature: first line that looks like an error (else first line), digits and hex ids masked, 120 chars.
State: ~/.cache/vft-kit/repeat-error/<session_id>.json. Main config (~/.claude) is never touched.
Fail-open: any error prints nothing. Self-test: python3 repeat-error-guard.py --self-test
"""
import json
import os
import re
import sys

STATE_DIR = os.path.expanduser('~/.cache/vft-kit/repeat-error')
ERRLINE = re.compile(r'error|exception|traceback|failed|denied|not found|refused|timed? ?out|拒绝|失败|错误|拦', re.I)
REASON = ('[repeat-error] 这个报错和刚才那次一样，同一个错误第 2 次了。不要再换参数或绕过重试：'
          '1) 逐字读报错，它通常写明了原因或该怎么改（被 hook 拦下就按提示改写）；'
          '2) 看真实状态：文件、版本、日志、之前成功那次的参数，跟现在逐项对比；'
          '3) 远端或慢任务先在本地或几秒内的小实验里复现，复现并修好后再提交；'
          '4) 写出 2 个候选原因和 1 条能区分它们的检查，先跑这条检查。')


def signature(err):
    lines = [l.strip() for l in re.sub(r'\x1b\[[0-9;]*m', '', err or '').splitlines() if l.strip()]
    if not lines:
        return ''
    line = next((l for l in lines if ERRLINE.search(l)), lines[0])
    line = re.sub(r'\b[0-9a-f]{7,}\b', 'H', line, flags=re.I)
    return re.sub(r'\d+', '#', line)[:120]


def decide(payload, env, state_dir=STATE_DIR):
    cfg = env.get('CLAUDE_CONFIG_DIR', '')
    if not cfg or os.path.normpath(os.path.expanduser(cfg)) == os.path.expanduser('~/.claude'):
        return None
    sid = re.sub(r'[^A-Za-z0-9-]', '', payload.get('session_id') or '')[:64]
    if not sid or payload.get('is_interrupt'):
        return None
    err = payload.get('error')
    sig = signature(err if isinstance(err, str) else json.dumps(err, ensure_ascii=False))
    if not sig:
        return None
    path = os.path.join(state_dir, sid + '.json')
    try:
        with open(path) as f: seen = json.load(f)
    except (OSError, ValueError):
        seen = []
    repeat = sig in seen[-2:]
    os.makedirs(state_dir, exist_ok=True)
    with open(path, 'w') as f:
        json.dump((seen + [sig])[-5:], f, ensure_ascii=False)
    if not repeat:
        return None
    return {'hookSpecificOutput': {'hookEventName': 'PostToolUseFailure', 'additionalContext': REASON}}


def self_test():
    import tempfile
    d = tempfile.mkdtemp()
    env = {'CLAUDE_CONFIG_DIR': '/u/.claude-max'}
    run = lambda err, sid='s1', e=env, **k: bool(decide({'session_id': sid, 'error': err, **k}, e, d))
    blocked = 'Exit code 1\n[context-mode] mvn blocked: use ctx_execute (run 3)'
    cases = [
        (run(blocked), False),                                   # first time: nothing
        (run(blocked.replace('3', '4')), True),                  # same error, only a number differs
        (run('Traceback ...\nNameError: name List is not defined'), False),
        (run(blocked), True),                                    # within the last two signatures
        (run(blocked, sid='s2'), False),                         # other session
        (run(blocked, e={'CLAUDE_CONFIG_DIR': os.path.expanduser('~/.claude')}), False),  # main session
        (run(blocked, e={}), False),
        (run(blocked, sid='s3', is_interrupt=True), False),
        (run(''), False),
        (signature('ok line\nError: kernel 1b6363a7ff failed at 12:30') == 'Error: kernel H failed at #:#', True),
    ]
    bad = [i for i, (got, want) in enumerate(cases) if got != want]
    print('self-test ' + ('FAIL cases ' + repr(bad) if bad else 'ok'))
    return 1 if bad else 0


if __name__ == '__main__':
    if '--self-test' in sys.argv:
        sys.exit(self_test())
    try:
        out = decide(json.load(sys.stdin), os.environ)
    except Exception:
        sys.exit(0)
    if out:
        print(json.dumps(out, ensure_ascii=False))
