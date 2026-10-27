# 组件系统：把设计方向接到可工作的状态与布局

源码在本 skill 的 `components/ui/`（shadcn/ui 的开放源码、组合式 primitive、语义 tokens 与完整 blocks），MIT 许可见 [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md)。不安装新插件、不自动执行 CLI、不把项目整体换成 shadcn。

## 1. 先选落地路径，不先选库

1. 查项目现有组件、设计 tokens、表单/路由/权限/图标/动效设施。已有 VFT 项目继续用 VFT，不因为这份参考换成 shadcn；业务表格沿用项目规定模板。
2. Vue、原生小程序和 React 的源码不能直接互抄。非 React 项目借鉴语义、状态、组件拆分与布局关系，在本框架既有组件上实现；不为风格强装 React。
3. 新 React 项目或项目已经采用 shadcn/相容 primitive，才评估引入必要组件。先盘点实际 React/Tailwind/primitive 版本与 alias，用户未授权时不运行 `npx shadcn`、不安装包、不覆盖 CSS/组件。
4. 对每项需求写“现有组件 → 必要定制 → 状态/键盘/数据接口 → 验收”。权限、服务端验证、路由守卫、焦点回退不是视觉负担，不准为简化演示删除。
5. UI UX Pro Max 决定候选视觉语言；本层承担结构、语义、状态与组合；动效层增强反馈与叙事，不能接管表单正确性或破坏 primitive 的焦点/弹层行为。

## 2. 开放代码与 registry：有源码，不是黑盒

shadcn 的价值不只是默认外观，而是把可修改源码放在项目中：组件用 `React.ComponentProps` 透传底层 API，`data-slot` 标记解剖位置，`data-state`/`aria-*` 驱动状态，`cva` 管理变体，语义 CSS 变量统一主题。可以调整视觉，不必 fork 整套框架；也因此引入后项目要对改动和升级负责。

固定源 commit `8f04138777c1b6996e709993362a7b0a12888ecf`，只选 new-york-v4 一套完整 UI，不拼接其他 base 的同名组件。

本地布局：`components/ui/ui/`（61 个 UI TSX 与 `_registry.ts` 依赖表）、`hooks/`、`lib/`、`blocks/`（dashboard-01、sidebar-07、login-01 与 `_registry.ts`）、`examples/`（RHF 与 Next 复杂表单、combobox）、`packages/react/`（message-scroller、use-render 源）、`globals.css`/`tailwind.css`（主题 token 与 data-state 动画）、`docs/`（安装、主题、Tailwind v4、React 19、表单与 12 篇组件文档）。

外部依赖（上游同版本声明，不是安装建议，以目标 lock 为准）：React/React DOM `19.2.3`；Tailwind CSS `^4.3.0`；`tw-animate-css ^1.4.0`（data-state 动画）；`radix-ui ^1.4.3`；`@base-ui/react 1.6.0`（combobox）；`cn ^0.2.2`；`class-variance-authority ^0.7.1`；`lucide-react 0.474.0`（dashboard 另用 `@tabler/icons-react`）；`react-hook-form ^7.62.0` + `@hookform/resolvers ^3.10.0` + `zod ^3.25.76`；`cmdk ^1.1.1`；`@tanstack/react-table ^9.0.0`（v9 feature API，不照搬进 v8）；`recharts 3.8.0`；`next-themes 0.4.6` + `sonner ^2.0.0`；`react-resizable-panels ^4`；`react-day-picker ^9.7.0`；`embla-carousel-react 8.5.2`；`vaul 1.1.2`；dashboard 拖拽用 `@dnd-kit/*`。任务不用的组件不引入其依赖。

**不是“同目录就同 primitive”**：这个固定集合多数从 `radix-ui` 导入，但 `ui/combobox.tsx` 已使用 `@base-ui/react`，消息滚动使用 `@shadcn/react/message-scroller`。这是上游自身的真实混合，不是本地混版本。每个组件以真实 imports/props 为准。

### 从 registry 到项目的接线清单

