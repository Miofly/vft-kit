# -*- coding: utf-8 -*-
"""
导出 xlsx 的共享字符串表(带索引)和各 sheet 的「单元格→si索引」映射,供规划改写映射用。
用法:
  $OFFICE_PY xlsx_dump.py <file.xlsx> [--strings-out list.txt] [--sheet <名称>]
不带 --sheet: 打印所有共享字符串 + 概览。
带 --sheet: 额外打印该 sheet 每个单元格引用的 si 索引(定位哪个格子要改)。
"""
import sys, re, zipfile, argparse
from xml.sax.saxutils import unescape

def dump_shared_strings(xml):
    sis = re.findall(r'<si>(.*?)</si>', xml, re.S)
    out = []
    for i, si in enumerate(sis):
        texts = re.findall(r'<t[^>]*>(.*?)</t>', si, re.S)
        joined = unescape(''.join(texts)).replace('_x000D_', '')
        is_rich = '<r>' in si
        out.append((i, is_rich, joined))
    return out

def sheet_cell_map(sheet_xml):
    """返回 [(cellRef, si_index_or_None, is_shared)]"""
    rows = re.findall(r'<c r="([A-Z]+\d+)"([^>]*)>(.*?)</c>', sheet_xml, re.S)
    res = []
    for ref, attr, inner in rows:
        shared = 't="s"' in attr
        v = re.search(r'<v>(\d+)</v>', inner)
        if shared and v:
            res.append((ref, int(v.group(1)), True))
        else:
            vv = re.search(r'<v>(.*?)</v>', inner)
            res.append((ref, vv.group(1) if vv else None, False))
    return res

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('xlsx')
    ap.add_argument('--strings-out')
    ap.add_argument('--sheet')
    args = ap.parse_args()

    z = zipfile.ZipFile(args.xlsx)
    ss = z.read('xl/sharedStrings.xml').decode('utf-8')
    strings = dump_shared_strings(ss)

    print(f"=== 共享字符串 {len(strings)} 条 (R=富文本多run) ===")
    lines = []
    for i, rich, txt in strings:
        flag = 'R' if rich else ' '
        line = f"[{i}]{flag}\t{txt}"
        lines.append(line)
        print(line[:120])
    if args.strings_out:
        open(args.strings_out, 'w', encoding='utf-8').write('\n'.join(lines))
        print(f"\n已写 {args.strings_out}")

    # sheet 名 → 文件映射
    wb = z.read('xl/workbook.xml').decode('utf-8')
    sheets = re.findall(r'<sheet name="([^"]+)"[^>]*r:id="(rId\d+)"', wb)
    rels = z.read('xl/_rels/workbook.xml.rels').decode('utf-8')
    rid2file = dict(re.findall(r'Id="(rId\d+)"[^>]*Target="(worksheets/[^"]+)"', rels))
    print(f"\n=== Sheet 列表 ===")
    for name, rid in sheets:
        print(f"  {name} -> xl/{rid2file.get(rid,'?')}")

    if args.sheet:
        target = None
        for name, rid in sheets:
            if name == args.sheet:
                target = 'xl/' + rid2file.get(rid, '')
        if target:
            sx = z.read(target).decode('utf-8')
            print(f"\n=== {args.sheet} 单元格→si ===")
            for ref, val, shared in sheet_cell_map(sx):
                tag = f"si[{val}]" if shared else f"数字/内联={val}"
                print(f"  {ref}: {tag}")

if __name__ == '__main__':
    main()
