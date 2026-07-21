---
name: office-doc-rewrite
description: >-
  在保留原文件全部图片、样式、合并单元格、列宽、页面布局的前提下，改写 Office 文档（.xlsx / .docx / .doc）里的文字内容——
  典型场景：拿一份现成的模板/旧文档（如架构设计表、评审报告单、周报模板），把里面的旧业务内容整篇替换成新项目的内容，产出一份可直接用的新文档。
  核心手法是「zip 层只改文字 XML」而非用 openpyxl/python-docx 整体重存（那样会丢图、丢样式）。
  当用户说「对标这个 xlsx 生成一份」「把这个模板改成 XX 项目的」「改一下这个 doc/表格但别动格式和图」「基于现有文档换内容」
  「行宽/图片变形了帮我修」等需求时，主动使用本 skill。即便用户只说「改这个 Excel/Word」，只要涉及在保留版式的前提下换文字，都应优先用它。
  处理 .doc 需要本机装 LibreOffice；处理图片重绘用 mermaid + playwright。
---

# Office 文档改写（保版式换内容）

## 它解决什么问题

用户常有一份**现成的模板或旧文档**（集团架构设计表、评审报告单、财务表、周报模板…），想把里面的旧内容整篇换成新项目的，但**格式、图片、合并单元格、列宽、页面布局必须原样保留**。

天真的做法是用 openpyxl / python-docx 打开改完再 `save()`——这会踩大坑：

- **openpyxl 重存 xlsx 会丢掉所有嵌入图片和图表**（它不完整支持 drawing）。
- **python-docx 改 `cell.text` 会清空该单元格的字体/颜色格式**，且对合并单元格有诡异行为。

本 skill 的核心选择：**把 Office 文件当成 zip 来处理，只精确改承载文字的那一个 XML，其它字节（图片、样式、drawing、锚点）一律不碰**。这样图片和版式 100% 无损。

三种文件的文字承载位置不同，手法也不同（下面分述）。

## 环境准备（第一步，必做）

本 skill 依赖 Python 库 openpyxl / python-docx / pillow，以及（可选）mermaid.js。本机 pip 常被 uv/homebrew 接管，直接 `pip install` 会报 "No virtual environment found"。**统一用一个专用 venv**，脚本已封装：

```bash
bash scripts/setup-env.sh
```

它在 `~/.cache/vft-kit/office-rewrite/venv` 建一个 venv 并装好依赖，幂等（已装则秒退）。后续所有 python 脚本都用这个 venv 的解释器：`$VENV/bin/python3`（脚本里用 `OFFICE_PY` 环境变量引用）。

处理 `.doc`（老 OLE 格式）还需要 **LibreOffice**（`soffice`）。检测：

```bash
ls /Applications/LibreOffice.app/Contents/MacOS/soffice   # macOS
which soffice libreoffice                                  # Linux
```

没有就让用户装（macOS: `brew install --cask libreoffice`）。不要擅自装重型软件。

## 通用工作流

1. **侦察**：先搞清文件内部结构（哪些是模板固定文字、哪些是要换的业务内容、图片挂在哪）。
2. **建映射**：列一张「原文字 → 新文字」的映射表，模板固定的表头/栏位/指导语**保留不动**。
3. **改写**：zip 层替换文字 XML，或对 docx 走 run 级 / XML 级替换。
4. **校验**：重新打开确认能读、图片数不变、无旧业务词残留、新内容到位。
5. **收尾**：清理临时文件，报告结果。

不同文件类型的具体做法见下。**处理前务必先读对应的 reference 文件**，里面有每种格式的完整踩坑清单。

### 处理 .xlsx → 读 [references/xlsx.md](references/xlsx.md)

要点速览（详见 reference）：
- 文字几乎都在 `xl/sharedStrings.xml` 的共享字符串表里，sheet XML 只存索引。**只改 sharedStrings 就够，sheet/图片/样式全自动保留**。
- 用 `scripts/xlsx_dump.py` 把 330 个共享字符串连同索引导出，据此规划映射。
- 富文本 si（带 `<r><rPr>` 多 run，如粗体关键词）要保留 rPr 结构。
- 用 `scripts/xlsx_swap.py` 按 `{si索引: 新文本}` 映射改写。
- 数字型单元格（如版本号 2.7）直接存在 sheet XML 里，不在 sharedStrings，需单独改 sheet。