| 项 | 在源码里看什么 | 采用到项目时做什么 |
|---|---|---|
| `registry:ui` / `registry:block` | UI 原语与组合页面分层 | 只引入任务所需项，不把整套 components/ui 当业务包 |
| `files[].path/type/target` | 原文件和目标落点 | 映射到现有 `components/ui`、hooks、路由目录；目标已存在先读 diff |
| `registryDependencies` | Button、Field、Sheet、use-mobile 等本地闭包 | 递归检查，不漏兄弟组件，不把名字当 npm 包 |
| `dependencies` | primitive、表格/表单/图表等外部包 | 对照真实 imports、项目 package/lock；不靠 registry 单一来源猜版本 |
| `cssVars`/CSS/theme | surface/foreground、sidebar、chart、radius 等 | 合入已有 semantic tokens，不整份覆盖全局主题 |
| aliases | 源码的 `@/registry/new-york-v4/*` | 重写为目标 alias 或设置明确映射。本地源码保留原 import：`@/registry/new-york-v4/*` → `components/ui/*`，`@shadcn/react/*` → `components/ui/packages/react/*` |

上游顶层 `registry.json` 的单包 `@radix-ui/*` 与 HSL sidebar 元数据已过时；以真实源码 imports 和 `ui/_registry.ts`、`blocks/_registry.ts` 为准。

固定源的 `cn` 是外部包 `cn`（package 范围 `^0.2.2`），`lib/utils.ts` 也只是 re-export，不是本地 `clsx/tailwind-merge` 的实现。项目有自己的 `cn` 时核对输入合并/冲突规则后显式接线，不假称“拷贝 utils 就零依赖”。

## 3. 核心交互契约：先语义和状态，再皮肤

### Button / Input：保留原生能力

- `Button` 用 `cva` 分离 variant（default/destructive/outline/secondary/ghost/link）与 size；`asChild` 选择 `Slot.Root`，否则是真实 `<button>`。已有 disabled、focus-visible、aria-invalid 样式。
- 源码没自动指定 `type="button"`：在表单中非提交动作必须明确 type；提交动作才用 submit。`variant="link"` 仍可能是 button，不自动有链接语义；导航应用 `<a>`/路由 Link 组合。
- `asChild` 接一个可接收 props/ref 的交互子节点，避免 button 套 button、链接套链接。Radix 的 asChild 不等于 Base UI 的 `render`，不能把 props 名机械互换。
- 按钮加载态需要应用提供 pending/aria-busy、可读标签、重复提交保护和反馈；不能只转圈。icon-only 需可访问名称，不能因图标已可见就省 label。
- `Input` 是原生 input 包装，不接管 value/defaultValue、name、type、required、autocomplete 或验证。调用者提供 label/htmlFor、描述/错误关联、受控 value/onChange 或非受控 defaultValue，不能混用后切换。
- 输入样式有 focus ring、disabled 与 aria-invalid，移动默认较大字号、md 下较小字号；这些是源值，不是所有平台可用的固定尺寸保证。错误状态不仅变红，还要告诉用户如何修正。

### Form 与 Field：两种层次，不删验证来“统一”

旧 `form.tsx` 是 RHF 适配层：`Form=FormProvider`，`FormField` 包 `Controller`，`FormItem` 用 `useId`，`FormControl` 通过 Slot 注入 id、aria-describedby、aria-invalid，`FormLabel/Description/Message` 连到同一 field。它不是 native `<form>`，仍需真实 form 的 onSubmit/submit button。

新 `field.tsx` 是表单库无关的语义/布局层：`FieldSet/FieldLegend` 组织字段组，`FieldGroup` 建 container-query 边界，`Field` 支持 vertical/horizontal/responsive，`FieldContent/Label/Description/Error` 组合说明和错误。`FieldError` 合并重复 message 并用 `role="alert"`；这不意味着它自动关联到了具体输入。

**选法**：已有 RHF Form 模式就延续；新表单可用 Field + RHF Controller、现有表单库或原生表单。不为获得一个 Label 更换整套状态管理。Field 的 `data-invalid` 是视觉状态，输入仍需 `aria-invalid`，描述/错误需 id 与 `aria-describedby` 等可访问关系；disabled 的样式标记不等于禁用了真实控件。

复杂 RHF 示例保留 schema、resolver、defaultValues、Controller、提交与 reset：RadioGroup 用 `value/onValueChange`，Select 用 `value/onValueChange`，Checkbox/Switch 用 `checked/onCheckedChange`，不是一律套 input 的 onChange。示例主要 toast 展示数据，不证明真实保存已完成；实际接口需错误、pending、防重、成功后状态与权限约束。

