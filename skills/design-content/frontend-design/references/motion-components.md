# 动效组件实施：语义先行、按任务取源码、保留宿主技术栈

本页是实施规范，不是“看起来会动就完成”的组件目录。可复制的 MIT 原码在 `components/motion/`（`core/` 33 个组件，`hooks/`、`lib/utils.ts` 为闭包，`docs/<name>/page.mdx` 为参数与用法；alias `@/hooks|@/lib` → `components/motion/hooks|lib`）。Animate UI 受限原码**没有打包**，只提供独立审读规范和已许可产品的官方包接入路线。许可见 [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md)。依赖：`react ^18`、`motion ^11.12.0`；部分组件另需 `react-dom`、`react-use-measure ^2.1.1`、`lucide-react`；`cn` 需 `clsx` + `tailwind-merge`。不自动升级到 Animate UI 的 motion 14。以下相对路径以本 skill 根为准；链接直接指向落盘文件。

## 1. 选型和分层

1. 先找宿主已有的 Button、Accordion、Tabs、Dialog、Tooltip、DropdownMenu。权限、校验、焦点、关闭拦截、异步状态、埋点属于业务语义层，不交给动画回调。
2. 信息状态变化才加动效：新增/离开、层级展开、当前项移动、读数变化。按钮旁装饰和滚动指示器不能代替 loading/error/success 文本。
3. **headless 语义层**负责键盘、ARIA、受控状态、焦点圈定/返还、Portal/Teleport、背景隔离和滚动锁；**装饰动画层**只读状态，不能重复注册 Escape、外点关闭或 body 锁。
4. React 项目可从 MIT 原码复制所需闭包；先改目标副本的 `@/` alias，本地副本保持原样以便对照。Vue/VFT 项目保留已有组件、权限指令、事件和 Teleport：使用 Vue Transition/CSS 或项目已装的 Vue 动画工具实现状态效果，**不把 React hooks/JSX 直接当 Vue 代码**。Vue 2.7 也不能直接消费需要 Vue 3.5 的包。
5. 动画值统一从项目 token 读取。建议新页面先用 opacity + 轻位移；大面积 blur、逐字拆分、磁吸和持续循环是可删装饰，不应用于 CRUD 表格主信息。参考下表的值是起步建议，不是上游全部默认值。

| 任务 | 原码入口 | 参数/状态 | 依赖与必须保留的语义 |
|---|---|---|---|
| Hero 标题、短提示分段入场 | [text-effect.tsx](../components/motion/core/text-effect.tsx)；[文档与示例](../components/motion/docs/text-effect/page.mdx) | `children:string`、`per`、`preset`、`trigger`、`delay`、`speedReveal`、`speedSegment`、两层 `variants/transition` | `react`、`motion/react`、`lib/utils.ts` → `clsx`/`tailwind-merge`；保留真实 heading 和完整读屏文本 |
| 内容进入视口 | [in-view.tsx](../components/motion/core/in-view.tsx)；[文档](../components/motion/docs/in-view/page.mdx) | `viewOptions`、`once`、`variants.hidden/visible`、`transition`、`as` | `react`、`motion/react`；不是业务懒加载/权限判断；无 JS 时重要内容仍可见 |
| KPI 数字翻滚 | [sliding-number.tsx](../components/motion/core/sliding-number.tsx)；[文档](../components/motion/docs/sliding-number/page.mdx) | `value:number`、`padStart:boolean`、`decimalSeparator:string` | `react-use-measure`、`motion/react`；金额精度在数据层完成，不交给动画 |
| 卡片/项目列表错峰 | [animated-group.tsx](../components/motion/core/animated-group.tsx)；[文档](../components/motion/docs/animated-group/page.mdx) | `preset`、`variants.container/item`、`as`、`asChild` | `react`、`motion/react`；保留 `ul/li`、稳定业务 key 和虚拟列表策略 |
| 图卡到详情的形变 | [morphing-dialog.tsx](../components/motion/core/morphing-dialog.tsx)；[文档](../components/motion/docs/morphing-dialog/page.mdx) | `transition`、`layoutId`、Context 内 `isOpen`；Title/Description/Image/Close 子组件 | `react-dom`、`lucide-react`、`hooks/useClickOutside.tsx`、utils；不是合规 Dialog 替代品，缺陷见 §3 |
| 桌面 CTA 磁吸 | [magnetic.tsx](../components/motion/core/magnetic.tsx)；[文档](../components/motion/docs/magnetic/page.mdx) | `intensity=.6`、`range=100`、`actionArea=self/parent/global`、`springOptions` | `react`、`motion/react`；只在精细指针启用，真实 button/a 保留键盘及触控 |
| 阅读进度条 | [scroll-progress.tsx](../components/motion/core/scroll-progress.tsx)；[文档](../components/motion/docs/scroll-progress/page.mdx) | `containerRef`、`springOptions`、`className` | utils、`motion/react`；不是上传/任务 progress；需明确实际滚动容器 |
| FAQ 折叠 | [accordion.tsx](../components/motion/core/accordion.tsx)；[文档](../components/motion/docs/accordion/page.mdx) | `expandedValue`、`onValueChange`、Item `value`、`variants`、`transition` | utils、`motion/react`；原码只有部分语义，优先宿主 Accordion |

