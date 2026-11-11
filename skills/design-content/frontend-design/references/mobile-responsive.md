# 手机端实施与验收

整页新建、重做、风格迁移及移动端适配先读本文件；局部修复只加载受影响的部分。项目断点、组件与滚动壳优先。应用布局细节见 [app-screens.md](app-screens.md)，控件语义见 [component-systems.md](component-systems.md)，通用质量与证据分级见 [design-review.md](design-review.md)。

## 1. 先定重组，不缩小桌面

- 写清窄屏的阅读顺序、主操作、导航、表格/图表和弹层策略；字段只移动或渐进披露，不删除任务必需信息。断点取内容开始失效的位置，已有项目断点保持同源；测试宽度不是新断点。
- 优先内在尺寸、Flex/Grid、`min-width: 0`、可换行操作区；容器复用需要时才用容器查询。流式字号采用含 `rem` 的上下限，避免纯 `vw` 字号抵消文字放大。遵守项目已有单位转换，不另加一套全局缩放。
- 长中文、长ID和按钮组用真实内容检查。表格/代码/轮播允许局部横滚，入口与可滚动提示明确；正文不因某个宽子项产生整页横滚。不要用全局 `overflow-x: hidden` 藏错。
- 图片声明固有尺寸或比例；按内容需要使用 `srcset`/`sizes` 或 `picture` 做分辨率选择与艺术裁剪。首屏关键图不机械懒加载，手机不裁掉关键对象。

## 2. 视口、底栏与软键盘

普通内容页用自然流；全屏工具才使用项目已有唯一纵向滚动壳。`svh` 适合稳定的小视口，`dvh` 跟随浏览器栏变化，`vh` 可作旧浏览器回退；它们都不保证解决软键盘遮挡。短横屏要能滚到最后一个操作。

按宿主能力选择规则，不把下面的选择器全局粘贴：

```css
.mobile-shell {
  min-block-size: 100vh;
  min-block-size: 100svh;
}
.mobile-workspace {
  block-size: 100vh;
  block-size: 100dvh;
  overflow-y: auto;
}
.mobile-actions {
  padding-block-end: max(1rem, env(safe-area-inset-bottom, 0px));
}
```

- 安全区由一层负责：顶部、底部与横屏左右凹口都检查。仅边到边画布确有需要时由宿主设置 `viewport-fit=cover`，不要每个组件重写 viewport 或重复加 inset；固定底栏还要为正文保留其完整占位。
- 保留 `width=device-width, initial-scale=1` 和用户缩放；不设置 `user-scalable=no` 或用 `maximum-scale=1` 修复输入问题。移动文本输入通常至少16 CSS px，仍需在目标iOS上检查自动放大与焦点偏移。
- 输入有持久 label，按数据选择 `type`、`inputmode`、`autocomplete`；保留粘贴、密码管理器与中文IME。移动端不无条件 autofocus。
- 依次聚焦首个/最后一个字段：键盘打开后字段、就地错误和提交路径仍可达，关闭后滚动位置合理。先修滚动和布局；只有真实遮挡无法解决时才引入 VisualViewport，处理其可用性、resize/scroll与清理。不要把pinch zoom误当键盘，不靠猜测键盘高度移动整页。

## 3. 触摸、弹层与动效

