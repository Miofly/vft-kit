import datetime as dt
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = pathlib.Path(__file__).parents[1] / "scripts" / "collect.py"
SPEC = importlib.util.spec_from_file_location("co_work_summary_collect", SCRIPT)
collect = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = collect
SPEC.loader.exec_module(collect)


class GeminiParsingTests(unittest.TestCase):
    def test_pretty_json_is_parsed_as_one_document(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "session.json"
            path.write_text(
                json.dumps(
                    {
                        "messages": [
                            {
                                "role": "user",
                                "content": "实现报表导出",
                                "timestamp": "2026-08-14T10:00:00+08:00",
                                "cwd": "/workspace/demo",
                            }
                        ]
                    },
                    ensure_ascii=False,
                    indent=2,
                ),
                encoding="utf-8",
            )

            records, warnings = collect.load_gemini_records(path)

        self.assertEqual(1, len(records))
        self.assertEqual([], warnings)

    def test_non_mapping_message_is_skipped_without_crashing(self):
        entries, warnings = collect.gemini_entries_from_records(
            [{"message": "纯字符串消息"}],
            fallback_date=dt.date(2026, 8, 14),
            fallback_project="gemini-test",
        )

        self.assertEqual([], entries)
        self.assertTrue(any("消息结构" in item for item in warnings))

    def test_summary_limit_counts_unique_messages(self):
        records = [
            {
                "role": "user",
                "content": "重复任务",
                "timestamp": "2026-08-14T10:00:00+08:00",
            }
            for _ in range(5)
        ]
        records.append(
            {
                "role": "user",
                "content": "唯一任务",
                "timestamp": "2026-08-14T11:00:00+08:00",
            }
        )

        entries, warnings = collect.gemini_entries_from_records(
            records,
            fallback_date=dt.date(2026, 8, 14),
            fallback_project="gemini-test",
        )

        self.assertEqual(["重复任务", "唯一任务"], [item.summary for item in entries])
        self.assertEqual([], warnings)

    def test_fallback_file_date_is_disclosed(self):
        entries, warnings = collect.gemini_entries_from_records(
            [{"role": "user", "content": "无时间任务"}],
            fallback_date=dt.date(2026, 8, 14),
            fallback_project="gemini-test",
        )

        self.assertEqual(1, len(entries))
        self.assertTrue(any("文件修改日期" in item for item in warnings))


class RuntimeContractTests(unittest.TestCase):
    def test_reversed_range_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "结束日期不能早于开始日期"):
            collect.resolve_date_range("2026-08-15", "2026-08-14")

    def test_invalid_date_has_friendly_error(self):
        with self.assertRaisesRegex(ValueError, "日期格式必须为 YYYY-MM-DD"):
            collect.resolve_date_range("2026/08/14", "2026-08-14")

    def test_dedup_keeps_same_summary_on_different_dates(self):
        entries = [
            collect.SessionEntry(
                "Codex", "/demo", "demo", dt.date(2026, 8, 13), "修复登录"
            ),
            collect.SessionEntry(
                "Codex", "/demo", "demo", dt.date(2026, 8, 13), "修复登录"
            ),
            collect.SessionEntry(
                "Codex", "/demo", "demo", dt.date(2026, 8, 14), "修复登录"
            ),
        ]

        result = collect.deduplicate_sessions(entries)

        self.assertEqual(
            [dt.date(2026, 8, 13), dt.date(2026, 8, 14)],
            [item.date for item in result],
        )

    def test_module_has_no_cache_path(self):
        source = SCRIPT.read_text(encoding="utf-8")

        self.assertNotIn("REPO_CACHE", source)
        self.assertNotIn("repos.json", source)

    def test_main_reports_reversed_range_without_collecting(self):
        stdout = io.StringIO()
        stderr = io.StringIO()

        exit_code = collect.main(
            ["--start", "2026-08-15", "--end", "2026-08-14"],
            stdout=stdout,
            stderr=stderr,
        )

        self.assertEqual(2, exit_code)
        self.assertEqual("", stdout.getvalue())
        self.assertIn("结束日期不能早于开始日期", stderr.getvalue())

    def test_cli_does_not_create_or_modify_files_in_isolated_home(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = pathlib.Path(tmp)
            (home / ".claude" / "projects").mkdir(parents=True)
            (home / ".codex" / "sessions").mkdir(parents=True)
            (home / ".gemini" / "tmp").mkdir(parents=True)
            repo = home / "work" / "demo"
            repo.mkdir(parents=True)
            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "config", "user.email", "owner@example.com"],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(repo), "config", "user.name", "Owner"],
                check=True,
            )
            (repo / "work.txt").write_text("done\n", encoding="utf-8")
            subprocess.run(["git", "-C", str(repo), "add", "work.txt"], check=True)
            commit_env = {
                **os.environ,
                "GIT_AUTHOR_DATE": "2026-08-14T10:00:00+08:00",
                "GIT_COMMITTER_DATE": "2026-08-14T10:00:00+08:00",
            }
            subprocess.run(
                ["git", "-C", str(repo), "commit", "-q", "-m", "实现零写入采集"],
                check=True,
                env=commit_env,
            )

            def snapshot():
                return {
                    str(path.relative_to(home)): path.read_bytes()
                    for path in home.rglob("*")
                    if path.is_file()
                }

            before = snapshot()
            env = {**os.environ, "HOME": str(home), "PYTHONDONTWRITEBYTECODE": "1"}
            completed = subprocess.run(
                [
                    "python3",
                    str(SCRIPT),
                    "--start",
                    "2026-08-14",
                    "--end",
                    "2026-08-14",
                ],
                capture_output=True,
                text=True,
                env=env,
                timeout=30,
            )
            after = snapshot()

        self.assertEqual(0, completed.returncode, completed.stderr)
        self.assertEqual(before, after)
        self.assertIn("实现零写入采集", completed.stdout)
        self.assertNotIn("状态", completed.stdout)


