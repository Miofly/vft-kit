"""仅测试离线关系检查，不测试论文质量；运行本文件即可。"""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("check_evidence.py")
spec = importlib.util.spec_from_file_location("check_evidence", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def complete():
    return {
        "stage": "final", "title": "测试记录",
        "sources": [{"id": "S1", "title": "测试材料", "kind": "data",
                     "location": "原始匿名记录表第1行", "verified": True,
                     "read_state": "fulltext"}],
        "claims": [{"id": "C1", "text": "描述性观察", "kind": "observation",
                    "status": "supported", "evidence": [{"source_id": "S1", "locator": "表1"}]}],
        "requirements": [{"id": "R1", "text": "适用格式已核对", "status": "done"}],
        "review": [{"id": "V1", "issue": "复核范围与结果已记录", "status": "resolved"}]
    }


class Checks(unittest.TestCase):
    def test_complete(self):
        self.assertTrue(module.validate(complete())["ok"])

    def test_draft_warnings(self):
        d = complete()
        d["stage"] = "draft"
        d["claims"][0].update(status="pending", evidence=[])
        d["sources"][0].update(verified=False, read_state="abstract")
        result = module.validate(d)
        self.assertTrue(result["ok"])
        self.assertEqual(len(result["warnings"]), 2)

    def test_final_pending_blocks(self):
        d = complete()
        d["claims"][0]["status"] = "pending"
        self.assertFalse(module.validate(d)["ok"])

    def test_missing_source(self):
        d = complete()
        d["claims"][0]["evidence"][0]["source_id"] = "missing"
        self.assertFalse(module.validate(d)["ok"])

    def test_duplicate_id(self):
        d = complete()
        d["sources"].append(copy.deepcopy(d["sources"][0]))
        self.assertFalse(module.validate(d)["ok"])

    def test_duplicate_normalized_doi(self):
        d = complete()
        d["sources"][0]["doi"] = "https://doi.org/10.1234/ABC"
        other = copy.deepcopy(d["sources"][0])
        other.update(id="S2", doi="doi:10.1234/abc")
        d["sources"].append(other)
        self.assertFalse(module.validate(d)["ok"])

    def test_observation_needs_data(self):
        d = complete()
        d["sources"][0]["kind"] = "literature"
        self.assertFalse(module.validate(d)["ok"])

    def test_supported_needs_evidence_even_draft(self):
        d = complete()
        d["stage"] = "draft"
        d["claims"][0]["evidence"] = []
        self.assertFalse(module.validate(d)["ok"])

    def test_observation_needs_read_data_even_draft(self):
        d = complete()
        d["stage"] = "draft"
        d["sources"][0]["read_state"] = "record"
        self.assertFalse(module.validate(d)["ok"])

    def test_locator_required(self):
        d = complete()
        d["claims"][0]["evidence"][0]["locator"] = " "
        with self.assertRaises(ValueError):
            module.validate(d)

    def test_boolean_string_rejected(self):
        d = complete()
        d["sources"][0]["verified"] = "false"
        with self.assertRaises(ValueError):
            module.validate(d)

    def test_missing_arrays_rejected(self):
        d = complete()
        del d["requirements"]
        with self.assertRaises(ValueError):
            module.validate(d)

    def test_open_review_blocks_final(self):
        d = complete()
        d["review"][0]["status"] = "open"
        self.assertFalse(module.validate(d)["ok"])

    def test_empty_final_not_ready(self):
        d = complete()
        d.update(sources=[], claims=[], requirements=[], review=[])
        self.assertFalse(module.validate(d)["ok"])

    def test_proposal_only_not_final(self):
        d = complete()
        d["claims"][0].update(kind="proposal", evidence=[])
        self.assertFalse(module.validate(d)["ok"])

    def test_abstract_final_blocks(self):
        d = complete()
        d["sources"][0]["read_state"] = "abstract"
        self.assertFalse(module.validate(d)["ok"])

    def test_cli_readonly_and_exit_codes(self):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder) / "ledger.json"
            for data, status in [(complete(), 0), ({**complete(), "review": []}, 1), ({}, 2)]:
                original = json.dumps(data).encode()
                p.write_bytes(original)
                result = subprocess.run([sys.executable, "-I", str(SCRIPT), str(p)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, status, result.stdout + result.stderr)
                self.assertIsInstance(json.loads(result.stdout), dict)
                self.assertEqual(p.read_bytes(), original)
            p.write_text("{invalid", encoding="utf-8")
            result = subprocess.run([sys.executable, "-I", str(SCRIPT), str(p)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("input_error", json.loads(result.stdout))


if __name__ == "__main__":
    unittest.main()
