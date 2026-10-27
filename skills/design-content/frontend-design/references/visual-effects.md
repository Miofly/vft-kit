# 视觉效果实现库：Magic UI 与 React Bits

这是一套可检索的实现资料与移植规范，不是只列官网，也不是要求把所有效果叠上页面。用户指定复杂文字、叠卡、光束、粒子或着色器时，应完整实现其几何、状态与交互；预算用于管理同时运行的成本，不能用“少动画”代替需求。许可边界见 [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md)。

## 1. 先过许可与技术栈边界

- **Magic UI：MIT**。本地 `components/effects/` 保留全部 79 个 canonical TSX、77 篇组件 MDX、keyframes CSS（`globals.css`）与本地依赖（`lib/utils.ts`、`ui/`）。以 `components/effects/index.json` 查名称、分类、源文件、外部包版本和文档，不必联网猜实现。
- **React Bits：MIT + Commons Clause，不是 MIT**。此固定版本禁止单独、合集或移植版组件再分发；此公共 skill **不含其任何组件代码、CSS、shader 或 registry 文件**，只保留下面的能力映射与独立分析。可以在符合条款的应用/网站/产品中使用，不能把它们搬进公共组件包、技能合集或 Vue 端口。需要组件源码时在目标应用内按官方仓库 `DavidHDev/react-bits` 的 `src/ts-default/<分类>/<组件>/` 审读，并判断用途是否被许可；不下载进公共 skill。
- 现有 VFT、业务组件、主题、路由和可访问交互优先。React 源码不能直接贴到 Vue；不换栈、不替换项目按钮/弹窗、不把 Magic UI 的全局 reset/Geist/主题直接覆盖现有产品。
- 本地 `components/effects/` 是素材源，不是已装依赖的应用。检查目标的 React/Motion/Tailwind/GSAP 等真实版本，缺依赖先报告范围或使用现有等价实现；本 skill 不授权安装、起服务、构建、联网画像或部署。

## 2. 源码入口与覆盖

路径以本 skill 根为准。Magic UI canonical 为 `components/effects/magicui/<name>.tsx`；用法、props 与 keyframes 在 `components/effects/docs/<name>.mdx`（演示文件未保留，MDX 的 Usage 段即最小用法）。索引比文件名猜测可靠；上游 registry 列出的 script-copy-btn、flip-text、scratch-to-reveal、box-reveal、iphone-15-pro、arc-timeline、grid-beams 在该版本源码树不存在，本地也没有。

| 类型 | Magic UI 本地完整实现 | React Bits 官方仓库中的同类参考（不分发） |
| --- | --- | --- |
| 分字/分词、模糊、翻转、轮换、扰码 | text-animate、hyper-text、word-rotate、morphing-text、typing-animation、text-3d-flip、kinetic-text、dia-text-reveal | SplitText、BlurText、RotatingText、DecryptedText 等 |
| 列表/轨道/内容集合 | marquee、animated-list、bento-grid、orbiting-circles、dock；组合用法见对应 MDX | Stack、ScrollStack、Carousel、Masonry、AnimatedList 等 |
| 指针、磁吸、倾斜、聚光 | magic-card、lens、glare-hover、dock、cool-mode、pointer 等；精确磁吸/倾斜另按状态合同实现 | Magnet、TiltedCard、SpotlightCard 等 |
| 边框、发光、闪光、材质 | border-beam、shine-border、backlight、neon-gradient-card、shimmer-button、shiny-button、rainbow-button | BorderGlow、ShinyText 等 |
| SVG 路径与连线 | animated-beam 的真实端点测量、渐变路径；animated-circular-progress-bar | 官方仓库的路线/绘制类；本地无实现 |
| 网格/点阵/噪声/极光背景 | grid-pattern、dot-pattern、hexagon-pattern、interactive-grid-pattern、flickering-grid、noise-texture、retro-grid、warp-background、aurora-text | Aurora、Particles、Galaxy、Threads、Noise 等 |
| Canvas/WebGL/3D | particles、floating-3d-particles、icon-cloud、globe；不是它们全都用 WebGL，`index.json` 逐项列外部包 | 当前 Aurora/Particles 原生 WebGL2；其他条目可能 Three/OGL/GSAP，按固定源实际 imports 核实 |
| 滚动进度/入场/视差 | scroll-progress、text-reveal、blur-fade、scroll-based-velocity | AnimatedContent、ScrollReveal、ScrollVelocity、ScrollStack 等 |

无须复制 JS/CSS、JS/TW、TS/CSS、TS/TW 四份：Magic UI 用其 canonical TS+Tailwind，React Bits 只参考 TS-CSS 变体。声音与 Studio/工具不作为视觉组件数量；不带 Pro/premium 资产、站点照片或字体文件。

