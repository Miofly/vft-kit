# 改写 .docx 完整指南

## docx 比 xlsx 宽容,但有三个坑

docx 用 python-docx 处理相对安全（图片一般能保留），但改文字有三个必踩的坑：

### 坑1：不要改 `cell.text` / `paragraph.text`

`cell.text = "新值"` 会**删掉该单元格所有 run 并新建一个无格式的 run**,字体、字号、颜色、加粗全丢。
正解：改 **run 的 text**（`run.text = ...`），run 携带格式,只换文字不动格式。

### 坑2：一句话被拆成多个 run

Word 常把一句话按输入历史/格式边界拆成多个 run：
```
"视频彩铃H5重构架构设计评审"  →  runs = ['视频彩铃', 'H5', '重构架构', '设计评审']
```
所以**逐个 run 做子串替换会匹配不到**（"视频彩铃重构"跨了两个 run）。
正解：把段落所有 run 的 text **拼接成完整字符串**,做子串替换,再把结果**写回第一个 run、清空其余 run**。`docx_swap.py` 的 `replace_in_para` 就是这么做的。

### 坑3：合并单元格陷阱（最隐蔽）

`table.rows[i].cells` 对**合并单元格**会返回多个指向**同一个 `<w:tc>` 元素**的 cell 对象。
一个常见但**错误**的写法是用 `id(cell._tc)` 去重避免重复处理：
```python
seen = set()
for cell in row.cells:
    if id(cell._tc) in seen: continue   # ❌ 会误杀
    seen.add(id(cell._tc))
```
问题：垂直合并时,被合并的下方 cell 会返回**上方 cell 的 `_tc`**,导致某些**内容不同的正常单元格**的 `_tc` 恰好等于前面处理过的,被 `continue` 跳过 → **漏改**。这个 bug 表现为"大部分改了、个别没改",且**同样的去重逻辑会让你的残留检测假阴性**（漏检的格子也搜不到）。

正解：**别走 `row.cells`,直接遍历 body 里所有 `<w:tc>` / `<w:p>` XML 元素**：
```python
from docx.oxml.ns import qn
from docx.text.paragraph import Paragraph
for tc in doc.element.body.iter(qn('w:tc')):
    for p_el in tc.iter(qn('w:p')):
        replace_in_para(Paragraph(p_el, None), rules)
```
每个物理 `<w:tc>` 在 XML 里只出现一次,天然无重复,不需要去重,也就不会误杀。`docx_swap.py` 已封装。

## 完整流程

```bash
eval "$(bash scripts/setup-env.sh)"
# 先 dump 看结构(用 python-docx 打印段落 + 表格单元格文字)
# 写规则 JSON: [["旧文本","新文本"], ...] 按顺序子串替换
$OFFICE_PY scripts/docx_swap.py in.docx out.docx rules.json
```

规则用**子串替换**,所以从长到短排列避免嵌套误替换（先替换长的完整句,再替换短的词）。

## 校验

零残留检测**必须走 XML 层遍历**（同坑3原因,别用 row.cells）：
```python
from docx.oxml.ns import qn
full = ""
for p in doc.paragraphs: full += p.text + "\n"
for tc in doc.element.body.iter(qn('w:tc')):
    for p in tc.iter(qn('w:p')):
        full += "".join(n.text or '' for n in p.iter(qn('w:t'))) + "\n"
# 然后 grep 旧业务词
```