Next 示例用 `useActionState`、`next/form`、server action 和独立 schema：server 端 `safeParse(FormData)`，失败返回 fieldErrors 和 values，pending 禁用控件/提交。原 action 的 1 秒等待与“Do something”是演示，不是数据库保存、认证或授权；接业务时保留服务端校验并补 CSRF/权限/数据持久化等项目要求，不能把 success 返回值当业务完成。

### Dialog / Sheet / Popover：焦点和 portal 不属于装饰

| 组件 | 实际结构与用途 | 不能被视觉定制破坏的契约 |
|---|---|---|
| Dialog | Root、Trigger、Portal、Overlay、Content、Title/Description、Close；内容居中 | `open/onOpenChange` 或 `defaultOpen`；模态焦点管理、Esc/外部交互及关闭回焦由 Radix 驱动，项目仍需实测 |
| Sheet | 复用 Radix Dialog primitive，Content 按 top/right/bottom/left 放边缘 | 不是自制绝对定位 div；保留标题、关闭入口、遮罩、焦点和长内容滚动 |
| Popover | Root/Trigger/Anchor，Portal 内 Content，align/sideOffset/碰撞定位 | 用于附着式轻交互，不当成必然模态 Dialog；表单嵌套弹出层必须测焦点与 Esc 层级 |

- 标题和说明优先使用各组件提供的 Title/Description。`PopoverTitle` 此快照实际渲染的是 div，不因名字或类型提示就获得 dialog title 的 ARIA 关联；按真实 DOM 检查，不照名字假定语义。
- 原 Dialog/Sheet Content 没替所有长表单配置最大高度/内部滚动。需要时设视口约束和独立滚动区，保证小屏键盘弹出后关闭、标题和提交仍可达；不要用 body 的额外强制 scroll lock 与 primitive 对抗。
- Portal 改变 DOM 位置：祖先 overflow、transform、z-index、主题和 dir 的继承都要检查。弹层里再开 Select/Popover 时，关闭顺序、外点行为、焦点归还、滚动容器必须一起测。
- 不通过 `preventDefault()` 全面关闭自动焦点来压警告；确需自定义时提供等价的初始/返回焦点。权限失败或异步失败不要提前关弹层丢失输入。

### Select / Combobox：不同控件，不同输入模型

`select.tsx` 用 Radix Select：Root 状态、Trigger/Value、Portal/Content/Viewport、Group/Label/Item、ItemIndicator、滚动按钮。`value/onValueChange` 是选择值，`disabled` 与 placeholder 是独立状态；Content 用 available-height/trigger-width 等变量限制滚动与定位。无需搜索的有限选项可优先用 native-select，避免无谓复杂度。

本快照有两条 Combobox 路线，按现有项目选一条，不拼半套：

1. `ui/combobox.tsx` 是 **Base UI**：Root、Input、Trigger/Clear、Portal → Positioner → Popup、List/Item、Empty、Group/Label、Chips/ChipRemove；`render` 组合 InputGroup/Button。`data-open/closed/highlighted`、anchor/available-size 变量不同于 Radix 的 data-state/定位变量。由底层管理搜索/选择/多选与键盘，实际采用前核对所需 API 和安装版本。
2. `examples/combobox-demo.tsx` 是 **Radix Popover + cmdk Command + Button** 的组合。显式持有 open/value，触发器标 `role="combobox"`/aria-expanded，CommandInput 搜索、CommandEmpty 空结果、onSelect 更新值并关层；是可读组合案例，不是新 Base Combobox 的 API 示例。

异步搜索仍需应用补 loading/error、取消/竞态控制、选项稳定 key、对象/字符串 value 映射与无结果反馈。列表虚拟化、IME 输入和触屏滚动不能因为“primitive 自带无障碍”就免测。

### Table / Sidebar / Navigation / Tabs：布局与应用状态分开

**Table** 保留真实 table/thead/tbody/tr/th/td/caption，外层 overflow-x-auto，selected 行只改样式。它不是带排序分页的 DataGrid；排序、选择、过滤、分页来自 block 的 TanStack 层或项目设施。金额/日期/权限/服务端分页语义仍由业务负责，不能靠复制假数据完成。

