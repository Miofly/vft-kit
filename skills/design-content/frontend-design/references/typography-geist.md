# Geist：字体角色、实现与验证

来源：<https://github.com/vercel/geist-font>，固定 commit `b5d164a0c066c2c9bfcd5ab65dd8244551f0ac06`。Geist 是可选字体，不是所有设计的默认答案。保留项目现有品牌字和用户指定字体；黏土教育站的圆润标题、奢侈品站的衬线排版，不应被统一替换成 Geist。

## 字体角色

| 字体 | 适合 | 不应替代 |
|---|---|---|
| Geist Sans | 产品界面、英文正文、标题、控件与密集信息；按真实内容调字号、字重和行高 | 中文字库、用户已有品牌字体、所有行业的视觉个性 |
| Geist Mono | 代码、命令、终端、标识符；确需对齐的数值 | 全站正文、只为显得技术感的小标签；普通表格数值可先用 Sans + `tabular-nums` |
| Geist Pixel | 游戏、像素风与特定展示标题；上游有五种变体 | 长正文、表单、密集数据、需要快速阅读的关键操作 |

本地仅打包未修改的 Sans / Mono 两份可变 WOFF2 与 OFL 许可；Pixel 的角色有记录，未打包其字体文件。需要 Pixel 时按上述固定来源或更新后的明确版本取得文件并保留许可，不能引用不存在的本地文件。

## 非 Next.js 项目：本地托管

字体源在本 skill 的 `assets/fonts/geist/`。先展开 `VFT_KIT_DIR`，再定位 `skills/design-content/frontend-design/assets/fonts/geist`。`VFT_KIT_DIR` 必须由调用环境提供；公共 skill 不假定个人目录。将所需 WOFF2 与 `OFL-1.1.txt` 一起复制到目标项目约定的公共字体目录，记录来源。不要把本机绝对文件路径写进浏览器 URL。

以下 CSS 假设目标站点实际托管在 `/fonts/geist/`；有部署 base、CDN 或现成字体管理器时按项目规则调整。它是落地示例，不是向所有项目自动追加的全局样式。

```css
@font-face {
  font-family: 'Geist';
  src: url('/fonts/geist/Geist-Variable.woff2') format('woff2');
  font-style: normal;
  font-weight: 100 900;
  font-display: swap;
}

@font-face {
  font-family: 'Geist Mono';
  src: url('/fonts/geist/GeistMono-Variable.woff2') format('woff2');
  font-style: normal;
  font-weight: 100 900;
  font-display: swap;
}

.product-page {
  font-family: 'Geist', 'PingFang SC', 'Microsoft YaHei', system-ui, sans-serif;
}

.product-page pre,
.product-page code {
  font-family: 'Geist Mono', ui-monospace, monospace;
}

.product-page .numeric-value {
  font-variant-numeric: tabular-nums;
}
```

只注册实际使用的字体。只预加载首屏必需的一份 WOFF2，`as="font" type="font/woff2" crossorigin` 与实际请求地址一致；不要为每个字重下载一个静态文件。自托管跨域时验证 CORS 和缓存响应，避免字体请求失败后不断重试。

`font-display: swap` 让内容先可读，但不保证零布局偏移。比较回退字形和最终字体的真实尺寸；只有测量后才设置 `size-adjust`、`ascent-override` 等指标，不能照搬任意百分比。

## Next.js 项目：复用原有字体管线

上游 npm 包 `geist` 的 `geist/font/sans`、`geist/font/mono` 入口依赖 `next/font/local`。它们不是通用 Vue/Vite 入口，不要在 Vue 中照抄 import。

项目已经使用该包且版本支持时，可按官方方式使用 `GeistSans` / `GeistMono` 的 `.variable` 或 `.className`。也可由项目现有 `next/font/local` 加载本地 WOFF2，声明 `weight: '100 900'` 和稳定的 CSS variable。不要同时注册两套相同字体或为此引入 Next.js。

## 中英混排与可读性

- Geist 不提供完整中文排版方案。为汉字、中文标点与缺字设置目标系统真实存在的回退；项目已有合规中文 Web 字体时优先复用。
- 中英文分别检查基线、字重、标点挤压、数字与按钮对齐，不通过压缩行高掩盖汉字裁切。
- 以真实最长标题、中文按钮、价格、小数、负数和混合代码检查；`1Il0O` 等易混字形在相关场景需可辨。
- 字号层级、行宽与字距按内容和设备确定。密集应用与营销落地页不共用同一展示字号表。
- 放大到 200%、窄屏及系统字体回退时，信息与操作不截断；长代码允许横向滚动，而不是把整个页面撑宽。

## 字体交付检查

1. 校验 WOFF2 文件头和固定来源 hash，许可随文件交付；二进制存在不代表已正确加载。
2. 页面请求无 404、CORS 或 MIME 错误，查看真实计算字体和字体加载结果。
3. 冷加载和字体阻断时文本仍可读；加载完成后按钮、导航和卡片没有不可接受的跳动。
4. 桌面与窄屏检查中英长文本、数字、字重和焦点状态，不只看英文示例。
5. 未运行浏览器、冷缓存或真实设备检查时分别标未验证。

## 检查边界

浏览器可解码与应用不代表产品 CSS 路径、CORS、缓存、冷加载 CLS 或中文实际字形覆盖已验证；Latin 字体加载成功不证明汉字由它绘制，中文回退与目标页字重仍按前述步骤验收。

## 许可与边界

字体遵循 SIL Open Font License 1.1，不是 Apache/MIT。可嵌入和随软件分发，需保留版权与许可，不单独售卖字体；修改版还需遵守保留名称等条款。本 skill 保留官方字体原字节，不改名、不子集化、不转换。使用这套字体不意味着获得 Vercel 品牌背书或其他品牌素材授权。