## 2. 动效与生命周期契约

### 文本 TextEffect

- `per=word` 默认以空白拆分；`char` 还调用 `split('')`，不是 Unicode grapheme 分段器。中文无空格会变成一个 word；emoji、组合音标可能拆坏。需要逐字时在目标实现使用 `Intl.Segmenter`，不修改保真源码，也不要把中文按英文词数估算时长。
- 默认 `preset=fade`，也有 `blur/fade-in-blur/scale/slide`。默认 stagger 为 char `.03`、word `.05`、line `.1` 秒，除以 `speedReveal`；段时长 `.3/speedSegment`。两个 speed 必须有限且 `>0`，不能用 `0` 表示停动画。
- `trigger=false` 通过 AnimatePresence 退出并卸载整个文本，不是“暂停但保留正文”。重要标题不能因此消失。`line` 按显式换行而非视觉换行分段。
- word/char 分支有 `sr-only` 完整文字，动画片段 `aria-hidden`；line 分支不隐藏、也不额外提供整句。不能再无条件套一层读屏全文造成重复播报。容器 `as=h1/h2` 应与页面纲要一致。
- `onAnimationComplete` 只用于装饰后处理；多段、退出和中断均可能触发，不可把它当请求成功、路由跳转或解锁权限信号。
- 原码没有 reduced-motion 分支。减少动态时直接渲染完整静态文字，并禁用拆分/延迟/blur；只设 duration=0 仍会有分段结构和初始隐藏问题。

### 入视 InView

- `useInView(ref, viewOptions)` 与组件独立 `once` 不是同一配置。原码 `once` 在**任意**动画完成时设 `isViewed=true`，没有检查完成的是 hidden 还是 visible；初始隐藏动画也可能使它提前锁为可见。需要一次性入场时优先目标副本采用 observer 的 once 语义，或仅在 visible 完成时锁存。
- 默认 hidden opacity=0，SSR 静态 HTML 可能先不可见，不能给关键正文、导航或首屏 LCP 包一层后不提供静态退路。`as` 虽声明 ElementType，内部却按 `motion[as]` 索引，不能假定任意自定义组件都能用。
- 进出视口不应反复重触发网络请求。滚动容器、`root`、`margin`、`amount` 跟业务布局一致；嵌套容器要在目标环境验证。

### 数字 SlidingNumber

- 每位渲染 0–9 共十个候选字形，测量高度后做最短环向位移。默认 spring 为 stiffness `280` / damping `18` / mass `.3`。`padStart` 只是小于十的整数补一位零，不是任意长度 format。
- `Math.abs(value).toString()` 再按小数点切分；不会保留 `1.20` 的尾零，科学计数法、NaN、Infinity、超安全整数、负零都不适合作为未经检查的输入。它不是 Intl.NumberFormat、Decimal 或金融舍入器。
- SSR/首次测量前数字候选均不可见；十个数字也未设置 `aria-hidden`。实施时让可访问树只有一个格式化静态值，翻滚层整体隐藏；容器预留 tabular-nums 和高度，失败时显示静态值。
- 值更新要合并高频流，避免每个采样都重做十位测量。目标实现明确中断策略“向最新值收敛”，不要排队播完全部旧值。减少动态时直接显示最新静态值。

