# 风格检索库：把方向落成可复用的设计系统

此层提供 UI UX Pro Max 的结构化检索与设计系统流程；不安装第二个插件。先理解任务与品牌，再查少量相关资料，形成一套明确视觉语言；不要把整库读入上下文，也不要把检索排名当设计结论。

## 来源、范围与边界

- 固定上游：`nextlevelbuilder/ui-ux-pro-max-skill`，commit `28b3b8dee8c976df4fa3e94aed4e092ad43fcb03`；采用 canonical `src/ui-ux-pro-max/data/` 与 `scripts/`。
- 本地目录：本 skill 的 `search/`；`data/` 为数据，`scripts/` 为搜索、设计系统生成、校验与测试；MIT 见 [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md)。
- 保留完整结构化数据、原版 BM25 搜索、行业规则推理、设计系统生成器、数据校验器与相关回归测试。无需 pip 依赖，不请求模型，不联网查询。
- 本版本有 **88 条风格记录**：50 active、29 supplemental、9 deprecated；前两类共 79 条可按身份检索，不等于 79 个互不重叠的基础风格。普通模糊搜索只推荐 active，supplemental 用准确名称/别名/ID 定位，deprecated 解析为 canonical 或跨域重定向。
- 数据中的性能、可访问性、明暗模式字段是风险提示和实施条件，不是实测评分或 WCAG 合规认证。字体目录是元数据，不含字体二进制；图标代码也不等于已安装对应包。

## 1. 先锁定设计契约

开始前用一段话记录以下信息，缺失但不阻塞的项自行作保守判断，不无限追问。

| 输入 | 要落定的事 |
|---|---|
| 产品与主要任务 | 卖课、预约、浏览商品、处理表格等；首要 CTA 与完整任务链 |
| 受众与场景 | 年龄、专业程度、使用频率、文字量、设备、网络与低端设备限制 |
| 既有系统 | 先查项目组件、CSS 变量、字体、品牌色、路由与交互规范；续做项目不重新换皮 |
| 用户明确意图 | 指定风格、参考 URL、字体、配色、禁止项、是否保留现有品牌 |
| 技术约束 | 真实 framework/版本、可用组件与图标库、SSR、移动端、无障碍要求 |
| 视觉方向 | 一个主风格、一个有理由的辅助材料/排版手法；避免把所有流行标签叠在一起 |

**裁决顺序**：安全与可访问性硬约束 → 用户当前明确要求 → 既有品牌/项目契约 → 已确认的页面覆盖与全局设计系统 → 检索候选与行业默认值。用户未要求改品牌时，不允许生成器悄悄替换其主色、字体、密度或组件。

风格、行业、布局分开决定：`Claymorphism` 是表现语言；`education` 是使用场景；课程目录/进度/评价/报名是信息架构；`Hero + Features + CTA` 不是风格。Bento 是布局组织时优先查 landing/pattern，不能仅因名称相似改写材料与字体。

## 2. 定位本地引擎，按域搜索

公共 skill 不内置个人路径。调用者必须把 `FRONTEND_DESIGN_DIR` 设为**当前实际加载的 frontend-design skill 的绝对路径**，或提供 `VFT_KIT_DIR`（绝对插件根）；缓存安装位置可能变化，不猜 `~/.claude`、不从工作目录跨级找路径。

```bash
# 二选一：FRONTEND_DESIGN_DIR 是实际 skill 根；或已设置绝对 VFT_KIT_DIR。
if [ -z "${FRONTEND_DESIGN_DIR:-}" ]; then
  export FRONTEND_DESIGN_DIR="${VFT_KIT_DIR:?set absolute VFT_KIT_DIR or FRONTEND_DESIGN_DIR}/skills/design-content/frontend-design"
fi
case "$FRONTEND_DESIGN_DIR" in /*) ;; *) printf '%s\n' 'FRONTEND_DESIGN_DIR must be absolute' >&2; exit 1 ;; esac
export UUPM_SEARCH="$FRONTEND_DESIGN_DIR/search/scripts/search.py"
export PYTHONDONTWRITEBYTECODE=1
python3 -B "$UUPM_SEARCH" --help
```

