# 设计系统：轻量科技风（teal → cyan）

这套视觉语言的目标是「高大上但不 AI 味」：白底卡片 + 细描边 + 淡网格底纹 + 克制的青/cyan 渐变点缀。
它刻意**避开饱和的"AI 蓝"大色块**，改用浅色背景上的小面积渐变（徽标、序号、强调字、进度条），显得专业、干净、信息密度高。

所有图都遵循同一套 CSS token，所以一份文档里的多张图天然风格统一。

## 1. 设计 token（每个 HTML 都以这段开头）

```css
:root{
  --accent:#0ea5a4;   /* teal，主强调 */
  --accent2:#06b6d4;  /* cyan，渐变终点 */
  --ink:#0f2433;      /* 主文字 */
  --sub:#5b7180;      /* 次要文字 */
  --line:#dde8ed;     /* 卡片描边 */
}
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:"Microsoft YaHei","PingFang SC",sans-serif;}  /* Windows 上中文必须指定，否则截图会缺字 */
```

### 换主题色（配方表）
换色主要改 `--accent` / `--accent2` 两个变量，常用配方：

| 风格 | --accent | --accent2 | 配套（深一档 / 背景） |
|------|----------|-----------|----------------------|
| 青/cyan（默认） | `#0ea5a4` | `#06b6d4` | 深 `#0b6e6d`；底 `#f7fafb` |
| 暖金高端 | `#d97706` | `#f59e0b` | 深 `#b45309`；底 `#fcf8f1`、文字用暖棕 `#3a2a17` |
| 橙金 → 琥珀（明快） | `#ea580c` | `#f59e0b` | 深 `#c2410c`；底 `#fcf8f1` |
| 靛紫 → 品红 | `#6d28d9` | `#db2777` | 深 `#5b21b6`；底 `#faf7fe` |
| 翠绿 → 青柠 | `#15803d` | `#84cc16` | 深 `#166534`；底 `#f6faf3` |
| 石墨深色底霓虹青（暗黑科技）| 见下方「暗色变体」 | | |

> **换色不止改 accent，三处要同步跟上**，否则会「主色变了、底子还是青的」露馅：
> 1. **渐变大数字**里那处更深的色 `#0b6e6d` → 换成新主色的深一档（见上表）；
> 2. **`#shot` 背景顶部光晕** `radial-gradient(... rgba(14,165,164,.10) ...)` 的 rgba → 换成新主色的 rgba（如暖金用 `rgba(217,119,6,.14)`）；
> 3. 非青色系建议把 **`#shot` background-color 和网格线** 调成同色温的浅底（见上表「底」），暖色尤其明显——浅暖底 + 暖光晕才有「高端暖色」的整体感，而不是白底上贴几个橙块。

## 2. 根容器（截图目标 `#shot`）

渲染脚本默认截取 `id="shot"` 的元素。务必把整张图包在一个 `#shot` 里，并在它上面铺浅色背景 + 淡网格，这是"科技感"的关键来源：

```css
#shot{
  width:900px;                 /* 按内容定宽：单行流程 960~980，2x2 卡片 760~840 */
  padding:34px 30px 32px;
  background-color:#f7fafb;
  background-image:
    radial-gradient(1000px 320px at 50% -140px,rgba(14,165,164,.10),transparent 70%), /* 顶部光晕 */
    linear-gradient(rgba(15,36,51,.035) 1px,transparent 1px),                          /* 横网格 */
    linear-gradient(90deg,rgba(15,36,51,.035) 1px,transparent 1px);                    /* 竖网格 */
  background-size:auto,28px 28px,28px 28px;
}
```

## 3. 通用组件（按需取用）

```css
/* 标题：左侧渐变竖条 + 标题文字 */
.title{display:flex;align-items:center;gap:11px;margin-bottom:26px;}
.title .bar{width:5px;height:24px;border-radius:4px;background:linear-gradient(180deg,var(--accent),var(--accent2));}
.title h1{font-size:21px;font-weight:700;color:var(--ink);letter-spacing:.5px;}

/* 卡片：白底 + 细描边 + 轻投影；顶部可加一条渐变高光 */
.card{position:relative;background:#fff;border:1px solid var(--line);border-radius:16px;
  padding:22px;box-shadow:0 6px 18px rgba(15,36,51,.06);overflow:hidden;}
.card .top{height:3px;position:absolute;left:0;top:0;right:0;background:linear-gradient(90deg,var(--accent),var(--accent2));}

/* 圆形/圆角序号徽标 */
.badge{width:36px;height:36px;border-radius:50%;background:linear-gradient(135deg,var(--accent),var(--accent2));
  color:#fff;font-size:14px;font-weight:800;display:flex;align-items:center;justify-content:center;
  box-shadow:0 4px 10px rgba(6,182,212,.35);border:2px solid #fff;}

/* 标签芯片（罗列要点用） */
.chip{font-size:11.5px;color:#0b6e6d;background:rgba(14,165,164,.10);
  border:1px solid rgba(14,165,164,.22);padding:3px 10px;border-radius:20px;font-weight:600;}

/* 对比胶囊：old=灰，new=渐变 */
.pill.old{background:#eef2f5;color:#5e7280;border:1px solid #dde6ea;padding:6px 12px;border-radius:8px;font-size:12.5px;font-weight:600;}
.pill.new{color:#fff;background:linear-gradient(135deg,var(--accent),var(--accent2));padding:6px 12px;border-radius:8px;font-size:12.5px;font-weight:600;}

/* KPI 大数字：渐变文字 */
.num{font-size:38px;font-weight:800;line-height:1;letter-spacing:-1px;
  background:linear-gradient(120deg,#0b6e6d,var(--accent2));-webkit-background-clip:text;background-clip:text;color:transparent;}
.num .u{font-size:20px;font-weight:700;}  /* 数字后的单位 */

/* 进度/占比条 */
.track{height:9px;border-radius:6px;background:#eef2f5;overflow:hidden;}
.fill{height:100%;border-radius:6px;background:linear-gradient(90deg,var(--accent2),var(--accent));}
```