### 列表 AnimatedGroup

- 默认 container stagger `.1s`，item 默认 opacity `0→1`；preset 还可加 slide/scale/blur/blur-slide/zoom/flip/bounce/rotate/swing。
- `asChild` 在这里是**每项 wrapper 的 ElementType**，不是 Radix 的“合并唯一子节点”布尔开关。默认额外包 div；列表需用 `as=ul`、`asChild=li`，table/tbody/tr 不能随意包 div。
- 原码 child wrapper 用 index 作为 key，且没有列表退出 AnimatePresence；排序、分页、筛选、流式插入不可直接假定稳定身份/离场动画正确。复制到目标后改业务 key，或保留宿主 TransitionGroup。
- 不要同时给整页 InView、整组 AnimatedGroup、每个 TextEffect 都设置独立 delay。选一个主节拍。长列表上限只动首屏少量项，虚拟化节点不能被大量 wrapper 破坏。

## 3. 交互组件已知缺陷：不可照抄后声称无障碍完成

### MorphingDialog 是视觉参考，不能替代成熟 Dialog

源码证据均在本地 [morphing-dialog.tsx](../components/motion/core/morphing-dialog.tsx)。

| 已有实现 | 缺口与目标修法 |
|---|---|
| Provider 有 context `triggerRef`；Trigger 接独立可选 `triggerRef` prop | Trigger 没有默认接 context ref，Content 返焦使用的可能始终为空。使用宿主 Dialog 的 trigger/return-focus；不要声称默认已返焦 |
| Content `aria-labelledby=motion-ui-morphing-dialog-title-*` | Title 没有对应 id；Description 实际 id 为 `dialog-description-*`，与 Content 引用不符。目标实现必须令每个 IDREF 指向真实、唯一节点 |
| 原生按钮支持 Enter/Space；Content 有 Escape、Tab 首尾循环 | querySelectorAll 不排除 disabled/隐藏节点，只在打开时取一次；异步内容/零可聚焦项/嵌套层/外部焦点会破坏循环。用既有焦点作用域，空内容容器应可程序聚焦 |
| `createPortal(document.body)` 在 mounted 后执行，避开服务端 document | 服务端只输出 trigger，打开态/Teleport 目标/首帧布局需核对；Portal 不等于焦点陷阱或背景 inert |
| 打开时 `body.classList.add('overflow-hidden')` | effect 没有开态卸载清理；Content 往往在关闭后直接卸载，不会经过 `else`，可能留下 body 锁且不返焦。也不保存先前 class、不支持嵌套计数/滚动位置恢复。复用宿主锁管理器 |
| keydown 和 useClickOutside 监听器有卸载移除 | 锁清理仍然缺失；document Escape 未限定顶层开态，不能把监听器移除等同全部副作用清理 |
| MorphingDialogTrigger 渲染 button | 无显式 `type=button`，表单里可能触发 submit。目标副本要补 type，同时不能在 button 内嵌 button/a |

生产路线：先保留 VFT/宿主 Dialog（现有 title、description、before-close、确认异步、权限、Teleport、层级管理）；将图片/标题的装饰变换绑定 open 状态。关闭发生时立刻更新业务状态、停止输入；离场只延缓视觉移除，不延缓权限撤销或滚动解锁责任。可禁用形变但不能禁用关闭。不要再挂一套全局 Escape/body 锁。

### Accordion 只实现单开折叠，不是完整 headless Accordion

- button 有 `type=button` 和 `aria-expanded`，但无 Header 结构、trigger/content ID 关联、panel label/region；方向键/Home/End 导航也未实现。`aria-orientation` 在普通 div 上不构成完整 widget。
- `expandedValue!==undefined` 才受控；**只传 `onValueChange` 监听而不传 value，内部状态不会更新**，因为 setter 只在没有回调时调用。目标中应明确受控并同步 value，或修复目标副本 uncontrolled setter 与通知并存。
- 折叠退出时 motion.div 暂留 DOM，没有 inert/焦点迁移；含输入框时关闭前将焦点移回 trigger，退出面板立即 inert。唯一 value 必须稳定，不用数组 index。
- height:auto/opacity 动画只负责视觉。可变高度、图片晚加载、快速开关、校验消息、退出中再打开都需测试；减少动态时直接切换可见/不可见。