`-B`/`PYTHONDONTWRITEBYTECODE` 避免在 skill 下生成 `__pycache__`。默认命令只读 CSV、输出 stdout。`--json` 用于精确取字段；`--full` 展开文本长字段。先取 1–3 条，需要比较时才增加 `-n`（范围 1–20）。普通检索不要带 `--persist`。

### 中文意图 → 英文检索词

引擎主要按英文数据索引。把中文需求转为简短英语词组，不把长篇提示词原封不动塞进去；保留品牌约束在设计契约中，不期待引擎理解品牌名。

| 中文意图 | 可用查询 | 域与解释 |
|---|---|---|
| 亲切、儿童教育、软黏土 | `Claymorphism`；`educational platform` | style 精确身份 + product 行业，分开查 |
| 宠物美容、暖色预约 | `pet grooming`；`warm orange playful` | product/color；再准确指定 claymorphism |
| 奢侈品、摄影、衬线编辑排版 | `luxury ecommerce`；`editorial luxury serif` | product/typography/landing，不自动等于玻璃 |
| 网页磨砂玻璃 | `Glassmorphism` | style；局部透明层与背景模糊 |
| Apple 原生 Liquid Glass | `Apple Liquid Glass` | style；平台 material，不能当通用 web CSS 效果 |
| 极简瑞士、信息清楚 | `minimalism-and-swiss-style` | style canonical ID |
| 高密度后台、键盘操作 | `dashboard table`；`keyboard focus` | product/ux；保留业务信息密度 |
| 页面模块结构 | `course catalog`、`testimonial pricing` | landing；不应覆盖主风格 |
| 降低动效、焦点、表单错误 | `reduced motion`、`focus`、`form error` | ux/web；每次只查一个问题 |
| Vue/React 等实现细则 | `forms responsive accessibility` | `--stack vue` / 实际 stack；与 design-system 分次运行 |

### 全部检索域与用途

| 参数 | 数据/作用 | 什么时候用 |
|---|---|---|
| `--domain style` | canonical、alias、状态、颜色/材料/效果、风险与实现清单 | 选视觉语言；精确名称优先 |
| `--domain product` | 产品分类、行业主/辅风格、布局、配色倾向 | 产品需求不清或跨行业时 |
| `--domain color` | primary/on-primary、secondary、accent、surface、error、ring 等 | 建语义配色，而不只挑一个漂亮色 |
| `--domain typography` | 标题/正文搭配、用途、导入提示 | 建字体层级；检查实际字符覆盖和字体授权 |
| `--domain google-fonts` | 字体类别、字重/轴、子集与来源 | 字体找不到、需中文或可变字体时精确核实 |
| `--domain landing` | 模块顺序、CTA、转化与结构模式 | 决定页面叙事和任务顺序 |
| `--domain ux` | 问题、Do/Don't、示例、严重度 | 交互、反馈、焦点、触屏、表单等 |
| `--domain web` | Web 界面规则 | 语义、响应式与浏览器交互 |
| `--domain react` | React 性能规则 | 实际项目是 React 时，不泛化成所有框架 |
| `--domain chart` | 图表与数据量/类型匹配 | 数据可视化，不把装饰图当统计图 |
| `--domain icons` | 图标选择、库、导入方式 | 先复用项目现有图标；命中不代表包已安装 |
| `--domain gsap` | 动效强度、触发、时长、示例 | 任务确需动效且项目可承载时；不是必装 GSAP |

支持的 stack：`react`、`nextjs`、`vue`、`svelte`、`astro`、`swiftui`、`react-native`、`flutter`、`nuxtjs`、`nuxt-ui`、`html-tailwind`、`shadcn`、`jetpack-compose`、`threejs`、`angular`、`laravel`、`javafx`、`wpf`、`winui`、`avalonia`、`uno`、`uwp`。选择真实技术栈，不为使用这个库迁移项目。