## 3. 可执行实现如何取用

### 3.1 React 项目的最短完整路径

1. 在索引查效果，读源码和对应同名 demo/MDX。`sourceImports` 是 AST 得到的实际依赖，`declaredDependencies` 是 registry 声明；两者不一致时以真实 imports 和目标版本为准。先读再复制，别把根站依赖包整套安装。
2. 只复制选中 canonical 与本地 import 闭包。`@/lib/utils` 映射 `components/effects/lib/utils.ts`（独立 `cn`），`@/components/ui/*` 映射 `components/effects/ui/*`。
3. 将路径别名和 import 改到目标现有组件。需要 `cn` 时优先目标已有函数；不要导入官网 shell、认证中间件、网络 Tweet 或网站配置。
4. 若组件使用 `animate-*`，读取 `components/effects/globals.css` 和 MDX 中 `css`/keyframes 配置，带上**需要的那段**。只有 TSX 没有对应 keyframes 的 marquee、边框或网格不是完整复刻。文件使用 Tailwind v4 语法；v3/其他 CSS 方案按目标转换，不能混语法。
5. 先把内容、按钮、布局和静态最终态接好，再启用同一套参数与时间线。SSR 先输出真实标题/数字/说明，挂载后创建 observer/canvas；随机视觉值不要造成 hydration mismatch。
6. 按下面的缺口补语义、媒体查询和清理，并用目标原来的静态检查与实际交互验收。不因源码来自成熟库就跳过这些步骤。

### 3.2 Vue/原生适配合同

许可允许时，移植的是行为而不是“把 JSX 删成 div”：

| 保留对象 | 必须等价 |
| --- | --- |
| 状态 | idle/hover/focus/pressed/dragging/settling/reduced/hidden/disposed；点击、键盘与指针走同一业务真值 |
| 几何 | 原点、边界、容器坐标、端点位置、层序、mask、视口/滚动宿主、像素比；布局改变后重新测量 |
| 物理 | 速度、阻尼/刚度、质量、插值、stagger、scrub、循环相位；不用普通 CSS fade 冒充磁吸或倾斜 |
| 生命周期 | Vue mounted/onUnmounted 或原生 mount→cleanup；持有并释放 rAF、timeout、observer、事件、Motion/GSAP、GL 资源 |
| 内容/语义 | 完整真实文本只读一次、按钮/链接保留键盘；装饰 canvas aria-hidden 且 pointer-events:none，不能罩住主操作 |
| 回退 | 无 JS/SSR、coarse pointer、低端、减少动效、GL 不可用/丢失，都保留相同信息和业务能力 |

只允许移动装饰层，不移动点击目标躲开手指。数据布局采用项目支持的 Grid/Flex，旧 WebView/项目规范收紧时遵守项目。React Bits 的端口也属于条款禁止再分发的组件，不在公共库里做“换框架绕限制”。

## 4. 深读的效果机制与参数起点

以下参数来自固定源，不是通用强制值；生产适配须针对目标字体、尺寸和设备验收。完整可运行函数保留在 canonical，不以这张表替代源码。

| 效果 | 真正机制/参数 | 交互和清理重点 |
| --- | --- | --- |
| Magic TextAnimate | children 按 word/character/line/text 切片；duration=.3s、startOnView=true、once=false；variants/container/item 的 stagger 分配 | `accessible=true` 保留 sr-only 原文并隐藏装饰片段；初始 hidden、无 JS 与 reduced 另补；中文/组合字需 grapheme 分段，不能只 `split("")` |
| Magic HyperText | 每帧按 elapsed/duration 确定已解锁字符，其余从字符集取值；duration=800ms，默认 hover 重播 | 有 rAF 取消和初始 delay 清理，但 view 分支内部 timeout 未保存；需取消、最终原文、不强制大写、focus/keyboard/touch/reduced 路径 |
| Magic Marquee | repeat=4 的同内容轨道，CSS 默认 duration=40s、gap=1rem；横/纵和 reverse | pauseOnHover 默认 false；复制组要避免 SR/Tab 重复，补 focus/显式暂停与减少动效，不只 hover 停 |
| Magic MagicCard | 指针减容器 rect 得局部坐标；gradientSize=200；orb 用 spring 250/30/mass .6，glowSize=420/blur=60 | 原有 pointerout/blur/visibility 复位并移除监听；无显式 reduced/focus 替代，不把光当唯一焦点反馈；触屏不追随 |
| Magic AnimatedBeam | 从/到元素中心相对容器得坐标，二次曲线；curvature=0、pathWidth=2、duration=5s、repeat=Infinity | 容器 ResizeObserver 有 disconnect；同尺寸内部重排需重测端点，动态减少动效显示静态路径；SVG 装饰语义另加 |
| Magic Particles | Canvas2D 粒子位置/透明度/边缘渐隐，加 pointer 吸附插值；quantity=100、staticity/ease=50、size=.4 | 有 rAF/resize timeout/mousemove 清理；未见 offscreen/reduced/后台暂停；初始化重复生成粒子问题见下节，不照抄成本假设 |
| Magic Globe | `cobe` WebGL，phi 每帧+.005、pointer delta/1400 与 spring；默认 mapSamples=16000、DPR=2 | unmount destroy+移除 resize，但零延迟 opacity timeout 未取消；无本地 shader，属于外部 cobe，不声称自带完整 GLSL |
| Magic scroll-progress/text-reveal | Motion scroll progress 映射 scaleX/opacity；容器、offset 决定范围 | 保留原生滚动；正文可读，进度条不要成为唯一导航或读数；reduce 不应留下低透明文字 |