### Magnetic 和 ScrollProgress 的范围

- Magnetic 每个实例在 document 注册 mousemove；self/parent 只是 hover 门控，不是局部事件绑定。卸载会移除 mousemove 和 parent enter/leave，但大量实例仍是全局监听/逐帧布局测量开销。
- `range>0`、`intensity` 有限；actionArea 运行时切换到 self/parent 不保证重置先前 global hover。切换模式或减少动态时明确归零/取消订阅。
- 磁吸只在 `(hover:hover) and (pointer:fine)` 且非 reduced-motion 开启；触控无等效 hover，不能阻止默认滚动，也不能让点击目标逃走。键盘 focus-visible 不漂移；焦点环和命中区始终清楚。
- ScrollProgress 使用 `useScroll({container:containerRef, layoutEffect:Boolean(containerRef?.current)})`，默认 spring stiffness `200` / damping `50` / restDelta `.001`；内部没有 target/offset API，不要传不存在的参数。默认没有 fixed/sticky，要由布局决定定位与 z-index。
- 进度条纯装饰 `aria-hidden=true`；若确需读屏进度，提供低频更新且有正确 min/max/value 的独立语义。空文档、嵌套滚动、方向切换、路由卸载和 reduced-motion 的“无弹性直接读进度”都要覆盖。

## 4. Animate UI：官方包产品内使用，不分发受限实现

固定 SHA 的 React 包并非只用 Radix，也有 Base UI、React Aria；Vue 包真实存在，使用 Vue 3 + Reka UI + Motion for Vue。其原码和移植版均未放进本 skill。React 包 `@animate-ui/react@2.3.0`（React 19、Motion 14，Radix 1.6 / Base UI 1.8 / React Aria Components 1.21 按需 peer）；Vue 包 `@animate-ui/vue@2.3.0`（Vue 3.5、motion-v 2.8、reka-ui 2.11）。以下是独立状态规范；受限原码未打包，不构成实现承诺。

### 框架与依赖边界

| 路线 | 固定版本声明 | 入口形状 | 不能混用的部分 |
|---|---|---|---|
| React 2.3.0 | React/ReactDOM `^19`、motion `^14`；Radix `^1.6` / Base UI `^1.8` / React Aria Components `^1.21` 按家族选择 | `@animate-ui/react/primitives/radix-ui/accordion` 等子路径；必须先核对实际安装包 exports | 不拿 MP 的 React18/motion11 依赖当兼容证明，不混入另一家族的 Context/Portal/Trigger |
| Vue 2.3.0 | Vue `^3.5`、motion-v `^2.8`、reka-ui `^2.11`；floating-ui/vue、vue-input-otp、shiki 按组件 | `@animate-ui/vue/primitives/reka-ui/accordion` 等子路径 | Root/Trigger/Portal 名称和 `v-model` 与 React不同；不是 Vue2 插件，也不把 Vue TS render 函数当 TSX |

以上只描述上游声明，不自动安装、不运行 CLI。宿主已经有同等组件时，保留它们，仅采用状态规范；只有许可证适用于实际产品、且技术栈匹配时才消费官方包。Base UI/React Aria 的 menu、modal、selectedKey API 与 Radix 不同，不能全局替换名字后编译。

### 五组同构交互的执行契约