### 图标
用**线性 SVG**（stroke 描边，`stroke-width:1.7~1.8`，`color:var(--accent)`），不要用 emoji（emoji 彩色、风格不统一、跨平台渲染不一致）。
直接从 [lucide.dev](https://lucide.dev) 找图标，把 `<path>` 贴进 `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ...>`。
`assets/icons.md` 收录了常用图标的 path（文档、对勾、模块、协作、循环、闪电、盾牌等）。

## 4. 暗色变体（"暗黑科技"风，可选）

当用户想要更强的科技/酷感时，把根容器换成深色，accent 换成霓虹青：

```css
:root{ --accent:#22d3ee; --accent2:#2dd4bf; --ink:#e6f1f5; --sub:#8fa6b2; --line:rgba(255,255,255,.10); }
#shot{ background-color:#0b1220;
  background-image:
    radial-gradient(900px 300px at 50% -120px,rgba(34,211,238,.18),transparent 70%),
    linear-gradient(rgba(255,255,255,.04) 1px,transparent 1px),
    linear-gradient(90deg,rgba(255,255,255,.04) 1px,transparent 1px);
  background-size:auto,28px 28px,28px 28px; }
.card{ background:rgba(255,255,255,.04); border:1px solid rgba(255,255,255,.10);
  box-shadow:0 8px 24px rgba(0,0,0,.35); }  /* 玻璃拟态 */
```

## 5. 布局配方：5 个起手模板 + 自由组合（详见 assets/templates/）

下面 5 个是最常见内容形态的起手模板，全部是改文字就能用的完整 HTML。**但它们是起点不是上限**——内容不合就改结构、拼版、或从下方组件起手新写一个；真正保证统一的是本文档的 token 和组件，不是模板本身（详见 SKILL.md 第 1 步）。

| 模板文件 | 适用内容 | 形态 |
|----------|----------|------|
| `card-grid.html` | 几条并列的要点 / 前置条件 / 特性 | NxN 卡片，序号徽标 + 图标 + 标题 + 说明 |
| `kpi-dashboard.html` | 一组成果指标 / 数据看板 | 3 列大数字卡片（渐变数字 + 图标水印） |
| `step-flow.html` | 主流程的步骤标题 | 横向 N 步，序号 + 图标 + 标题，箭头连接 |
| `timeline.html` | 有先后/含细节的流程大纲 | 纵向时间线，左侧渐变主线串各步 |
| `comparison.html` | A vs B 对比（传统 vs AI 等） | 每行 old→new 胶囊 + 提升幅度条 |

### 选型直觉
- 内容是「**并列的几点**」→ card-grid
- 内容是「**一串数字成果**」→ kpi-dashboard
- 内容是「**先做 A 再做 B**且只要标题」→ step-flow
- 内容是「**流程 + 每步要点/子项**」→ timeline
- 内容是「**两种方式/前后对比**」→ comparison

### 组合 / 自定义（内容不落进单个模板时）
- **分区拼版**：一张图里上半部放 KPI 看板、下半部放对比行；或左流程右要点。各区共用同一套 token 即可浑然一体。
- **改结构**：模板列数/行式不合适，直接改 HTML（如 card-grid 从 3 列改 2 列、comparison 去掉幅度条加一列说明）。
- **新形态**：四象限、中心辐射、矩阵、雷达式罗列等没有现成模板的，用 `.card`/`.badge`/`.chip`/`.num`/线性图标当积木从零拼，照样统一。
- 原则：**先服务内容的表达，再考虑套哪个模板**，而不是反过来把内容削足适履。

## 6. 排版细节（踩过的坑）
- **定宽**：`#shot` 用固定 `width`，按内容选 760~980px；横向流程更宽，方块网格更窄。
- **中文字体**：`body` 必须带 `"Microsoft YaHei","PingFang SC"`，否则 chromium 可能用缺字字体导致方块/缺字。
- **换行**：卡片标题用 `<br/>` 手动断行更可控，别依赖自动换行。
- **关键词加粗**：说明文字里把数字/术语用 `<b>` 包起来（`.d b{color:var(--ink);font-weight:600;}`），信息层次更清晰。
- **Mermaid 不适合**：卡片渐变、玻璃拟态、精确网格这类效果 Mermaid 做不出来；这套方案用 HTML/CSS 就是为了拿到完全的视觉控制权。
