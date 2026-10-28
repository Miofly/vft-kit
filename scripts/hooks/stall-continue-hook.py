#!/usr/bin/env python3
"""Stop hook: when a third-party-model instance announces its next step and then ends the turn, push it on once.

spark-x2.6 (cc-as / cc-xf) sometimes ends a turn mid-task with only "直接抓 raw README。" and no tool call
(seen in ~/.claude-as/turns.jsonl: finish=stop, 0 tool calls, 93 tokens). Claude Code then waits for the user.
This hook blocks that stop once when all hold:
  - the instance is not the main config (CLAUDE_CONFIG_DIR set and not ~/.claude): the main model does not do this;
  - stop_hook_active is false (never blocks twice in a row);
  - the last message before the final reply is a tool_result (mid-task, not answering the user);
  - the final reply has no tool_use and its text is short and announces an action ("直接抓…", "再看…", "Let me…").
Two more one-shot pushes (same instance / stop_hook_active / no-tool_use gates, any reply length):
  - ASK: the reply ends by offering options ("要不要我…", "要的话我…", "…还是…？你定") without naming an
    irreversible action (commit/push/删除/付费/发布…). In cc-xf transcripts 21/44 turn ends did this and the user
    had to say "别老问我" 4 times; rules alone did not stick.
  - WAIT: in non-interactive mode (CLAUDE_CODE_ENTRYPOINT=sdk-cli, i.e. `claude -p` / dispatched task) the reply
    ends with "等…完成后回报". Ending the turn there exits the session and nobody reads the background task
    (2026-10-23 coach round 1, T1: kqi run left orphaned).
  - THEORY / GIVEUP: the reply concludes from "理论上 / 基于架构" without a measurement, or calls a stage "改不了 /
    固定成本" without naming what was tried or the physical floor (cc-xf did both in 1b6363a7; uv later cut that
    "fixed" setup by 85s). Also caught in table / estimate form: "❌ 无法加速", "理论 ~60-90s", "基于架构预估".
  - OVERCLAIM: "已是最优 / 略胜 / 完美 / 净赚" with no sample count (cc-advise reviews: 14 of 47 findings were
    conclusions overturned by data; 1b6363a7 called a winner at n=3).
  - FIXED: "已修复 / 验证通过" when no command ran after the last Edit/Write this turn (xf AutoJs runs: 0 of 5
    code-changing rounds ran the fix on the phone; glm declared "全链路验证通过" on 1 sample).
Fail-open: any error prints nothing. Self-test: python3 stall-continue-hook.py --self-test
"""
import json
import os
import re
import sys

MAX_TEXT = 300
ANNOUNCE = re.compile(
    r'(?:^|[。！；，,.!\n])\s*(?:我|我先|我来|让我|现在|接着|然后|下一步|先|再|改用|改走|直接|开始)?\s*'
    r'(?:抓|查|看|跑|读|执行|调用|运行|拿|取|改|写|装|试|搜|拉|下载|解析|验证|确认)'
    r'|\b(?:let me|i\'ll|i will|next,? i|now i)\b', re.I)
REASON = ('你刚才说了下一步要做的事，但没有调用任何工具就结束了这一轮。现在直接调用工具去执行；'
          '如果任务其实已经完成，就给出最终答复。')
ASK = re.compile(r'(要不要我|要的话我|需要的话我|要我[^。\n]{0,40}[吗？?]|需要我[^。\n]{0,40}[吗？?]|还是[^。\n]{0,60}[？?]'
                 r'|你(来)?定[。.！!]?\s*$|请(你)?选择|是否需要|待你定|你定下一步|先说清再)')  # 待你定/先说清再: menu-and-stop seen in 936561bc #3022, 1b6363a7 #210
LOOP = '[loop-guard]'  # written by the ccmax LiteLLM proxy (cc-as/tool_text_hook.py LoopGuard) when it cuts a repeat loop
LOOP_REASON = ('上一次回复的推理陷入复读，被代理中断了，这一轮没有任何产出。不要沿用刚才的思路，也不要解释这次中断：'
               '直接调用下一个工具继续原任务；如果任务其实已经完成，就给出最终答复。')
