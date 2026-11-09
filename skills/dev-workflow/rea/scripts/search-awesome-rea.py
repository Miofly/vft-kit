#!/usr/bin/env python3
"""search-awesome-rea.py — awesome-rea 上游离线检索 CLI（仅标准库）。

数据源为本地上游 JSON（rea-resources.json / tool-resources.json / papers.json /
evidence-classes.json），不联网、不建索引/缓存。证据档位（evidence_class）与
runtime_status 均直接取自 evidence-classes.json 的上游核验记录，不代表本次实测；
C0/not-run 等档位不会被改写为「已验证运行时」。

用法示例:
  python3 search-awesome-rea.py --skill-dir /abs/.../rea \\
      --query ghidra --target binary --limit 3 --json
"""
import argparse
import json
import os
import sys

RESULT_LISTS = ("rea-resources.json", "tool-resources.json", "papers.json")
EVIDENCE_FILE = "evidence-classes.json"
ALL_TARGETS = ("website", "game", "app", "binary", "firmware", "protocol")
DISCLAIMER = ("evidence_class/runtime_status 来自上游 evidence-classes.json 的核验记录，"
              "不是本次实测；C0 与 not-run 不构成运行时验证。")


def _die(msg):
    print("error: " + msg, file=sys.stderr)
    sys.exit(1)


def _abs_dir(p, opt):
    if not os.path.isabs(p):
        _die(f"{opt} 必须是绝对路径，收到: {p}")
    return p


def _load_json(path, label):
    if not os.path.isfile(path):
        _die(f"缺少 {label} 文件: {path}")
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        _die(f"{label} 读取失败({path}): {e}")


def load_data(data_dir):
    """返回 (合并后的条目列表, evidence 映射 id->entry)。"""
    data_dir = _abs_dir(data_dir, "--data-dir")
    items = []
    seen = {}
    for name in RESULT_LISTS:
        raw = _load_json(os.path.join(data_dir, name), name)
        if not isinstance(raw, list):
            _die(f"{name} 应为 JSON list，实际为 {type(raw).__name__}")
        for it in raw:
            if not isinstance(it, dict) or not isinstance(it.get("id"), str) or not it["id"]:
                _die(f"{name} 存在缺字符串 id 或非对象的条目")
            iid = it["id"]
            if iid in seen:
                _die(f"检测到重复 id: {iid}（{seen[iid]} 与 {name}）")
            seen[iid] = name
            items.append({**it, "_source_file": name})
    ev_raw = _load_json(os.path.join(data_dir, EVIDENCE_FILE), EVIDENCE_FILE)
    if not isinstance(ev_raw, dict) or not isinstance(ev_raw.get("entries"), list):
        _die(f"{EVIDENCE_FILE} 应为含 entries list 的 JSON object")
    evidence = {}
    for entry in ev_raw["entries"]:
        if not isinstance(entry, dict) or not isinstance(entry.get("id"), str) or not entry["id"]:
            _die(f"{EVIDENCE_FILE} 存在缺字符串 id 或非对象的条目")
        if entry["id"] in evidence:
            _die(f"{EVIDENCE_FILE} 检测到重复证据 id: {entry['id']}")
        level = entry.get("evidence_class")
        if level is not None and (type(level) is not int or level not in range(4)):
            _die(f"{EVIDENCE_FILE} 非法 evidence_class: {entry['id']}")
        evidence[entry["id"]] = entry
    return items, evidence


def _haystack(it):
    """查询字段：名称/标题 + 中英文 description；paper 附加 title_zh/scope_limitations/why_fits。"""
    parts = [it.get("name") or it.get("title") or "",
             it.get("title_zh") or "",
             it.get("description_en") or "",
             it.get("description_zh") or "",
             it.get("scope_limitations_en") or "",
             it.get("scope_limitations_zh") or "",
             it.get("why_fits_en") or "",
             it.get("why_fits_zh") or ""]
    return "\n".join(str(p).lower() for p in parts)


def _title_key(it):
    return str(it.get("name") or it.get("title") or "").lower()


def _limit_type(v):
    try:
        n = int(v)
    except ValueError:
        raise argparse.ArgumentTypeError("--limit 必须是正整数")
    if n <= 0:
        raise argparse.ArgumentTypeError("--limit 必须是正整数")
    return n