| 任务 | React/Radix 状态与参数 | Vue/Reka 对照 | 焦点、离场、中断与检查 |
|---|---|---|---|
| FAQ / 设置分组 Accordion | Root `type=single/multiple`、`value/defaultValue/onValueChange`，Item `value`；Content `transition/exitTransition/forceMount/asChild` | Root 的 modelValue/update 与 Reka 原语；Content 读取 item open，上层 ReducedMotionConfig；不是手写按钮猜状态 | Header/Trigger/Content 来自同一语义家族；离场面板 inert；single/multiple 不能混 value 类型；焦点在 panel 内时关闭须返 trigger |
| Tabs 面板与移动指示器 | `value/defaultValue/onValueChange`；List `transition`，Content `transition/exitTransition` | `modelValue`；List `asChild` 时禁用自动 indicator；Content 的 leaving/waiting 状态独立于 active | 当前面板先离场再入场，高度平滑；等待项 hidden、离场项 inert，快速 A→B→C 最终只 C 可交互；方向键、手动激活和 RTL 遵循 headless 层 |
| Dialog | `open/defaultOpen/onOpenChange`；Overlay/Content `transition/exitTransition`，Content `from` 方向；Title/Description/Close/Portal 保留原语 | `DialogRoot` 等 Reka 导出；Content/Overlay 经 modal 适配层 | 开态聚焦/陷阱/背景隔离来自 Radix/Reka，不是动画层自造。退出后返 trigger，但用户已主动移焦到别处不强抢；必测开态卸载/嵌套/路由离开 |
| Tooltip | Provider 延迟；Root `open/defaultOpen/onOpenChange`、`followCursor/followCursorSpringOptions`；Content `transition/exitTransition`，Portal `forceMount` | Reka Root/Trigger 注入 follow-cursor；Content 使用 Reka transform-origin | 键盘聚焦也必须触发；tooltip 不放可操作按钮。hover暖启动和跟随光标只装饰，touch 不依赖它传达信息；Portal forceMount 不代表关闭内容仍可交互 |
| DropdownMenu | Root open；Content 与 SubContent 各有 `transition/exitTransition`；checkbox/radio 与 ItemIndicator 保留受控状态 | Reka 菜单工厂；根 Content returnFocus=trigger，SubContent returnFocus=none | roving focus、typeahead、Escape、子菜单方向来自 headless 层。关闭命令只执行一次；菜单→Dialog 焦点交接不能先返 trigger 再抢到弹窗；禁用项不触发操作 |

### reduced-motion、SSR 和清理的真实边界

- 两端 utility 都有 token、tempo、reduced-motion 配置；策略 `user/always/never`。React 用外部 store 监听 matchMedia，SSR snapshot=false；Vue 在 mounted 后读取媒体查询并在卸载移除 change 监听。初始服务端和客户端偏好切换必须验证，不能称“SSR天然一致”。
- Disclosure 的减少动态分支设 instant；Anchored 的 reduce 分支取消缩放，但仍可能保留 opacity 过渡；Modal 的 reduce 分支去掉位移/翻转，**不等于所有过渡 duration=0**。产品“完全无动画”要求还需显式零过渡并检查手写 CSS/WAAPI。
- Tabs internal 有 ResizeObserver、MutationObserver、timer 与动画跟随句柄；代码有对应 disconnect/clearTimeout 路径。只能据此说“存在清理实现”，尚未运行 StrictMode、快速换页、resize 中卸载等实际检查。
- Vue modal 入场使用 mounted 内 requestAnimationFrame，所审片段未见对该入场 rAF 的显式取消；需要在目标产品加卸载时序测试。菜单工厂/Portal 存活跨离场，不能把业务 closed 与 DOM removed 当同一时刻。
- 焦点返回存在特殊处理：当关闭时焦点已位于内容外的有效元素，阻止默认返焦，避免动画结束后偷焦点；外点事件也识别“按下时还未打开”的输入，避免同一次点击打开后立即关闭。保留原语事件和调用方的 preventDefault，不另加 document click 抢跑。

## 5. 可执行组合 recipes

### A. Landing：一个主节拍，不做整页特效叠加

1. 先静态完成 Header、h1、CTA、截图和响应式布局；内容在 SSR HTML 可读。
2. 标题可用 TextEffect 的 fade/word；中文短句用整句或 grapheme 安全方案。delay 从 0 起、speed 参数为正；动效层不得生成第二个 h1。
3. 卡片保留 ul/li，用 AnimatedGroup 只动首屏 3–6 项；container stagger 从 `.06–.1s` 起。禁止每张再套一次入视延迟。
4. CTA 真实 button/a 不改行为；可选磁吸只在 fine pointer 开启，intensity 从 `.15–.25` 起、range 从 `80–120` 起。减少动态/触控直接静态。
5. 验收：Tab 顺序与静态页一致；无JS/reduced-motion 下标题/CTA可见；中文/emoji不破；手机不横向溢出；首屏动画不推迟点击和 LCP。

### B. FAQ：语义折叠 + 内容高度