```bash
python3 -B "$UUPM_SEARCH" "Claymorphism" --domain style -n 1 --full
python3 -B "$UUPM_SEARCH" "educational platform" --domain product -n 2
python3 -B "$UUPM_SEARCH" "warm orange playful" --domain color -n 2 --json
python3 -B "$UUPM_SEARCH" "friendly rounded" --domain typography -n 2
python3 -B "$UUPM_SEARCH" "course catalog" --domain landing -n 2
python3 -B "$UUPM_SEARCH" "focus keyboard form error" --domain ux -n 3
python3 -B "$UUPM_SEARCH" "forms responsive accessibility" --stack vue -n 3
```

结果为 0 时明确写“库未命中”；缩短/换同义词或改正确域，不把回退方案伪装成命中。legacy 标签的 `redirect` 要跟到指定域/ID。`--json` 中的 canonical ID、Status、Parent、Replacement 是结构信息，不因文案相近就手工拼接新流派。

## 3. 生成候选，再做明确覆盖

新项目或确实需要新视觉系统时先跑聚合；局部修复、成熟品牌续做不强制重建。

```bash
python3 -B "$UUPM_SEARCH" "educational platform children playful" \
  --design-system -p "Course Studio" --format markdown
# 需要结构化处理时用 --json；--design-system 模式不会应用 --stack。
python3 -B "$UUPM_SEARCH" "luxury ecommerce editorial photography" \
  --design-system -p "Maison" --json
```

上游的真实流程是：产品分类 → `ui-reasoning.csv` 的匹配规则/条件 → style、color、typography、landing 多域检索 → canonical 风格选择 → 明暗模式一致的语义色板 → 输出布局、风格、颜色、字体、效果与反模式。行业条件规则比单纯 BM25 风格排名更有权重，能得到完整候选，但不是用户指定约束的解析器。

**已复现的限制**：固定版本把 `luxury ecommerce glassmorphism` 和 `luxury ecommerce brutalism` 都生成成 `liquid-glass`；直接 `--domain style` 分别正确命中 `glassmorphism`、`brutalism`。因此下面覆盖步骤不可跳过，不能把原始 `--design-system` 输出直接当最终规范。

1. 独立精确查询用户指定风格，如 `Glassmorphism --domain style -n 1 --json`，取完整材料、效果、风险和实现字段。没有指定时才在行业候选中选择。
2. 先读现有设计系统/品牌 tokens。将自动候选分为“沿用”“补全空缺”“拒绝”三类；有品牌时只填空，不换主色与字体。
3. 形成**最终决策表**：每一项写采用值、来源（用户/项目/检索/设计判断）、覆盖原因。风格覆盖同时检查阴影、边框、圆角、色板模式、字体、动效和反模式，不只改标题中的风格名。
4. 对 `liquid-glass` 核对平台：原生 Apple material 使用平台 API/规范；普通 web 的半透明 blur 明确叫 frosted glass/glassmorphism，不承诺光学折射或系统级动态材质。网页项目不可仅因“luxury”自动换成 Apple 材质。
5. 自由混搭最多一主一辅，并说明各自作用范围。例如 clay 卡片配少量硬阴影按钮，不把整站叫“纯软黏土”。
6. 在实现前检查决策表与用户输入逐项重合，再把最终系统交给组件与页面。确认后才持久化。

### 显式品牌/风格的验收样本

| 输入契约 | 引擎候选/精确结果 | 最终必须保留 |
|---|---|---|
| education + clay | 聚合候选 claymorphism；精确 style 也是 claymorphism | clay 结构与风险；课程任务链另定 |
| pet grooming + clay | 聚合候选 claymorphism；精确 style 也是 claymorphism | 同主风格，不强套教育站黑边/绿按钮 |
| web luxury + glassmorphism | 聚合可能是 liquid-glass；精确是 glassmorphism | 明确采用 web glassmorphism，拒绝原生材质误称 |
| 已有品牌 `#123456`/项目字体 + 用户要 Brutalism | luxury 聚合仍可能推荐 liquid-glass/Cormorant | 保留品牌 tokens，精确采用 brutalism，候选不得反向覆盖 |

上游 CLI 不会自动识别任意品牌色或保留项目文件；最终值以决策表为准。

