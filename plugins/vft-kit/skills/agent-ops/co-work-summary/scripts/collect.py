#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
collect.py — 采集指定时间段的「工作素材」，供工作总结生成使用。

数据源（三源默认全部采集）：
  1. Claude Code  ~/.claude/projects/*/*.jsonl
  2. Codex        ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
  3. Gemini       ~/.gemini/tmp/<project_hash>/chats/session-*.json(l)
  4. Git 提交     默认扫描用户主目录，各仓库分别读取 Git 身份

输出：人类可读 markdown 素材，打印到 stdout。

用法：
  python3 collect.py                                      # 本周（周一 00:00 ~ 现在）
  python3 collect.py --start 2026-08-03 --end 2026-08-07  # 指定时间段（均含）
  python3 collect.py --start 2026-07-01 --end 2026-07-31  # 如整月
"""
import argparse
import datetime
import glob
import json
import os
import pathlib
import subprocess
import sys
from dataclasses import dataclass

HOME = os.path.expanduser("~")
CC_PROJECTS_DIR = os.path.join(HOME, ".claude", "projects")
CODEX_SESSIONS_DIR = os.path.join(HOME, ".codex", "sessions")
GEMINI_TMP_DIR = os.path.join(HOME, ".gemini", "tmp")
MAX_SUMMARIES_PER_SESSION = 5
MAX_SUMMARY_LENGTH = 160


@dataclass(frozen=True)
class SessionEntry:
    source: str
    project_id: str
    project_name: str
    date: datetime.date
    summary: str


@dataclass(frozen=True)
class GitIdentity:
    email: str
    name: str

    def matches(self, author_name, author_email):
        if self.email:
            return author_email.casefold() == self.email.casefold()
        return bool(self.name) and author_name == self.name


@dataclass(frozen=True)
class CommitEntry:
    repo_id: str
    repo_name: str
    date: datetime.date
    subject: str


# ---------- 通用工具 ----------

def local_tz():
    return datetime.datetime.now().astimezone().tzinfo


def resolve_date_range(start_value=None, end_value=None, today=None):
    """解析含边界的本地日期区间；输入无效时抛出可读错误。"""
    today = today or datetime.datetime.now().date()
    try:
        start_date = (datetime.datetime.strptime(start_value, "%Y-%m-%d").date()
                      if start_value else
                      today - datetime.timedelta(days=today.weekday()))
        end_date = (datetime.datetime.strptime(end_value, "%Y-%m-%d").date()
                    if end_value else today)
    except ValueError as exc:
        raise ValueError("日期格式必须为 YYYY-MM-DD") from exc
    if end_date < start_date:
        raise ValueError("结束日期不能早于开始日期")
    return start_date, end_date


def parse_iso_local(ts):
    """ISO 时间戳（UTC 带 Z）→ 本地时区 datetime；失败返回 None。"""
    if not ts:
        return None
    try:
        d = datetime.datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
        return d.astimezone()
    except Exception:
        return None


def parse_ts_any(val):
    """尽量解析 unix 秒/毫秒 或 ISO 字符串 → 本地 datetime。"""
    if val is None:
        return None
    if isinstance(val, (int, float)):
        try:
            if val > 1e12:  # 毫秒
                val = val / 1000.0
            return datetime.datetime.fromtimestamp(val).astimezone()
        except Exception:
            return None
    return parse_iso_local(val)


def base_project(cwd):
    """从工作目录取项目名（最后一段）。"""
    if not cwd:
        return None
    return os.path.basename(cwd.rstrip("/")) or None


def first_text(content):
    """从 message.content（str 或 list of parts）提取第一段文本。"""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        for blk in content:
            if isinstance(blk, dict):
                t = blk.get("text") or blk.get("input_text")
                if t:
                    return t
    return None


# 注入上下文/噪音前缀：真实用户输入不会以这些开头
INJECTED_PREFIXES = (
    "# AGENTS.md", "<INSTRUCTIONS>", "<environment_context>",
    "<user_instructions>", "# Instructions", "Base directory for this skill",
    "<system-reminder>", "Caveat:",
)


def clean_title(text):
    if not text:
        return None
    text = text.strip().replace("\n", " ")
    if not text or text.startswith("<"):
        return None
    for p in INJECTED_PREFIXES:
        if text.startswith(p):
            return None
    return text[:MAX_SUMMARY_LENGTH]


def deduplicate_sessions(entries):
    """同一来源、项目、日期和摘要只保留一次，跨日期活动不合并。"""
    result = []
    seen = set()
    for entry in entries:
        key = (entry.source, entry.project_id, entry.date, entry.summary)
        if key in seen:
            continue
        seen.add(key)
        result.append(entry)
    return result


# ---------- Claude Code ----------

def collect_cc(start_dt, end_dt):
    """采集 Claude Code 用户消息，返回 (entries, warnings)。"""
    entries = []
    warnings = []
    if not os.path.isdir(CC_PROJECTS_DIR):
        return [], ["Claude Code 会话目录不可用：%s" % CC_PROJECTS_DIR]
    for proj_dir in os.listdir(CC_PROJECTS_DIR):
        full = os.path.join(CC_PROJECTS_DIR, proj_dir)
        if not os.path.isdir(full):
            continue
        for jf in glob.glob(os.path.join(full, "*.jsonl")):
            session_entries = []
            session_seen = set()
            cwd = None
            try:
                if os.path.getmtime(jf) < start_dt.timestamp():
                    continue
            except OSError as exc:
                warnings.append("无法读取 Claude Code 文件时间 %s：%s" %
                                (jf, exc))
                continue
            try:
                with open(jf, "r", encoding="utf-8") as fh:
                    for line_number, line in enumerate(fh, start=1):
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            record = json.loads(line)
                        except json.JSONDecodeError:
                            warnings.append(
                                "Claude Code 文件 %s 第 %d 行不是有效 JSON" %
                                (jf, line_number))
                            continue
                        if not isinstance(record, dict) or \
                                record.get("type") != "user":
                            continue
                        cwd_value = record.get("cwd")
                        if isinstance(cwd_value, str) and cwd_value:
                            cwd = cwd_value
                        when = parse_iso_local(record.get("timestamp"))
                        if not when or not (start_dt <= when <= end_dt):
                            continue
                        message = record.get("message")
                        if not isinstance(message, dict):
                            warnings.append(
                                "Claude Code 文件 %s 的用户消息结构异常" % jf)
                            continue
                        summary = clean_title(
                            first_text(message.get("content")))
                        if not summary:
                            continue
                        project_id = (os.path.realpath(cwd) if cwd else
                                      "claude:%s" % proj_dir)
                        project_name = base_project(cwd) or proj_dir
                        key = (project_id, when.date(), summary)
                        if key in session_seen:
                            continue
                        session_seen.add(key)
                        session_entries.append(SessionEntry(
                            "CC", project_id, project_name,
                            when.date(), summary))
                        if len(session_entries) >= MAX_SUMMARIES_PER_SESSION:
                            break
            except OSError as exc:
                warnings.append("无法读取 Claude Code 文件 %s：%s" %
                                (jf, exc))
                continue
            entries.extend(session_entries)
    return deduplicate_sessions(entries), warnings


# ---------- Codex ----------

def collect_codex(start_dt, end_dt):
    """采集 Codex 用户消息，返回 (entries, warnings)。"""
    entries = []
    warnings = []
    if not os.path.isdir(CODEX_SESSIONS_DIR):
        return [], ["Codex 会话目录不可用：%s" % CODEX_SESSIONS_DIR]
    d = start_dt.date() - datetime.timedelta(days=1)
    end_d = end_dt.date() + datetime.timedelta(days=1)
    while d <= end_d:
        day_dir = os.path.join(CODEX_SESSIONS_DIR,
                               "%04d" % d.year, "%02d" % d.month, "%02d" % d.day)
        if os.path.isdir(day_dir):
            for rf in glob.glob(os.path.join(day_dir, "rollout-*.jsonl")):
                cwd = None
                session_time = None
                session_entries = []
                session_seen = set()
                try:
                    with open(rf, "r", encoding="utf-8") as fh:
                        for line_number, line in enumerate(fh, start=1):
                            line = line.strip()
                            if not line:
                                continue
                            try:
                                rec = json.loads(line)
                            except json.JSONDecodeError:
                                warnings.append(
                                    "Codex 文件 %s 第 %d 行不是有效 JSON" %
                                    (rf, line_number))
                                continue
                            if not isinstance(rec, dict):
                                continue
                            rtype = rec.get("type")
                            payload = rec.get("payload", {}) or {}
                            if not isinstance(payload, dict):
                                continue
                            if rtype == "session_meta":
                                cwd_value = payload.get("cwd")
                                if isinstance(cwd_value, str) and cwd_value:
                                    cwd = cwd_value
                                session_time = (
                                    parse_iso_local(payload.get("timestamp")) or
                                    parse_iso_local(rec.get("timestamp")) or
                                    session_time)
                                continue
                            if rtype != "response_item" or \
                                    payload.get("role") != "user":
                                continue
                            summary = clean_title(
                                first_text(payload.get("content")))
                            if not summary:
                                continue
                            when = (parse_iso_local(rec.get("timestamp")) or
                                    parse_iso_local(payload.get("timestamp")) or
                                    session_time)
                            if not when or not (start_dt <= when <= end_dt):
                                continue
                            project_id = (os.path.realpath(cwd) if cwd else
                                          "codex:%s" % os.path.basename(rf))
                            project_name = base_project(cwd) or "codex"
                            key = (project_id, when.date(), summary)
                            if key in session_seen:
                                continue
                            session_seen.add(key)
                            session_entries.append(SessionEntry(
                                "Codex", project_id, project_name,
                                when.date(), summary))
                            if len(session_entries) >= \
                                    MAX_SUMMARIES_PER_SESSION:
                                break
                except OSError as exc:
                    warnings.append("无法读取 Codex 文件 %s：%s" %
                                    (rf, exc))
                    continue
                entries.extend(session_entries)
        d += datetime.timedelta(days=1)
    return deduplicate_sessions(entries), warnings


# ---------- Gemini ----------

def parse_json_lines(raw, path):
    """解析 JSONL；坏行只产生警告，不影响其余记录。"""
    records = []
    warnings = []
    for line_number, line in enumerate(raw.splitlines(), start=1):
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            warnings.append("Gemini 文件 %s 第 %d 行不是有效 JSON" %
                            (path, line_number))
    return records, warnings


def load_gemini_records(path):
    """读取 Gemini JSON/JSONL，并返回 (records, warnings)。"""
    path = pathlib.Path(path)
    try:
        raw = path.read_text(encoding="utf-8").strip()
    except OSError as exc:
        return [], ["无法读取 Gemini 文件 %s：%s" % (path, exc)]
    if not raw:
        return [], []
    if path.suffix == ".jsonl":
        return parse_json_lines(raw, path)
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return parse_json_lines(raw, path)
    if isinstance(data, list):
        return data, []
    if isinstance(data, dict):
        records = data.get("messages") or data.get("history") or [data]
        if isinstance(records, list):
            return records, []
        return [], ["Gemini 文件 %s 的消息列表结构不受支持" % path]
    return [], ["Gemini 文件 %s 的根结构不受支持" % path]


def gemini_entries_from_records(records, fallback_date, fallback_project):
    """将多形态 Gemini 消息转换为安全的会话条目。"""
    entries = []
    warnings = []
    seen = set()
    for rec in records:
        if not isinstance(rec, dict):
            warnings.append("Gemini 消息结构不是对象，已跳过")
            continue
        raw_message = rec.get("message", rec)
        if not isinstance(raw_message, dict):
            warnings.append("Gemini 消息结构不受支持，已跳过")
            continue
        role = raw_message.get("role") or rec.get("role")
        if role != "user":
            continue
        content = raw_message.get("content") or rec.get("content")
        summary = clean_title(first_text(content))
        if not summary:
            continue
        cwd = None
        for obj in (rec, raw_message):
            for key in ("cwd", "projectPath", "workingDirectory",
                        "project_path"):
                value = obj.get(key)
                if isinstance(value, str) and value:
                    cwd = cwd or value
        when = None
        for obj in (rec, raw_message):
            for key in ("timestamp", "createTime", "createdAt", "ts"):
                when = parse_ts_any(obj.get(key))
                if when:
                    break
            if when:
                break
        activity_date = when.date() if when else fallback_date
        if activity_date is None:
            warnings.append("Gemini 用户消息缺少可用时间，已跳过")
            continue
        if when is None:
            warnings.append(
                "Gemini 用户消息缺少时间，使用文件修改日期 %s" %
                activity_date.isoformat())
        project_id = os.path.realpath(cwd) if cwd else fallback_project
        project_name = base_project(cwd) or fallback_project
        key = (project_id, activity_date, summary)
        if key in seen:
            continue
        seen.add(key)
        entries.append(SessionEntry(
            "Gemini", project_id, project_name, activity_date, summary))
        if len(entries) >= MAX_SUMMARIES_PER_SESSION:
            break
    return deduplicate_sessions(entries), warnings


def collect_gemini(start_dt, end_dt):
    """采集 Gemini 用户消息，返回 (entries, warnings)。"""
    entries = []
    warnings = []
    if not os.path.isdir(GEMINI_TMP_DIR):
        return [], ["Gemini 会话目录不可用：%s" % GEMINI_TMP_DIR]
    for chat_file in glob.glob(os.path.join(GEMINI_TMP_DIR, "*", "chats", "session-*.json*")):
        hash_name = os.path.basename(os.path.dirname(os.path.dirname(chat_file)))
        try:
            mtime_date = datetime.datetime.fromtimestamp(os.path.getmtime(chat_file)).date()
        except OSError as exc:
            mtime_date = None
            warnings.append("无法读取 Gemini 文件时间 %s：%s" %
                            (chat_file, exc))
        records, file_warnings = load_gemini_records(chat_file)
        warnings.extend(file_warnings)
        if not records:
            continue
        file_entries, entry_warnings = gemini_entries_from_records(
            records, fallback_date=mtime_date,
            fallback_project="gemini-" + hash_name[:8])
        warnings.extend(entry_warnings)
        entries.extend(
            entry for entry in file_entries
            if start_dt.date() <= entry.date <= end_dt.date())
    return deduplicate_sessions(entries), warnings


def collect_all_sessions(start_dt, end_dt):
    """采集全部本地 AI 数据源，单源失败不影响其他来源。"""
    entries = []
    warnings = []
    for collector in (collect_cc, collect_codex, collect_gemini):
        source_entries, source_warnings = collector(start_dt, end_dt)
        entries.extend(source_entries)
        warnings.extend(source_warnings)
    return deduplicate_sessions(entries), warnings


# ---------- Git ----------

def build_find_command(root):
    """构建只读仓库扫描命令，同时支持 .git 目录与文件。"""
    root = os.path.realpath(os.fspath(root))
    prune_names = ("node_modules", "Pods", "__pycache__")
    prune_paths = (
        os.path.join(root, "Library"),
        os.path.join(root, ".Trash"),
        os.path.join(root, "Flutter", "flutter"),
        os.path.join(root, ".claude", "plugins"),
        os.path.join(root, ".codex", "plugins"),
        os.path.join(root, ".codex", ".tmp"),
    )
    command = ["find", root, "("]
    for index, name in enumerate(prune_names):
        if index:
            command.append("-o")
        command.extend(["-name", name])
    for path in prune_paths:
        command.extend(["-o", "-path", path])
    command.extend([")", "-prune", "-o", "-name", ".git",
                    "-print", "-prune"])
    return command


def unique_existing_roots(roots):
    """规范化扫描根目录并返回 (roots, warnings)。"""
    result = []
    warnings = []
    seen = set()
    for root in roots:
        path = os.path.realpath(os.path.expanduser(os.fspath(root)))
        if path in seen:
            continue
        seen.add(path)
        if not os.path.isdir(path):
            warnings.append("仓库扫描目录不存在：%s" % path)
            continue
        result.append(path)
    return result, warnings


def discover_repos(roots=None, runner=subprocess.run, timeout=180):
    """每次重新扫描仓库，返回 (repos, warnings)，不写持久化文件。"""
    roots, warnings = unique_existing_roots(roots or [HOME])
    repos = set()
    for root in roots:
        command = build_find_command(root)
        try:
            completed = runner(
                command, capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            warnings.append("仓库扫描超时：%s" % root)
            continue
        except OSError as exc:
            warnings.append("仓库扫描失败：%s：%s" % (root, exc))
            continue
        if completed.returncode != 0:
            detail = completed.stderr.strip() or "未知错误"
            warnings.append("仓库扫描失败：%s：%s" % (root, detail))
        for marker in completed.stdout.splitlines():
            marker = marker.strip()
            if marker:
                repos.add(os.path.realpath(os.path.dirname(marker)))
    return sorted(repos), warnings


def _run_git_config(repo, key, runner):
    try:
        completed = runner(
            ["git", "-C", repo, "config", "--get", key],
            capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return completed.stdout.strip() if completed.returncode == 0 else ""


def read_repo_identity(repo, runner=subprocess.run):
    """逐仓库读取作者身份；邮箱优先，名称作为降级。"""
    email = _run_git_config(repo, "user.email", runner)
    name = _run_git_config(repo, "user.name", runner)
    if not email and not name:
        return None, "仓库 %s 未配置 Git 身份，已跳过" % repo
    return GitIdentity(email=email, name=name), None


def parse_git_lines(raw, repo, warnings):
    """解析以单元分隔符输出的 git log 行。"""
    parsed = []
    for line_number, line in enumerate(raw.splitlines(), start=1):
        parts = line.split("\x1f", 3)
        if len(parts) != 4:
            warnings.append("仓库 %s 的第 %d 条 Git 记录格式异常" %
                            (repo, line_number))
            continue
        date_text, author_name, author_email, subject = parts
        try:
            commit_date = datetime.datetime.strptime(
                date_text, "%Y-%m-%d").date()
        except ValueError:
            warnings.append("仓库 %s 的提交日期无效：%s" %
                            (repo, date_text))
            continue
        parsed.append((commit_date, author_name, author_email,
                       subject.strip()))
    return parsed


def collect_git(repos, start_date, end_date, runner=subprocess.run):
    """按各仓库自身 Git 身份采集提交，返回 (entries, warnings)。"""
    entries = []
    warnings = []
    since = start_date.strftime("%Y-%m-%d") + " 00:00:00"
    until = end_date.strftime("%Y-%m-%d") + " 23:59:59"
    for repo in repos:
        identity, warning = read_repo_identity(repo, runner)
        if warning:
            warnings.append(warning)
            continue
        command = [
            "git", "-C", repo, "log",
            "--all",
            "--since=%s" % since,
            "--until=%s" % until,
            "--date=format:%Y-%m-%d",
            "--pretty=format:%cd%x1f%an%x1f%ae%x1f%s",
            "--no-merges",
        ]
        try:
            completed = runner(
                command, capture_output=True, text=True, timeout=20)
        except subprocess.TimeoutExpired:
            warnings.append("仓库 %s 的 Git 查询超时" % repo)
            continue
        except OSError as exc:
            warnings.append("仓库 %s 的 Git 查询失败：%s" % (repo, exc))
            continue
        if completed.returncode != 0:
            detail = completed.stderr.strip() or "未知错误"
            warnings.append("仓库 %s 的 Git 查询失败：%s" %
                            (repo, detail))
            continue
        repo_id = os.path.realpath(repo)
        repo_name = os.path.basename(repo_id)
        for commit_date, author_name, author_email, subject in \
                parse_git_lines(completed.stdout, repo, warnings):
            if identity.matches(author_name, author_email):
                entries.append(CommitEntry(
                    repo_id, repo_name, commit_date, subject))
    return sorted(
        entries,
        key=lambda item: (item.repo_id, item.date, item.subject)), warnings


# ---------- 输出 ----------

def disambiguated_labels(entries, id_attr, name_attr):
    """名称冲突时追加父目录；仍冲突时使用完整内部标识。"""
    name_ids = {}
    for entry in entries:
        name = getattr(entry, name_attr)
        name_ids.setdefault(name, set()).add(getattr(entry, id_attr))
    labels = {}
    used = set()
    for entry in entries:
        item_id = getattr(entry, id_attr)
        if item_id in labels:
            continue
        name = getattr(entry, name_attr)
        label = name
        if len(name_ids[name]) > 1:
            if os.path.isabs(item_id):
                parent = os.path.basename(os.path.dirname(item_id))
                label = os.path.join(parent, name) if parent else item_id
            else:
                label = "%s — %s" % (name, item_id)
        if label in used:
            label = item_id
        labels[item_id] = label
        used.add(label)
    return labels


def render_material(start_date, end_date, sessions, commits, warnings):
    """将采集结果渲染为供技能归纳的 Markdown 素材。"""
    sessions = deduplicate_sessions(sessions)
    commits = sorted(
        commits,
        key=lambda item: (item.repo_id, item.date, item.subject))
    lines = [
        "# 工作素材  %s ~ %s" % (
            start_date.strftime("%m.%d"), end_date.strftime("%m.%d")),
        "",
    ]
    if not sessions and not commits:
        lines.extend(["> 区间内未采集到可确认的工作记录。", ""])

    lines.extend(["## A. AI 会话记录", ""])
    if not sessions:
        lines.extend(["_区间内无 AI 会话记录_", ""])
    else:
        labels = disambiguated_labels(
            sessions, "project_id", "project_name")
        grouped = {}
        for entry in sessions:
            grouped.setdefault(entry.project_id, []).append(entry)
        for project_id in sorted(grouped, key=lambda key: labels[key]):
            lines.append("### %s" % labels[project_id])
            lines.append("")
            for entry in sorted(
                    grouped[project_id],
                    key=lambda item: (item.date, item.source, item.summary)):
                lines.append("- %s [%s] %s" % (
                    entry.date.strftime("%m.%d"),
                    entry.source,
                    entry.summary,
                ))
            lines.append("")

    lines.extend(["## B. Git 提交记录", ""])
    if not commits:
        lines.extend(["_区间内无本人 Git 提交_", ""])
    else:
        labels = disambiguated_labels(commits, "repo_id", "repo_name")
        grouped = {}
        for entry in commits:
            grouped.setdefault(entry.repo_id, []).append(entry)
        for repo_id in sorted(grouped, key=lambda key: labels[key]):
            lines.append("### %s" % labels[repo_id])
            lines.append("")
            for entry in sorted(
                    grouped[repo_id],
                    key=lambda item: (item.date, item.subject)):
                lines.append("- %s %s" % (
                    entry.date.strftime("%m.%d"), entry.subject))
            lines.append("")

    session_labels = disambiguated_labels(
        sessions, "project_id", "project_name") if sessions else {}
    commit_labels = disambiguated_labels(
        commits, "repo_id", "repo_name") if commits else {}
    projects = sorted(set(session_labels.values()) | set(commit_labels.values()))
    lines.extend(["## C. 出现过活动的项目", ""])
    lines.extend([", ".join(projects) if projects else "_无_", ""])

    unique_warnings = list(dict.fromkeys(item for item in warnings if item))
    if unique_warnings:
        lines.extend([
            "## D. 采集提示",
            "",
            "> 以下问题表明采集结果可能不完整。",
            "",
        ])
        lines.extend("- %s" % item for item in unique_warnings)
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


# ---------- 主流程 ----------

def build_parser():
    ap = argparse.ArgumentParser(
        description="只读采集本机 AI 编码会话与本人 Git 提交")
    ap.add_argument("--start", help="开始日（含），格式 YYYY-MM-DD；默认本周周一")
    ap.add_argument("--end", help="结束日（含），格式 YYYY-MM-DD；默认今天")
    ap.add_argument(
        "--repo-root", action="append", default=[], metavar="PATH",
        help="补充仓库扫描根目录；可重复传入，默认始终扫描用户主目录")
    return ap


def main(argv=None, stdout=None, stderr=None):
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    args = build_parser().parse_args(argv)

    tz = local_tz()
    try:
        start_date, end_date = resolve_date_range(args.start, args.end)
    except ValueError as exc:
        print("错误：%s" % exc, file=stderr)
        return 2
    start_dt = datetime.datetime.combine(start_date, datetime.time.min).replace(tzinfo=tz)
    end_dt = datetime.datetime.combine(end_date, datetime.time.max).replace(tzinfo=tz)

    sessions, session_warnings = collect_all_sessions(start_dt, end_dt)
    repos, repo_warnings = discover_repos([HOME, *args.repo_root])
    commits, git_warnings = collect_git(repos, start_date, end_date)
    material = render_material(
        start_date,
        end_date,
        sessions,
        commits,
        [*session_warnings, *repo_warnings, *git_warnings],
    )
    print(material, file=stdout, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
