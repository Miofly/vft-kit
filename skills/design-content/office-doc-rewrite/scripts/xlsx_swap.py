# -*- coding: utf-8 -*-
"""
按 {si索引: 新文本} 映射改写 xlsx 的 sharedStrings.xml,zip 层操作,保留图片/样式/sheet 全部不动。
富文本 si(带 <r><rPr>)保留首个 run 的 rPr,整体替换为单 run 新文本(视觉几乎无差)。
支持富文本双段: 映射值写成 ["加粗前缀","普通后缀"] 会渲染成 前缀加粗+后缀常规。

用法:
  $OFFICE_PY xlsx_swap.py <in.xlsx> <out.xlsx> <mapping.json> [--sheet-num-edits edits.json]

mapping.json:  {"1": "新标题", "23": "新正文", "12": ["1）关键词", "：说明文字"]}
sheet-num-edits.json (可选,改 sheet XML 里的数字/内联单元格,如版本号):
  {"xl/worksheets/sheet6.xml": [["<c r=\"E17\" s=\"71\"><v>2.7</v></c>", "<c r=\"E17\" s=\"71\"><v>3.5</v></c>"]]}
"""
import sys, re, json, zipfile, os
from xml.sax.saxutils import escape

def esc(s):
    return escape(s, {'"': '&quot;'})

def swap_shared_strings(xml, mapping):
    parts = re.split(r'(<si>.*?</si>)', xml, flags=re.S)
    si_positions = [i for i, p in enumerate(parts) if p.startswith('<si>')]
    changed = 0
    for si_idx, part_idx in enumerate(si_positions):
        key = str(si_idx)
        if key not in mapping:
            continue
        newval = mapping[key]
        orig = parts[part_idx]
        is_rich = '<r>' in orig
        if isinstance(newval, list) and len(newval) == 2:
            bold, normal = newval
            rpr_m = re.search(r'<r><rPr>(.*?)</rPr>', orig, re.S) or re.search(r'<rPr>(.*?)</rPr>', orig, re.S)
            rpr = rpr_m.group(1) if rpr_m else '<sz val="12"/><color rgb="FF333333"/><rFont val="等线"/><charset val="134"/><scheme val="minor"/>'
            rpr_bold = rpr if '<b/>' in rpr else '<b/>' + rpr
            parts[part_idx] = (
                f'<si><r><rPr>{rpr_bold}</rPr><t xml:space="preserve">{esc(bold)}</t></r>'
                f'<r><rPr>{rpr}</rPr><t xml:space="preserve">{esc(normal)}</t></r></si>'
            )
        elif is_rich:
            rpr_m = re.search(r'<rPr>(.*?)</rPr>', orig, re.S)
            rpr_xml = f'<rPr>{rpr_m.group(1)}</rPr>' if rpr_m else ''
            parts[part_idx] = f'<si><r>{rpr_xml}<t xml:space="preserve">{esc(newval)}</t></r></si>'
        else:
            parts[part_idx] = f'<si><t xml:space="preserve">{esc(newval)}</t></si>'
        changed += 1
    return ''.join(parts), changed

def main():
    in_x, out_x, map_f = sys.argv[1], sys.argv[2], sys.argv[3]
    mapping = json.load(open(map_f, encoding='utf-8'))
    num_edits = {}
    if '--sheet-num-edits' in sys.argv:
        num_edits = json.load(open(sys.argv[sys.argv.index('--sheet-num-edits') + 1], encoding='utf-8'))

    z = zipfile.ZipFile(in_x)
    names = z.namelist()
    files = {n: z.read(n) for n in names}

    ss = files['xl/sharedStrings.xml'].decode('utf-8')
    ss2, changed = swap_shared_strings(ss, mapping)
    files['xl/sharedStrings.xml'] = ss2.encode('utf-8')
    print(f"sharedStrings 改了 {changed} 条")

    for path, pairs in num_edits.items():
        s = files[path].decode('utf-8')
        for old, new in pairs:
            if old in s:
                s = s.replace(old, new); print(f"{path}: 替换数字单元格 ✓")
            else:
                print(f"{path}: 未匹配 {old[:40]} ⚠")
        files[path] = s.encode('utf-8')

    if os.path.exists(out_x):
        os.remove(out_x)
    with zipfile.ZipFile(out_x, 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in names:  # 保持原顺序
            zo.writestr(n, files[n])
    print(f"已生成 {out_x}")

if __name__ == '__main__':
    main()