React Bits 的知识提炼不含复制实现：

- **SplitText**：固定版使用 GSAP、ScrollTrigger、SplitText 和 `@gsap/react`，不再假设旧版依赖。delay=50ms、duration=1.25s、默认按 chars、rise、view；等字体后测分行；挂载判断减少动效，退出会取消 rAF、移除 pointer/click、kill queued/busy/该元素 trigger 并 revert 拆字。适配必须保持这些回收，动态偏好变化另验，不以存在一次 `matchMedia` 宣称全程覆盖。
- **TiltedCard**：当前 TS-CSS 为原生 React/DOM，不强制 Motion；rotateAmplitude=12°、scaleOnHover=1.05、perspective=800、smoothness=.6，有 pointer/focus/键盘、全局拖动与 deviceorientation，卸载取消帧/observer/全部监听。陀螺仪权限与无传感器回退、减少动效动态切换仍须目标设备验证；不用一张 rotate CSS 截图冒充交互。
- **Stack**：可见层默认4、fan、tilt=30、threshold=90、autoplay=false；状态包含 drag→send-to-back→settling，键盘和顶卡语义已存在；unmount 停 MotionValues、清 idle timer、全局拖动监听。要保留身份稳定与快速操作政策，不因效果叫“stack”就退化成顺序轮播。
- **ScrollStack**：itemDistance=100、stackDistance=24、stackPosition=15%、baseScale=.8、itemScale=.05、holdDistance=200；当前原生实现，不是默认 Lenis；默认 smoothScroll=true 注册非 passive wheel。为保留项目原生滚动，按需要设置 false 并验证，不抄默认 wheel 接管；清理 rAF/glide、ResizeObserver 与事件。
- **Aurora/Particles**：该 SHA 是原生 WebGL2 和完整内嵌 shaders，不是旧文章所说的 OGL；Aurora speed=1、layers=1、blend=.5；Particles count=200、spread=10、speed=.1，支持多种交互/连接。已见 reduced 初始快照、visibility/IntersectionObserver 暂停，以及取消 rAF、断 observer、删 program/buffer/VAO。未见显式 webglcontextlost/restored 处理，不能宣称上下文恢复已安全；公共 skill 不复制其受限 shader。

## 5. 已知源码缺口：成熟不是自动安全

以下是固定文件静态审读发现，不是运行漏洞/性能实测结论；移植时在目标实现修，本地副本保持原样以便对照。

| 位置（Magic UI canonical 内） | 现象与所需补齐 |
| --- | --- |
| `particles.tsx` 的 initCanvas/resizeCanvas/drawParticles | resizeCanvas 已清空并生成 quantity，随后 drawParticles 再追加 quantity；初始数组可能为 2×quantity。应在目标确保初始化只建一次，并断言实际粒子数；本轮未运行 Canvas 验证 |
| `hyper-text.tsx` view observer 回调 | 创建 delay timeout 没保存/清掉；离开或卸载可残留回调。加所有者与取消；已有 rAF cleanup 不代替 timeout cleanup |
| `globe.tsx` effect | `setTimeout` 读 `canvasRef.current!` 未回收；卸载/重挂要防空 ref。需要粗指针/键盘、reduce、context lost、离屏成本策略 |
| `text-animate.tsx` | initial hidden 且未见局部 useReducedMotion；主标题不能依赖 JS 显示。按字切 UTF-16 会拆 emoji/组合字符；改目标分段不改变真实文本 |
| `marquee.tsx` | 原样重复 children 四次，未将克隆标 aria-hidden 或从 Tab 序列移除；补副本语义、暂停按钮、focus-within 与 reduced |
| `magic-card.tsx` | 指针 glow 有全局复位，但没有键盘 focus 的等价静态可视焦点，也无局部 reduced 关闭追随；可保留边框而关闭随动 |
| `animated-beam.tsx` | 只观察容器尺寸，无法保证端点自身同容器内移动时更新；连线需静态说明/读序，光束不能伪造数据传输成功 |