1. 复用宿主 Accordion，把稳定业务 id 作为 value；受控状态在父层同步，不能只挂回调。
2. headless 层先实现 header button、expanded/controls/labelledby、方向键和禁用规则；再按 expanded 添加高度/opacity 动画。
3. Content 中若有链接/表单，收起前检查 activeElement；在视觉退出的第一帧撤销交互/inert，结束后移除。
4. reduced-motion 直接切换；动态图片晚到时重新测量，不能靠固定 max-height 截正文。
5. 验收：按键开关、快速连点10次、全部收起、焦点在panel内收起、内容异步增长、两个Accordion实例互不串状态。

### C. 数据页：数字反馈不影响精度和刷新

1. 用业务数值/Decimal产生精确结果，用项目 formatter 输出静态字符串；只给有限安全范围的展示数值加翻滚。`1.20`、千分位、币种、NaN/错误态不强塞给 SlidingNumber。
2. 保持一个可访问的完整值，翻滚层 aria-hidden；不把十个候选数字放进 live region。流数据只按业务刷新节奏更新，不逐帧公告。
3. 调整数字容器固定行高、tabular-nums和预留宽度。测量前、SSR、resize或字体加载失败显示静态读数。
4. 验收：9→10、99→100、0→负数、小数位变化、快速更新、窗口缩放；值最终一致，reduced-motion没有滚轮，财务舍入测试仍在数据层通过。

### D. 列表卡片 → 详情 Dialog

1. 卡片只有一个主操作；读取权限和详情请求仍走原业务代码。先用成熟 Dialog 验证 open/close、loading/error/empty、提交中关闭规则。
2. 提供真实 Title/Description ID；触发按钮 ref、return-focus目标、焦点圈定与层级锁由宿主维护，避免 MP 原码的已知引用/解锁缺陷。
3. 动画只给图片/表面用共享身份；离场中同一项再打开应取消旧退出，数据请求取消或校验请求代次，不能回写上一条详情。
4. Vue 保留 Teleport 目标和 scoped 样式可达性；SSR 先输出关闭态，mounted后才测量；跨滚动容器的几何形变要用实测坐标，不直接复制React layoutId。
5. 验收：键盘打开/闭合、Escape、外点、触发器卸载、双弹层、表单按钮不误submit、开态路由切换、滚动位置和原body样式恢复、reduced-motion仍可完整操作。

### E. Tabs + 菜单：视觉退出不得延长权限和交互

1. Tabs 的激活 value 与路由/权限保持单一来源；移除权限时立刻切到合法项。离场面板 inert，等待面板 hidden；有昂贵表单时明确 keepMounted 与未保存数据策略。
2. List indicator 只是当前项装饰，不能作为唯一选中标识；选中项还有对比度/文本状态，focus-visible不能被indicator盖住。
3. 菜单操作更新业务状态一次；会打开Dialog的菜单项遵循原组件焦点交接，取消菜单默认返焦只在确知新焦点归属时做。
4. 验收：A→B→C快速切、RTL/纵向箭头、禁用项、typeahead、菜单子层Escape只关顶层、点击已关闭触发器、退出中点击另一个控件不被偷焦点。

## 6. 实施验收门槛

- **状态**：default 与 controlled 两条路径、回调只有一次、快速反转朝最新状态收敛；视觉结束不决定业务成功。
- **SSR**：无 window/document 顶层访问；初始文本/数字有静态退路；hydration不靠随机id；Portal/Teleport目标一致。
- **键盘与焦点**：Tab/Shift+Tab、Escape、方向键、Home/End按widget规范；焦点圈定与返还只归一个管理者；所有 aria IDREF 可解析。
- **减少动态**：系统偏好初始开启和运行中切换都测；循环/磁吸/自动滚动停掉；关动画后状态仍有可见反馈。
- **触控**：无 hover 才可理解的信息；不劫持页面滚动；44px左右触控命中区按项目要求校准，不因装饰位移缩小。
- **清理**：卸载后无遗留媒体监听、全局鼠标/键盘监听、observer、timer、rAF、动画订阅、body锁或屏外可聚焦节点。
- **验收口径**：源码blob相同、静态导入闭包和TS转译通过，仅证明保真/路径/语法；不等于类型正确、依赖已装或浏览器全库运行通过。没有运行的写“未验证”。