- 重要操作不依赖 hover。`@media (hover: hover) and (pointer: fine)` 仅开启指针增强；触摸有点击/展开等价路径，键盘有明确焦点。混合输入设备单独验，不通过屏幕宽度判断是否支持触摸。
- 44×44 CSS px是常用触控设计目标；WCAG 2.2 AA SC 2.5.8通常为24×24 CSS px或满足适用例外。检查真实点击区和间距，不只看图标。内联文字链接等例外按标准判，不能把所有小目标自动判违规。
- 拖动有非拖动替代；覆盖滚动经过、手指移出、第二指、`pointercancel`与lost capture后再拖。按交互方向选择 `touch-action`，不要在全页禁用缩放或原生触摸滚动。
- 复用现有Dialog/Sheet/Popover与Portal：焦点进入/返回、modal背景不可操作、滚动锁定/解锁、关闭路径、屏幕旋转和键盘展开一起验。窄屏换抽屉不是只改宽度，也不强制所有弹层变抽屉。
- 新Vue交互缺少成熟基础时参考 [Reka UI](https://github.com/unovue/reka-ui)；React输入等价性参考 [React Aria](https://github.com/adobe/react-spectrum)。先核对目标版本及依赖，保留项目组件，不自动换库。不要默认新引入已停止维护的 [Vaul](https://github.com/emilkowalski/vaul)。
- 保留brief要求的完整动效，不因手机直接静态化。单独测无hover、滚动冲突、离屏/后台暂停、动态reduced-motion、切换/卸载和中断终态；Canvas/WebGL按真实设备调整像素密度、粒子数量与模糊面积，记录画质差异与测量条件，不承诺通用FPS。

## 4. 验收矩阵与完成条件

| 维度 | 起始样本与通过条件 |
|---|---|
| 宽度 | 320、390、430、768、1440 CSS px及实际断点两侧；未要求支持的档说明理由。整页看至页底，内容和操作完整，无意外页面横滚 |
| 高度/方向 | 例如844×390短横屏；浏览器栏伸缩、固定导航与底栏不遮操作 |
| 放大 | 200%文字放大；适用WCAG回流要求时，以1280px桌面视口400%浏览器缩放形成约320 CSS px，或等价回流测试；数据表等二维布局按适用例外处理。缩小viewport不等于已经验证文字缩放 |
| 输入 | 鼠标、键盘、触摸分别走真实任务；记录引擎、输入模拟方式与设备。仅改viewport不计触摸通过 |
| 内容/状态 | 长中文/长ID，加载/空/错/重试/成功，打开菜单/弹层、末字段输入、重复操作；主题仅覆盖brief/项目支持的每一套 |
| 动效/性能 | 开始/中间/终态、快速中断、reduce、离屏/后台与回来；慢网/CPU模拟标为实验室条件，手机成本结论需要目标设备实测 |
| 真机 | 目标包括iOS/Android时分别记录Safari/Chrome检查；软键盘、safe-area、原生手势和低电量模式无法用桌面Chromium证明 |

### 无依赖DOM初筛

本skill的 `scripts/mobile-audit.mjs` 导出 `collectMobileAudit()`，在**当前已获准的目标页面**中执行。不导航、不点击、不改样式、不联网、不安装axe；只返回视口尺寸、页面横向溢出、当前可见小点击区候选、viewport缩放限制与小字号输入候选，不采集文案、输入值、Cookie或URL。

Node侧读取模块，再经现有浏览器的 `page.evaluate` 执行：

```js
// FRONTEND_DESIGN_DIR 由调用方提供绝对路径；浏览器runner不继承shell环境时显式传入。
const { collectMobileAudit } = await import(`${FRONTEND_DESIGN_DIR}/scripts/mobile-audit.mjs`);
const report = await page.evaluate(`(${collectMobileAudit.toString()})()`);
console.log(report);
```

离线回归：`node --test` 后传入本skill绝对路径下的 `tests/mobile-audit.test.mjs` 与 `tests/integration.test.mjs`。浏览器夹具回归为 `tests/mobile-audit.browser.mjs`：先在Node runner定义绝对路径常量 `FRONTEND_DESIGN_DIR`、`OUTPUT_DIR`，再执行文件内容；需已有ego-browser及其当前用法指南，只创建独立空白测试页，不启动服务。它覆盖五档宽度与短横屏的明暗夹具，以及溢出、小目标、小字号输入、禁缩放四个故障；不代表业务页或真机验收。

在各宽度、主题及关键状态分别执行；先用项目真实ready条件等待页面稳定，滚到后续区块再检查。`status: clear`仅表示当前文档/当前视口未发现这些候选，不是兼容认证。`review`逐项人工复核：小目标可有合规例外；页面溢出须定位到具体元素；裁切/遮挡/伪元素点击区需另测。iframe、Shadow DOM内容不在扫描范围，不能据此称整页通过。

已有axe或Lighthouse时复用。axe由项目已有包或明确授权的本地路径加载，不从CDN往认证页注入脚本；记录工具版本和适用规则，人工复核 `incomplete`。axe不证明软键盘、安全区、原生手势、业务结果或完整无障碍合规。缺依赖就标未跑，不在设计任务中自动安装。

完成时给：路由/实际内容与状态、宽高、主题、引擎/设备/输入、自动候选处理结果、截图/连续帧路径，以及未跑项。模拟器、静态代码、截图和真机证据分别标明。没有批准的预览环境不启动服务，把运行验证列为未验证。

## 5. 外部资料的取舍

以下为补充阅读与独立整理的实施建议，不附带第三方源码或自动安装步骤：

- [Vercel Web Interface Guidelines](https://github.com/vercel-labs/web-interface-guidelines)：借鉴移动输入、安全区与设备检查；不采用禁缩放修复、强制最短Loading等与无障碍/真实ready冲突的建议。
- [UI Skills](https://github.com/ibelick/ui-skills)：借鉴短质量检查；不继承强制Tailwind/React、默认不加动画或统一200ms上限。
- [axe-core](https://github.com/dequelabs/axe-core)：自动无障碍检查引擎，作为人工验收的补充。
- [Open Props](https://github.com/argyleink/open-props)：按需参考流式尺寸/字排token，不整套覆盖项目设计系统。
- [Vue Bits](https://github.com/DavidHDev/vue-bits)：Vue视觉效果参考，不是手机兼容保证；按组件核对触摸、SSR、回收和许可。MIT + Commons Clause素材不打包进本公共skill。

出现“文档有手机字样，所以兼容通过”的误判，根因是把指导与运行证据混为一谈；用上述矩阵、DOM初筛和单独真机记录区分三者。
