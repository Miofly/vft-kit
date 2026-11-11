#!/usr/bin/env python3
"""Experimental, build-pinned Qt executor for filehelper ONLY.

Reads the existing exec-backend JSON contract on stdin. Never restarts WeChat,
loads a dylib, navigates, or uses keyboard/clipboard. A validated external probe
rediscovers live objects each time, then LLDB invokes Qt on the main thread.
Each target/text pair gets an exclusive durable claim BEFORE evaluation; even
unknown results cannot be retried automatically. Submitted is not delivered.

WXS_NATIVE_CONFIG must name a private JSON config. No implicit PID, addresses,
build or paths are selected. See references/qt-native-send-derivation.md.
"""
import hashlib
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


class Refused(ValueError):
    pass


def number(value):
    if isinstance(value, bool):
        raise Refused('invalid numeric profile field')
    try:
        n = int(value, 0) if isinstance(value, str) else int(value)
    except (ValueError, TypeError):
        raise Refused('invalid numeric profile field') from None
    if not 0 < n < 2 ** 63:
        raise Refused('invalid numeric profile field')
    return n


def validate_payload(payload):
    if not isinstance(payload, dict) or payload.get('op') != 'send':
        raise Refused('only send is supported')
    if payload.get('wxid') != 'filehelper':
        raise Refused('this experimental executor only accepts exact wxid=filehelper')
    if payload.get('mention') not in (None, '', []):
        raise Refused('mentions are not supported')
    text = payload.get('text')
    if not isinstance(text, str) or not text or len(text) > 2000 or '\0' in text:
        raise Refused('text must contain 1..2000 characters without NUL')
    try:
        raw = text.encode('utf-16-le')
    except UnicodeEncodeError:
        raise Refused('invalid Unicode text') from None
    return raw


def validate_config(config):
    required = ('pid', 'module', 'module_sha256', 'probe', 'lldb_runner', 'state_dir',
                'input_vtable', 'editor_vtable', 'editor_offset', 'recipient_offset',
                'text_metacall', 'input_metacall', 'qstring_destructor', 'qstring_empty')
    if not isinstance(config, dict) or any(k not in config for k in required):
        raise Refused('incomplete native configuration')
    for key in ('module', 'probe', 'lldb_runner', 'state_dir'):
        if not isinstance(config[key], str) or not Path(config[key]).is_absolute():
            raise Refused('configuration paths must be absolute')
    if not re.fullmatch(r'[a-f0-9]{64}', config['module_sha256']):
        raise Refused('invalid module fingerprint')
    for key in required:
        if key not in ('module', 'module_sha256', 'probe', 'lldb_runner', 'state_dir'):
            number(config[key])
    if number(config['editor_offset']) > 4096 or number(config['recipient_offset']) > 4096:
        raise Refused('object field offset out of bounds')
    return config


def read_config():
    path = os.environ.get('WXS_NATIVE_CONFIG', '')
    if not path or not Path(path).is_absolute():
        raise Refused('WXS_NATIVE_CONFIG absolute path is required')
    config = validate_config(json.loads(Path(path).read_text()))
    module = Path(config['module'])
    if not str(module).endswith('/WeChatSend.app/Contents/Resources/wechat.dylib'):
        raise Refused('only the explicit WeChatSend clone is permitted')
    if hashlib.sha256(module.read_bytes()).hexdigest() != config['module_sha256']:
        raise Refused('module fingerprint changed; revalidate profile before sending')
    pid = number(config['pid'])
    command = subprocess.run(['ps', '-p', str(pid), '-o', 'comm='],
                             capture_output=True, text=True, check=True).stdout.strip()
    expected = str(module).removesuffix('/Resources/wechat.dylib') + '/MacOS/WeChat'
    if command != expected:
        raise Refused('PID does not own the configured clone executable')
    return config


def discover(config):
    result = subprocess.run([config['probe'], str(number(config['pid'])),
                             str(config['input_vtable']), str(config['editor_vtable'])],
                            capture_output=True, text=True, timeout=20, check=True)
    data = json.loads(result.stdout)
    return select_binding(config, data)