**Sidebar** 有三层职责：

- Provider 持 desktop open、独立 openMobile 和 isMobile；desktop 支持受控 open/onOpenChange 或 defaultOpen。use-mobile 在 effect 中判 `<768px`，不能把初次 SSR/水合直接当手机结果。
- desktop 有 sidebar/floating/inset 与 offcanvas/icon/none，固定面板和占位 gap 共同避免正文跳位；mobile 用 Sheet，保留 sr-only 标题/说明。Content 自己负责 overflow，Header/Footer 不随整页乱滚；可折叠菜单用现成 Collapsible 组合。
- Button/asChild、isActive、Tooltip、MenuAction/Badge/SubMenu 建导航层级。图标折叠时不丢名称、active 不能只靠 hover，页面链接需真实路由与 aria-current 等应用语义。

源 Provider 会写 7 天 `sidebar_state` cookie，并监听 Cmd/Ctrl+B 切换。采用前查项目 cookie/快捷键策略和文本编辑冲突；cookie 不是权限状态。Rail `tabIndex=-1` 不是键盘主入口，必须保留可聚焦 Trigger。源固定宽度可覆盖 CSS 变量，不能强套所有布局。

**NavigationMenu** 区分 Trigger/Content 和真正 Link，可选共享 Viewport（原默认 true）或每项独立弹层。active 与 open 是不同状态，触发器箭头和内容 data-motion 支持视觉反馈。保留链接语义、键盘与路由状态，别把整组导航变成只有 onClick 的 div。

**Tabs** 用 Root/List/Trigger/Content，Root 透传 controlled value/onValueChange 或 defaultValue，orientation 影响键盘与布局；variant default/line 只管样式。不同 Tab 的远程数据加载成本、自动/手动激活和隐藏面板状态由项目决定。跨路由跳转通常用导航链接，不伪装成页内 tabs。

## 4. 三套完整布局与复杂表单：读组合，不抄截图

### Dashboard-01：应用壳 → 指标 → 图表 → 数据工作区

保留 page、data.json 和 9 个局部组件，共 11 文件。page 组合 SidebarProvider/AppSidebar/SidebarInset，SiteHeader 承接导航与页面操作；SectionCards 用 container queries 分配指标密度；ChartAreaInteractive 有时间区间选择；DataTable 分离列定义、状态、排序/选择/过滤/分页、拖拽与行详情。

可借鉴：应用壳稳定，局部内容自适应；数据表复杂状态独立于页面；多种控件共享同一主题。不能直接迁移：样例销售数据、虚构菜单/用户、图表结论、行权限、客户端分页与业务接口。表格当前源使用 TanStack v9 feature API，旧 v8 项目不能照搬 import；横向滚动和触屏拖拽还需真实验证。

### Sidebar-07：信息层级明确的工作台

保留 page 和 5 个组件，共 6 文件。AppSidebar 包 TeamSwitcher、NavMain、NavProjects、NavUser；NavMain 用 Collapsible 构建嵌套导航，Footer 用户操作与主导航分区，page 的面包屑、Trigger、Separator、SidebarInset 建内容起点。

可借鉴：团队/空间、主导航、项目快捷入口、账号操作分层；折叠态不是删内容而是改变可见密度。不能直接迁移：假路由、工作区权限、用户身份与默认展开状态；路由切换后 mobile 是否关闭也要按业务实现，不靠模板猜。

### Login-01：窄表单与语义 Field，不是认证系统

保留 page + LoginForm。外层居中/max-width，Card 组织标题与说明，FieldGroup 放 email/password、辅助链接、提交与替代登录。用现有认证接口接管真实提交、密码错误、pending、回跳、会话与风控；模板的链接/社交按钮不是可用后端。不要复制品牌/社交图标当已获授权的认证集成。

### Complex forms：RHF 与 Next 各留一条完整路径

- `form-rhf-complex.tsx`：schema + resolver + Controller + 分组/条件错误 + reset + 提交演示，适合学“多种控件如何映射同一表单状态”。
- `form-next-complex.tsx` + `form-next-complex-action.ts` + `form-next-complex-schema.ts`：客户端状态与服务端验证闭包，适合学 progressive form/action 反馈，不把 Next 专有机制强加给 Vite/Vue。
- 跨字段约束、服务端错误、真实保存、未保存离开提示与失败保留输入，在项目原有设施中补齐；不为了外观放宽 schema、不吞错误、不绕过权限。

