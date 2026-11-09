#!/usr/bin/env python3
"""test-search-awesome-rea.py — search-awesome-rea.py 的标准库 unittest 自测。

fixture 用 tempfile 临时目录（自动清理，不落项目）；另有一条针对本地真实上游的
冒烟测试，通过 REA_TEST_DATA_DIR 指定绝对数据路径，未指定时 skip。
运行: python3 test-search-awesome-rea.py
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "search-awesome-rea.py")
REAL_DATA = os.environ.get("REA_TEST_DATA_DIR", "")
ALL_TARGETS = ("website", "game", "app", "binary", "firmware", "protocol")

spec = importlib.util.spec_from_file_location("search_awesome_rea", SCRIPT)
rea_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rea_mod)


def _write_fixture(root):
    """rea 2 条 + tools 6 条(每 target 一条) + papers 2 条 + 证据档位(C0/C2/C3)。"""
    rec = {"evidence_url": "https://example.com/ev", "verification": "source-reviewed",
           "verified_at": "2026-11-09", "requirements": ["python 3"],
           "description_en": "eng desc", "description_zh": "中文描述"}
    rea = [{"id": "R1", "name": "ghidra decompiler", "url": "https://ex/r1", "kind": "project",
            "targets": ["binary"], "relationship": "official-core", **rec}]
    tools = [{"id": f"TOOL{i}", "name": f"{t} scan tool", "url": f"https://ex/t{i}",
              "kind": "tool", "targets": [t], "relationship": "foundation",
              "description_en": f"scan for {t}", "description_zh": "中文描述",
              "requirements": None, "evidence_url": rec["evidence_url"],
              "verification": "source-reviewed", "verified_at": "2026-11-09"}
             for i, t in enumerate(ALL_TARGETS)]
    tools[3]["description_en"] = "ghidra-integrated binary scan"  # TOOL3 亦命中 ghidra
    rea.append({"id": "RL2", "name": "firmware notes", "url": "https://ex/rl2",
                "kind": "documentation", "targets": ["firmware", "protocol"],
                "relationship": "official-documentation", **rec})
    papers = [{"id": "P1", "title": "ghidra paper", "title_zh": "ghidra 论文",
               "url": "https://ex/p1", "kind": "research", "targets": ["binary"],
               "verification": "source-reviewed", "evidence_urls": ["https://ex/p1a"],
               "requirements": None, "scope_limitations_zh": "仅函数级基准",
               "description_en": "paper eng", "description_zh": "中文描述"},
              {"id": "P2", "title": "other paper", "url": "https://ex/p2", "kind": "research",
               "targets": ["website"], "verification": "source-reviewed", "evidence_urls": []}]
    for name, payload in (("rea-resources.json", rea), ("tool-resources.json", tools),
                          ("papers.json", papers)):
        with open(os.path.join(root, name), "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False)
    with open(os.path.join(root, "evidence-classes.json"), "w", encoding="utf-8") as f:
        json.dump({"entries": [{"id": "R1", "evidence_class": 2, "runtime_status": "not-run"},
                               {"id": "TOOL2", "evidence_class": 0, "runtime_status": "not-run"},
                               {"id": "TOOL3", "evidence_class": 1, "runtime_status": "not-run"},
                               {"id": "P1", "evidence_class": 3, "runtime_status": "not-run"}]}, f)


class CliTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.d = self._tmp.name
        _write_fixture(self.d)

    def tearDown(self):
        self._tmp.cleanup()

    def run_cli(self, *args, data_dir=True):
        argv = [sys.executable, SCRIPT, "--skill-dir", self.d]
        if data_dir:
            argv += ["--data-dir", self.d]
        argv += list(args)
        return subprocess.run(argv, capture_output=True, text=True)

    def ok_json(self, *args, **kw):
        r = self.run_cli(*args, **kw)
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def bad(self, *args, **kw):
        r = self.run_cli(*args, **kw)
        self.assertNotEqual(r.returncode, 0, (args, r.stdout, r.stderr))
        self.assertTrue(r.stderr.strip(), args)

    # ---- 正例检索 ----
    def test_query_english_title_first(self):
        out = self.ok_json("--query", "ghidra", "--json")
        ids = [x["id"] for x in out["results"]]
        self.assertEqual(set(ids), {"R1", "P1", "TOOL3"}, "ghidra 命中: R1名/P1题/TOOL3描述")
        self.assertEqual(ids[0], "R1", "标题命中应排在描述命中前")
        self.assertEqual((out["total"], out["returned"], out["truncated"]), (3, 3, False))

    def test_query_chinese(self):
        out = self.ok_json("--query", "中文描述", "--limit", "1", "--json")
        # 8 条资源 + P1 带中文描述 = 9；P2 无
        self.assertEqual(out["total"], 9)
        self.assertEqual((out["returned"], out["truncated"]), (1, True))

    def test_all_six_targets(self):
        for i, t in enumerate(ALL_TARGETS):
            out = self.ok_json("--target", t, "--json")
            hits = {x["id"] for x in out["results"]}
            self.assertIn(f"TOOL{i}", hits, t)
            self.assertTrue(all(t in x["targets"] for x in out["results"]), t)
            self.assertGreaterEqual(out["total"], 1, t)
        self.assertEqual(self.ok_json("--target", "binary", "--json")["total"], 3)  # R1+P1+TOOL3

    def test_kind_filter_and_papers_only(self):
        out = self.ok_json("--kind", "research", "--json")
        self.assertEqual({x["id"] for x in out["results"]}, {"P1", "P2"})
        out = self.ok_json("--kind", "tool", "--query", "scan", "--json")
        self.assertEqual({x["id"] for x in out["results"]}, {f"TOOL{i}" for i in range(6)})

    def test_limit_and_truncated(self):
        out = self.ok_json("--query", "scan", "--limit", "3", "--json")
        self.assertEqual((out["total"], out["returned"], out["truncated"]), (6, 3, True))
        out = self.ok_json("--target", "binary", "--limit", "10", "--json")
        self.assertEqual((out["total"], out["returned"], out["truncated"]), (3, 3, False))

    def test_negative_no_match(self):
        out = self.ok_json("--query", "zzzznope", "--json")
        self.assertEqual(out["total"], 0)
        self.assertEqual(out["results"], [])

    def test_multi_term_all_required(self):
        self.assertEqual(self.ok_json("--query", "ghidra paper", "--json")["total"], 1)
        self.assertEqual(self.ok_json("--query", "absent-one absent-two", "--json")["total"], 0)

    def test_default_data_dir(self):
        # 不传 --data-dir 时应按 <skill-dir>/references/awesome-rea/upstream/data 解析
        nested = os.path.join(self.d, "references", "awesome-rea", "upstream", "data")
        os.makedirs(nested)
        _write_fixture(nested)
        r = self.run_cli("--query", "ghidra", "--json", data_dir=False)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(r.stdout)["total"], 3)

    def test_text_output_not_json(self):
        r = self.run_cli("--query", "ghidra", "--limit", "2")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("ghidra decompiler", r.stdout)
        self.assertIn("不是本次实测", r.stdout)
        self.assertNotIn('"total"', r.stdout)

    # ---- 证据档位不改写 runtime_status ----
    def test_evidence_class_not_runtime(self):
        out = self.ok_json("--query", "ghidra", "--json")
        by_id = {x["id"]: x for x in out["results"]}
        for x in out["results"]:
            self.assertEqual(x["runtime_status"], "not-run",
                             "证据档位不得把 runtime_status 改写为已验证: " + x["id"])
        self.assertEqual(by_id["R1"]["evidence_class"], "C2")
        self.assertEqual(by_id["P1"]["evidence_class"], "C3")
        r = self.run_cli("--target", "app", "--json")  # TOOL2(app) 为 C0
        by_id = {x["id"]: x for x in json.loads(r.stdout)["results"]}
        self.assertEqual(by_id["TOOL2"]["evidence_class"], "C0")
        self.assertEqual(by_id["TOOL2"]["runtime_status"], "not-run")
        # 无证据档位条目：字段为 null，不虚构
        out = self.ok_json("--kind", "research", "--json")
        by_id = {x["id"]: x for x in out["results"]}
        self.assertIsNone(by_id["P2"]["evidence_class"])
        self.assertIsNone(by_id["P2"]["runtime_status"])

    def test_scope_and_source_preserved(self):
        path = os.path.join(self.d, "evidence-classes.json")
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        data["entries"][0].update(scope="partial", evidence_status="observed")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f)
        item = self.ok_json("--query", "ghidra decompiler", "--json")["results"][0]
        self.assertEqual(item["scope"], "partial")
        self.assertEqual(item["evidence_status"], "observed")
        self.assertEqual(item["source_file"], "rea-resources.json")
        self.assertEqual(item["verified_at"], "2026-11-09")

    def test_duplicate_or_malformed_evidence_refused(self):
        path = os.path.join(self.d, "evidence-classes.json")
        invalid = [[], {"entries": {}}, {"entries": [None]},
                   {"entries": [{"id": []}]},
                   {"entries": [{"id": "R1", "evidence_class": 9}]},
                   {"entries": [{"id": "R1"}, {"id": "R1"}]}]
        for payload in invalid:
            with self.subTest(payload=payload):
                with open(path, "w", encoding="utf-8") as f:
                    json.dump(payload, f)
                result = self.run_cli("--query", "ghidra", "--json")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("error:", result.stderr)
                self.assertNotIn("Traceback", result.stderr)

    # ---- 非法参数/坏数据 ----
    def test_empty_request(self):
        self.bad()
        self.bad("--query", "   ")

    def test_invalid_limit(self):
        self.bad("--query", "ghidra", "--limit", "0")
        self.bad("--query", "ghidra", "--limit", "-2")
        self.bad("--query", "ghidra", "--limit", "abc")

    def test_relative_dirs(self):
        for skill_dir, extra in (("relative", []), (self.d, ["--data-dir", "rel"])):
            r = subprocess.run([sys.executable, SCRIPT, "--skill-dir", skill_dir,
                                "--query", "x"] + extra, capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0, extra)
            self.assertIn("绝对路径", r.stderr)

    def test_missing_file(self):
        os.remove(os.path.join(self.d, "papers.json"))
        self.bad("--query", "ghidra")

    def test_bad_json(self):
        with open(os.path.join(self.d, "rea-resources.json"), "w") as f:
            f.write("{not json")
        self.bad("--query", "ghidra")

    def test_duplicate_id(self):
        path = os.path.join(self.d, "tool-resources.json")
        with open(path, encoding="utf-8") as f:
            items = json.load(f)
        items.append(dict(items[0]))
        with open(path, "w", encoding="utf-8") as f:
            json.dump(items, f)
        self.bad("--query", "scan")

    def test_dup_id_across_lists(self):
        path = os.path.join(self.d, "papers.json")
        with open(path, encoding="utf-8") as f:
            papers = json.load(f)
        papers.append({"id": "R1", "title": "dup", "url": "u", "kind": "research",
                       "targets": ["website"], "verification": "source-reviewed"})
        with open(path, "w", encoding="utf-8") as f:
            json.dump(papers, f)
        self.bad("--query", "ghidra")


@unittest.skipUnless(os.path.isfile(os.path.join(REAL_DATA, "rea-resources.json")),
                     "本地真实上游不存在")
class RealUpstreamTests(unittest.TestCase):
    def base(self, *args):
        return [sys.executable, SCRIPT, "--skill-dir", HERE,
                "--data-dir", REAL_DATA] + list(args)

    def test_ghidra_binary(self):
        r = subprocess.run(self.base("--query", "ghidra", "--target", "binary",
                                     "--limit", "3", "--json"),
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        out = json.loads(r.stdout)
        self.assertGreaterEqual(out["total"], 1)
        self.assertLessEqual(out["returned"], 3)
        self.assertTrue(all("binary" in x["targets"] for x in out["results"]))
        self.assertIn("不是本次实测", out["note"])

    def test_paper_only_filter(self):
        r = subprocess.run(self.base("--kind", "research", "--limit", "5", "--json"),
                           capture_output=True, text=True)
        out = json.loads(r.stdout)
        # 上游 papers 235 条 + tool-resources 9 条 + rea-resources 1 条 kind=research
        self.assertEqual(out["total"], 245)
        self.assertTrue(all(x["kind"] == "research" for x in out["results"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
