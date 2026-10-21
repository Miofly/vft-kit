# 通用工作流、校验与脚本清单

## 通用工作流

1. **侦察**：先搞清文件内部结构（哪些是模板固定文字、哪些是要换的业务内容、图片挂在哪）。
2. **建映射**：列一张「原文字 → 新文字」的映射表，模板固定的表头/栏位/指导语**保留不动**。
3. **改写**：zip 层替换文字 XML，或对 docx 走 run 级 / XML 级替换。
4. **校验**：重新打开确认能读、图片数不变、无旧业务词残留、新内容到位。
5. **收尾**：清理临时文件，报告结果。

不同文件类型的具体做法见下。**处理前务必先读对应的 reference 文件**，里面有每种格式的完整踩坑清单。

## 校验清单（改完必做）

无论哪种文件，改完都要过一遍：

1. **能打开**：`OFFICE_PY` 加载一次（openpyxl / python-docx 不报错）。
2. **图片数不变**：解压数 `xl/media/image*` 或 `word/media/*`，和原文件一致。
3. **零残留**：全文搜旧业务关键词（如"视频彩铃""vring""旧项目名"），确认一个不剩。**注意合并单元格去重会造成假阴性**——用 XML 层遍历搜，别用 `row.cells`+id去重。
4. **新内容到位**：抽查关键字段确实换成了新业务词。
5. **图片比例**（若换了图）：每张新图长宽比 ≈ 原框比例（误差 <0.05）。

## 你可能看不到图

很多终端环境（如 otty）下，Claude Code 的 `Read` 或 Codex 的 `view_image` 可能不可用，`file://` 也可能被禁。此时**不要盲目相信"渲染成功"**：
- 靠 mermaid 语法正确性 + 长宽比数值 + **导出图内所有文字节点**来验证内容完整。
- 需要人眼确认时，起一个本地 http server（`python3 -m http.server`）让用户或 ego-lite（无 ego-lite 时 playwright MCP）访问，或直接让用户在 Excel/Word 里打开成品确认。
- 老实告诉用户"我看不到渲染效果，请你打开确认"，别假装看过了。

## 脚本清单

| 脚本 | 作用 |
|------|------|
| `scripts/setup-env.sh` | 建 venv 装依赖（openpyxl/python-docx/pillow），打印 `OFFICE_PY` 路径 |
| `scripts/xlsx_dump.py` | 导出 xlsx 所有共享字符串（带索引）+ 各 sheet 单元格→si 映射 |
| `scripts/xlsx_swap.py` | 按 `{si索引:新文本}` 映射改 sharedStrings（保富文本 rPr） |
| `scripts/xlsx_measure_frames.py` | 量每张图 twoCellAnchor 框的真实像素比例 |
| `scripts/fit_image_ratio.py` | 把新图 padding 加白边到目标比例（不拉伸） |
| `scripts/xlsx_replace_images.py` | 替换 xl/media 图片 + 可选恢复原始 drawing 锚点 |
| `scripts/docx_swap.py` | XML 层遍历改 docx 文字（避合并单元格陷阱，保 run 格式） |
| `scripts/doc_convert.sh` | LibreOffice 转 doc↔docx↔txt |
| `scripts/mmd_render.mjs` | mermaid → 高清 PNG（ego-lite 优先，无则 playwright），附文字节点导出 |

所有 python 脚本用 `$OFFICE_PY` 跑（setup-env.sh 会打印路径）。改文件一律**先备份/在副本上操作**，openpyxl 不支持的元素重存会丢，zip 层改则安全。
