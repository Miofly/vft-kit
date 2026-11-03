"""Offline state-machine tests; no provider calls or shared profile writes."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('gate', Path(__file__).with_name('task-completion-gate.py'))
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class GateTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.env = patch.dict(os.environ, {'CLAUDE_CONFIG_DIR': self.folder.name, 'CCMAX_TASK_GATE': '1'})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.call('UserPromptSubmit', prompt='修复并验证')

    def call(self, event, **fields):
        return gate.hook({'session_id': 'test-session', 'hook_event_name': event, **fields})

    def finish(self, status, **fields):
        with contextlib.redirect_stdout(io.StringIO()):
            gate.finish('test-session', {'revision': 1, 'status': status, **fields})

    def tool(self, name='Bash', ok=True):
        self.call('PostToolUse', tool_name=name, tool_input={'command': 'assert acceptance'},
                  tool_response={'is_error': not ok})

    def test_arbitrary_reply_cannot_finish(self):
        for text in ['.', '任意措辞的进度', '全部完成，已通过', '无法继续']:
            self.call('UserPromptSubmit', prompt='工作任务')
            self.assertEqual(self.call('Stop', last_assistant_message=text)['decision'], 'block')

    def test_stall_bound_and_progress_reset(self):
        for _ in range(3):
            self.assertEqual(self.call('Stop')['decision'], 'block')
        self.assertIn('TASK_STALLED', self.call('Stop')['systemMessage'])
        self.tool()
        self.assertEqual(self.call('Stop')['decision'], 'block')

    def test_completion_requires_evidence(self):
        with self.assertRaises(ValueError):
            self.finish('completed', checks=[])
        with self.assertRaises(ValueError):
            self.finish('completed', checks=[{'requirement': '验收', 'evidence': [99]}])
        self.tool(ok=False)
        with self.assertRaises(ValueError):
            self.finish('completed', checks=[{'requirement': '验收', 'evidence': [1]}])

    def test_edit_requires_later_acceptance(self):
        self.tool()
        self.tool('Edit')
        self.tool('Read')
        for evidence in [[1], [3]]:
            with self.assertRaises(ValueError):
                self.finish('completed', checks=[{'requirement': '修复并验收', 'evidence': evidence}])
        self.tool()
        self.finish('completed', checks=[{'requirement': '修复并验收', 'evidence': [4]}])
        self.assertIsNone(self.call('Stop'))
        self.tool('Read')
        self.assertEqual(self.call('Stop')['decision'], 'block')

    def test_revision_fences_old_receipts(self):
        self.tool()
        self.call('UserPromptSubmit', prompt='另一项任务')
        with self.assertRaises(ValueError):
            self.finish('completed', checks=[{'requirement': '旧任务', 'evidence': [1]}])

    def test_answer_blocked_cancelled(self):
        self.finish('answered', reason='纯问答，答案依据已列出')
        self.assertIsNone(self.call('Stop'))
        self.call('UserPromptSubmit', prompt='停止')
        self.assertIsNone(self.call('Stop'))
        self.call('UserPromptSubmit', prompt='新的任务')
        with contextlib.redirect_stdout(io.StringIO()):
            gate.finish('test-session', {'revision': 3, 'status': 'blocked', 'reason': '需要用户扫码', 'remaining': ['登录后验收']})
        self.assertIsNone(self.call('Stop'))

    def test_edits_cannot_be_plain_answer(self):
        self.tool('Edit')
        with self.assertRaises(ValueError):
            self.finish('answered', reason='不执行了')

    def test_standalone_controls_only(self):
        script = str(Path(gate.__file__).resolve())
        command = f'python3 "{script}" --status --session test-session'
        self.assertTrue(gate.control_command(command, 'test-session'))
        self.assertFalse(gate.control_command(command + '; touch other', 'test-session'))
        self.assertFalse(gate.control_command(command, 'other-session'))

    def test_duplicate_tool_receipt(self):
        for _ in range(2):
            self.call('PostToolUse', tool_name='Bash', tool_use_id='one', tool_response={'exit_code': 0})
        with gate.locked('test-session') as state:
            self.assertEqual(len(state['tools']), 1)

    def test_resume_and_continue_preserve_evidence(self):
        self.tool()
        before = self.call('SessionStart', source='compact')
        self.assertIn('revision=1', before['hookSpecificOutput']['additionalContext'])
        self.call('UserPromptSubmit', prompt='继续')
        with gate.locked('test-session') as state:
            self.assertEqual(state['revision'], 1)
            self.assertEqual(len(state['tools']), 1)
            self.assertEqual(state['prompt'], '修复并验证')

    def test_failed_tools_are_not_progress(self):
        for _ in range(3):
            self.assertEqual(self.call('Stop')['decision'], 'block')
            self.tool(ok=False)
        self.assertIn('TASK_STALLED', self.call('Stop')['systemMessage'])
        self.assertTrue(gate.response_failed({'interrupted': True}))
        self.assertTrue(gate.response_failed({'exitCode': 1}))

    def test_failed_terminal_command_invalidates_previous_receipt(self):
        self.finish('answered', reason='纯问答')
        self.call('PostToolUseFailure', tool_name='Bash', tool_input={'command': (
            f'python3 "{Path(gate.__file__).resolve()}" --finish --session test-session --receipt \'{{}}\'')},
            error='invalid receipt')
        self.assertEqual(self.call('Stop')['decision'], 'block')

    def test_old_heuristics_disabled(self):
        import runpy
        old = runpy.run_path(str(Path(gate.__file__).with_name('stall-continue-hook.py')))
        self.assertIsNone(old['decide']({}, dict(os.environ)))


if __name__ == '__main__':
    unittest.main()