### 处理 .docx → 读 [references/docx.md](references/docx.md)

要点速览：
- 用 python-docx，但**不要改 `cell.text`**（会丢格式）。改 run 的 text，或走 XML 层遍历 `<w:t>`。
- **合并单元格陷阱**：`row.cells` 对合并单元格返回共享 `_tc`，用 `id(cell._tc)` 去重会误杀正常单元格，导致漏改。正解是直接遍历 body 里所有 `<w:tc>`/`<w:p>` 元素（`scripts/docx_swap.py` 已封装）。
- 一句话可能被拆成多个 run（`['视频彩铃','H5','重构']`），子串替换要先拼接再回写第一个 run、清空其余。

### 处理 .doc（老 OLE 格式）→ 读 [references/doc.md](references/doc.md)

- `.doc` 是二进制 OLE，不能 zip 层改。**用 LibreOffice 转成 .docx → 按上面的 docx 手法改 → 转回 .doc**。
- 转换命令封装在 `scripts/doc_convert.sh`（doc↔docx↔txt）。

## 图片重绘（当模板里的图也需要换）

如果模板里的图片是旧业务的（如架构图、流程图），要换成新内容的图：

- **首选 mermaid + playwright** 渲染成 PNG（流程图、时序图、架构组件图、上下文图这类框线连接图，mermaid 最专业）。脚本 `scripts/mmd_render.mjs`。
- 用 `scripts/xlsx_replace_images.py` 替换 `xl/media/imageN.png`。
- **关键坑——图片变形与遮挡**：xlsx 图片用 `twoCellAnchor`（双单元格锚点）定位，显示框大小由 from/to 单元格坐标决定，**与图片像素无关**。若新图长宽比 ≠ 原框比例，图会被拉伸变形；若你擅自改锚点把框改大，图会**盖住旁边的文字**（表现为"文字被截断"，实为被图遮挡）。
  - **正解**：① 保持原始 drawing 锚点不动（从原文件恢复）；② 用 pillow 把新图 **padding 加白边到原框的长宽比**（绝不拉伸），让它精确填充原框。`scripts/fit_image_ratio.py` 已封装。
  - 先用 `scripts/xlsx_measure_frames.py` 量出每个图框的真实像素比例（累加列宽/行高换算），据此 padding。
- **mermaid 布局坑**：v11 里 `subgraph` 内嵌 `direction` 常导致整图塌缩成一条细线。拿不准就用扁平的 `节点 --> 节点` 写法，让 mermaid 自己布局，比例不理想再靠 padding 兜底。渲染后用 `mmd_render.mjs` 附带的文字节点导出确认文字完整无截断（因为你可能看不到图）。

详见 [references/images.md](references/images.md)。

## 校验清单（改完必做）

无论哪种文件，改完都要过一遍：

1. **能打开**：`OFFICE_PY` 加载一次（openpyxl / python-docx 不报错）。
2. **图片数不变**：解压数 `xl/media/image*` 或 `word/media/*`，和原文件一致。
3. **零残留**：全文搜旧业务关键词（如"视频彩铃""vring""旧项目名"），确认一个不剩。**注意合并单元格去重会造成假阴性**——用 XML 层遍历搜，别用 `row.cells`+id去重。
4. **新内容到位**：抽查关键字段确实换成了新业务词。
5. **图片比例**（若换了图）：每张新图长宽比 ≈ 原框比例（误差 <0.05）。

## 你可能看不到图

很多终端环境（如 otty）下，Read 一张图片没有回显、`file://` 被禁。此时**不要盲目相信"渲染成功"**：
- 靠 mermaid 语法正确性 + 长宽比数值 + **导出图内所有文字节点**来验证内容完整。
- 需要人眼确认时，起一个本地 http server（`python3 -m http.server`）让用户或 playwright MCP 访问，或直接让用户在 Excel/Word 里打开成品确认。
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
| `scripts/mmd_render.mjs` | mermaid → 高清 PNG（playwright），附文字节点导出 |

所有 python 脚本用 `$OFFICE_PY` 跑（setup-env.sh 会打印路径）。改文件一律**先备份/在副本上操作**，openpyxl 不支持的元素重存会丢，zip 层改则安全。
