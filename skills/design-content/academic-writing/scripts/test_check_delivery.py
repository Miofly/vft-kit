"""交付闸门正反样本与真实CLI测试。"""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_check_evidence import complete
from check_delivery import audit, LAYERS


class Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.paper = self.root / 'paper.md'
        self.paper.write_text('正文[1]。\n参考文献\n[1] 合成测试资料\n')
        self.ledger = self.root / 'ledger.json'
        self.ledger.write_text(json.dumps(complete()))
        self.layers = {x: {'status': 'passed', 'evidence': '仅为测试用合成核验记录'} for x in LAYERS}

    def test_final_without_attestations_blocks(self):
        self.assertFalse(audit(self.paper, self.ledger)['ok'])

    def test_final_with_all_layers(self):
        self.assertTrue(audit(self.paper, self.ledger, attestations=self.layers)['ok'])

    def test_draft_keeps_pending(self):
        d = complete()
        d['stage'] = 'draft'
        self.ledger.write_text(json.dumps(d))
        result = audit(self.paper, self.ledger)
        self.assertTrue(result['ok'])
        self.assertTrue(result['warnings'])

    def test_bad_manuscript_blocks_despite_attestations(self):
        self.paper.write_text('正文[2]。\n参考文献\n[1] 资料')
        self.assertFalse(audit(self.paper, self.ledger, attestations=self.layers)['ok'])

    def test_incomplete_layer(self):
        self.layers['methods']['status'] = 'pending'
        self.assertFalse(audit(self.paper, self.ledger, attestations=self.layers)['ok'])

    def test_missing_layer_rejected(self):
        del self.layers['methods']
        with self.assertRaises(ValueError):
            audit(self.paper, self.ledger, attestations=self.layers)

    def test_empty_attestation_rejected(self):
        self.layers['methods']['evidence'] = ' '
        with self.assertRaises(ValueError):
            audit(self.paper, self.ledger, attestations=self.layers)

    def test_wrong_status_type_rejected(self):
        self.layers['methods']['status'] = []
        with self.assertRaises(ValueError):
            audit(self.paper, self.ledger, attestations=self.layers)

    def test_bad_docx_cli(self):
        p = self.root / 'bad.docx'
        p.write_text('not zip')
        script = Path(__file__).with_name('check_delivery.py')
        result = subprocess.run([sys.executable, '-B', '-I', str(script), str(p), str(self.ledger)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('input_error', json.loads(result.stdout))

    def test_cli_no_writes(self):
        script = Path(__file__).with_name('check_delivery.py')
        before = {x.name: x.read_bytes() for x in self.root.iterdir()}
        result = subprocess.run([sys.executable, '-B', '-I', str(script), str(self.paper), str(self.ledger)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertFalse(json.loads(result.stdout)['ok'])
        self.assertEqual(before, {x.name: x.read_bytes() for x in self.root.iterdir()})


if __name__ == '__main__':
    unittest.main()
