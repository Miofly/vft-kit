# -*- coding: utf-8 -*-
"""
改 docx 文字内容,保留格式。核心避坑:
1. 不用 cell.text=（会清格式）;改 run.text。
2. 一句话常被拆成多个 run,先拼接整段再子串替换,回写第一个 run、清空其余。
3. 合并单元格陷阱: row.cells 对合并单元格返回共享 _tc,用 id 去重会误杀正常格→漏改。
   正解: 直接遍历 body 里所有 <w:p>(段落 + 表格单元格里的段落都覆盖到),不走 row.cells。
用法:
  $OFFICE_PY docx_swap.py <in.docx> <out.docx> <rules.json>
rules.json: [["旧文本","新文本"], ["视频彩铃重构","爱皮宇宙平台"], ...]  (按顺序子串替换)
"""
import sys, json
import docx
from docx.oxml.ns import qn
from docx.text.paragraph import Paragraph

def replace_in_para(para, rules):
    full = "".join(r.text for r in para.runs)
    new = full
    for a, b in rules:
        new = new.replace(a, b)
    if new == full or not para.runs:
        return False
    para.runs[0].text = new
    for r in para.runs[1:]:
        r.text = ""
    return True

def main():
    in_d, out_d, rules_f = sys.argv[1], sys.argv[2], sys.argv[3]
    rules = json.load(open(rules_f, encoding='utf-8'))
    d = docx.Document(in_d)
    changed = 0

    # 顶层段落
    for p in d.paragraphs:
        if replace_in_para(p, rules):
            changed += 1
    # 所有表格单元格里的段落 —— 走 XML 层遍历,绕开合并单元格 id 去重陷阱
    for tc in d.element.body.iter(qn('w:tc')):
        for p_el in tc.iter(qn('w:p')):
            if replace_in_para(Paragraph(p_el, None), rules):
                changed += 1

    d.save(out_d)
    print(f"替换 {changed} 处,已存 {out_d}")

if __name__ == '__main__':
    main()
