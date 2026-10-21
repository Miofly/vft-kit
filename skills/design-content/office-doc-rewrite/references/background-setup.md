# 背景与环境准备

## 它解决什么问题

用户常有一份**现成的模板或旧文档**（集团架构设计表、评审报告单、财务表、周报模板…），想把里面的旧内容整篇换成新项目的，但**格式、图片、合并单元格、列宽、页面布局必须原样保留**。

天真的做法是用 openpyxl / python-docx 打开改完再 `save()`——这会踩大坑：

- **openpyxl 重存 xlsx 会丢掉所有嵌入图片和图表**（它不完整支持 drawing）。
- **python-docx 改 `cell.text` 会清空该单元格的字体/颜色格式**，且对合并单元格有诡异行为。

本 skill 的核心选择：**把 Office 文件当成 zip 来处理，只精确改承载文字的那一个 XML，其它字节（图片、样式、drawing、锚点）一律不碰**。这样图片和版式 100% 无损。

三种文件的文字承载位置不同，手法也不同（下面分述）。

下文 `<skill-dir>` 指当前 `SKILL.md` 所在目录的绝对路径，由 Claude Code 或 Codex 从已加载 skill 位置解析；不要按当前工作目录猜测。

## 环境准备（第一步，必做）

本 skill 依赖 Python 库 openpyxl / python-docx / pillow，以及（可选）mermaid.js。本机 pip 常被 uv/homebrew 接管，直接 `pip install` 会报 "No virtual environment found"。**统一用一个专用 venv**，脚本已封装：

```bash
bash "<skill-dir>/scripts/setup-env.sh"
```

它在 `~/.cache/vft-kit/office-rewrite/venv` 建一个 venv 并装好依赖，幂等（已装则秒退）。后续所有 python 脚本都用这个 venv 的解释器：`$VENV/bin/python3`（脚本里用 `OFFICE_PY` 环境变量引用）。

处理 `.doc`（老 OLE 格式）还需要 **LibreOffice**（`soffice`）。检测：

```bash
ls /Applications/LibreOffice.app/Contents/MacOS/soffice   # macOS
which soffice libreoffice                                  # Linux
```

没有就让用户装（macOS: `brew install --cask libreoffice`）。不要擅自装重型软件。
