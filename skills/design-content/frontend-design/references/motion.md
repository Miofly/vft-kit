# 动效：配方、生命周期与验收

动效先回答“什么变化需要被看见”，再决定实现。用户要求动画时要实现可观察的状态和节奏，不能只写原则；用户没要求时也不必把所有界面变成舞台。许可见 [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md)。

## 1. 先读哪一层

以下路径均以本 skill 根目录为基准；`recipes/` 是可读配方与可运行示例，不是自动执行入口。

| 需要 | 实际可读文件 |
| --- | --- |
| 完整动效配方、token 与取舍 | `recipes/motion-recipes.md`（完整原文，含 load、行遮罩、图片开窗、滚动叙事、横向图库、数字、页面过渡等） |
| 滚动场景的结构与回退 | `recipes/scenes.md` |
| 已实现的滚动底座 | `recipes/stage.js`、`stage.css` |
| 动作索引与适用主题 | `recipes/motions.json`（完整，不是只有名字） |
| 可直接移植的无依赖示例 | `recipes/recipes.html`、`recipes.mjs` |
| 新配方的小测 | `recipes/recipes.test.mjs` |
| Apple 式区块分级淡入（实测参数） | 本文「配方 D」 |
| 展示站真实叠卡观察 | [case-studies.md 参考站观察](case-studies.md) |

此固定版本**尚未发布** `library/scenes.json`、每场景 JS/CSS 与 demo 目录；不能把目录描述当成已交付文件。本地保留真实 stage 和完整文字配方，并提供明确标为本地改写的可执行示例；不声称复用了不存在的相机飞行/叠卡组件。

## 2. 动效预算和工具选择

优先级：操作反馈/状态连续性 > 解释产品的运动 > 一个主题记忆点 > 装饰。高频输入、数据刷新与工作台通常更安静。品牌展示可以大胆，但每一段被占用的滚动距离应有新信息。时间参数是起点，不是跨设备/跨品牌的神谕。

| 场景 | 可调起点 | 实现路线 |
| --- | --- | --- |
| 按下、颜色、短位移反馈 | 100–180ms，按压缩放约 .97–1 | CSS transition；保留项目已有按钮、焦点和 disabled 行为 |
| 菜单/弹窗/局部切换 | 150–350ms，小幅位移或 .97–1 scale | 先用已有组件动画，不另造弹窗语义 |
| 一次性重点入场 | 400–900ms，12–24px；少量子项可错开 50–90ms | CSS / WAAPI / 项目已有 Motion；正文首屏不等待 reveal |
| 遮罩开图 | 700–1200ms；滚动型以进度而非秒为轴 | CSS `clip-path`，或已有 GSAP timeline；先评估大图重绘开销 |
| 一幅图承载多个章节 | 一次 hold 约 1–3 屏，依据实际叙事缩短 | 原生 sticky + CSS timeline；多轨协调时已有 GSAP/ScrollTrigger |
| 可打断的布局、手势/共享元素 | 参数依组件尺寸和手势速度调 | 项目已集成的 Motion/GSAP；无需为一个 hover 安装新库 |

普通进入可从 `cubic-bezier(.22,1,.36,1)` 起，长遮罩可从 `cubic-bezier(.76,0,.24,1)` 起，滚动 scrub 用 linear/none 让滚动决定进度。spring 适合需要速度连续性的手势，不是所有按钮、列表、图表都必须用。循环只在表达持续状态或主题时使用，需可停；不要默认永动、全站 stagger 或强制凑够八个移动元素。

先查项目依赖与已用模式。CSS 足够就不用库；不能把原文 CDN 标签、React Bits/MCP 或安装脚本当成本次授权。既有 GSAP 与 Motion 可分区协作，但同一元素的 transform 只给一个所有者。Vue/Svelte/原生项目不因参考代码是 React 而换栈。

## 3. 配方 A：按钮驱动的案例叠卡

可执行文件：`recipes/recipes.html` 与 `recipes.mjs`。它不是 `tasteskill.dev` 组件逐字镜像；案例文字与图形自绘，无站点截图/照片拷贝。

