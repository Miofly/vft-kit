#!/usr/bin/env python3
"""PostToolUse hook (cc-* instances only): the instance keeps reading / restating without converging -> force a hypothesis.

xf-spark wrote "根因逐渐清晰，让我继续读…" 8 times in a row (AutoJs round 2) and restated the same sentence ~10 times
(round 6); the main session never does this. When the last 3 assistant texts of the current turn are all vague
"keep reading" lines, or are the same sentence (first 25 chars, digits/markup stripped), inject once per turn:
write 2 candidate causes and 1 command that tells them apart, or mark the item undecided and move on.
Replay (2026-10-23): 4 of 447 cc-xf turns, 0 of 2033 main-session turns.
State: ~/.cache/vft-kit/converge/<session_id> holds the turn key it last fired on. Fail-open; self-test: --self-test
"""
import json
import os
import re
import sys

STATE_DIR = os.path.expanduser('~/.cache/vft-kit/converge')
VAGUE = re.compile(r'逐渐清晰|越来越清楚|继续(读|看|查|深挖|分析)|还需要(确认|再看)|让我(再|继续)(看|读|查)'
                   r'|let me (continue|keep) (reading|looking)', re.I)
REASON = ('[converge] 你最近三段话都是「继续读 / 逐渐清晰」或同一句话重复，没有收敛。停下来写出：'
          '2 个候选原因（各自预测会看到什么），1 条能区分它们的命令，然后只跑这条命令。'
          '写不出候选原因，就把这一项标「未定」，转去下一条。')


def norm(t):
    return re.sub(r'[\d\s`*#|]+', '', t)[:25]


def turn_texts(path):
    """-> (key of the current turn, assistant texts in it)."""
    rows = []
    with open(path) as f:
        for line in f.readlines()[-400:]:
            try: rows.append(json.loads(line))
            except ValueError: pass
    key, texts = '', []
    for r in rows:
        c = (r.get('message') or {}).get('content')
        if r.get('isSidechain'):
            continue
        if r.get('type') == 'user' and not r.get('isMeta') and (isinstance(c, str) or (
                isinstance(c, list) and not any(isinstance(b, dict) and b.get('type') == 'tool_result' for b in c))):
            key, texts = r.get('uuid') or r.get('timestamp') or str(len(texts)), []
        elif r.get('type') == 'assistant' and isinstance(c, list):
            texts += [b['text'].strip() for b in c if isinstance(b, dict) and b.get('type') == 'text' and b.get('text', '').strip()]
    return key, texts


def decide(payload, env, state_dir=STATE_DIR):
    cfg = env.get('CLAUDE_CONFIG_DIR', '')
    if not cfg or os.path.normpath(os.path.expanduser(cfg)) == os.path.expanduser('~/.claude'):
        return None
    sid = re.sub(r'[^A-Za-z0-9-]', '', payload.get('session_id') or '')[:64]
    if not sid or not payload.get('transcript_path'):
        return None
    key, texts = turn_texts(payload['transcript_path'])
    w = texts[-3:]
    if len(w) < 3 or not (all(VAGUE.search(t) for t in w) or len({norm(t) for t in w}) == 1):
        return None
    path = os.path.join(state_dir, sid)
    try:
        if open(path).read() == key:
            return None  # once per turn
    except OSError:
        pass
    os.makedirs(state_dir, exist_ok=True)
    with open(path, 'w') as f:
        f.write(key)
    return {'hookSpecificOutput': {'hookEventName': 'PostToolUse', 'additionalContext': REASON}}


def self_test():
    import tempfile
    d = tempfile.mkdtemp()
    env = {'CLAUDE_CONFIG_DIR': '/u/.claude-max'}

    def run(texts, sid='s1', e=env, prompt_uuid='u1'):
        rows = [{'type': 'user', 'uuid': prompt_uuid, 'message': {'content': '查一下'}}]
        for t in texts:
            rows += [{'type': 'assistant', 'message': {'content': [{'type': 'text', 'text': t},
                                                                   {'type': 'tool_use', 'name': 'Read', 'input': {}}]}},
                     {'type': 'user', 'message': {'content': [{'type': 'tool_result', 'content': 'x'}]}}]
        p = os.path.join(d, 't.jsonl')
        with open(p, 'w') as f:
            f.write('\n'.join(json.dumps(r, ensure_ascii=False) for r in rows))
        return bool(decide({'session_id': sid, 'transcript_path': p}, e, d))
    vague = ['根因逐渐清晰。让我读关键源码文件。', '根因逐渐清晰。让我继续读关键源码。', '让我继续读挖矿死循环的代码。']
    same = ['并发 S1 验证在跑（3 账号 RUNNING）。等 stability', '并发 S1 验证在跑（3 账号 RUNNING）。等 stability'] * 2
    cases = [
        (run(vague), True),
        (run(vague), False),                                  # once per turn
        (run(vague, prompt_uuid='u2'), True),                 # new turn fires again
        (run(same[:3], sid='s2'), True),
        (run(['先看日志。', '日志说 OOM，查内存峰值。', '峰值 15G，换 lowvram 再跑。'], sid='s3'), False),
        (run(vague[:2], sid='s4'), False),
        (run(vague, sid='s5', e={'CLAUDE_CONFIG_DIR': os.path.expanduser('~/.claude')}), False),
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
