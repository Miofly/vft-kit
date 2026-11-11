"""Offline executor tests: never attach to WeChat or submit a message."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import native_executor as native


def config_fixture(root='/fixture'):
    return dict(pid=123, module=root+'/WeChatSend.app/Contents/Resources/wechat.dylib',
                module_sha256='a'*64, probe=root+'/probe', lldb_runner=root+'/runner.py',
                state_dir=root+'/receipts', input_vtable='0x1000', editor_vtable='0x2000',
                editor_offset='0x200', recipient_offset='0x258', text_metacall='0x3000',
                input_metacall='0x4000', qstring_destructor='0x5000', qstring_empty='0x6000')


def probe_fixture():
    return dict(pid=123, base='0x100000000', bounded=False, candidates=[
        dict(kind='input', address='0x700000000', qobject_backlink=True,
             filehelper_offsets=['0x258'], recipient={'offset':'0x258','wxid':'filehelper'}, members=[
                 dict(offset='0x200', address='0x700001000', vptr='0x100002000')])])


class ExecutorTests(unittest.TestCase):
    def test_payload_unicode_and_literal_text(self):
        text='中文🙂\n";not code;\\'
        self.assertEqual(native.validate_payload(dict(op='send', wxid='filehelper', text=text)),
                         text.encode('utf-16-le'))

    def test_wrong_recipient_refused(self):
        for peer in ['文件传输助手', 'filehelper ', 'x\n', None]:
            with self.subTest(peer=peer), self.assertRaises(native.Refused):
                native.validate_payload(dict(op='send', wxid=peer, text='test'))

    def test_invalid_text_refused(self):
        for text in ['', '\0', 'x'*2001, '\ud800', None]:
            with self.subTest(text=str(text)[:10]), self.assertRaises(native.Refused):
                native.validate_payload(dict(op='send', wxid='filehelper', text=text))

    def test_mention_refused(self):
        with self.assertRaises(native.Refused):
            native.validate_payload(dict(op='send', wxid='filehelper', text='test', mention='all'))

    def test_profile_required(self):
        self.assertEqual(native.validate_config(config_fixture())['pid'], 123)
        for key in config_fixture():
            bad=config_fixture(); del bad[key]
            with self.subTest(key=key), self.assertRaises(native.Refused):
                native.validate_config(bad)

    def test_binding_unique_and_owned(self):
        binding=native.select_binding(config_fixture(), probe_fixture())
        self.assertEqual(binding, (0x100000000, 0x700000000, 0x700001000))
        for failure in ['bounded', 'missing_bounded', 'pid', 'recipient', 'member', 'vtable', 'duplicate']:
            probe=probe_fixture()
            if failure=='bounded': probe['bounded']=True
            if failure=='missing_bounded': del probe['bounded']
            if failure=='pid': probe['pid']=124
            if failure=='recipient': probe['candidates'][0]['recipient']['wxid']='other'
            if failure=='member': probe['candidates'][0]['members']=[]
            if failure=='vtable': probe['candidates'][0]['members'][0]['vptr']='0x9999'
            if failure=='duplicate': probe['candidates']*=2
            with self.subTest(failure=failure), self.assertRaises(native.Refused):
                native.select_binding(config_fixture(), probe)

    def test_recipient_identity_validation(self):
        for wxid in ('filehelper', 'wxid_person_123', '123456@chatroom', 'legacy.name'):
            self.assertEqual(native.validate_recipient(wxid), wxid)
        for wxid in (None, '', '张三', 'filehelper ', 'x\n', 'x'*129, 'a"b'):
            with self.subTest(wxid=wxid), self.assertRaises(native.Refused):
                native.validate_recipient(wxid)

    def test_exact_recipient_preflight_binding(self):
        probe = probe_fixture()
        wxid = 'wxid_person_01234567890123456789'
        probe['candidates'][0]['recipient']['wxid'] = wxid
        self.assertEqual(native.select_binding(config_fixture(), probe, wxid)[1], 0x700000000)
        for recipient in (None, {'offset':'0x250','wxid':wxid},
                          {'offset':'0x258','wxid':wxid+'x'}):
            probe['candidates'][0]['recipient'] = recipient
            with self.assertRaises(native.Refused):
                native.select_binding(config_fixture(), probe, wxid)

    def test_legacy_filehelper_hit_is_not_identity_proof(self):
        probe = probe_fixture()
        del probe['candidates'][0]['recipient']
        with self.assertRaises(native.Refused):
            native.select_binding(config_fixture(), probe)

    def test_preflight_never_submits_or_claims(self):
        with patch.object(native, 'read_config', return_value=config_fixture()), \
             patch.object(native, 'discover', return_value=(1,2,3)) as discover, \
             patch.object(native, 'claim') as claim, \
             patch.object(native, 'execute') as execute:
            result = native.preflight({'op':'preflight','wxid':'filehelper'})
            discover.assert_called_once_with(config_fixture(), 'filehelper')
            claim.assert_not_called()
            execute.assert_not_called()
            self.assertEqual(result['status'], 'target_matched')
            self.assertFalse(result['send_ready'])

    def test_explicit_alias_resolution_and_ambiguity(self):
        config = config_fixture()
        config['allowed_recipients'] = ['filehelper', 'wxid_unique']
        config['recipient_aliases'] = {'张三':['wxid_one','wxid_two'],
                                       'yourtools':['wxid_unique'],
                                       '唯一备注':['wxid_unique']}
        for hint in ('文件助手','文件传输助手','filehelper'):
            self.assertEqual(native.resolve_recipient(config, hint)['candidates'], [{'wxid':'filehelper'}])
        for hint in ('yourtools','唯一备注','wxid_unique'):
            result = native.resolve_recipient(config, hint)
            self.assertEqual(result['status'], 'resolved')
            self.assertEqual(result['candidates'], [{'wxid':'wxid_unique'}])
        self.assertEqual(native.resolve_recipient(config, '张三')['status'], 'ambiguous')
        self.assertEqual(native.resolve_recipient(config, '未知联系人')['status'], 'not_found')
        self.assertFalse(native.resolve_recipient(config, '张三')['send_ready'])
        config['recipient_aliases'] = {'filehelper':['wxid_wrong']}
        self.assertEqual(native.resolve_recipient(config, 'filehelper')['status'], 'ambiguous')
        for values in ('wxid_one', [], ['张三'], [None]):
            config['recipient_aliases'] = {'坏映射':values}
            with self.assertRaises(native.Refused):
                native.resolve_recipient(config, '坏映射')

    def test_allowlist_defaults_to_filehelper(self):
        config = config_fixture()
        native.authorize_recipient(config, 'filehelper')
        with self.assertRaises(native.Refused):
            native.authorize_recipient(config, 'wxid_person_123')
        config['allowed_recipients'] = ['filehelper', 'wxid_person_123']
        native.authorize_recipient(config, 'wxid_person_123')
        for allowed in ([], '*', ['*'], ['张三'], [None]):
            config['allowed_recipients'] = allowed
            with self.assertRaises(native.Refused):
                native.authorize_recipient(config, 'filehelper')

    def test_nonallowlisted_send_does_not_probe_or_claim(self):
        with patch.object(native, 'read_config', return_value=config_fixture()), \
             patch.object(native, 'discover') as discover, \
             patch.object(native, 'claim') as claim:
            with self.assertRaises(native.Refused):
                native.execute({'op':'send','wxid':'wxid_other','text':'test'})
            discover.assert_not_called()
            claim.assert_not_called()

    def test_long_recipient_expression_has_exact_guard(self):
        wxid = 'wxid_person_01234567890123456789'
        expr = native.expression(config_fixture(), (1,2,3), b't\0', wxid)
        self.assertIn(f'wxn_len=={len(wxid)}', expr)
        self.assertIn(f'wxn_chars,"{wxid}",{len(wxid)}', expr)
        self.assertIn('wxn_peer[23]&128', expr)
        self.assertIn('wxn_len>22', expr)
        self.assertNotIn('filehelper', expr)

    def test_compiled_recipient_guard_short_long_and_mismatch(self):
        import subprocess
        config = config_fixture()
        source = '''#include <cstdlib>
#include <cstring>
#include <cstdint>
static int on_main = 1;
int pthread_main_np() { return on_main; }
alignas(8) unsigned char input[1024] = {}, editor[16] = {};
'''
        for name, wxid in [('short_peer','filehelper'),
                           ('long_peer','wxid_person_01234567890123456789')]:
            expr = native.expression(config, (0x100000000,1,2), b't\0', wxid)
            expr = expr.replace('wxn_i=1ULL,wxn_e=2ULL',
                                'wxn_i=(unsigned long)input,wxn_e=(unsigned long)editor')
            # Compile the whole send expression, but execute ONLY its guard.
            source += f'int syntax_{name}() {{return {expr};}}\n'
            guard = expr.split('    if(wxn_guard())', 1)[0] + 'wxn_guard(); })'
            source += f'bool {name}() {{return {guard};}}\n'
        source += '''int main() {
  *(uint64_t*)input=0x100001000ULL; *(uint64_t*)editor=0x100002000ULL;
  *(uint64_t*)(input+0x200)=(uint64_t)editor;
  unsigned char *peer=input+0x258;
  memcpy(peer,"filehelper",11); peer[23]=10;
  if(!short_peer() || long_peer()) return 1;
  peer[0]='x'; if(short_peer()) return 2; peer[0]='f';
  peer[10]='x'; if(short_peer()) return 3; peer[10]=0;
  on_main=0; if(short_peer()) return 4; on_main=1;
  *(uint64_t*)editor=0; if(short_peer()) return 5;
  *(uint64_t*)editor=0x100002000ULL;
  char text[]="wxid_person_01234567890123456789";
  *(uint64_t*)peer=(uint64_t)text;
  *(uint64_t*)(peer+8)=sizeof(text)-1;
  *(uint64_t*)(peer+16)=(1ULL<<63)|64;
  if(!long_peer() || short_peer()) return 6;
  *(uint64_t*)(peer+16)=(1ULL<<63)|2;
  if(long_peer()) return 7;
  return 0;
}
'''
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'guard.cpp'
            path.write_text(source)
            executable = str(Path(root) / 'guard')
            subprocess.run(['clang++','-std=gnu++17',str(path),'-o',executable],
                           capture_output=True, text=True, check=True)
            subprocess.run([executable], capture_output=True, text=True, check=True)

    def test_claim_identity_and_existing_filehelper_digest(self):
        import hashlib
        with tempfile.TemporaryDirectory() as root:
            payload = {'wxid':'filehelper','text':'test'}
            path, _ = native.claim(root, payload, 123)
            self.assertEqual(path.stem, hashlib.sha256(b'123\0filehelper\0test').hexdigest())
            other, _ = native.claim(root, dict(payload, wxid='wxid_other'), 123)
            self.assertNotEqual(path, other)

    def test_expression_guards_and_utf16_data(self):
        text='中文🙂'; expr=native.expression(config_fixture(), (0x100000000,0x700000000,0x700001000), text.encode('utf-16-le'))
        self.assertIn('pthread_main_np',expr)
        self.assertIn('"filehelper",10',expr)
        self.assertIn('wxn_old==0',expr)
        self.assertIn('wxn_equal && wxn_guard()',expr)
        self.assertIn('wxn_block+16))=24',expr)
        self.assertIn('55357,56898',expr)  # surrogate pair for U+1F642
        self.assertEqual(expr.count('((void*)wxn_i,0,8,wxn_args)'),1)

    def test_durable_claim_prevents_retry(self):
        with tempfile.TemporaryDirectory() as root:
            payload=dict(wxid='filehelper',text='test')
            path,result=native.claim(root,payload,123)
            self.assertEqual(result['status'],'status_unknown')
            self.assertTrue(path.exists())
            path2,result2=native.claim(root,payload,123)
            self.assertEqual(path,path2)
            self.assertIsNone(result2)
            self.assertEqual(path.stat().st_mode & 0o777,0o600)

    def test_submit_result_and_persistence_failure_stay_ambiguous(self):
        for persistence_failure in (False, True):
            with self.subTest(persistence_failure=persistence_failure), tempfile.TemporaryDirectory() as root:
                config=config_fixture(); config['state_dir']=root
                payload=dict(op='send',wxid='filehelper',text='test')
                def runner(args, **kwargs):
                    # Emulate a completed native call without invoking LLDB.
                    script=args[-1]
                    import re
                    paths=re.findall(r'"([^"\n]+runner\.json)"',script)
                    self.assertEqual(len(paths),1)
                    cfg=json.loads(Path(paths[0]).read_text())
                    Path(cfg['output']).write_text(json.dumps(dict(ok=True,detached=True,value=2)))
                    from types import SimpleNamespace
                    return SimpleNamespace(returncode=0)
                real_replace = native.os.replace
                with patch.object(native,'discover',return_value=(0x100000000,0x700000000,0x700001000)), \
                     patch.object(native.subprocess,'run',side_effect=runner), \
                     patch.object(native.os,'replace',side_effect=OSError('disk error') if persistence_failure else real_replace):
                    result=native.execute_locked(config,payload,b't\0')
                self.assertEqual(result['status'],'status_unknown' if persistence_failure else 'submitted_unconfirmed')
                # A durable claim exists even if updating it failed.
                receipts=list(Path(root).glob('*.json'))
                self.assertEqual(len(receipts),1)
                self.assertEqual(json.loads(receipts[0].read_text())['status'],
                                 'status_unknown' if persistence_failure else 'submitted_unconfirmed')

    def test_duplicate_never_evaluates(self):
        with tempfile.TemporaryDirectory() as root:
            config=config_fixture(); config['state_dir']=root
            payload=dict(op='send',wxid='filehelper',text='test')
            native.claim(root,payload,123)
            with patch.object(native,'read_config',return_value=config), \
                 patch.object(native,'discover',return_value=(1,2,3)), \
                 patch.object(native.subprocess,'run') as run:
                result=native.execute(payload)
                self.assertEqual(result['status'],'status_unknown')
                run.assert_not_called()


if __name__=='__main__':
    unittest.main()