**静态结构**：一个标题、四张说明卡、状态文本和真实 `button`。卡片不含可聚焦后代；无 JS 时四张卡全部按文档流展示。`mountExampleStack(root)` 挂载后叠放，返回 cleanup。

**状态和轨道**：

- 前景 `translateY(0) scale(1)`；第二层 `translateY(-24px) scale(.94)`；第三层 `translateY(-48px) scale(.88)`，变换原点顶部中央。后层负位移不占文档流，增强态容器上方须预留最大位移加阅读间距（示例 `margin-top:4rem`），避免叠层盖住标题。
- 点击后前景以 450ms 到 `translateY(32px) scale(1.03), opacity:0`；其他层以 550ms 补位，ease-out；结束后把退场卡放到末尾并恢复最终样式，不保留填充动画。
- 一次切换内设 `aria-disabled` 并忽略重复触发，保持键盘焦点，之后恢复；状态文本报告当前序号与标题。无 hover 依赖，Enter/Space/触屏沿同一路径。
- 非前景卡 `aria-hidden`，只让当前内容可被读到；若项目卡片要包含链接/表单，还必须对非活动卡使用项目既有 inert/焦点管理，不能照搬纯说明卡结构。
- 减少动效时直接换到相同终态；运行时切换偏好、隐藏标签页或卸载会取消动画，不能留下半透明卡。卸载恢复原始 style/语义、移除监听；重新挂载重新开始。

在原项目挂载生命周期调用 `mountExampleStack`，卸载调用返回值；SSR 只导入模块，不在服务端调用挂载。模块导入本身不读取 DOM。示例 HTML 使用模块，本机 `file://` 可能限制模块导入，需在**已存在或获授权**预览中看，不要擅自起服务来规避。

观察页的 240/450/550/650ms 多轨、三层比例及减少动效限制见 [case-studies.md 参考站观察](case-studies.md)。本配方选 450/550ms 是简化实现，不声称与参考站逐帧一致；站点在减少动效下仍报告 `200–300ms` 动画，不能据此判减少动效通过。

## 4. 配方 B：原生滚动图片开窗

示例 HTML 含无依赖 CSS 开窗：默认显示完整自绘图，只有 `@supports (animation-timeline: view())` + `prefers-reduced-motion: no-preference` + 宽屏精细指针时，采用 sticky stage 与局部 clip。触屏、窄屏、不支持或减少动效直接看到完整图，不用 JS 将正文先隐藏。

实施要点：

1. 图/内容先有固有尺寸；外框 `overflow: clip`，别无意用 `overflow: hidden` 造出 timeline 监听的错误滚动祖先。
2. 在 scene 根上命名 view timeline，子层引用它。示例从 `inset(18% 20%)` 开至 `inset(0%)`，180svh 只是可调展示参数，不是全站高度要求。
3. 小屏回文档流，正文和 CTA 在运动层之外；不得让被裁剪的区域藏住唯一动作或文字信息。
4. 允许浏览器自然滚动；不截获 wheel/touch，不以 body overflow 锁住用户，不让 scroll runway 变成空白停顿。
5. 若项目不支持 CSS timeline，保留静态页即可；不要为“所有浏览器一定动”引入未经批准的 polyfill。

完整上游 `Opening window`、`Held picture, passing captions`、`Sideways gallery`、`Receding hero` 与 `Page to page` 的 HTML/CSS/JS 原文都保留在 `recipes/motion-recipes.md`。复制这些较复杂配方时须补齐项目生命周期、语义与首屏可读性，不能直接把原文的 `html.js` 开关用于首屏隐藏正文。

## 5. 配方 C：复用真实 Stage 的 GSAP 开窗

已有 GSAP/ScrollTrigger 项目可使用 `recipes.mjs` 的 `mountOpeningScene(root)`；先读原始 `stage.js` 与 `stage.css`。`stage.css` 的 sticky 规则要求根元素有 `js` class，可在底座成功加载后加上；这个 class 只启用 scene 样式，不能顺带挂全局隐藏正文的 CSS。无依赖时它静态回退，**不会安装或加载 CDN**。

最小 markup（在项目中接入已审核底座，不把下例当安装命令）：

