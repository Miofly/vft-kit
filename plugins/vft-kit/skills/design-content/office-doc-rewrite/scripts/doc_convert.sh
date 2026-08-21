#!/usr/bin/env bash
# LibreOffice 转换 doc/docx/txt。用于 .doc(老OLE) 编辑: doc→docx 改→docx→doc。
# 用法:
#   bash doc_convert.sh <输入文件> <目标格式> <输出目录>
#   目标格式: docx | doc | txt
# 例:
#   bash doc_convert.sh report.doc docx ./work        # doc→docx(便于改)
#   bash doc_convert.sh report.docx doc ./out          # docx→doc(转回原格式)
#   bash doc_convert.sh report.doc txt ./work          # 看内容
set -euo pipefail

SRC="$1"; FMT="$2"; OUT="${3:-.}"

# 纵深防御: 拒绝路径里的 shell 元字符(即便下面已用引号+无 eval,这里提前拦掉可疑输入)
case "$SRC$OUT" in
  *[';|&`$()']*) echo "错误: 路径含非法字符(; | & \` \$ ( ))" >&2; exit 1 ;;
esac

# 定位 soffice
SOFFICE=""
for c in /Applications/LibreOffice.app/Contents/MacOS/soffice soffice libreoffice; do
  if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then SOFFICE="$c"; break; fi
done
[ -z "$SOFFICE" ] && { echo "错误: 未找到 LibreOffice(soffice)。macOS 装: brew install --cask libreoffice" >&2; exit 1; }

mkdir -p "$OUT"
case "$FMT" in
  docx) FILTER="docx" ;;
  doc)  FILTER="doc:MS Word 97" ;;
  txt)  FILTER="txt:Text" ;;
  *) echo "不支持的格式: $FMT" >&2; exit 1 ;;
esac

"$SOFFICE" --headless --convert-to "$FILTER" --outdir "$OUT" "$SRC" 2>&1 | tail -1
