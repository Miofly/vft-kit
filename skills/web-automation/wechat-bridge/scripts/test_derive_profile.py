"""Offline regression tests; never start Ghidra or touch a WeChat process."""
import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import derive_profile as derive


class ProfileTests(unittest.TestCase):
    def test_current_build_methods_not_old_map(self):
        log = ('INFO METHOD mmui::ChatInputView 8 Send 1\n'
               'INFO METHOD QTextEdit 16 setPlainText 1\n')
        methods = derive.parse_methods(log)
        self.assertEqual(methods['mmui::ChatInputView']['8'], {'name': 'Send', 'argc': 1})
        self.assertNotIn('5', methods['mmui::ChatInputView'])

    def test_missing_methods_are_not_invented(self):
        self.assertEqual(derive.parse_methods('old output without method tables'), {})

    def test_classes_and_vtables(self):
        text = ('"mmui::ChatInputView": {"metaobject": "9c884f0", '
                '"stringdata": "a16fe48", "data": "85e1c0c", '
                '"static_metacall": "133510", "vtables": ["0x9caf6c8"]}')
        cls = derive.parse_classes(text)['mmui::ChatInputView']
        self.assertEqual(cls['vtables'], ['0x9caf6c8'])
        self.assertEqual(cls['static_metacall'], '0x133510')

    @patch.object(derive.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout='', stderr=''))
    def test_first_run_creates_directory_and_imports(self, run):
        with tempfile.TemporaryDirectory() as root:
            project = os.path.join(root, 'missing')
            derive.run_headless('/ghidra', project, '/thin.dylib', False)
            self.assertTrue(os.path.isdir(project))
            self.assertIn('-import', run.call_args.args[0])
            self.assertNotIn('-process', run.call_args.args[0])

    @patch.object(derive.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout='', stderr=''))
    def test_existing_empty_directory_still_imports(self, run):
        with tempfile.TemporaryDirectory() as project:
            derive.run_headless('/ghidra', project, '/thin.dylib', False)
            self.assertIn('-import', run.call_args.args[0])

    @patch.object(derive.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout='', stderr=''))
    def test_existing_project_reused(self, run):
        with tempfile.TemporaryDirectory() as project:
            Path(project, 'wechat.gpr').touch()
            derive.run_headless('/ghidra', project, '/thin.dylib', False)
            self.assertIn('-process', run.call_args.args[0])

    @patch.object(derive.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout='', stderr=''))
    def test_fresh_import_is_explicit(self, run):
        with tempfile.TemporaryDirectory() as project:
            Path(project, 'wechat.gpr').touch()
            derive.run_headless('/ghidra', project, '/thin.dylib', True)
            self.assertIn('-import', run.call_args.args[0])

    def test_headless_failure_propagates(self):
        result = SimpleNamespace(returncode=7, stdout='failure', stderr='diagnostic')
        with tempfile.TemporaryDirectory() as project, patch.object(derive.subprocess, 'run', return_value=result):
            with self.assertRaises(SystemExit):
                derive.run_headless('/ghidra', project, '/thin.dylib', False)


if __name__ == '__main__':
    unittest.main()
