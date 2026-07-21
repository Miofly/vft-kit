# 改写 .xlsx 完整指南

## 为什么不能用 openpyxl 整体重存

openpyxl 打开 xlsx 改完 `wb.save()` 会**丢弃它不完整支持的元素**——尤其是**嵌入图片、图表、部分条件格式**。一份带 7 张架构图的表,openpyxl 存完图全没了。所以：**openpyxl 只用来「读」和「校验」,改写一律走 zip 层**。

## xlsx 内部结构(先摸清)

xlsx 就是个 zip。解压看结构：
```bash
unzip -l file.xlsx
```
关键文件：
- `xl/sharedStrings.xml` — **共享字符串表**,几乎所有文字都在这。每个 `<si>` 是一个字符串,sheet 里用 `<v>N</v>` 引用第 N 个(0-based)。
- `xl/worksheets/sheetN.xml` — 每个工作表,单元格 `<c t="s"><v>5</v></c>` 表示"引用 sharedStrings 第5个"。
- `xl/media/imageN.png` — 图片。
- `xl/drawings/drawingN.xml` — 图片锚点(位置/大小)。
- `xl/workbook.xml` + `xl/_rels/workbook.xml.rels` — sheet 名 ↔ rId ↔ 文件 映射。

## 核心洞察：只改 sharedStrings 就够

先确认单元格文字类型统计：
```bash
for i in 1 2 3 ...; do grep -o 't="s"' xl/worksheets/sheet$i.xml | wc -l; done
```
如果全是 `t="s"`(共享字符串),没有 `t="inlineStr"`(内联)——**那么只改 sharedStrings.xml,sheet/图片/样式/合并单元格全部自动保留**,这是最安全的路径。

用 `xlsx_dump.py` 导出所有共享字符串（带索引）：
```bash
$OFFICE_PY xlsx_dump.py file.xlsx --strings-out /tmp/strings.txt
```
读这份列表,区分：
- **模板固定文字**(表头"项目名称"、栏位"优先级"、指导语"在此粘贴...图") → **保留不动**
- **业务内容**(旧项目名、旧功能描述) → 要换

## 富文本 si 的处理

带 `R` 标记的 si 是**富文本多 run**,结构如：
```xml
<si><r><rPr><sz val="12"/><b/>...</rPr><t>关键词</t></r><r><rPr>...</rPr><t>：说明</t></r></si>
```
即"关键词"加粗、"说明"常规。`xlsx_swap.py` 处理两种情况：
- 映射值是普通字符串 → 保留首个 run 的 rPr,整体替换为单 run(样式统一,视觉几乎无差)。
- 映射值是 `["加粗前缀","普通后缀"]` → 渲染成 前缀加粗 + 后缀常规(还原原来的粗体强调)。

## 数字型单元格不在 sharedStrings

版本号、数量这类**数字**直接存在 sheet XML：`<c r="E17" s="71"><v>2.7</v></c>`。
它们不在 sharedStrings,要改得单独动 sheet XML。用 `xlsx_swap.py` 的 `--sheet-num-edits` 参数：
```json
{"xl/worksheets/sheet6.xml": [["<c r=\"E17\" s=\"71\"><v>2.7</v></c>", "<c r=\"E17\" s=\"71\"><v>3.5</v></c>"]]}
```
先用 `xlsx_dump.py --sheet <名称>` 找出数字单元格的确切 XML。

## 单元格 ↔ si 定位

要知道"某个格子该改哪个 si",用：
```bash
$OFFICE_PY xlsx_dump.py file.xlsx --sheet "业务分析概要"
```
它打印 `D51: si[23]` 这样的映射。注意：**同一 si 可能被多个格子复用**(合并单元格或重复文字),改一个 si 会影响所有引用它的格子——通常这正是你要的,但要留意别误伤。

## 完整改写流程

```bash
# 1. 环境
eval "$(bash scripts/setup-env.sh)"   # 得到 $OFFICE_PY

# 2. 导出字符串,人工规划映射
$OFFICE_PY scripts/xlsx_dump.py in.xlsx --strings-out /tmp/ss.txt

# 3. 写映射 JSON: {"1":"新标题","23":"新正文","12":["1）关键词","：说明"]}
#    (在临时目录写 mapping.json)

# 4. 改写
$OFFICE_PY scripts/xlsx_swap.py in.xlsx out.xlsx mapping.json \
    --sheet-num-edits num.json   # 可选

# 5. 校验(见 SKILL.md 校验清单)
```

## 校验（务必）

```bash
# 图片数不变
unzip -l out.xlsx | grep -c "xl/media/image"
# 能打开 + 抽查内容 + 零残留
$OFFICE_PY -c "import openpyxl; wb=openpyxl.load_workbook('out.xlsx'); ..."
```
**零残留检测别用 openpyxl 的 row.cells 去重**（合并单元格会假阴性）——直接读 sharedStrings.xml 全文 grep 旧业务词最可靠。
