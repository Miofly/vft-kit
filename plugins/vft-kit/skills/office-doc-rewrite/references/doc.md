# 改写 .doc（老 OLE 格式）完整指南

## .doc 不是 zip,不能直接改

`.doc` 是微软老的 **OLE 复合二进制格式**（`file` 命令显示 "Composite Document File V2"）,不是 zip+XML,没法像 xlsx/docx 那样 zip 层改文字。WPS 存的 .doc 也是这个格式。

## 方案：LibreOffice 转 docx → 改 → 转回 doc

需要本机装 **LibreOffice**。检测：
```bash
ls /Applications/LibreOffice.app/Contents/MacOS/soffice   # macOS
which soffice libreoffice                                  # Linux
```
没有让用户装：`brew install --cask libreoffice`。**不要擅自装重型软件**。

流程（`doc_convert.sh` 封装了转换）：
```bash
# 1. doc → docx（便于精确改）
bash scripts/doc_convert.sh report.doc docx ./work

# 2. 先看内容规划映射
bash scripts/doc_convert.sh report.doc txt ./work && cat ./work/*.txt

# 3. 按 docx 手法改（见 docx.md,注意合并单元格陷阱）
$OFFICE_PY scripts/docx_swap.py ./work/report.docx ./work/new.docx rules.json

# 4. 转回 doc（和原格式一致）
bash scripts/doc_convert.sh ./work/new.docx doc ./out
```

## 建议同时保留 docx

转回 .doc 会经过 LibreOffice 的二次转换,可能有细微排版差异。**建议同时交付 .docx 版本**（更通用、更精确）,让用户选。评审报告单这类表格文档,docx 保真度更高。

## 校验

转回的 .doc 用 LibreOffice 转 txt 复查内容：
```bash
bash scripts/doc_convert.sh out/new.doc txt /tmp/verify && cat /tmp/verify/*.txt
```
确认：新业务词到位、旧业务词零残留、日期等字段已更新。