def select_binding(config, data):
    if data.get('bounded') or data.get('pid') != number(config['pid']):
        raise Refused('incomplete probe or wrong PID')
    offset = hex(number(config['recipient_offset']))
    candidates = [c for c in data.get('candidates', [])
                  if c.get('kind') == 'input' and c.get('qobject_backlink') is True
                  and offset in c.get('filehelper_offsets', [])]
    if len(candidates) != 1:
        raise Refused('filehelper input must resolve uniquely; open its conversation first')
    candidate = candidates[0]
    members = [m for m in candidate.get('members', [])
               if number(m['offset']) == number(config['editor_offset'])]
    if len(members) != 1:
        raise Refused('editor must belong to the resolved input')
    base = number(data['base'])
    if number(members[0]['vptr']) != base + number(config['editor_vtable']):
        raise Refused('editor vtable mismatch')
    return base, number(candidate['address']), number(members[0]['address'])


def expression(config, binding, utf16):
    base, inp, editor = binding
    units = [int.from_bytes(utf16[i:i+2], 'little') for i in range(0, len(utf16), 2)]
    values = ','.join(map(str, units))
    address = lambda key: base + number(config[key])
    # QArrayData offset is relative to header start (24), not the offset field.
    # Initial ref=1 and capacity=len+1 let Qt copy/refcount normally; destruct
    # using the build-verified QString destructor, including property results.
    return f'''({{ unsigned long wxn_i={inp}ULL,wxn_e={editor}ULL; int wxn_rc=-100;
    auto wxn_meta=(void(*)(void*,int,int,void**)){address('text_metacall')}ULL;
    auto wxn_destroy=(void(*)(void*)){address('qstring_destructor')}ULL;
    auto wxn_guard=[&]() {{return ((int(*)())pthread_main_np)()
      && *(unsigned long*)wxn_i=={address('input_vtable')}ULL
      && *(unsigned long*)wxn_e=={address('editor_vtable')}ULL
      && *(unsigned long*)(wxn_i+{number(config['editor_offset'])})==wxn_e
      && *((unsigned char*)wxn_i+{number(config['recipient_offset'])}+23)==10
      && ((int(*)(const void*,const void*,unsigned long))memcmp)(
           (void*)(wxn_i+{number(config['recipient_offset'])}),"filehelper",10)==0;}};
    if(wxn_guard()) {{
      void *wxn_before=(void*){address('qstring_empty')}ULL;void *wxn_bargs[]={{&wxn_before}};
      wxn_meta((void*)wxn_e,1,9,wxn_bargs);
      int wxn_old=((int*)wxn_before)[1];wxn_destroy(&wxn_before);
      if(wxn_old==0) {{
        unsigned short wxn_units[]={{{values},0}};
        unsigned char *wxn_block=(unsigned char*)((void*(*)(unsigned long,unsigned long))calloc)(1,{24+(len(units)+1)*2});
        if(wxn_block) {{
          *((int*)wxn_block)=1;*((int*)(wxn_block+4))={len(units)};
          *((unsigned*)(wxn_block+8))={len(units)+1};*((long*)(wxn_block+16))=24;
          ((void*(*)(void*,const void*,unsigned long))memcpy)(wxn_block+24,wxn_units,{len(utf16)});
          void *wxn_q=wxn_block;void *wxn_set[]={{0,&wxn_q}};
          wxn_meta((void*)wxn_e,0,16,wxn_set);wxn_destroy(&wxn_q);
          void *wxn_actual=(void*){address('qstring_empty')}ULL;void *wxn_aargs[]={{&wxn_actual}};
          wxn_meta((void*)wxn_e,1,9,wxn_aargs);
          bool wxn_equal=(((int*)wxn_actual)[1]=={len(units)} &&
            ((int(*)(const void*,const void*,unsigned long))memcmp)(
              (char*)wxn_actual+*((long*)((char*)wxn_actual+16)),wxn_units,{len(utf16)})==0);
          wxn_destroy(&wxn_actual);
          if(wxn_equal && wxn_guard()) {{
            int wxn_action=0;void *wxn_args[]={{0,&wxn_action}};
            ((void(*)(void*,int,int,void**)){address('input_metacall')}ULL)((void*)wxn_i,0,8,wxn_args);
            void *wxn_after=(void*){address('qstring_empty')}ULL;void *wxn_afterargs[]={{&wxn_after}};
            wxn_meta((void*)wxn_e,1,9,wxn_afterargs);
            wxn_rc=((int*)wxn_after)[1]==0?2:1;wxn_destroy(&wxn_after);
          }} else wxn_rc=-3;
        }} else wxn_rc=-4;
      }} else wxn_rc=-2;
    }} wxn_rc; }})'''.replace('\n', ' ')


