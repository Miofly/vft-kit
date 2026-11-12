#!/usr/bin/env python3
"""只读论文结构预检：Markdown/文本/DOCX 数字引用，TeX/BibTeX 引用与标签。

不编译、不联网、不执行宏、不提取压缩包；通过不代表内容真实或版式合规。
仅支持明确的数字编号或常见 cite 命令；不支持格式会报告未覆盖。
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys
import zipfile
from xml.etree import ElementTree as ET

# Only this trusted script directory is imported, never the manuscript directory.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from vendor.citation_integrity.bib_parser import parse_bib_entries_from_text, find_duplicate_key_groups
from vendor.citation_integrity.tex_parser import collect_citations_from_text
from vendor.citation_integrity.cross_reference_lint import lint_cross_references

MAX_BYTES = 20 * 1024 * 1024


def read_text(path):
    if path.stat().st_size > MAX_BYTES:
        raise ValueError(f"文件超过 20 MiB 限额：{path.name}")
    return path.read_text(encoding="utf-8-sig")


def read_docx(path):
    with zipfile.ZipFile(path) as z:
        names = [x.filename for x in z.infolist()]
        if len(names) != len(set(names)):
            raise ValueError("DOCX 含重复压缩成员")
        if sum(x.file_size for x in z.infolist()) > MAX_BYTES:
            raise ValueError("DOCX 全部成员展开后超过 20 MiB 限额")
        if z.testzip() is not None:
            raise ValueError("DOCX 压缩成员损坏")
        raw = z.read("word/document.xml")
        if b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
            raise ValueError("DOCX XML 不允许 DTD/实体声明")
        tree = ET.fromstring(raw)
        ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
        text = "\n".join("".join(p.itertext()) if not p.findall(".//w:t", ns)
                         else "".join(t.text or "" for t in p.findall(".//w:t", ns))
                         for p in tree.findall(".//w:p", ns))
        review = bool(tree.findall(".//w:ins", ns) or tree.findall(".//w:del", ns))
        return text, names, review


def strip_tex_comments(text):
    return "\n".join(re.split(r"(?<!\\)%", line, maxsplit=1)[0] for line in text.splitlines())


def check(manuscript, bibs=(), anonymous_terms=()):
    errors, warnings = [], []
    info = {"format": manuscript.suffix.lower(), "citation_check": "not_covered"}
    suffix = manuscript.suffix.lower()
    if suffix == ".docx":
        text, names, tracked = read_docx(manuscript)
        warnings.append("DOCX 仅检查主文档段落；未核对字体、页码、分页、脚注、页眉或外部文献域")
        if tracked or "word/comments.xml" in names:
            warnings.append("DOCX 含修订或批注，须人工确认交付版本")
    elif suffix in {".md", ".txt", ".tex"}:
        text = read_text(manuscript)
    else:
        raise ValueError("仅支持 .md/.txt/.docx/.tex；旧 .doc 先在副本上转换")
    if not text.strip():
        errors.append("主文档没有可读取正文")
    if re.search(r"TODO|\[待(?:核实|补充|填写|确认)[^\]]*\]|【待[^】]*】", text, re.I):
        warnings.append("正文存在待处理标记")
    for term in anonymous_terms:
        if not isinstance(term, str) or not term.strip():
            raise ValueError("匿名检查词不能为空")
        if term in text:
            errors.append(f"正文命中用户指定匿名标识：{term}")
    if suffix == ".tex":
        clean = strip_tex_comments(text)
        clean = re.sub(r"\\begin\{(?:verbatim|lstlisting|minted)\}[\s\S]*?\\end\{(?:verbatim|lstlisting|minted)\}", "", clean)
        if re.search(r"\\(?:input|include|subfile|includegraphics|bibliography|addbibresource)\b", clean):
            warnings.append("存在外部 TeX/图像/文献资源：仅检查显式输入文件，不递归读取或编译")
        citations = collect_citations_from_text(clean, str(manuscript))
        entries = []
        for bib in bibs:
            raw = read_text(bib)
            parsed = parse_bib_entries_from_text(raw, str(bib))
            if raw.strip() and not parsed:
                errors.append(f"BibTeX 未解析出条目：{bib.name}")
            entries.extend(e for e in parsed if e.entry_type not in {"comment", "string", "preamble"})
        if not bibs:
            warnings.append("未提供 --bib，未核对引文 key 与文后条目")
        else:
            info["citation_check"] = "common_tex_commands"
            keys = {e.key for e in entries}
            used = {c.key for c in citations}
            for key in sorted(used - keys):
                errors.append(f"引用缺少 BibTeX 条目：{key}")
            for key in sorted(keys - used):
                warnings.append(f"BibTeX 条目未被当前输入正文引用：{key}")
            for group in find_duplicate_key_groups(entries):
                errors.append(f"重复 BibTeX key：{group.key}")
            dois = []
            for e in entries:
                for field in ("title", "author", "year"):
                    if not e.fields.get(field):
                        warnings.append(f"BibTeX {e.key} 缺少 {field}，须按条目类型核对")
                if e.fields.get("doi"):
                    doi = re.sub(r"^(?:https?://(?:dx\.)?doi\.org/|doi:\s*)", "", e.fields["doi"].strip(), flags=re.I).lower()
                    dois.append(doi)
            for doi, n in Counter(dois).items():
                if n > 1:
                    errors.append(f"重复 BibTeX DOI：{doi}")
            info.update(citation_keys=len(used), bibliography_entries=len(entries))
        for issue in lint_cross_references({str(manuscript): clean}):
            (errors if issue.code == "CI-MISSING-LABEL" else warnings).append(issue.message)
        labels = re.findall(r"\\label\{([^}]+)\}", clean)
        for label, n in Counter(labels).items():
            if n > 1:
                errors.append(f"重复 LaTeX label：{label}")
        # shortcut: static regex coverage only; use the real toolchain for custom macros/BibTeX expressions.
        warnings.append("TeX/BibTeX 为常见语法静态预检，不执行自定义宏，不等于编译或引文语义核验")
    else:
        if bibs:
            raise ValueError("--bib 仅用于 .tex；数字参考文献从正文的参考文献节读取")
        clean = re.sub(r"(?ms)^\s*(```|~~~)[^\n]*\n.*?^\s*\1\s*$", "", text)
        if re.search(r"\[image_(?:\d+_)?\d+\]", clean):
            errors.append("存在未替换的图片占位符")
        if suffix == ".md":
            from urllib.parse import unquote
            for image in re.findall(r"!\[[^\]]*\]\(([^)]+)\)", clean):
                target = image.strip().split(' "', 1)[0].strip("<>")
                if re.match(r"(?:[a-z][a-z0-9+.-]*:|//)", target, re.I):
                    warnings.append("外部/内嵌图像未下载核验：" + target[:100])
                    continue
                candidate = (manuscript.parent / unquote(target.split("#", 1)[0])).resolve()
                if not candidate.is_file() or candidate.stat().st_size == 0:
                    errors.append("本地图像缺失或为空：" + target)
        heading = re.search(r"(?im)^\s*(?:#{1,6}\s*)?(?:参考文献|references)\s*[:：]?\s*$", clean)
        if not heading:
            warnings.append("未识别独立的参考文献标题，数字引文对应未覆盖")
        else:
            body, refs = clean[:heading.start()], clean[heading.end():]
            refs = re.split(r"(?im)^\s*(?:#{1,6}\s*)?(?:附录|致谢|appendix|acknowledg\w*)\b.*$", refs)[0]
            numbers = re.findall(r"(?m)^\s*\[(\d+)\]\s*\S", refs)
            available = {int(n) for n in numbers}
            used = set()
            for m in re.finditer(r"(?<!!)\[(\d+(?:\s*[-–,，]\s*\d+)*)\](?!\s*\(|\s*:|\s*\[[^\d\]])", body):
                for item in re.split(r"[,，]", m[1]):
                    ends = re.split(r"[-–]", item)
                    start, stop = int(ends[0]), int(ends[-1])
                    if start < 1 or stop < start or stop - start > 1000:
                        errors.append(f"非法引用编号或范围：{m[0]}")
                    else:
                        used.update(range(start, stop + 1))
            if not numbers:
                warnings.append("参考文献不是 [数字] 编号格式，引用对应未覆盖（含作者—年份格式）")
            else:
                info["citation_check"] = "numeric_brackets"
                for key in sorted(used - available):
                    errors.append(f"正文引用 [{key}] 无文后条目")
                for key in sorted(available - used):
                    warnings.append(f"文后条目 [{key}] 未识别到正文数字引用")
                for key, n in Counter(numbers).items():
                    if n > 1:
                        errors.append(f"重复参考文献编号：[{key}]")
                info.update(citation_keys=len(used), bibliography_entries=len(numbers))
        warnings.append("数字方括号可能包含非引文；仅作候选核对，不支持全部引用体例或自动域")
    if not anonymous_terms:
        warnings.append("未提供匿名标识词表，匿名要求未验证")
    return {"ok": not errors, "errors": errors, "warnings": warnings, **info,
            "scope": "只读结构预检，不证明来源真实、学术质量、编译或最终版式"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manuscript", type=Path)
    parser.add_argument("--bib", type=Path, action="append", default=[])
    parser.add_argument("--anonymous-term", action="append", default=[])
    args = parser.parse_args()
    try:
        for p in [args.manuscript, *args.bib]:
            if not p.is_absolute():
                raise ValueError("所有输入文件路径必须是绝对路径")
        result = check(args.manuscript, args.bib, args.anonymous_term)
    except (OSError, UnicodeError, ValueError, KeyError, zipfile.BadZipFile, ET.ParseError) as exc:
        print(json.dumps({"ok": False, "input_error": str(exc)}, ensure_ascii=False))
        return 2
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