## 4. 分层 tokens 与组件，不做一页贴皮

将确定后的值放入项目已有 token 系统，避免新建一套平行主题。三层职责如下。

| 层 | 内容 | 约束 |
|---|---|---|
| 基础值 primitives | 色阶、字体、字重/字号/行高、间距、圆角、边框、阴影、时长/easing | 一组有节奏的尺度；数值由品牌、内容与设备确定 |
| 语义值 semantic | primary/on-primary、surface/on-surface、muted、border、focus、success/warning/error、elevation | 文本与底色成对；覆盖默认、hover、pressed、disabled、明暗模式 |
| 组件值 component | Button/Card/Input/Nav/Modal/Table 等对语义值的引用 | 同类组件同规则；页面覆盖只改必要差异 |

- 排版先定角色：display、h1/h2、body、label、caption，再选字体。标题可独特，正文优先可读；Inter、系统字体、衬线都不是禁项。中文需实际覆盖字符与字重、合理 fallback；外部字体不可用时不能让布局坍塌。
- 间距由内容层级与布局网格决定；radius、shadow、border 是同一材料语言的不同变量。不要把每个框都变成圆卡片，也不禁止有意义的圆角或奶油色背景。
- 建好按钮、输入、卡片、导航、反馈状态再组合页面；empty/loading/error/success/disabled/focus 必须与默认态同一系统。
- 页面结构从任务倒推：课程目录与进度、预约时间与反馈、产品规格与购买步骤各不相同。视觉相似不等于信息架构相同。
- 图表使用类型、数量级、比较任务选型；颜色不做唯一编码。图标复用同一套 SVG/项目组件，控制 viewBox、线宽、尺寸与装饰语义，别把 emoji 当无标签功能图标。
- 检索的 GSAP snippet 只当实现参考。简单交互用现有 CSS/动画系统；不为“高级感”加依赖、滚动劫持、磁吸光标或强制入场动画。可无动画。

## 5. Master + 页面覆盖：只写确认过的系统

普通查询与 `--design-system` 默认仅 stdout，**只有 `--persist` 才落盘**。必须显式给目标项目的绝对 `--output-dir`，不使用 cwd 默认，不写到用户主目录，不写入本 skill 目录。下面命令会创建目标项目文件，不是只读示例。

```bash
: "${DESIGN_PROJECT_ROOT:?set absolute target project root before persisting}"
case "$DESIGN_PROJECT_ROOT" in /*) ;; *) printf '%s\n' 'DESIGN_PROJECT_ROOT must be absolute' >&2; exit 1 ;; esac
python3 -B "$UUPM_SEARCH" "educational platform children playful" \
  --design-system --persist -p "Course Studio" --output-dir "$DESIGN_PROJECT_ROOT"
python3 -B "$UUPM_SEARCH" "educational platform course detail enrollment" \
  --design-system --persist -p "Course Studio" --page "course-detail" \
  --output-dir "$DESIGN_PROJECT_ROOT"
```

实际路径为 `$DESIGN_PROJECT_ROOT/design-system/course-studio/MASTER.md` 和 `pages/course-detail.md`。项目/页面名经 safe slug 处理。读取次序：先读 MASTER，再读当前页面覆盖；只覆盖明确差异，未写项继承 MASTER，不能把某页特例扩散到整个站。

**注意**：持久化生成的是上游候选，不会自动应用上一节的人工品牌/风格覆盖。先 stdout 审核，若采用落盘命令，必须在实现前把决策表中的最终值合入 MASTER/页面覆盖并核对，不能保留错误候选供后续 agent 使用。项目已有同类设计文件时优先编辑原文件，不另起目录。

无 `--force` 时已有文件不被覆盖；已有 MASTER 但新页面尚不存在时仍可新增页面覆盖。需要覆盖时先读、比较、保留既有决策，再由用户授权范围决定是否使用 `--force`；不要用它重试掩盖冲突。并发 agent 不应同时编辑同一设计文件。

