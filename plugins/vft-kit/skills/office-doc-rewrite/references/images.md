# 图片重绘与替换完整指南

当模板里的图是旧业务的（架构图、流程图、时序图、组件图），要换成新内容的图时。

## 用什么画

- **框线连接图**（流程图、时序图、架构组件图、系统上下文图、状态机）→ **mermaid**,它专门画这类图,线条规整专业。`mmd_render.mjs` 渲染成高清 PNG。
- **精确版式的信息图**（KPI 看板、要点卡片、渐变质感）→ 用 `co-infographic-generator` skill（HTML+CSS）。
- **纯数据统计图**（柱/折/饼）→ `multi-chart-draw` 的 ECharts。

本 skill 主要用 mermaid,因为架构设计文档里的图基本都是框线连接图。

## 坑1：twoCellAnchor —— 图片变形与遮挡文字

xlsx 图片用 `twoCellAnchor`（双单元格锚点）定位：显示框由 `<xdr:from>` 和 `<xdr:to>` 两个单元格坐标决定,**图片会被缩放填满这个框,与图片本身像素无关**。

两个致命后果：
1. **变形**：若新图长宽比 ≠ 原框比例,图被拉伸/压扁。横向时序图放进竖长框会被竖向拉长成鬼样。
2. **遮挡文字**：若你为了"让图好看"擅自改锚点 `<xdr:to>` 把框改大,图会**盖住旁边单元格的文字**。用户看到的是"文字显示不全/被截断",其实文字数据完好,只是被图片图层遮住了。

**正解（两步）**：
1. **锚点保持原样**（别改 drawing.xml 的 from/to）。如果之前改坏了,用 `xlsx_replace_images.py --restore-anchors-from <原文件>` 从原文件恢复。
2. **让新图适配原框比例**：先量原框比例,再把新图 padding 加白边到该比例（**绝不拉伸**）。

```bash
# 量每个框的真实像素比例
$OFFICE_PY scripts/xlsx_measure_frames.py orig.xlsx
# 输出: image6 [逻辑架构]: 框≈1692x6436px 比0.26

# 渲染新图
node scripts/mmd_render.mjs seq.mmd /tmp/new6.png 4

# padding 到框比例(不拉伸,加白边)
$OFFICE_PY scripts/fit_image_ratio.py /tmp/new6.png /tmp/fit6.png 0.26

# 替换(可同时恢复锚点)
$OFFICE_PY scripts/xlsx_replace_images.py in.xlsx out.xlsx img_map.json \
    --restore-anchors-from orig.xlsx
```

padding 后每张图比例应 ≈ 框比例（误差 <0.05）,校验：
```python
from PIL import Image; im=Image.open('fit6.png'); print(im.size[0]/im.size[1])
```

## 坑2：让图适配框,而非改框适配图

被 padding 出巨大白边时（如横图放进 0.26 竖框,或 15 步流程横排放进方框）,与其加超大白边让内容缩得看不清,不如**改 mermaid 布局方向**让图天然接近框比例：
- 竖长框（比<0.5）→ 用 `flowchart TB` 纵向排列步骤。
- 横宽框（比>2）→ 用 `flowchart LR` 横向。
- 方框（比≈1）→ 适度分支。
调整布局后再 padding 兜底剩余的比例差。

## 坑3：mermaid subgraph 塌缩

mermaid v11 里 **`subgraph` 内嵌 `direction TB/LR` 常导致整图塌缩成一条细线**（渲染出 1200×56 这种）。表现为比例极端异常。

规避：
- **优先用扁平写法** `A --> B --> C`,让 mermaid 自己布局,别嵌套 subgraph+direction。
- 需要分组时,subgraph 不加内部 `direction`,靠节点连线的自然方向排布。
- 渲染后**看比例数值**,若出现 >8 或 <0.15 的极端比例,基本是塌缩了,改写布局。

## 坑4：你可能看不到图

很多终端环境（otty 等）Read 图片无回显、`file://` 被禁,**你根本看不到渲染效果**。别假装看过。验证内容完整的办法：
```bash
node scripts/mmd_render.mjs --check diagram.mmd
# 打印图内所有文字节点,确认文字都在、无截断、无错字
```
`mmd_render.mjs` 渲染时也会把文字节点打到 stderr。最终视觉效果**让用户在 Excel 里打开确认**,或起 `python3 -m http.server` 让用户/playwright MCP 看图。

## drawing → 图片 → sheet 映射速查

```bash
# 图片挂在哪个 sheet
cat xl/worksheets/_rels/sheetN.xml.rels   # sheet → drawing
cat xl/drawings/_rels/drawingN.xml.rels   # drawing → media/imageN.png
# 锚点跨度(看框大概多大)
grep -A5 twoCellAnchor xl/drawings/drawingN.xml
```