QUESTION = re.compile(r'(吗|么|呢|对不对|是不是|哪个|哪些|什么|怎么|为什么|多少|几个)\s*[？?]?\s*$|[？?]\s*$')
IRREVERSIBLE = re.compile(r'commit|push|merge|提交|推送|删除|删掉|清空|付费|花钱|积分|外发|发布|部署|上线|拍板|业务')
ASK_REASON = ('你在结尾把选择题丢给了用户。用户多次要求「自己决定、别老问我」：选你推荐的那项，直接做完、核实后再汇报。'
              '只有不可逆或外发的动作（commit/push/删除/花钱/发布）和业务取舍才问；如果用户这次只要方案或解释，'
              '就删掉这句提问直接结束。')
WAIT = re.compile(r'等[^。\n]{0,30}(完成|跑完|出结果|结束|出图)|唤醒我|完成后(回报|告诉|汇报)|挂(上|着)[^。\n]{0,12}(监控|后台)')
WAIT_REASON = ('现在是非交互模式（claude -p / 任务书派发）：结束本轮等于会话退出，后台任务完成时没人接。'
               '改成前台等待：Bash 跑 `end=$((SECONDS+540)); until <查完成> || [ $SECONDS -ge $end ]; do sleep 30; done; <查状态>`，'
               '没完成就再跑一次，拿到结果、核实后再给最终汇报。')

THEORY = re.compile(r'理论上|理论(更|会)?快|理论\s*[~～约]?\s*\d|基于架构|基于[^。\n]{0,6}预估|按理说|应该会更快|估计会更快')
THEORY_REASON = ('你的结论里有「理论上 / 基于架构」这类没实测的判断。能跑就先跑出实测数字再下结论；'
                 '确实跑不了的，把这句改成「未验证：……（原因）」，不要当结论写。')
GIVEUP = re.compile(r'改不了|没法再压|无法再压|压不动|固定成本|无法优化|没有优化空间|无法加速|不可压|❌\s*(无法|不可)')
GIVEUP_REASON = ('你判了某段「改不了 / 固定成本」。按 skill cc-experiment：只有试过至少一种替代做法、'
                 '或算出它已贴近物理下限（带宽×字节数等）才能这么说。补上试过什么或下限的算式；都没有就把它列进下一波实验。')
# Assertions only: "最优路线" (a doc name), "找最优方案", "最优先" are not claims (replay of 403 cc-xf turn ends, 2026-10-23).
OVERCLAIM = re.compile(r'(已|就|定为|确定|证明|墙钟|才)是?最优|最优(解|的是)|完美|略胜|净赚|稳定(更)?快')
OVERCLAIM_REASON = ('你用了「最优 / 完美 / 略胜」这类比较结论，但没写样本数。补上依据：各跑了几次（n=）、是否同批、'
                    '差值是否大于平台波动；n<3 或跨时段的只能写「初步、未定」。没做过比较就删掉这个词。')
FIXED = re.compile(r'验证通过|已修复|修复完成|修好了|全链路(验证)?通过|问题已解决')
EDIT_TOOLS = {'Edit', 'Write', 'NotebookEdit', 'MultiEdit'}
FIXED_REASON = ('你说已修复 / 验证通过，但最后一次改文件之后没有跑过任何命令。验证要按用户原始的输入规模和路径跑一次，'
                '看到业务结果（不是构建通过、不是单个样本）；先失败后成功的，先解释第一次为什么失败。现在去跑；'
                '确实跑不了的，把结论改成「已改未验证：……（原因）」。')


def turn_tail(path):
    """-> (final assistant blocks, whether the message before them is a tool_result)."""
    rows = []
    with open(path) as f:
        for line in f.readlines()[-400:]:
            try: rows.append(json.loads(line))
            except ValueError: pass
    rows = [r for r in rows if r.get('type') in ('user', 'assistant') and not r.get('isMeta')]
    final = []
    while rows and rows[-1]['type'] == 'assistant':
        c = rows.pop()['message'].get('content') or []
        final = (c if isinstance(c, list) else [{'type': 'text', 'text': c}]) + final
    prev = rows[-1]['message'].get('content') if rows else None
    after_tool = isinstance(prev, list) and any(isinstance(b, dict) and b.get('type') == 'tool_result' for b in prev)
    prompt = '' if after_tool else prev if isinstance(prev, str) else ''.join(
        b.get('text', '') for b in prev or [] if isinstance(b, dict) and b.get('type') == 'text')
    return final, after_tool, prompt.strip()