def build_parser():
    p = argparse.ArgumentParser(
        description="awesome-rea 上游资源离线检索（纯标准库，只读本地 JSON）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=DISCLAIMER,
    )
    p.add_argument("--skill-dir", required=True,
                   help="rea skill 目录绝对路径（默认取 <skill-dir>/references/awesome-rea/upstream/data）")
    p.add_argument("--data-dir", default=None,
                   help="数据目录绝对路径，覆盖默认（用于上游文件未同步到 skill 内时）")
    p.add_argument("--query", default=None,
                   help="检索词，空格分多 term，全部命中才算匹配（大小写不敏感）")
    p.add_argument("--target", default=None, choices=ALL_TARGETS,
                   help="按 targets 领域过滤")
    p.add_argument("--kind", default=None,
                   help="按 kind 完全值过滤（如 tool/project/case-study/research，区分大小写不敏感）")
    p.add_argument("--limit", type=_limit_type, default=10,
                   help="最多返回条数，正整数，默认 10")
    p.add_argument("--json", action="store_true", dest="as_json",
                   help="输出结构化 JSON 而非简明文本")
    return p


def search(items, evidence, query, target, kind, limit):
    terms = [t for t in (query or "").split() if t]
    q = terms[0].lower() if terms else None
    res = []
    for idx, it in enumerate(items):
        targets = it.get("targets") or []
        k = (it.get("kind") or "")
        if target and target not in targets:
            continue
        if kind and kind.lower() != k.lower():
            continue
        if q:
            hay = _haystack(it)
            if any(t.lower() not in hay for t in terms):
                continue
        ev = evidence.get(it["id"])
        title_hits = 0
        if q:
            title = _title_key(it)
            title_hits = sum(1 for t in terms if t.lower() in title)
        # 关联证据档位：字段直取上游，绝不据 evidence_class 改写 runtime_status
        res.append((title_hits, idx, {
            "id": it["id"],
            "name": it.get("name") or it.get("title"),
            "url": it.get("url"),
            "kind": k or None,
            "targets": targets,
            "relationship": it.get("relationship"),
            "verification": it.get("verification"),
            "evidence_class": (f"C{ev['evidence_class']}"
                               if ev and ev.get("evidence_class") is not None else None),
            "runtime_status": ev.get("runtime_status") if ev else None,
            "scope": ev.get("scope") if ev else None,
            "evidence_status": ev.get("evidence_status") if ev else None,
            "source_file": it.get("_source_file"),
            "verified_at": it.get("verified_at"),
            "requirements": it.get("requirements"),
            "limitations": it.get("scope_limitations_zh") or it.get("scope_limitations_en"),
            "evidence_url": it.get("evidence_url"),
            "evidence_urls": it.get("evidence_urls"),
        }))
    # 稳定排序：有 query 时标题命中优先，其余保持源文件出现顺序
    res.sort(key=lambda r: (0 if q else 1, -r[0], r[1]))
    total = len(res)
    return {"total": total,
            "returned": min(total, limit),
            "truncated": total > limit,
            "results": [r[2] for r in res[:limit]]}


def render_text(out, args):
    head = f"matched {out['total']}, showing {out['returned']}" + ("（已按 limit 截断）" if out["truncated"] else "")
    print(head)
    print(DISCLAIMER)
    for r in out["results"]:
        ev = f"{r['evidence_class']}/{r['runtime_status']}" if r["evidence_class"] else "-"
        tg = ",".join(r["targets"] or [])
        print(f"\n[{ev}] {r['id']} — {r['name']}")
        print(f"  kind={r['kind']} targets={tg} relationship={r['relationship']} verification={r['verification']}")
        print(f"  url: {r['url']}")


def main(argv=None):
    args = build_parser().parse_args(argv)
    skill_dir = _abs_dir(args.skill_dir, "--skill-dir")
    if args.data_dir is not None:
        data_dir = _abs_dir(args.data_dir, "--data-dir")
    else:
        data_dir = os.path.join(skill_dir, "references", "awesome-rea", "upstream", "data")
    if not (args.query and args.query.strip()) and not args.target and not args.kind:
        _die("空请求：至少指定 --query / --target / --kind 之一")
    items, evidence = load_data(data_dir)
    out = search(items, evidence, args.query, args.target, args.kind, args.limit)
    if args.as_json:
        payload = dict(out)
        payload["data_dir"] = data_dir
        payload["note"] = DISCLAIMER
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        render_text(out, args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