可选 dials：`--variance 1-10` 偏向居中克制/大胆非对称，`--density 1-10` 偏向疏朗/紧凑，`--motion 1-10` 添加对应强度的动效建议。它们不是评分，也不是默认参数；`--variance` 还会改变风格选择，已有明确风格时不要用它反向覆盖。reduced motion/设备性能优先于 dial。

## 6. 三个真实案例：事实、可借鉴点与改写边界

以下为对公开演示页的浏览器只读观察与 computed styles 记录。不是上游库自动生成的效果，不代表已复刻整站。数字仅说明案例，**不是新项目的默认 tokens**。未查明照片和整站源码复用授权，因此只保留 URL 与分析，不复制图片、源码或 premium 资源。

### A. 教育平台：clay 标签下的硬阴影混合语言

来源：<https://www.uupm.cc/demo/educational-platform>

**观察事实**：标题 Fredoka、正文 Nunito；所查主标题 60px；卡片圆角 24px，深墨 `rgb(45,55,72)` 描边，`6px 6px 0` 硬阴影，并有 `inset -4px` 内阴影。绿色按钮 `#22c55e`、16px 圆角、`4px 4px 0` 硬阴影。内容链含课程目录、学习进度、评价与报名。

**优秀思路**：圆润字体与厚实体块降低学习门槛；明显边界和偏移阴影让课程/CTA 有可点击的实体感；进度与评价支持继续学习与报名，而非只有一个漂亮 Hero。

**复刻到新需求的方法**：保留“友好圆润 + 实体层级 + 学习任务链”的关系，先用现有课程数据排目录/进度，再统一 Card/Button 的边框、内/外阴影与按压态。若目标是更软的 clay，降低外阴影硬度/深墨边界，而不是机械复制 24px/6px。

**别混淆**：这不是纯粹无描边软黏土；硬描边、零模糊偏移阴影有 bold/cartoon 的混合特征。搜索 `Claymorphism` 只能给材料候选，不能自动推导其教育布局和具体 token。

### B. 宠物美容：暖色 clay 变体，照片与预约优先

来源：<https://www.uupm.cc/demo/pet-grooming>

**观察事实**：正文 Quicksand、标题 Nunito；所查主标题 60px；主色 `#ff8c42`。白卡片 24px 圆角，`8px 8px 0 rgba(255,140,66,.15)` 偏移阴影，并有 `inset -4px`；按钮 16px 圆角。可见宠物照片、服务、套餐、评价与预约。

**优秀思路**：暖橙和低不透明度同色阴影更贴合温暖照护；真实宠物照片提供情绪/服务可信度，价格与套餐支持选择，预约入口承接主任务。与教育页同属圆润实体感，但并不依赖重墨边和绿色 CTA。

**复刻到新需求的方法**：先排服务 → 价格/套餐 → 信任证据 → 预约的任务链；真实内容获授权后再选照片。用品牌暖色统一 focus/CTA/小强调，不把橙色同时铺到所有正文底色。预约表单给日期、服务、错误说明与提交反馈，不能只做视觉按钮。

**别混淆**：不能把教育站的描边、字体与阴影直接移植过来叫“宠物 clay”。两站共同的是软圆、厚度与亲和，不是完全相同的 CSS。

### C. 奢侈品电商：摄影与编辑排版为主，局部 web 磨砂为辅

来源：<https://www.uupm.cc/demo/luxury-ecommerce>

**观察事实**：标题 Playfair Display、正文 Inter；所查主标题 72px；大片摄影、品牌故事、商品与会员 CTA 构成页面。导航白色约 80% 不透明度、`blur(12px)`；所查 `.liquid-glass` 区块白色约 70%、`blur(20px)`、`0 8px 32px rgba(0,0,0,.08)` 阴影，圆角 0。

**优秀思路**：高端感主要来自大幅图像、留白、衬线/无衬线对比、节奏和产品叙事，不靠全页发光玻璃。透明导航是轻量层级处理；直角与小阴影维持编辑气质。Inter 在这里承担安静清晰的正文，不应为了“去 AI 味”被硬禁。