无 `useReducedMotion` 字面串不证明库绝无上层策略，存在它也不证明所有路径合规。要看组件、调用环境和实际设备。循环 shader/光束、noise、blur、box-shadow 不是只用 transform 就“免费”；背景必须留出主内容对比和点击层。

## 6. 组合配方：不削弱指定效果，也不互相抢资源

### A. 主题文字 + 案例叠卡 + 信息光束

- 字体/字号来自主题和现有资产；选 `TextAnimate` 的 by=word/line 与项目已有中文分段，最终完整标题始终可访问。若要真实扰码，则用 HyperText 机制并修其定时器/原文/输入触发，不能用 blur 代替 scramble。
- 卡片沿 [motion.md](motion.md) 的可操作叠层状态实现：前后卡有稳定身份、快速点击政策、键盘路径、终态复位。后层负位移须预留最大位移+阅读间距，不能盖标题。
- 在端点真实关联时接 AnimatedBeam，布局/字体/内容变化后重新测路径，cycle 与业务真实状态分离。卡片内容层高于装饰 SVG，beam pointer-events:none；减少动效保留静态连线/当前卡，而不是删除案例。
- 一个模块只有一个 transform 所有者。卡片 Tilt 与进退场若都要，应拆外层布局/内层倾斜，不能让两个系统覆盖同一 transform。

### B. 大幅渐变/极光 + 局部聚光 + CTA 闪光

- 背景选一种连续运动主场；Magic MIT 路线可从 warp/noise/grid/particles 组合并读完整源码，特定 React Bits shader 只能在许可允许的目标应用取用，不能把 CSS 渐变冒充要求的流体/极光数学。
- CTA 保留项目按钮与真实 disabled/loading/focus，装饰 shimmer 是伪元素/独立层；不拦 pointer、不重复业务按钮。聚光仅局部指针增强，焦点有静态描边；触屏不要求 hover 才看见文字。
- 颜色、亮度和 blur 按内容测对比，必要时用平静底层/遮罩，不能把标题放在每帧变亮的高频区。pause/reduced保留完整静态构图，不用一片空白替换背景主体。
- 限制多张高 DPR canvas 与大 blur 同时运行；低端改分辨率/层数/采样率时标“性能档位”，用户要求同效果时先测不劣再采用，不擅自降质。

### C. 3D/粒子产品舞台 + 滚动叙事

- 先定义对象、坐标、相机、光/材质、粒子密度和滚动关键帧，再接原生 scroll progress；wheel/touch 不被锁死。每个停留阶段必须有新信息，不靠超长 runway拖时长。
- Shader 是实现的一部分；合法使用时保留顶点/片元、uniform、混合方式、DPR/resize和错误处理，不只复制 JSX。Magic Globe 的 shader 在外部 cobe 包；React Bits shader未分发，不能写“本地完整GPU库”。
- WebGL创建失败或上下文丢失时暂停帧并显示同主题的静态图/DOM信息；context restored需重建program/buffer/texture/uniform，资源释放后不能继续 draw。
- Three 场景撤销时逐个 dispose geometry/material/texture/render target，释放控件、监听和renderer；OGL/原生GL对应 delete buffers/programs/textures/VAO、解绑observer和帧。隐藏标签页/离屏暂停，回来不重复建立第二条循环。

## 7. 验收与证据分级

- `tests/integration.test.mjs` 核对索引到文件、本地 import 闭包；设置 `TYPESCRIPT_PATH` 指向现成 TypeScript 模块时另做 TS/TSX 转译语法检查。它不安装、不联网、不起服务。
- Transpile 只证明语法可转换，不证明类型、依赖版本、React渲染、shader编译、视觉/a11y或移动性能。未运行别写“可直接上线”。
- 真验收用已有授权预览，按 [motion.md](motion.md) 浏览器规则，至少桌面/窄屏、键盘/触屏、初始与动态 reduced、无JS、失败/空/加载、卸载重挂/快速输入、后台/离屏、WebGL失效；记录开始/中间/终态和控制台。
- 字体另核覆盖字符、字重、真实载入、CLS、失败fallback；不能动效拆字改变标题、读序或把真实数字交给插值替代。
- 本轮仅源码/许可/索引与静态小测，没有安装依赖、启动服务、运行组件浏览器、模型、build/commit/push/部署。不要把先前 Taste 自绘配方浏览器通过算成 Magic/React Bits 组件运行通过。
