---
name: style-layout
description: 样式布局规范（设计稿还原、文档流优先、居中方式、Vue 2 禁用 Grid）
paths:
  - '**/*.vue'
  - '**/*.{css,scss,sass,less,styl}'
checks:
  - vue2-no-grid
  - absolute-hardcoded-layout
---

# 样式布局规范（vft-kit 注入）

写样式、还原 MasterGo / Figma / 蓝湖设计稿时遵守以下规范。标注「自动检查」的条目会在保存后由 vft-kit 校验。

## 0. 动手前先确认

- **确认项目 Vue 大版本**：看 `node_modules/vue/package.json` 或 `package.json` 的 `vue` 依赖。Vue 2 项目通常要兼容旧 WebView / 低版本浏览器，布局能力按第 3 节收紧。
- **看设计稿的图层结构，不只看坐标**：MasterGo 的「自动布局」对应 flex，方向、间距、对齐、padding 要直接翻译成 flex 属性。设计工具导出的 `left/top` 绝对坐标只是画布上的位置，不是布局意图。
- **先找重复的样式单元**：设计稿里反复出现的卡片、按钮、列表项、标题栏，先抽成组件，差异用 props / 插槽表达，再拼页面（见 vue-sfc 规则「组件复用」）。设计稿里的组件 / 实例（Component / Instance）通常就是应该抽组件的位置。

## 1. 文档流优先，定位只做点缀

- 默认用正常文档流：块级元素自然上下排列，行内内容自然换行，间距用 `margin` / `padding` / `gap`。
- 横向排列、对齐、等分用 flex。能用文档流 + flex 表达的结构，不要用定位。
- **`position: absolute` 只用于脱离流的元素**：角标、徽章、关闭按钮、遮罩、下拉浮层、装饰图、背景层等。定位元素的父级写 `position: relative` 作为参照。
- **禁止用绝对定位 + 写死的 `top/left` 像素值拼整页布局**（自动检查 `absolute-hardcoded-layout`，warn 级）：文案变长、换行、数据条数变化、屏幕宽度变化时会重叠或错位。
- 不用 `position: relative` + `top/left` 偏移去「挪」元素对齐设计稿；偏移说明结构或间距写错了，应改 `margin` / `padding` / 对齐方式。
- 尺寸少写死：文本容器不写固定 `height`，让内容撑开，最多给 `min-height`；宽度优先 `flex: 1`、百分比或 `max-width`。设计稿上的宽高主要用于图片、图标、头像等固定尺寸素材。

## 2. 居中

按顺序选，前面的能用就不要往后退：

1. **flex 居中**：父级 `display: flex; align-items: center; justify-content: center;`。文本垂直居中也用这种方式，高度写 `min-height`，上下留白用 `padding`。
2. **块级水平居中**：定宽块用 `margin: 0 auto`。
3. **定位居中**：元素必须脱离文档流（弹窗、浮层、覆盖在图片上的标记）时，用 `position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%);`。只需水平居中就只写 `left: 50%` + `translateX(-50%)`。

不要用 `left: 137px` 这类按设计稿算出来的值实现「看起来居中」；容器宽度一变就偏移。

**文本居中不要用 `line-height` 等于容器高度**（如 `height: 44px; line-height: 44px`）。原因是设计要兼容大字体：

- 用户调大系统字体、浏览器缩放或 App 适老化模式时，字号变大，写死的 `line-height` 不变，文字会溢出或被裁切。
- 文案换行后，每行都占满容器高度，多行文本会把容器撑破或重叠。
- 容器内含图标、多个行内元素时，基线对齐会让视觉中心偏移。

改用 flex 居中 + `min-height` + `padding`。`line-height` 只写无单位的倍数（如 `1.5`），用来控制行距，不承担居中。

## 2.1 大字体适配

- 字号用 `rem` / `em` 或项目约定的适配单位，不在行高、按钮高度等地方写死与字号相关的 `px`。
- 含文字的容器（按钮、标签、导航项、列表行）不写固定 `height`，用 `min-height`；需要单行显示时明确写 `white-space: nowrap; overflow: hidden; text-overflow: ellipsis;`。
- 图标与文字并排时用 flex `align-items: center` 对齐，图标尺寸可用 `em` 跟随字号。

## 3. Vue 2 项目

- **不用 CSS Grid**（`display: grid` / `inline-grid`、`grid-template-*`、`grid-area` 等；自动检查 `vue2-no-grid`）。网格和卡片列表用 flex + `flex-wrap` + 百分比宽度实现。
- **flex 容器慎用 `gap`**：iOS < 14.5 与 Chrome < 84 不支持 flex 的 `gap`，会导致间距消失。子元素之间用 `margin`，列表可以用 `:not(:last-child)` 或 `& + &` 加间距。
- 这一节不适用于 Vue 3 项目；Vue 3 可以按需使用 Grid 与 `gap`。

## 4. 还原检查清单

写完后对照设计稿确认：

- 文案加长一倍、换两行，布局不重叠。
- 列表条数变多或变少，后续内容跟着移动，不被盖住。
- 容器宽度变化（375 / 414 / 桌面宽度），居中元素仍居中。
- 除角标、浮层、装饰层外，没有绝对定位。
- 字号放大到 1.5 倍（系统大字体或浏览器缩放），文字不溢出、不被裁切，居中仍成立。

## 项目覆盖

项目根的 `.claude/vft-rules.json` 可以关闭本规则或调整检查级别。例如某个 Vue 2 项目确认只跑在新内核上：

```json
{
  "checks": { "vue2-no-grid": "off", "absolute-hardcoded-layout": "error" }
}
```