def edited_unverified(path):
    """True when, since the user's last prompt, a file was edited and no tool other than reading ran after the last edit."""
    rows = []
    with open(path) as f:
        for line in f.readlines()[-400:]:
            try: rows.append(json.loads(line))
            except ValueError: pass
    tools = []
    for r in rows:
        c = (r.get('message') or {}).get('content')
        if r.get('type') == 'user' and not r.get('isMeta') and (isinstance(c, str) or (
                isinstance(c, list) and not any(isinstance(b, dict) and b.get('type') == 'tool_result' for b in c))):
            tools = []  # a real user prompt starts a new turn
        elif r.get('type') == 'assistant' and isinstance(c, list):
            tools += [b.get('name', '') for b in c if isinstance(b, dict) and b.get('type') == 'tool_use']
    last = max((i for i, t in enumerate(tools) if t in EDIT_TOOLS), default=-1)
    return last >= 0 and not any(t not in EDIT_TOOLS | {'Read', 'Grep', 'Glob', 'TodoWrite'} for t in tools[last + 1:])


def decide(payload, env):
    cfg = env.get('CLAUDE_CONFIG_DIR', '')
    if not cfg or os.path.normpath(os.path.expanduser(cfg)) == os.path.expanduser('~/.claude'):
        return None
    if payload.get('stop_hook_active') or not payload.get('transcript_path'):
        return None
    final, after_tool, prompt = turn_tail(payload['transcript_path'])
    if any(b.get('type') == 'tool_use' for b in final if isinstance(b, dict)):
        return None
    text = ''.join(b.get('text', '') for b in final if isinstance(b, dict) and b.get('type') == 'text').strip()
    # The final reply is often not yet flushed to the transcript when Stop fires (seen in `claude -p`); the
    # payload's last_assistant_message is authoritative.
    text = (payload.get('last_assistant_message') or text).strip()
    tail = text[-200:]
    if LOOP in text:
        return {'decision': 'block', 'reason': LOOP_REASON}
    if env.get('CLAUDE_CODE_ENTRYPOINT') == 'sdk-cli' and (payload.get('background_tasks') or WAIT.search(tail)):
        return {'decision': 'block', 'reason': WAIT_REASON}
    # A plain question answered without tools ("能看到图片吗") may end with an offer; pushing it only buys a
    # pointless extra round (2026-10-28 ccmax spark-x2.6 replied "能看到，确认完毕。").
    if ASK.search(tail) and not IRREVERSIBLE.search(tail) and not QUESTION.search(prompt):
        return {'decision': 'block', 'reason': ASK_REASON}
    if THEORY.search(text):
        return {'decision': 'block', 'reason': THEORY_REASON}
    if GIVEUP.search(text) and not re.search(r'下限|试过|实测|已试', text):
        return {'decision': 'block', 'reason': GIVEUP_REASON}
    if OVERCLAIM.search(text) and not re.search(r'n\s*=\s*\d|\d+\s*(次|轮|个样本)|×\s*\d', text):
        return {'decision': 'block', 'reason': OVERCLAIM_REASON}
    if FIXED.search(text) and edited_unverified(payload['transcript_path']):
        return {'decision': 'block', 'reason': FIXED_REASON}
    if not after_tool or not text or len(text) > MAX_TEXT or not ANNOUNCE.search(text):
        return None
    return {'decision': 'block', 'reason': REASON}