def claim(state_dir, payload, pid):
    state_dir = Path(state_dir)
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    if state_dir.is_symlink() or state_dir.stat().st_uid != os.getuid() or state_dir.stat().st_mode & 0o077:
        raise Refused('receipt directory must be private and owned by current user')
    digest = hashlib.sha256((str(pid)+'\0filehelper\0'+payload['text']).encode()).hexdigest()
    path = state_dir / (digest + '.json')
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return path, None
    initial = {'status': 'status_unknown', 'request_id': digest, 'attempted_at': int(time.time())}
    with os.fdopen(fd, 'w') as stream:
        json.dump(initial, stream)
        stream.flush()
        os.fsync(stream.fileno())
    return path, initial


def execute(payload):
    utf16 = validate_payload(payload)
    config = read_config()
    state_dir = Path(config['state_dir'])
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    if state_dir.is_symlink() or state_dir.stat().st_uid != os.getuid() or state_dir.stat().st_mode & 0o077:
        raise Refused('receipt directory must be private and owned by current user')
    lock_fd = os.open(state_dir / '.native.lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(lock_fd)
        raise Refused('another native operation is in progress') from None
    try:
        return execute_locked(config, payload, utf16)
    finally:
        os.close(lock_fd)


def execute_locked(config, payload, utf16):
    binding = discover(config)
    receipt, result = claim(config['state_dir'], payload, number(config['pid']))
    if result is None:
        # Do not trust an old submitted state as current delivery confirmation.
        return {'status': 'status_unknown', 'diagnostic': 'duplicate attempt refused; inspect original receipt',
                'request_id': receipt.stem}
    try:
        with tempfile.TemporaryDirectory(prefix='wxs-expression-') as work:
            expr = Path(work) / 'expression.txt'
            expr.write_text(expression(config, binding, utf16))
            outcome = Path(work) / 'result.json'
            runner_config = Path(work) / 'runner.json'
            runner_config.write_text(json.dumps({'pid': number(config['pid']),
                                                 'expression': str(expr), 'output': str(outcome)}))
            # Runner uses SB API and always detaches in a finally block. Startup
            # script imports only locally installed code; never downloads or evals JSON.
            runner = json.dumps(config['lldb_runner'])
            conf = json.dumps(str(runner_config))
            script = f'import runpy; runpy.run_path({runner})["run"]({conf})'
            proc = subprocess.run(['xcrun', 'lldb', '--no-lldbinit', '--batch', '-o', 'script '+script],
                                  capture_output=True, text=True, timeout=25)
            if outcome.exists():
                info = json.loads(outcome.read_text())
                result['qt_result'] = info.get('value')
                result['detached'] = info.get('detached', False)
                if proc.returncode == 0 and info.get('ok') and info.get('detached'):
                    code = info['value']
                    if code == 2:
                        result.update(status='submitted_unconfirmed', diagnostic='native Qt submitted; draft cleared; independently verify chat')
                    elif code in (-100, -2, -4):
                        result.update(status='failed', diagnostic='native guards refused before submit')
                    else:
                        result['diagnostic'] = 'native result ambiguous; inspect draft and original receipt; do not retry'
                else:
                    result['diagnostic'] = 'native evaluation/detach failed; no automatic retry'
            else:
                result['diagnostic'] = 'native runner returned no receipt; no automatic retry'
    except Exception:
        # Claim is already durable: unexpected errors remain ambiguous, never retried.
        result['diagnostic'] = 'native execution outcome unknown; inspect original receipt'
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=receipt.parent, prefix='.receipt-',
                                         delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(result, stream, indent=2)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, receipt)
    except OSError:
        # The durable original claim remains unknown; do not turn a post-submit
        # persistence error into a definitive failure that callers might retry.
        result.update(status='status_unknown', diagnostic='receipt update failed; do not retry')
    return result


def main():
    try:
        raw = sys.stdin.buffer.read(32769)
        if len(raw) > 32768:
            raise Refused('request too large')
        result = execute(json.loads(raw))
    except (Refused, ValueError) as error:
        result = {'status': 'failed', 'diagnostic': str(error)}
    except Exception:
        result = {'status': 'failed', 'diagnostic': 'native preflight failed before evaluation'}
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