```html
<section class="scene" aria-label="产品工艺展示">
  <div class="scene-stage">
    <img class="scene-picture" src="/assets/authorized-product.webp"
         width="1600" height="1000" alt="产品工艺的真实说明">
  </div>
</section>
```

```css
.scene-picture { display: block; width: 100%; height: auto; }
.scene.is-live .scene-picture { width: 100%; height: 100%; object-fit: cover; }
```

```js
// 已有项目按其包管理/模块方式加载 GSAP、ScrollTrigger，以及本地 stage 底座后：
const cleanup = mountOpeningScene(sceneRoot);
// 在路由/组件卸载时调用 cleanup()；不要全局 kill 所有 ScrollTrigger。
```

本地适配使用 `Stage.scene`：hold=1，scrub=true，phone='rest'；图像从 `clipPath: inset(20% 28%), scale:1.08` 至完整图，占 timeline 前 .75，余 .25 停留。`stage.js` 的 `gsap.matchMedia` 负责宽度和减少动效切换；cleanup 对该次 matchMedia `revert` 并移出 `Stage.scenes`，不触碰其他场景。图片/字体加载后的 `Stage.ready()` 仅在页面仍挂载时刷新，异步任务需按项目取消标识防止卸载后写 DOM。

**底座限制**：原始 Stage 是页面级 IIFE，不是现成 SPA 插件。`Stage.smooth()` 注册匿名 ticker 且无统一 destroy，`Stage.split()` 不返回 SplitText 的 revert 句柄，`Stage.init()` 使用 `__scene` 哨兵。此适配不调用 smooth/split/init，只直接挂载自身 scene。别在 SPA 反复注入全局脚本；如确需这些功能，复用项目已有可清理集成，追踪实例/ticker/拆字还原，不用 `killAll()` 清掉别人的动画。

## 5.5 配方 D：Apple 式区块分级淡入上移

来源：2026-10-28 读 `apple.com.cn/mac` 线上 CSS/JS（`StaggeredFadeIn`、`animationDefaults`、`SectionHeader` 模块）得出的参数，不是逐帧录屏。它是 `recipes/motion-recipes.md`「Reveal on scroll (once)」的具体调参，区别在**按区块触发、区块内按阅读顺序错开**，不是每张卡各自观察。

| 项 | Apple 实值 |
| --- | --- |
| 初态 | `opacity:0; transform:translateY(30px)`，只在增强态挂；`html.no-js` 与非增强态直接 `opacity:1` |
| 触发 | 区块顶部到达视口 85%（`a0t - 85vh`）时**一次**播放；回滚不重放、不反向淡出 |
| 驱动 | 按时间播放，不随滚动 scrub |
| 时长 | opacity 0→1 用 900ms；位移 30px→0 用 700ms（先落位，再亮足） |
| 缓动 | `easeInOutQuad`，即 `cubic-bezier(.45,0,.55,1)` |
| 错开 | 区块头 tagline→标题→说明→链接各隔 150ms；内容卡片在区块头之后起步，按序号每张再隔 150ms |
| will-change | 接近视口才加 `opacity, transform`，播完移除 |

```css
@media (prefers-reduced-motion: no-preference) {
  .reveal-ready [data-stagger] > * {
    opacity: 0;
    transform: translateY(30px);
    transition:
      opacity 900ms cubic-bezier(.45,0,.55,1) calc(var(--i, 0) * 150ms),
      transform 700ms cubic-bezier(.45,0,.55,1) calc(var(--i, 0) * 150ms);
  }
  .reveal-ready [data-stagger].is-in > * { opacity: 1; transform: none; }
}
```

```js
// 挂载后再加 reveal-ready；返回 cleanup。区块头与卡片放同一个 [data-stagger] 下即按 DOM 顺序错开。
export function mountStaggerReveal(root = document) {
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return () => {};
  const groups = [...root.querySelectorAll('[data-stagger]')];
  groups.forEach((g) => [...g.children].forEach((el, i) => el.style.setProperty('--i', i)));
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) { e.target.classList.add('is-in'); io.unobserve(e.target); }
  }, { rootMargin: '0px 0px -15% 0px' });
  groups.forEach((g) => io.observe(g));
  document.documentElement.classList.add('reveal-ready');
  return () => { io.disconnect(); document.documentElement.classList.remove('reveal-ready'); };
}
```

