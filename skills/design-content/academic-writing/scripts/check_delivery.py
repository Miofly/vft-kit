#!/usr/bin/env python3
"""统一只读交付预检；通过仅指声明的检查层，不是学术批准或自动投稿。"""
import argparse
import json
from pathlib import Path
import sys
import zipfile
from xml.etree import ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_evidence import validate
from check_manuscript import check

LAYERS = ("evidence", "citations", "methods", "format", "rendering", "privacy")


def audit(manuscript, ledger, bibs=(), attestations=None):
    record = validate(json.loads(ledger.read_text(encoding="utf-8")))
    paper = check(manuscript, bibs)
    errors = ["证据记录：" + x for x in record["errors"]]
    errors += ["正文预检：" + x for x in paper["errors"]]
    warnings = record["warnings"] + paper["warnings"]
    layers = {}
    if attestations is not None:
        if not isinstance(attestations, dict) or set(attestations) != set(LAYERS):
            raise ValueError("人工复核记录须包含且仅包含六个检查层：" + ", ".join(LAYERS))
        for name in LAYERS:
            value = attestations[name]
            if (not isinstance(value, dict) or not isinstance(value.get("status"), str) or value.get("status") not in {"passed", "pending", "not_applicable"}
                    or not isinstance(value.get("evidence"), str) or not value["evidence"].strip()):
                raise ValueError(name + " 须有合法 status 和非空 evidence（实际核对定位或不适用依据）")
            layers[name] = value
    else:
        layers = {name: {"status": "pending", "evidence": "尚无实际复核记录"} for name in LAYERS}
    for name, item in layers.items():
        if item["status"] == "pending":
            (errors if record["stage"] == "final" else warnings).append("交付层未完成：" + name)
    return {"ok": not errors, "stage": record["stage"], "errors": errors, "warnings": warnings,
            "layers": layers, "record_check": record, "manuscript_check": paper,
            "scope": "只核对记录、正文静态结构和人工复核声明，不证明声明真实或替代作者批准"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manuscript", type=Path)
    parser.add_argument("ledger", type=Path)
    parser.add_argument("--bib", type=Path, action="append", default=[])
    parser.add_argument("--attestations", type=Path)
    args = parser.parse_args()
    try:
        for p in [args.manuscript, args.ledger, *args.bib, *([args.attestations] if args.attestations else [])]:
            if not p.is_absolute():
                raise ValueError("输入路径必须是绝对路径")
        attestations = json.loads(args.attestations.read_text(encoding="utf-8")) if args.attestations else None
        result = audit(args.manuscript, args.ledger, args.bib, attestations)
    except (OSError, UnicodeError, ValueError, KeyError, zipfile.BadZipFile, ET.ParseError) as exc:
        print(json.dumps({"ok": False, "input_error": str(exc)}, ensure_ascii=False))
        return 2
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