class RepoDiscoveryTests(unittest.TestCase):
    def test_discovers_git_directory_and_worktree_file_without_cache(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            regular = root / "regular"
            worktree = root / "worktree"
            ignored = root / "node_modules" / "ignored"
            (regular / ".git").mkdir(parents=True)
            worktree.mkdir()
            (worktree / ".git").write_text("gitdir: /tmp/example\n", encoding="utf-8")
            (ignored / ".git").mkdir(parents=True)

            repos, warnings = collect.discover_repos([root])

            self.assertEqual(
                {str(regular.resolve()), str(worktree.resolve())}, set(repos)
            )
            self.assertEqual([], warnings)
            self.assertFalse(any(path.name == "repos.json" for path in root.rglob("*")))

    def test_missing_scan_root_produces_warning(self):
        repos, warnings = collect.discover_repos(["/definitely/missing/co-work-summary"])

        self.assertEqual([], repos)
        self.assertTrue(any("不存在" in item for item in warnings))


class GitCollectionTests(unittest.TestCase):
    @staticmethod
    def make_runner():
        identities = {
            "/a/demo": ("a@example.com", "Alice"),
            "/b/demo": ("b@example.com", "Bob"),
        }

        def runner(args, **kwargs):
            repo = args[2]
            if args[3:6] == ["config", "--get", "user.email"]:
                return subprocess.CompletedProcess(
                    args, 0, stdout=identities[repo][0] + "\n", stderr=""
                )
            if args[3:6] == ["config", "--get", "user.name"]:
                return subprocess.CompletedProcess(
                    args, 0, stdout=identities[repo][1] + "\n", stderr=""
                )
            if args[3] == "log":
                email, name = identities[repo]
                subject = "提交A" if repo == "/a/demo" else "提交B"
                stdout = (
                    f"2026-08-14\x1f{name}\x1f{email}\x1f{subject}\n"
                    "2026-08-14\x1fOther\x1fother@example.com\x1f其他人的提交\n"
                )
                return subprocess.CompletedProcess(args, 0, stdout=stdout, stderr="")
            raise AssertionError("unexpected command: %r" % (args,))

        return runner

    def test_same_basename_repositories_keep_both_own_commits(self):
        entries, warnings = collect.collect_git(
            ["/a/demo", "/b/demo"],
            dt.date(2026, 8, 14),
            dt.date(2026, 8, 14),
            runner=self.make_runner(),
        )

        self.assertEqual(2, len(entries))
        self.assertEqual({"/a/demo", "/b/demo"}, {item.repo_id for item in entries})
        self.assertEqual({"提交A", "提交B"}, {item.subject for item in entries})
        self.assertEqual([], warnings)

    def test_git_failure_is_reported_instead_of_becoming_empty_success(self):
        def runner(args, **kwargs):
            if args[3] == "config":
                return subprocess.CompletedProcess(
                    args, 0, stdout="owner@example.com\n", stderr=""
                )
            return subprocess.CompletedProcess(
                args, 128, stdout="", stderr="permission denied"
            )

        entries, warnings = collect.collect_git(
            ["/private/demo"],
            dt.date(2026, 8, 14),
            dt.date(2026, 8, 14),
            runner=runner,
        )

        self.assertEqual([], entries)
        self.assertTrue(any("permission denied" in item for item in warnings))

    def test_missing_repo_identity_is_reported_and_repo_is_skipped(self):
        def runner(args, **kwargs):
            return subprocess.CompletedProcess(args, 1, stdout="", stderr="")

        entries, warnings = collect.collect_git(
            ["/repo/no-identity"],
            dt.date(2026, 8, 14),
            dt.date(2026, 8, 14),
            runner=runner,
        )

        self.assertEqual([], entries)
        self.assertTrue(any("Git 身份" in item for item in warnings))

    def test_log_reads_all_refs_and_keeps_distinct_same_subject_commits(self):
        commands = []

        def runner(args, **kwargs):
            commands.append(args)
            if args[3:6] == ["config", "--get", "user.email"]:
                return subprocess.CompletedProcess(
                    args, 0, stdout="owner@example.com\n", stderr=""
                )
            if args[3:6] == ["config", "--get", "user.name"]:
                return subprocess.CompletedProcess(
                    args, 0, stdout="Owner\n", stderr=""
                )
            stdout = (
                "2026-08-14\x1fOwner\x1fowner@example.com\x1f重复主题\n"
                "2026-08-14\x1fOwner\x1fowner@example.com\x1f重复主题\n"
            )
            return subprocess.CompletedProcess(args, 0, stdout=stdout, stderr="")

        entries, warnings = collect.collect_git(
            ["/repo/demo"],
            dt.date(2026, 8, 14),
            dt.date(2026, 8, 14),
            runner=runner,
        )

        log_command = next(command for command in commands if command[3] == "log")
        self.assertIn("--all", log_command)
        self.assertEqual(2, len(entries))
        self.assertEqual([], warnings)


class SessionCollectorTests(unittest.TestCase):
    def setUp(self):
        self.tz = dt.timezone(dt.timedelta(hours=8))
        self.start = dt.datetime(2026, 8, 14, 0, 0, tzinfo=self.tz)
        self.end = dt.datetime(2026, 8, 14, 23, 59, 59, tzinfo=self.tz)

    def test_claude_collector_keeps_multiple_real_user_summaries(self):
        with tempfile.TemporaryDirectory() as tmp:
            projects = pathlib.Path(tmp) / "projects"
            session = projects / "encoded-project" / "session.jsonl"
            session.parent.mkdir(parents=True)
            records = [
                {
                    "type": "user",
                    "timestamp": "2026-08-14T01:00:00Z",
                    "cwd": "/workspace/demo",
                    "message": {"content": "实现导出功能"},
                }
                for _ in range(5)
            ]
            records.append(
                {
                    "type": "user",
                    "timestamp": "2026-08-14T02:00:00Z",
                    "cwd": "/workspace/demo",
                    "message": {"content": "修复导出异常"},
                }
            )
            session.write_text(
                "\n".join(json.dumps(item, ensure_ascii=False) for item in records),
                encoding="utf-8",
            )

            with mock.patch.object(collect, "CC_PROJECTS_DIR", str(projects)):
                entries, warnings = collect.collect_cc(self.start, self.end)

        self.assertEqual(["实现导出功能", "修复导出异常"], [item.summary for item in entries])
        self.assertEqual([], warnings)

    def test_codex_collector_uses_each_user_message_timestamp(self):
        with tempfile.TemporaryDirectory() as tmp:
            sessions = pathlib.Path(tmp) / "sessions"
            rollout = sessions / "2026" / "08" / "14" / "rollout-test.jsonl"
            rollout.parent.mkdir(parents=True)
            records = [
                {
                    "timestamp": "2026-08-14T01:00:00Z",
                    "type": "session_meta",
                    "payload": {"cwd": "/workspace/demo"},
                }
            ]
            records.extend(
                {
                    "timestamp": "2026-08-14T01:10:00Z",
                    "type": "response_item",
                    "payload": {
                        "role": "user",
                        "content": [{"type": "input_text", "text": "实现支付页"}],
                    },
                }
                for _ in range(5)
            )
            records.append(
                {
                    "timestamp": "2026-08-14T02:10:00Z",
                    "type": "response_item",
                    "payload": {
                        "role": "user",
                        "content": [{"type": "input_text", "text": "修复支付回调"}],
                    },
                }
            )
            rollout.write_text(
                "\n".join(json.dumps(item, ensure_ascii=False) for item in records),
                encoding="utf-8",
            )

            with mock.patch.object(collect, "CODEX_SESSIONS_DIR", str(sessions)):
                entries, warnings = collect.collect_codex(self.start, self.end)

        self.assertEqual(["实现支付页", "修复支付回调"], [item.summary for item in entries])
        self.assertEqual([], warnings)


class RenderingTests(unittest.TestCase):
    def test_empty_success_differs_from_collection_warning(self):
        clean = collect.render_material(
            dt.date(2026, 8, 10), dt.date(2026, 8, 14), [], [], []
        )
        partial = collect.render_material(
            dt.date(2026, 8, 10),
            dt.date(2026, 8, 14),
            [],
            [],
            ["Git 扫描超时"],
        )

        self.assertIn("区间内未采集到可确认的工作记录", clean)
        self.assertNotIn("## D. 采集提示", clean)
        self.assertIn("## D. 采集提示", partial)
        self.assertIn("结果可能不完整", partial)

    def test_output_has_no_status_field_and_keeps_same_name_repositories(self):
        commits = [
            collect.CommitEntry("/a/demo", "demo", dt.date(2026, 8, 14), "提交A"),
            collect.CommitEntry("/b/demo", "demo", dt.date(2026, 8, 14), "提交B"),
        ]

        text = collect.render_material(
            dt.date(2026, 8, 14), dt.date(2026, 8, 14), [], commits, []
        )

        self.assertNotIn("状态", text)
        self.assertIn("a/demo", text)
        self.assertIn("b/demo", text)
        self.assertIn("提交A", text)
        self.assertIn("提交B", text)

    def test_parser_has_extra_repo_roots_and_no_refresh_option(self):
        help_text = collect.build_parser().format_help()

        self.assertIn("--repo-root", help_text)
        self.assertNotIn("--refresh-repos", help_text)

    def test_multiple_entries_from_one_repository_keep_simple_label(self):
        commits = [
            collect.CommitEntry("/a/demo", "demo", dt.date(2026, 8, 13), "提交A"),
            collect.CommitEntry("/a/demo", "demo", dt.date(2026, 8, 14), "提交B"),
        ]

        text = collect.render_material(
            dt.date(2026, 8, 13), dt.date(2026, 8, 14), [], commits, []
        )

        self.assertIn("### demo\n", text)
        self.assertNotIn("### a/demo\n", text)


class SkillContractTests(unittest.TestCase):
    def test_skill_metadata_and_command_match_new_contract(self):
        skill_dir = SCRIPT.parents[1]
        skill_text = (skill_dir / "SKILL.md").read_text(encoding="utf-8")
        readme_text = (skill_dir / "README.md").read_text(encoding="utf-8")
        combined = skill_text + "\n" + readme_text

        self.assertIn("name: co-work-summary", skill_text)
        self.assertIn("description: Use when", skill_text)
        self.assertIn('<skill_dir>/scripts/collect.py', skill_text)
        self.assertIn("--repo-root", combined)
        self.assertNotIn("python3 scripts/collect.py", combined)
        self.assertNotIn("--refresh-repos", combined)
        self.assertNotIn("（状态）", combined)
        self.assertNotIn("已上线 / 已提测", combined)

    def test_eval_set_uses_new_skill_name_and_has_near_miss(self):
        eval_path = SCRIPT.parents[1] / "evals" / "evals.json"

        data = json.loads(eval_path.read_text(encoding="utf-8"))

        self.assertEqual("co-work-summary", data["skill_name"])
        self.assertGreaterEqual(len(data["evals"]), 3)
        self.assertTrue(
            any("润色" in item["prompt"] for item in data["evals"]),
            "评测集需要覆盖只润色现有素材的近似反例",
        )


if __name__ == "__main__":
    unittest.main()