def self_test():
    import tempfile
    def run(final_text, prev_is_tool=True, active=False, cfg='/u/.claude-as', tool_use=False, entry='cli', tools=(), prompt='用户问题', **extra):
        prev = [{'type': 'tool_result', 'content': 'x'}] if prev_is_tool else prompt
        final = [{'type': 'thinking', 'thinking': '...'}, {'type': 'text', 'text': final_text}]
        if tool_use: final.append({'type': 'tool_use', 'name': 'Bash', 'input': {}})
        earlier = [{'type': 'user', 'message': {'content': '修一下'}}] + [
            {'type': 'assistant', 'message': {'content': [{'type': 'tool_use', 'name': t, 'input': {}}]}} for t in tools]
        rows = earlier + [{'type': 'user', 'message': {'content': prev}}] + [{'type': 'assistant', 'message': {'content': [b]}} for b in final]
        with tempfile.NamedTemporaryFile('w', suffix='.jsonl', delete=False) as f:
            f.write('\n'.join(json.dumps(r, ensure_ascii=False) for r in rows))
        out = decide({'transcript_path': f.name, 'stop_hook_active': active, **extra},
                     {'CLAUDE_CONFIG_DIR': cfg, 'CLAUDE_CODE_ENTRYPOINT': entry})
        os.unlink(f.name)
        return out['reason'][:4] if out else False
    A, W, S = ASK_REASON[:4], WAIT_REASON[:4], REASON[:4]
    report = '## 结论\n' + '数据' * 300
    cases = [
        (run('索引里没 README 正文，直接抓 raw README。'), S),
        (run('仓库信息拿到了。抓 README 和文件结构看实现。'), S),
        (run('Let me check the logs.'), S),
        (run(report + '要不要我先测这一条？还是先写回 skill？'), A),          # long report ending in options
        (run(report + '沉淀建议写进 startup-bench.md，要的话我顺手加。', prev_is_tool=False), A),
        (run('[loop-guard] 上游推理陷入复读，代理已中断本次回复。'), LOOP_REASON[:4]),
        (run('[loop-guard] 上游推理陷入复读，代理已中断本次回复。', active=True), False),  # pushes once only
        (run('能看到，图里是标题。要我做这件事吗？', prev_is_tool=False,
             prompt=[{'type': 'image'}, {'type': 'text', 'text': '能看到图片吗'}]), False),  # plain question, no tools
        (run(report + '改动未 commit。要我现在 commit 吗？'), False),        # irreversible: asking is right
        (run(report + '要不要我继续？', active=True), False),
        (run(report + '监控挂着，等 run2 跑完后回报。', entry='sdk-cli'), W),
        (run(report + '监控挂着，等 run2 跑完后回报。'), False),             # interactive: notification wakes it
        (run(report + '全部完成，PNG 已核实。', entry='sdk-cli'), False),
        (run('', entry='sdk-cli', last_assistant_message='要不要我继续？还是先停下？'), A),  # transcript not flushed yet
        (run(report + '已挂上。', entry='sdk-cli', background_tasks=[{'id': 'b1'}]), W),     # -p with live bg task
        (run(report + '已挂上。', background_tasks=[{'id': 'b1'}]), False),
        (run(report + '结论是 AI Studio 理论上比 Kaggle 快 4-5 倍。'), THEORY_REASON[:4]),
        (run(report + 'prepare 大头是装 torch，属于固定成本，改不了。'), GIVEUP_REASON[:4]),
        (run(report + '剩下的是带宽下限 120s，已试过 3 种下载方式，改不了。'), False),
        (run(report + '| STAGE 4 | ❌ 无法加速 |'), GIVEUP_REASON[:4]),                  # 936561bc #1231 table form
        (run(report + '基于架构预估，AI Studio 理论 ~60-90s。'), THEORY_REASON[:4]),
        (run(report + '方案列在上面，待你定下一步。'), A),
        (run(report + 'S2 略胜约 18s，定为最优。'), OVERCLAIM_REASON[:4]),
        (run(report + 'S2 略胜约 18s（n=6，同批）。'), False),
        (run(report + '按最优路线文档跑完，PNG 已核实。'), False),                       # doc name, not a claim
        (run(report + '已修复，验证通过。', tools=('Read', 'Edit')), FIXED_REASON[:4]),     # edited, never ran
        (run(report + '已修复，验证通过。', tools=('Edit', 'Bash')), False),
        (run(report + '已修复。', tools=('Edit', 'Read')), FIXED_REASON[:4]),
        (run('t1'), False),                                          # short final answer
        (run('直接抓 raw README。', prev_is_tool=False), False),       # answering the user, not mid-task
        (run('直接抓 raw README。', active=True), False),              # already pushed once
        (run('直接抓 raw README。', tool_use=True), False),            # it did call a tool
        (run('直接抓 raw README。', cfg=os.path.expanduser('~/.claude')), False),  # main session
        (run('看' + '长' * 400), False),                              # long reply = real answer
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
