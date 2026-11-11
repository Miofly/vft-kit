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
             filehelper_offsets=['0x258'], members=[
                 dict(offset='0x200', address='0x700001000', vptr='0x100002000')])])


class ExecutorTests(unittest.TestCase):
    def test_payload_unicode_and_literal_text(self):
        text='中文🙂\n";not code;\\'
        self.assertEqual(native.validate_payload(dict(op='send', wxid='filehelper', text=text)),
                         text.encode('utf-16-le'))

    def test_wrong_recipient_refused(self):
        for peer in ['文件传输助手', 'filehelper ', 'other', None]:
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
        for failure in ['bounded', 'pid', 'recipient', 'member', 'vtable', 'duplicate']:
            probe=probe_fixture()
            if failure=='bounded': probe['bounded']=True
            if failure=='pid': probe['pid']=124
            if failure=='recipient': probe['candidates'][0]['filehelper_offsets']=[]
            if failure=='member': probe['candidates'][0]['members']=[]
            if failure=='vtable': probe['candidates'][0]['members'][0]['vptr']='0x9999'
            if failure=='duplicate': probe['candidates']*=2
            with self.subTest(failure=failure), self.assertRaises(native.Refused):
                native.select_binding(config_fixture(), probe)

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
            payload=dict(text='test')
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
