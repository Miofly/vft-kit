#!/usr/bin/env python3
"""离线检查学术证据记录关系；不验证来源真实性、正文或学术质量。

用法：python3 -I <绝对脚本路径> <绝对记录路径>。
只读输入，stdout 输出 JSON；退出 0=通过，1=记录阻断，2=输入错误。
"""
import argparse
import json
import re
from pathlib import Path


def validate(data):
    """严格检查输入类型后检查证据关系，避免漏字段或字符串布尔值绕过。"""
    def require(condition, message):
        if not condition:
            raise ValueError(message)

    def text(obj, key, where):
        require(isinstance(obj.get(key), str) and bool(obj[key].strip()),
                f"{where}.{key} 必须是非空字符串")

    def choice(obj, key, values, where):
        require(isinstance(obj.get(key), str) and obj[key] in values,
                f"{where}.{key} 必须属于 {sorted(values)}")

    require(isinstance(data, dict), "顶层必须是 JSON 对象")
    text(data, "title", "记录")
    choice(data, "stage", {"draft", "final"}, "记录")
    for group in ("sources", "claims", "requirements", "review"):
        require(isinstance(data.get(group), list), f"{group} 必须显式为数组")
        for i, obj in enumerate(data[group]):
            where = f"{group}[{i}]"
            require(isinstance(obj, dict), f"{where} 必须是对象")
            text(obj, "id", where)
            if group == "sources":
                for key in ("title", "location"):
                    text(obj, key, where)
                choice(obj, "kind", {"literature", "policy", "data"}, where)
                choice(obj, "read_state", {"record", "abstract", "fulltext"}, where)
                require(type(obj.get("verified")) is bool,
                        f"{where}.verified 必须是布尔值")
                if "doi" in obj:
                    text(obj, "doi", where)
                    require(bool(re.fullmatch(r"10\.\d{4,9}/\S+", normalize_doi(obj["doi"]))),
                            f"{where}.doi 格式无效（不等于联网核验）")
            elif group == "claims":
                text(obj, "text", where)
                choice(obj, "kind", {"literature", "observation", "proposal"}, where)
                choice(obj, "status", {"supported", "pending"}, where)
                require(isinstance(obj.get("evidence"), list), f"{where}.evidence 必须是数组")
                for j, evidence in enumerate(obj["evidence"]):
                    pos = f"{where}.evidence[{j}]"
                    require(isinstance(evidence, dict), f"{pos} 必须是对象")
                    text(evidence, "source_id", pos)
                    text(evidence, "locator", pos)
            else:
                text(obj, "text" if group == "requirements" else "issue", where)
                choice(obj, "status", {"done", "pending"} if group == "requirements"
                       else {"open", "resolved"}, where)

    errors, warnings = [], []

    def unfinished(message):
        (errors if data["stage"] == "final" else warnings).append(message)

    for group in ("sources", "claims", "requirements", "review"):
        ids = [obj["id"].strip() for obj in data[group]]
        if len(ids) != len(set(ids)):
            errors.append(f"{group} 存在重复 ID")
    sources = {s["id"].strip(): s for s in data["sources"]}
    dois = set()
    for s in data["sources"]:
        if "doi" in s:
            doi = normalize_doi(s["doi"])
            if doi in dois:
                errors.append(f"重复 DOI：{doi}")
            dois.add(doi)
        if not s["verified"] or s["read_state"] != "fulltext":
            unfinished(f"来源 {s['id']} 未核验或未读完整材料")
    for c in data["claims"]:
        for e in c["evidence"]:
            if e["source_id"].strip() not in sources:
                errors.append(f"主张 {c['id']} 引用不存在的来源 {e['source_id']}")
        if c["status"] == "pending":
            unfinished(f"主张 {c['id']} 待核实")
        if c["status"] != "supported" or c["kind"] == "proposal":
            continue
        if not c["evidence"]:
            errors.append(f"主张 {c['id']} 标为 supported 但无证据")
        for e in c["evidence"]:
            source = sources.get(e["source_id"].strip())
            if source and not source["verified"]:
                errors.append(f"主张 {c['id']} 依赖未核验来源 {source['id']}")
        if c["kind"] == "observation":
            linked = [sources.get(e["source_id"].strip()) for e in c["evidence"]]
            if not any(s and s["kind"] == "data" and s["verified"]
                       and s["read_state"] == "fulltext" for s in linked):
                errors.append(f"观察主张 {c['id']} 缺少已核验且已读的原始数据来源")
    for r in data["requirements"]:
        if r["status"] != "done":
            unfinished(f"要求 {r['id']} 未完成")
    for r in data["review"]:
        if r["status"] == "open":
            unfinished(f"评审 {r['id']} 未关闭")
    if not data["claims"]:
        unfinished("没有主张记录")
    if data["stage"] == "final":
        if not any(c["kind"] != "proposal" for c in data["claims"]):
            errors.append("final 不能只有设计建议，须记录论证依据")
        if not data["requirements"]:
            errors.append("final 缺少适用要求记录")
        if not data["review"]:
            errors.append("final 缺少实际复核记录")
    return {"ok": not errors, "stage": data["stage"], "errors": errors,
            "warnings": warnings, "scope": "仅核对记录关系与状态，不证明学术真实性"}


def normalize_doi(value):
    return re.sub(r"^(?:https?://(?:dx\.)?doi\.org/|doi:\s*)", "",
                  value.strip(), flags=re.I).lower()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ledger", type=Path, help="证据记录 JSON 的绝对路径")
    args = parser.parse_args()
    try:
        if not args.ledger.is_absolute():
            raise ValueError("记录路径必须是绝对路径")
        result = validate(json.loads(args.ledger.read_text(encoding="utf-8")))
    except (OSError, UnicodeError, ValueError) as exc:
        print(json.dumps({"ok": False, "input_error": str(exc)}, ensure_ascii=False))
        return 2
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
