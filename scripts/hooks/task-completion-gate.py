#!/usr/bin/env python3
"""Opt-in AS task lifecycle gate. No reply-text classification and no model calls.

UserPromptSubmit opens a revision; PostToolUse records receipts; Stop requires an explicit terminal receipt.
--finish validates evidence against this revision's successful tools, after its last edit. This proves receipt
provenance/order, not semantic completeness: the agent still owns the requirement checklist and acceptance test.
Three no-progress continuations end with TASK_STALLED, never an unbounded restart or a success declaration.
State is private, session-scoped and locked. Existing non-opt-in profiles are untouched.
"""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import sys

MARK = 'TASK_GATE_RECEIPT '


def control_command(command, session):
    """Only a standalone gate invocation may preserve terminal state, never a compound shell command."""
    try:
        tokens = shlex.split(command)
        if len(tokens) < 5 or Path(tokens[0]).name not in ('python3', 'python', Path(sys.executable).name):
            return False
        if tokens[1] != str(Path(__file__).resolve()):
            return False
        if tokens[2:5] not in (['--status', '--session', session], ['--finish', '--session', session]):
            return False
        return len(tokens) == 5 if tokens[2] == '--status' else len(tokens) == 7 and tokens[5] == '--receipt'
    except ValueError:
        return False


MUTATIONS = {'Edit', 'Write', 'MultiEdit', 'NotebookEdit'}
READ_ONLY = {'Read', 'Grep', 'Glob', 'TodoWrite', 'TaskCreate', 'TaskUpdate', 'TaskList', 'TaskGet'}


def config_dir():
    return Path(os.environ.get('CLAUDE_CONFIG_DIR', str(Path.home() / '.claude-max'))).expanduser()


@contextmanager
def locked(session):
    if not re.fullmatch(r'[A-Za-z0-9-]{1,100}', session):
        raise ValueError('invalid session id')
    root = config_dir() / 'task-gate'
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = root / (hashlib.sha256(session.encode()).hexdigest() + '.json')
    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    with os.fdopen(fd, 'r+') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        raw = stream.read()
        state = json.loads(raw) if raw else {'revision': 0, 'status': 'active', 'tools': [], 'stops': 0}
        yield state
        stream.seek(0)
        stream.truncate()
        json.dump(state, stream, ensure_ascii=False)
        stream.flush()


def instructions(session, revision):
    script = str(Path(__file__).resolve())
    return (
        f'[TASK_GATE] 本轮 revision={revision}，session={session}。任务处于 active，普通文字不能结束任务。'
        '持续执行用户已授权事项；不要为迎合门控擅自发布、付费、删除或外派。'
        f'完成前用 Bash 运行 python3 "{script}" --status --session {session}，获取本轮工具证据编号。'
        f'再运行 python3 "{script}" --finish --session {session} --receipt \'JSON\'。'
        f'JSON 必须带 revision:{revision} 和 status。'
        '执行任务用 status=completed，checks 为逐项需求清单，每项包含 requirement（非空）、evidence（成功工具编号数组）；'
        'checks 必须覆盖本轮所有要求，证据必须来自真实验收，修改文件后至少包含一次修改后的非读取工具验收。'
        '纯问答用 status=answered、reason（答案依据），但已修改文件不能以问答结束；'
        '真实受阻/待用户确认不可逆动作用 status=blocked、reason、remaining；用户要求停止用 status=cancelled、reason。'
        '没有可用验收则明确 blocked，不编造完成或降低验收要求。finish 成功后给最终答复，不再执行工作工具；'
        '若又执行工具，状态重新 active。连续无进展会报 TASK_STALLED，绝不能称后台仍在执行。'
    )


def response_failed(value):
    if isinstance(value, dict):
        return (value.get('is_error') is True or value.get('interrupted') is True
                or any(isinstance(value.get(key), int) and value[key] != 0 for key in ('exit_code', 'exitCode')))
    return False