## 5. 主题、字体、暗色与响应式

1. 用成对 semantic tokens：background/foreground、card/card-foreground、popover/popover-foreground、primary/primary-foreground、secondary、muted、accent、destructive、border、input、ring、chart 与 sidebar 各自 token。主色不是所有文字的颜色，focus ring 也不是普通描边。
2. Tailwind v4 用 `@theme inline` 映射 CSS 变量，`.dark` 覆盖同名 tokens；保留 radius 尺度而非逐组件手填。固定源示例用 OKLCH，但旧 registry.json 还夹有 HSL 字符串，不能跨格式直接套用。
3. 不整体拷贝站点 globals.css。里面含文档站 style-* variants、站点布局与 legacy-themes 导入；只提取目标所需主题/基础层，并审原项目 reset/优先级。原 globals 已依赖 Tailwind、tw-animate-css、shadcn/tailwind.css，不是裸 CSS 即开即用。
4. 字体先映射项目 heading/body/mono 角色与 fallback，再调 tracking/line-height。组件默认 text-sm、nowrap、truncate 在中文长标题、缩放和多语言下须测；品牌字体不能被默认 shadcn 字体覆盖。
5. 以组件容器而非只以视口驱动 Field 与指标卡响应式；Sidebar/mobile 与 Sheet 的状态分别处理。最小可用尺寸、横向表格滚动、软键盘、放大字体和超长文本需真实验证。
6. 保留 `direction.tsx` 的 DirectionProvider/useDirection 作为 Radix 方向入口，但它不自动修正全部 left/right、padding、箭头、图表和 portal。Base Combobox 的方向上下文另按实际 primitive 核对；新布局优先 logical properties。未跑 RTL 不能宣称整套支持完成。

## 6. 与动效层的明确边界

- primitive 拥有语义、open/closed/selected 状态、portal、焦点与退出交互；业务层拥有验证、数据与授权；视觉层拥有 tokens 和材料；动效层只消费已正确的状态。
- 每个 DOM 节点/属性只有一个动画所有者。原 Dialog/Sheet/Popover 已有 tw-animate-css 的 data-state 动画与位移，不能再让 Motion/GSAP 同时写该节点 transform/opacity；可关闭其中一套效果，或把叙事动画放在不承担 primitive 定位的内部节点。
- Dialog 本身用 translate 居中，Popover/Select 有定位与 transform-origin；动画覆盖 transform 可能把弹层移出视口。Sidebar 由 width/left/right 协调占位，也不能只动画面板不改 gap。
- reduced-motion 禁掉非必要 slide/zoom/stagger，保留即时状态变化和焦点，不靠一段动画才能读内容。不要用 forceMount + 永久隐藏绕过 presence/焦点生命周期。
- loading、error、success、selection、validation 的视觉反馈必须不只靠动画。装饰不能延迟点击/提交、扩大重渲染或遮住可达性。

## 7. 最小完整验收，不把语法通过当上线

采用前：检查实际 package/lock、alias、CSS入口、primitive版本、client/server boundary、所需本地依赖；有现成组件就先复用。原码保留是为了可查，不是要求每个项目复制全部 61 个组件。

采用后逐项验证：

- 所有交互默认/hover/focus/pressed/disabled/loading/error/success；受控与非受控不混用；重复提交与异步失败不丢数据。
- 键盘顺序、Esc/外点关闭、初始/返回焦点、屏幕阅读名称、aria-invalid/description、对话框标题、表单 label 与错误关联。
- 弹层嵌套、滚动锁、移动键盘、portal 主题/dir、窄屏溢出、长内容、暗色与 reduced motion。
- Table 的数据量、排序/分页/选择、权限和服务端结果；Login 的真实认证结果；Form 的服务端验证与保存，而不只看 toast。
- 按实际项目最小测试/静态检查执行；用户没要求 build 时不额外打包，不启动本地服务代替验收。

原始 imports 保持一致；本地 import 闭包与（可选）TypeScript 语法核验（`tests/integration.test.mjs`）不证明类型正确、依赖已装或浏览器运行通过，不能将“参考闭包完整”说成“目标项目开箱即跑”。