**复刻到新需求的方法**：先用获授权商品图建立摄影构图与版式，再把 frosted glass 仅用于导航或少量叠层；明确前景/背景对比，遇复杂照片增加实底。无 blur 时保留几乎不透明背景、边界、导航功能和品牌层级。

**别混淆**：class 名叫 `.liquid-glass` 不证明实现了 Apple 的光学折射/动态平台 material。观察到的是普通 web frosted glass；不能因此推荐原生 API，也不能拿截图证明流体动画。

### 同类不等于同版：案例对照

| 维度 | 教育 | 宠物美容 | 奢侈品 |
|---|---|---|---|
| 主视觉语言 | 圆润 clay + 深墨硬边/硬阴影 | 暖色 clay、低透明度彩影 | 摄影、编辑排版、局部磨砂 |
| 字体关系 | Fredoka / Nunito | Nunito 标题 / Quicksand 正文 | Playfair Display / Inter |
| 任务链 | 找课、进度、评价、报名 | 服务、套餐、信任、预约 | 故事、商品、会员/购买 |
| 可迁移的规范 | 实体层级与学习反馈 | 亲和感与预约闭环 | 留白节奏与局部透明层 |
| 不直接迁移 | 绿色/重描边/固定像素 | 橙色/照片/具体卡片值 | 原图/72px/原生材质承诺 |

## 7. 实现与交付检查：视觉成立，也能使用

- 先复用项目栈、组件、tokens 与图标；不因库中建议就安装框架或动效包。原生和 web 规则按目标平台分别处理。
- 普通文本与背景至少 4.5:1，大文本至少 3:1；控件边界/状态与焦点等非文本对比核对 3:1 适用要求。玻璃须在实际背景及明暗模式测，不只测一块静态色。
- 键盘可达、可见 focus、逻辑顺序、按钮/链接语义、表单 label 与错误关联、图片 alt、图标可访问名称；不只靠颜色/hover 传达状态。
- 触屏目标按平台要求检查，网页通常优先约 44×44 CSS px 触控面积并验证间距；不是所有视觉图标都要画成同尺寸色块。
- 尊重 `prefers-reduced-motion`，移除非必要位移、视差、自动滚动等；不要强制所有元素入场。`transform/opacity` 优先于布局抖动，hover 不挤开内容。
- 无 `backdrop-filter`、降低透明效果或低端设备时提供更实的 surface、稳定边框与轻量阴影；不支持复杂效果仍能看清、导航、提交。具体性能必须实测，不照库里标签宣称流畅。
- 检查实际内容的长标题、中文、换行、空态、大数量、错误态、窄屏与横屏。以项目断点为准，可用 375/768/1024/1440 作为额外观察点，不把四个截图当全设备测试。
- 图片按容器比例、焦点、裁切与加载占位设计；字体 fallback 与慢网布局不跳变；固定导航不挡正文，弹层不丢焦点，页面不意外横向滚动。
- 最后逐项对照设计契约、决策表、MASTER/页面覆盖与实现。检索命中、脚本返回 0、构建通过都不是业务完成；按任务链验证交互，并明确未测设备、动效和真实后端。

## 8. 本地回归与未采用部分

```bash
python3 -B "$FRONTEND_DESIGN_DIR/search/scripts/validate_data.py"
# 测试含临时持久化案例；TMPDIR 设为调用方允许的绝对临时归档目录。
: "${DESIGN_TEST_TMPDIR:?set absolute approved temporary artifact directory}"
TMPDIR="$DESIGN_TEST_TMPDIR" PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover \
  -s "$FRONTEND_DESIGN_DIR/search/scripts/tests" -v
```

测试是快照回归，不保证最新框架/API；遇版本差异再查官方资料。

不采用整套安装器、重复 `.claude`/CLI 打包副本、其他 skills、营销图片/premium 内容，也不自动下载字体或图标。环境安装和默认 html-tailwind 路线不移植，沿用真实项目栈与环境；动效建议、示例配色与审美口号不升级为全局强制规则，功能和用户方向优先。不修第三方生成器，保持上游脚本/数据字节一致；“行业默认压过显式风格”的已复现限制通过第 3 节强制覆盖流程规避。