用法与限制：

- 每个区块一个 `[data-stagger]`，直接子元素就是播放顺序；子项超过约 6 个时把 `--i` 封顶（如 `Math.min(i, 5)`），否则最后一张要等 1s 以上。
- 首屏区块不挂，首屏标题与主操作必须一开始可读；只用于第二屏起的介绍区块，和 [SKILL.md](../SKILL.md) 的「不要每块都 fade-up」一致：Apple 也只在营销区块头和卡片组上用，导航、表单、价格表不用。
- `reveal-ready` 由 JS 成功挂载后加上，失败或无 JS 时全部可见；减少动效直接返回，不加初态。
- 已有 GSAP/Motion 项目用其 timeline 实现同一组参数，不另加 IntersectionObserver；同一元素 transform 只有一个所有者。
- 验收：慢速滚动看区块头→卡片的先后顺序，快速滚到底再回滚确认不重放，减少动效与无 JS 确认无空白区块。

## 6. 通用质量底线

- 优先 `transform`/`opacity`；`clip-path` 与大面积滤镜也可能昂贵，不等于自动 GPU 免费。少用永久 `will-change`，结束后移除。高度/布局动画只有在内容确需、频率低且测过时局部使用，不能用“禁 height”拆坏现有无障碍组件。
- 不依赖 hover 提供唯一说明。hover 变化限 `(hover:hover) and (pointer:fine)`；触屏保留可点控件、完整标签、合适目标尺寸。低端设备可降粒子/滤镜/层数，但不删内容或业务功能。
- `prefers-reduced-motion` 必须有完整静态终态；关闭大位移、视差、缩放、自动循环，可保留必要短淡化。不是统一 `duration:.01ms`，更不是仅加速正常大幅运动。
- 首屏标题、正文和主要操作从 HTML/CSS 起可读，不让它们初始 `opacity:0` 等待 JS、observer、字体或 CDN。下方 reveal 也需成功初始化后才增强、失败恢复，不靠一行 `.js` class 假定后续脚本总成功。
- rAF/timer/observer/媒体查询/事件/WAAPI/GSAP 实例都有明确所有者，卸载、路由切换和重新进入均清理。SSR/hydration 不提前访问 window、不随机首帧、不让动画改写业务真值。
- 持续循环需有适当暂停路径，离屏/后台停止；屏幕阅读器读最终真实数值，不把每帧变化放进 live region。不发明统计结果来配动画。

## 7. 验收：不只一张终态截图

1. 先静态、键盘、触屏与真实业务路径，再启用动效；保留改前行为。用已有最小 lint/type/test，不默认 build。
2. 浏览器优先规则与 [style-migration.md](style-migration.md) 一致：先 `command -v ego-browser`，有则 ego-lite 独立 taskSpace、打印 spaceId、结束 finish；无才 Playwright。未授权不启动服务。
3. 以至少开始/中间/结束状态看动画，叠卡另测快速点击、标签页切换、返回、卸载/重挂。滚动场景逐 0/25/50/75/100% 看遮挡、裁切、可读性和结束后滚动，不能仅确认元素存在。
4. 桌面、390px 附近与项目窄屏、coarse pointer、减少动效初始/动态切换、无 JS/依赖失败均看内容和操作；静态 fallback 是正常设计，不以“没有动”一概失败。
5. 核查控制台、布局跳动、卡顿和长任务；若报“更快”须同批至少三次且差异超过平台波动，不能把一次 headless 帧间隔当真机性能结论。
6. Node 小测只验证状态与清理，不证明视觉流畅/无障碍完整合规。技能根目录下可运行 `node recipes/recipes.test.mjs`。

上游 `scripts/scenes.mjs` 是原始取样工具而非默认浏览器路线：它会自行开 Chromium，对本地文件还会起 HTTP 服务，不在此运行。它采样 0–100% 并汇总桌面/手机/减少动效，相关 `lib/cdp.mjs` 依赖已保留，可参考其取样法移植到已授权的 ego-lite/Playwright 环境。上游 `lint.mjs` 含字体/颜色等 house-style 硬禁，不能把它的失败直接视为本地项目失败。
