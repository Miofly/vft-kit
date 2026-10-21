---
name: office-doc-rewrite
description: "按 Excel/Word 模板替换文字，保留图片、样式、合并单元格和版式；旧文档换内容、修复格式丢失；.doc 需 LibreOffice。"
---

# Office 文档改写（保版式换内容）

> **浏览器/API 边界**：遵守 [浏览器到 API 强制演进](../../BROWSER_API_EVOLUTION.md)。本地渲染、视觉、兼容性或浏览器本身的验证可保留浏览器；认证后的远端业务读写必须探索实际接口、写后独立回读，并在确认后更新本 skill，后续默认 API。

基于现有 Excel/Word 模板换业务文字，图片、样式、合并单元格和版式原样保留。

## 何时用

旧模板或旧文档整篇换成新项目内容，或修复改写后的格式丢失；支持 `.xlsx`、`.docx`、`.doc`（需 LibreOffice），含模板内图片重绘。

## 硬规则

- 先跑 `bash "<skill-dir>/scripts/setup-env.sh"`，所有 python 脚本用它打印的 `$OFFICE_PY` 运行。
- 把 Office 文件当 zip 处理，只改承载文字的 XML；不用 openpyxl 重存 xlsx，不改 docx 的 `cell.text`。
- 处理前先读对应格式的 reference；改文件先备份或在副本上操作。
- 换图保持原 drawing 锚点，用白边 padding 到原框比例，绝不拉伸。
- 改完必过校验清单：能打开、图片数不变、旧业务词零残留、新内容到位、图片比例。
- 看不到渲染效果时明说并请用户打开确认，不假装看过。
- 不擅自安装 LibreOffice 等重型软件。

下文 `<skill-dir>` 指当前 `SKILL.md` 所在目录的绝对路径，由 Claude Code 或 Codex 从已加载 skill 位置解析；不要按当前工作目录猜测。

## 路由

| 任务 | references | 脚本 |
|---|---|---|
| 背景、环境准备 | [background-setup.md](references/background-setup.md) | [setup-env.sh](scripts/setup-env.sh) |
| 通用工作流、校验清单、看不到图、脚本清单 | [workflow-checks.md](references/workflow-checks.md) | — |
| 改 `.xlsx` | [xlsx.md](references/xlsx.md) | [xlsx_dump.py](scripts/xlsx_dump.py)、[xlsx_swap.py](scripts/xlsx_swap.py) |
| 改 `.docx` | [docx.md](references/docx.md) | [docx_swap.py](scripts/docx_swap.py) |
| 改 `.doc` | [doc.md](references/doc.md) | [doc_convert.sh](scripts/doc_convert.sh) |
| 图片重绘与替换 | [images.md](references/images.md) | [mmd_render.mjs](scripts/mmd_render.mjs)、[xlsx_measure_frames.py](scripts/xlsx_measure_frames.py)、[fit_image_ratio.py](scripts/fit_image_ratio.py)、[xlsx_replace_images.py](scripts/xlsx_replace_images.py) |