def hook(payload):
    if os.environ.get('CCMAX_TASK_GATE') != '1':
        return None
    session = payload['session_id']
    event = payload.get('hook_event_name')
    with locked(session) as state:
        if event == 'SessionStart':
            return {'hookSpecificOutput': {'hookEventName': event, 'additionalContext': (
                f"[TASK_GATE] 恢复状态 status={state['status']}。" + instructions(session, state['revision']))}}
        if event == 'UserPromptSubmit':
            prompt = payload.get('prompt', '')
            if state['status'] in ('active', 'stalled', 'blocked') and re.fullmatch(
                    r'\s*(?:继续|继续做|继续执行|接着做|continue|go on)[。.!！\s]*', prompt, re.I):
                state.update(status='active', stops=0)
                return {'hookSpecificOutput': {'hookEventName': event, 'additionalContext': (
                    '继续原任务，不清除需求和已执行证据。' + instructions(session, state['revision']))}}
            state.update(revision=state['revision'] + 1, status='active', tools=[], stops=0, last_edit=0,
                         prompt=prompt)
            # Exact control commands only; other requests are resolved explicitly through --finish.
            if re.fullmatch(r'\s*(?:停止|暂停|先停|别继续|不要继续|stop)(?:[。.!！\s]*)', prompt, re.I):
                state.update(status='cancelled', reason='用户要求停止')
                return None
            return {'hookSpecificOutput': {'hookEventName': event, 'additionalContext': instructions(session, state['revision'])}}
        if event in ('PostToolUse', 'PostToolUseFailure'):
            tool = payload.get('tool_name', '')
            inp = payload.get('tool_input') or {}
            command = inp.get('command', '')
            is_control = tool == 'Bash' and control_command(command, session)
            if is_control:
                if event == 'PostToolUseFailure' or response_failed(payload.get('tool_response')):
                    state['status'] = 'active'
                return None
            ident = payload.get('tool_use_id')
            if ident and any(t.get('tool_use_id') == ident for t in state['tools']):
                return None
            ok = event == 'PostToolUse' and not response_failed(payload.get('tool_response'))
            seq = len(state['tools']) + 1
            state['tools'].append({'id': seq, 'tool_use_id': ident, 'name': tool, 'ok': ok,
                                   'input': str(command or inp)[:800],
                                   'result': str(payload.get('tool_response', payload.get('error', '')))[:1600]})
            state['status'] = 'active'
            if ok:
                state['stops'] = 0
            if tool in MUTATIONS:
                state['last_edit'] = seq
            return None
        if event == 'Stop':
            if state['status'] in ('completed', 'answered', 'blocked', 'cancelled'):
                return None
            # Terminal failure stays visible; no dependence on final reply wording or transcript flush.
            if state['status'] == 'stalled':
                return {'systemMessage': 'TASK_STALLED：任务未完成，连续无工具进展，已停止自动续跑。'}
            state['stops'] += 1
            if state['stops'] > 3:
                state['status'] = 'stalled'
                return {'systemMessage': 'TASK_STALLED：任务未完成，连续3次续跑无工具进展。请检查模型/额度；不是执行成功。'}
            return {'decision': 'block', 'reason': (
                f"[TASK_GATE {state['stops']}/3] 本轮状态仍为 active，不能结束；不是按回复措辞判断。"
                '继续执行剩余任务和验收；若已完成、纯问答、真实受阻或用户停止，按状态协议提交终态。'
                + instructions(session, state['revision']))}
    return None


def finish(session, receipt):
    with locked(session) as state:
        if receipt.get('revision') != state['revision']:
            raise ValueError('stale revision; run --status')
        status = receipt.get('status')
        if status not in ('completed', 'answered', 'blocked', 'cancelled'):
            raise ValueError('invalid terminal status')
        if status == 'completed':
            checks = receipt.get('checks')
            if not isinstance(checks, list) or not checks:
                raise ValueError('completed requires requirement checks and real tool evidence')
            evidence = set()
            for check in checks:
                if not isinstance(check, dict) or not isinstance(check.get('requirement'), str) or not check['requirement'].strip():
                    raise ValueError('each check needs a requirement')
                ids = check.get('evidence')
                if not isinstance(ids, list) or not ids or any(type(i) is not int for i in ids):
                    raise ValueError('each check needs evidence IDs')
                evidence.update(ids)
            tools = {t['id']: t for t in state['tools']}
            if any(i not in tools or not tools[i]['ok'] for i in evidence):
                raise ValueError('evidence must reference successful tools in this revision')
            if state.get('last_edit', 0) and not any(
                    i > state['last_edit'] and tools[i]['name'] not in READ_ONLY | MUTATIONS for i in evidence):
                raise ValueError('file edits require a later acceptance tool receipt, not only a read')
        else:
            if not isinstance(receipt.get('reason'), str) or not receipt['reason'].strip():
                raise ValueError('terminal status needs a concrete reason')
            if status == 'answered' and state.get('last_edit', 0):
                raise ValueError('cannot finish file edits as a plain answer')
            if status == 'blocked' and not receipt.get('remaining'):
                raise ValueError('blocked requires remaining work')
        state.update(status=status, receipt=receipt)
    print(MARK + json.dumps(receipt, ensure_ascii=False))


def settings():
    script = str(Path(__file__).resolve())
    cmd = f'python3 "{script}"'
    hooks = {event: [{'hooks': [{'type': 'command', 'command': cmd, 'timeout': 5}]}]
             for event in ('SessionStart', 'UserPromptSubmit', 'PostToolUse', 'PostToolUseFailure', 'Stop')}
    return {'env': {'CCMAX_TASK_GATE': '1', 'CCMAX_AS_CONTINUE': '1'}, 'hooks': hooks}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session')
    parser.add_argument('--status', action='store_true')
    parser.add_argument('--finish', action='store_true')
    parser.add_argument('--receipt')
    parser.add_argument('--settings-json', action='store_true')
    args = parser.parse_args()
    try:
        if args.settings_json:
            print(json.dumps(settings()))
        elif args.status:
            with locked(args.session) as state:
                print(json.dumps(state, ensure_ascii=False))
        elif args.finish:
            finish(args.session, json.loads(args.receipt))
        else:
            out = hook(json.load(sys.stdin))
            if out:
                print(json.dumps(out, ensure_ascii=False))
    except Exception as error:
        if args.finish or args.status or args.settings_json:
            print(str(error), file=sys.stderr)
            return 1
        # Lifecycle failures must be visible instead of silently claiming a successful completion.
        print(json.dumps({'decision': 'block', 'reason': f'TASK_GATE_ERROR：{type(error).__name__}: {error}；终态未验证，请报告门控故障，不得宣称完成。'}, ensure_ascii=False))
        return 0  # Command-hook JSON decisions are consumed only on a successful command exit.
    return 0


if __name__ == '__main__':
    sys.exit(main())
