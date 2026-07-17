---
name: fe-auto-test
description: 用 Playwright MCP 在真实浏览器里验证前端页面行为——打开本地 dev server、检查控制台报错、验证组件是否挂载、检查 Canvas / Three.js / WebGL 是否渲染成功、截图调试、做 UI 交互回归；并能用 Lighthouse MCP 对任意页面做**全维度体检**（性能 / 无障碍 / 最佳实践 / SEO）+ 缓存压缩实测 + 资源按域名/大小拆解，产出按收益排序的优化建议。封装了"探测 dev server 实际端口 → 浏览器打开 → 查报错/查渲染 → 全维度体检 → 截图 → 清理 → 关服务"的完整闭环，并处理 dev 端口不固定的坑(脚本自动探测，不硬编码)。用户说"验证下页面/看看渲染对不对/检查控制台报错/三维/Three.js/canvas 没出来/组件没挂载/截个图看看/跑下 UI 测试/playwright 打开看看/页面白屏排查/跑下 lighthouse/做个性能审计/这页性能怎么样/LCP/TBT/Core Web Vitals/无障碍评分/优化建议/首屏太慢/详细报告/全面体检/缓存配得对不对"等场景时触发。即使只说"帮我看看这个页面对不对"且需要真实浏览器渲染时，也用本 skill。打开页面验证后会**默认**附带一次全维度页面体检（性能首屏 / 无障碍 / 最佳实践 / SEO / 缓存压缩 / 资源拆解），无需用户显式说"跑性能"。还能做**容错 / 边界 / 全站批量测试**（bundled Playwright 编程式脚本）：清 LocalStorage/清缓存后刷新、脏存储容错、已登录 vs 未登录守卫差异、SSR Hydration 一致性、逐路由(sitemap 抽样)批量查渲染与 console 报错、CDN 缓存/压缩/SSR 冷启动 TTFB 实测。用户说"做容错测试/清缓存清 localStorage 刷新/已登录未登录区别/每个路由都看下/CDN 缓存实测/SSR 冷启动/hydration"等也触发。纯代码静态分析能解决的问题不用本 skill。
---

# fe-auto-test — Playwright 浏览器验证 / 调试

用 Playwright MCP 跑**真实浏览器**来验证前端行为：控制台报错、Vue 挂载、Canvas/Three.js/WebGL 渲染、UI 交互、截图。和静态读代码不同，它能拿到 JS 执行后的真实 DOM 与运行时错误。

## 何时用 / 何时不用

**用**：需要看「运行时真实表现」——白屏排查、组件挂没挂上、three.js/canvas 有没有画出来、有没有 console error、交互点击后状态对不对、视觉截图；以及需要**量化性能 / 无障碍 / 最佳实践 / SEO 评分并给优化建议**（Lighthouse 全维度体检）。

**注意：全维度体检已是默认动作。** 只要页面正常打开，闭环第 4 步会**默认**对它跑一次完整体检——不只是性能首屏，还包括无障碍 / 最佳实践 / SEO 三维度评分、缓存与压缩的实测、资源按域名/大小的拆解。不需要用户显式说"跑性能 / 做审计"。所以哪怕用户只说"打开看看这个页面对不对"，渲染没问题后也顺手把全维度结论一并给出。这样用户问"报告再详细点"时已经有了，不用回头补做。

**不用**：编译错误、类型错误、纯逻辑 bug、能靠读代码/grep/lint 定位的问题。启动真实浏览器是有成本的，确实需要真实渲染时才用。

## ⚠️ 三个本机前提（不懂会踩）

1. **依赖可能没装**：本 skill 依赖 playwright / lighthouse。**别假定它们在**——闭环第 0 步会自动检查并补装（见下）。
2. **dev 端口不固定**：Vite 端口被占会自动 +1（5173→5174…），所以**禁止硬编码端口**，必须先跑探测脚本拿实际端口。
3. **产物统一落中央目录**（`$FE_TEST_OUTPUT_DIR`，未设则 `$HOME/.claude/playwright`）：`--output-dir` 已把 **snapshot/console 这类自动命名产物**写到这里，不落项目。**但 `browser_take_screenshot` 例外**——它的相对 filename 是相对 MCP 进程 cwd（`$HOME`）解析的，会落到家目录而非中央目录，所以截图必须传**绝对路径**（见第 6 步）。清理脚本默认清中央目录，不要去项目根找截图。**本机若把 MCP 的 `--output-dir` 指到了别处，务必让 `FE_TEST_OUTPUT_DIR` 与之一致**，否则截图落一处、清理扫另一处。

## 两条路：MCP 路径 vs 脚本路径

本 skill 的每项能力都有**两种实现**，能力等价，区别只在依赖：

| | MCP 路径 | 脚本路径 |
|---|---|---|
| 渲染 / console / 截图 / 交互 | `browser_*`（playwright 插件） | `route-audit.mjs`、`resilience-audit.mjs` 等 |
| 全维度体检 | lighthouse MCP 的 7 个工具 | **`lighthouse-audit.mjs`（一条命令跑完全部）** |
| 依赖 | MCP 注册 + **重启会话**才生效 | 只要 npm 包 + chromium，**装完立即可用** |
| 擅长 | 交互式逐步调试、点一下看一下 | 批量、无人值守、依赖没齐时的退路 |

**关键认知**：CC 的 MCP **新注册后当前会话拿不到工具，必须重启**。所以依赖缺失时**不要停下来让用户重启**——第 0 步会自动补装 npm 包并走脚本路径把活干完，同时把 MCP 注册好留给下次会话。

## 标准闭环

> **先分流**：用户**给了完整 URL（线上地址 / 任意 http(s) 链接）** → 跳过第 1 步，直接从第 2 步 `browser_navigate` 那个 URL 开始（线上没有 dev server 可探测，第 8 步也不用关服务）。只有**要验证本地项目**（用户没给 URL、说"看看这个页面/项目"）才走第 1 步探测 dev server。

### 0. 依赖检查 + 自动补装（每次必跑，第一件事）

```bash
bash "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/fe-auto-test/scripts/check-deps.sh"
```

- 缺 playwright / chromium / lighthouse **自动装**（npm 包 + 浏览器内核，装完本次即可用）；顺手把 playwright 插件和 lighthouse MCP 也注册好（留给下次会话）。
- 看**末尾的两个标记**决定各自走哪条路。**两个能力分开判**——最常见的情况就是 playwright 插件在、lighthouse MCP 不在，别因为缺一个就把另一个也降级了：

  | 标记 | =1 | =0 |
  |---|---|---|
  | `PW_READY` | 渲染/console/截图/交互用 `browser_*` | 改用 `route-audit.mjs`、`resilience-audit.mjs`、`ssr-status-sweep.mjs` |
  | `LH_READY` | 体检可用 lighthouse MCP | 改用 `lighthouse-audit.mjs`（能力等价，还更省 token） |

- `=0` 时**别停、别让用户重启**，走脚本路径把活干完，结论照样给全。（`MCP_READY` 是两者的与，仅为兼容保留，别只看它。）
- 退出码 1 = 硬依赖装失败（网络/权限），这才需要人工介入，把它打印的手动命令给用户。

### 1. 探测 / 启动 dev server（仅本地项目）

先探测实际端口（不硬编码）：

```bash
bash "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/fe-auto-test/scripts/check-server.sh" [项目目录]
```

- 省略 `[项目目录]` 用当前目录；探测顺序：读 `vite.config.*`/`vue.config.js` 里 `server` 段的 `port`（不会误抓 `preview.port`）→ 框架默认端口 → 扫常见备选端口。
- **打印端口号**（如 `5173`）= 服务在跑，用这个端口。
- **打印空行 / exit 1** = 没起服务，去项目目录用它自己的命令启动（`pnpm dev` / `npm run dev` 等），起好后重新跑一次探测拿端口。
- **stderr 有 ⚠ 警告** = 这个端口是**扫出来的**、不在项目配置里。脚本已验证它确实在返回 HTML，但挡不住 nginx / 别的项目也占着常见端口。这种端口**只用来打开页面看，第 8 步绝不能关它**。

### 2. 浏览器打开页面

用探测到的实际端口，调 Playwright MCP：

- `browser_navigate` → `http://localhost:{实际端口}`
- `browser_snapshot` → 拿到无障碍树/DOM 结构，确认页面渲染出来了（白屏会一眼看出来）

### 3. 检查控制台报错

- `browser_console_messages` → 拉全部 console 输出，重点看 `error`/`warning`。
- 这是排查白屏、组件不显示的第一手段——运行时报错基本都在这。
- **别把良性噪声当 bug**：下面这些是浏览器/三方库常见的无害报错，**不影响功能**，下结论时要排除掉，不要误报成问题：
  - `The play() request was interrupted by a call to pause()`（音视频自动播放/暂停竞态）
  - `ResizeObserver loop completed with undelivered notifications`（ResizeObserver 循环，无害）
  - 第三方脚本（统计/广告/SDK）的 404 / CORS / 自身报错
  - 判定真 bug 的标准：报错栈指向**业务代码**、或伴随**渲染缺失/交互失效**（结合 snapshot 与实际表现），而不是只看 error 计数。

### 4. 全维度页面体检（默认执行，不用等用户开口要"性能"）

页面能打开、没致命报错后，**默认对当前页跑一次完整体检**——这是本闭环的固定环节，不是"按需配方"。覆盖五块：**① 性能首屏 ② 无障碍 ③ 最佳实践 / SEO ④ 缓存 + 压缩（实测）⑤ 资源按域名/大小拆解**。目标是一次跑完就拿到「够详细、能直接答用户后续追问」的报告，而不是先给个简版、等用户说"再细点"才回头补做。

> **何时可跳过/简化**：纯白屏 / 报错排查且页面根本没渲染出来——指标没意义，先把渲染修好。其余情况一律默认跑全套。

#### 走哪条路，看第 0 步的 `LH_READY`

**`LH_READY=0` → 脚本路径（一条命令跑完全部，推荐）**

```bash
node "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/fe-auto-test/scripts/lighthouse-audit.mjs" <url> \
  --device=mobile --resources=/tmp/res.json [--q='?debug=true']
# 再把资源清单喂给拆解脚本：
python3 "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/fe-auto-test/scripts/resource-report.py" /tmp/res.json
```

一次输出：四维评分（性能/无障碍/最佳实践/SEO）+ 六项指标（FCP/LCP/TBT/CLS/SI/TTI，带 🟢🟡🔴 分档）+ 未用 JS + 未用 CSS + 无障碍 `score:0` 硬失败项 + 最佳实践/SEO 失败项。**等价于下面串行调 7 个 MCP 工具的全部产出**，且不会撑爆 token（输出已主动裁剪，资源清单单独落盘）。

它直接 import lighthouse 库，不经过 MCP，所以**装完立即可用、无需重启**。`localhost` 自动改写 `127.0.0.1`、NO_FCP 自动提示 anti-debug 陷阱，坑都在脚本里处理了。落盘的资源清单格式与 MCP 的 `analyze_resources` 一致，`resource-report.py` 两边都能吃。

**`LH_READY=1` → MCP 路径**（交互式调试更顺手时用）

**串行跑下面这串工具**（务必**串行**、本地 URL 用 `127.0.0.1`、工具先 `ToolSearch` 拉 schema；坑位见下方「Lighthouse 配方」）。Lighthouse MCP 后端是单个 Chrome，偶尔报 `ECONNREFUSED 127.0.0.1:<port>`（那是 lighthouse→chrome 的端口，不是目标站）——**直接重试一次**即可，别当成站点故障。

**性能（4 件套）**
1. `get_core_web_vitals`（`device:"mobile"`、`includeDetails:true`）→ FCP / LCP / CLS / TBT
2. `get_performance_score`（`device:"mobile"`）→ 综合分 + Speed Index / TTI
3. `find_unused_javascript`（`minBytes:20000`）→ 首屏未使用 JS（体积优化第一抓手）
4. `get_lcp_opportunities`（`device:"mobile"`、`includeDetails:true`）→ **默认就跑**，不要只在 LCP 慢时跑。它的 `unused-css-rules` 是**唯一能量化未用 CSS** 的来源（`find_unused_javascript` 不含 CSS）——很多页面 CSS 全量打包、未用占比高达 90%+，不跑就会漏掉首屏最大的一块脂肪。LCP 本身慢（>2.5s）时它还会给关键图片预加载 / 阻塞资源等机会项。

**无障碍 / 最佳实践 / SEO**
5. `run_audit`（`device:"mobile"`、`categories:["accessibility","best-practices","seo"]`）→ 三维度评分。
6. 无障碍分 < 90 时，追加 `get_accessibility_score`（`includeDetails:true`）→ 拿失败项明细。**只看 `score:0` 的失败项**（返回的列表里绝大多数是 `score:null` 的 N/A，不是问题，别报）。常见硬失败：`label`（表单缺 label）、`color-contrast`（对比度不足）、`meta-viewport`（`user-scalable=no` 禁缩放）。

**缓存 / 压缩 / 资源拆解（这块是"详细报告"的关键，必跑）**
7. `analyze_resources`（`device:"mobile"`）→ 拿全量资源清单。**注意两个坑**：
   - **输出会撑爆 token**（常 70k+ 字符，报 `exceeds maximum allowed tokens` 并落盘）。**不要去 Read 它**，错误信息里会给落盘路径。
   - **它根本不返回缓存 TTL / 压缩状态**（实测字段只有 filename/type/sizeKB/mimeType/url）。缓存与压缩真值只能自己发请求测。
8. 把上一步的落盘路径喂给 bundled 脚本，一步出「资源拆解 + 缓存压缩实测」：
   ```bash
   python3 "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/fe-auto-test/scripts/resource-report.py" <analyze_resources落盘路径>
   ```
   脚本会：按 type / 域名（区分自有 vs 第三方）/ 大小拆解资源；检测 **legacy 包被现代浏览器误下载**；标注**非 webp 的大图**；并对最大的几个静态资源**实测 `Cache-Control` 与 `Content-Encoding`（gzip vs brotli）**，自动标红「无长缓存 / 仅 gzip 未开 br / 文本未压缩」。探针走 `probe-headers.mjs`（node 直连），**不用 curl**——curl 会被本机 context-mode hook 拦。
   - ⚠️ **看到「探测失败」就如实说没测到**：脚本会把探测失败和"确实没配"分开报。失败项旁边写着「不代表站点没配」，那就**别把它写进报告的缓存结论里**。没测到 ≠ 没配置。
   （若 analyze_resources 这次没落盘、是内联返回的，把那段 JSON 存成一个文件再传给脚本即可。）

跑完按下方「判读 → 生成优化建议」映射成按收益排序的清单，并按报告模板把五块都答到，而不是只贴指标数字。

### 5. 按需做针对性检查

页面有 canvas/three、需要验证组件挂载或 UI 交互时，再选下面对应的「调试配方」（用 `browser_evaluate` 在页面里跑 JS 取真值）。

**用户点名「容错 / 边界 / 全站」测试时**（登录态、刷新、清缓存、清 LocalStorage、已登录/未登录差异、CDN/缓存、每个路由都看看、Hydration）——走下方「容错 / 边界 / 全站批量测试（Node 脚本配方）」。这类要跑几十个页面 + 反复清存储 reload，用 MCP 一个个点太慢，改用 bundled 的 Playwright 编程式脚本一把梭。

### 6. 截图调试（命名规范 + 落点）

- `browser_take_screenshot`，**filename 必须传中央目录的绝对路径**（`~` 不会被展开，要写成真实展开后的路径），文件名统一 `test-{功能描述}.png`：
  - ✅ `/Users/<你>/.claude/playwright/test-three-scene.png`
  - ❌ `~/.claude/playwright/test-three-scene.png`（波浪号 MCP 不展开，会创建一个名为 `~` 的目录）
  - ❌ `test-three-scene.png`（相对名）、`screenshot1.png`、`all-rendered-final.png`
- **为什么必须绝对路径**：`--output-dir` 只管 snapshot/console 这类自动命名产物；`browser_take_screenshot` 的**相对 filename 是相对 MCP 进程 cwd（即 `$HOME`）解析**，会落到家目录而不是中央目录，第 7 步清理脚本（只扫中央目录）就清不到、还污染家目录。传绝对路径一步到位。
- 规范前缀 `test-` 是为了第 7 步清理脚本能精确识别。

### 7. 清理临时截图

```bash
bash "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/fe-auto-test/scripts/cleanup-screenshots.sh"
```

默认清中央目录（`$FE_TEST_OUTPUT_DIR`，未设则 `$HOME/.claude/playwright`）里的 `test-*` / `page-*` 截图；只删命名规范内的截图，不递归、不 rm -rf。

> **截图目录必须和 playwright MCP 的 `--output-dir` 是同一个**。若本机把 `--output-dir` 指到了别处（如某个中央资料目录），要么把 `FE_TEST_OUTPUT_DIR` 设成同一路径，要么第 6 步截图时就传那个目录的绝对路径——否则截图落 A、清理扫 B，永远清不掉。

### 8. 收尾

- `browser_close` 关浏览器。
- 若 dev server 是**你为这次验证启动的**，关掉它：
  ```bash
  bash "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/fe-auto-test/scripts/close-server.sh" <端口>
  ```
  **必须传端口**（第 1 步探测到的那个）。不传端口时脚本只会列出常见端口上在跑的服务、**不会动手**——它分不清哪个是你起的、哪个是用户本来就开着的，盲扫 kill 会顺手杀掉用户另一个终端里的项目（甚至本机的 nginx）。
- **这几种情况别关**：用户原本就开着的服务；第 1 步 stderr 给了 ⚠ 警告的「扫出来的端口」；用户给的是线上 URL（压根没起服务）。

## 调试配方

### 检查 Three.js / WebGL / Canvas

页面包含 canvas/three 时，光看截图不够，用 `browser_evaluate` 取运行时真值：

```js
() => {
  const canvas = document.querySelector('canvas');
  if (!canvas) return { ok: false, reason: 'no <canvas> in DOM' };
  // 优先 webgl2，回退 webgl
  const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
  return {
    ok: !!gl,
    canvasSize: [canvas.width, canvas.height],          // 0 说明没拿到尺寸/未渲染
    contextLost: gl ? gl.isContextLost() : null,
    glError: gl ? gl.getError() : null,                 // 0(NO_ERROR) 才正常
    drawingBuffer: gl ? [gl.drawingBufferWidth, gl.drawingBufferHeight] : null,
  };
}
```

判读：`ok:false` → canvas 没挂或拿不到 WebGL context；`canvasSize` 含 0 → 尺寸塌陷（常见于父容器没高度）；`glError` 非 0 → 有 WebGL 错误；再配合第 3 步的 console 看 three.js 自己抛的错。

### 检查 Vue 组件是否挂载

```js
() => {
  const app = document.querySelector('#app');
  return {
    appExists: !!app,
    appHasChildren: app ? app.children.length > 0 : false,  // false 多半是挂载失败/白屏
    bodyText: document.body.innerText.slice(0, 200),        // 看是否有真实内容
    vueDevtools: !!window.__VUE__,                          // Vue 运行时是否存在
  };
}
```

`appHasChildren:false` + console 有 error → 多半是渲染期抛错导致整树没挂上，去看 console 的报错栈。

### UI 交互回归

`browser_click` / `browser_type` / `browser_fill_form` 触发交互，再用 `browser_snapshot` 或 `browser_evaluate` 断言交互后的状态（如弹窗出现、列表更新、URL 变化）。截图前用 `browser_wait_for` 等异步内容稳定，避免截到加载中的中间态。

**带动画的元素 click 会超时**：CTA 按钮常有呼吸/缩放动画，`browser_click` 等元素「visible, enabled and **stable**」永远等不到稳定 → `TimeoutError: element is not stable`。这不是 bug，是动画。绕过：用 `browser_evaluate` 直接派发点击，并顺手断言副作用（如 hash 变化）：

```js
() => {
  const btn = [...document.querySelectorAll('button,a,div')].find(e => e.textContent.trim() === '开始测试');
  if (!btn) return { clicked: false, reason: 'not found' };
  const before = location.hash;
  btn.click();
  return { clicked: true, hashBefore: before };  // 之后再读 location.hash 看是否跳转
}
```

### Lighthouse 性能 / 可访问性审计 + 优化建议

需要**量化评分 + 可落地优化建议**（而不只是"能不能跑、有没有报错"）时，用 Lighthouse MCP。它跑的是 lab 环境的真实测量，比肉眼截图客观。

**前提坑（不懂会卡 / 测崩）：**

1. **工具是延迟加载的**，先 `ToolSearch` 拉 schema：
   `select:mcp__lighthouse__get_core_web_vitals,mcp__lighthouse__get_performance_score,mcp__lighthouse__find_unused_javascript,mcp__lighthouse__analyze_resources,mcp__lighthouse__get_lcp_opportunities,mcp__lighthouse__get_accessibility_score,mcp__lighthouse__run_audit`
2. **必须串行，绝不并行**：MCP 后端是单个 Chrome 实例，两个 Lighthouse 调用并发会把它搞崩（报 `ECONNREFUSED 127.0.0.1:<port>`，那是 lighthouse→chrome 的端口，不是目标站）。一次只发一个，等结果再发下一个。
3. **本地 URL 用 `127.0.0.1` 不用 `localhost`**：headless Chrome 对 localhost 偶有解析问题。端口仍从 `check-server.sh` 探测，不硬编码。
4. **全 N/A 陷阱**：若所有指标返回 N/A（`NO_FCP`），先用 `get_performance_score url="https://example.com"` 做对照——example.com 正常而目标站全 N/A，基本是页面有 **anti-debug 的 `debugger` 陷阱**拦了 Lighthouse 的 Debugger 域。绕过：找该站自己的 debug 后门参数（这类站通常留了一个，如 `?debug=true`、`?debug=1&bypass=1`），加到 URL 上再测。找不到后门就只能上 Playwright 量 `performance` API（见下方降级方案）——Playwright 不开 Debugger 域，不会触发陷阱。

**工具选用——第 4 步全维度体检默认会跑标 ✅ 的，其余按需：**

| 工具 | 默认? | 用途 | 建议参数 |
|---|---|---|---|
| `get_core_web_vitals` | ✅ 默认 | **首屏** LCP / FCP / CLS / TBT，最常用的入口 | `device:"mobile"`（Google 排名看移动端）、`includeDetails:true` |
| `get_performance_score` | ✅ 默认 | 综合分 + Speed Index / TTI（首屏完整画像） | 配 `get_core_web_vitals` 一起看 |
| `find_unused_javascript` | ✅ 默认 | **速度优化空间**：首屏未使用 JS（"过度打进首屏"的 chunk，体积第一抓手） | `minBytes:20000` 过滤噪声 |
| `get_lcp_opportunities` | ✅ 默认 | **量化未用 CSS**（`unused-css-rules`，唯一来源）+ LCP 慢时的机会项 | `device:"mobile"`、`includeDetails:true`；不要等 LCP 慢才跑 |
| `run_audit` | ✅ 默认 | 无障碍 / 最佳实践 / SEO 三维度评分 | `categories:["accessibility","best-practices","seo"]`、`device:"mobile"`；想要慢网速实测加 `throttling:true` |
| `get_accessibility_score` | ✅ 条件 | 无障碍分 < 90 时取失败项明细（只看 `score:0`） | `includeDetails:true` |
| `analyze_resources` | ✅ 默认 | 全量资源清单（喂给 `resource-report.py` 做拆解+缓存实测） | 输出会撑爆 token 且不含缓存 TTL，**靠脚本消化，别直接读** |
| `compare_mobile_desktop` / `check_pwa_readiness` / `get_security_audit` | 按需 | 移动桌面对比 / PWA / 安全，用户点名才跑 | — |

**判读 → 生成优化建议：**

- **综合分低但 FCP/LCP 绿 → 瓶颈在 TBT**（主线程被 JS 解析/执行阻塞），别误判成"图片大/LCP 慢"。优化重心是**减少首屏主线程 JS**：`find_unused_javascript` 命中的大块就是首屏脂肪，逐个异步化 / 移出首屏 / 切依赖链。
- **LCP 慢（>2.5s）** → 跑 `get_lcp_opportunities`，常见是首屏大图没预加载 / 被阻塞 CSS·JS 拖住 / 字体阻塞。
- **CLS 高（>0.1）** → 图片/广告/字体没占位导致布局抖动，给固定宽高或 `aspect-ratio` 占位。
- **缓存配错（看 `analyze_resources`）** → 静态资源（JS/CSS/图片/字体）若 cache TTL 短、甚至 `no-cache` / 缺 `Cache-Control`，二次访问白白重下，拖慢回访首屏。建议：带 hash 的静态产物上 `Cache-Control: public, max-age=31536000, immutable`（一年长缓存）；HTML 入口走 `no-cache` 或短 TTL 以便发版即时生效。同时 `analyze_resources` 报的未压缩 / 过大资源（没开 gzip/brotli、单文件过肥）也在这里一并提。
- **无障碍扣分** → 多是对比度不足、`<img>` 缺 alt、按钮无可访问名、表单缺 label，逐条对应 `get_accessibility_score` 的 details 整改。

把上面映射成**按收益排序、可落地**的建议——别只复述指标数字。

**输出建议用这个结构**（全维度体检要把下面各块都答到；某块确实无内容时一句"无问题"带过，别省略整块）：

```
## 渲染 & 报错
一句话：渲染对不对 + console error 计数（良性噪声要排除，说明哪些被排除）。

## Lighthouse 全维度体检（{url}，{device}）
| 维度 | 评分 | 评价 |
（性能综合分 / 无障碍 / 最佳实践 / SEO，🟢🟡🔴）

### 性能指标
| 指标 | 实测 | 阈值 | 评价 |
（FCP / LCP / CLS / TBT / Speed Index / TTI；🟢🟡🔴）

## 一、性能 — 首屏 & 速度优化空间
- 首屏快慢总判断 + 最慢的一项。
- "过度打进首屏"的 JS（find_unused_javascript，给 KB 与未用占比）。
- 未用 CSS（lcp_opportunities 的 unused-css-rules，给 KB 与占比）——别漏。

## 二、缓存 / 压缩 / 资源拆解（来自 resource-report.py）
- 资源按域名拆：自有(项目 OSS/CDN) vs 第三方各占多少，最大的几个是谁。
- 缓存实测：带 hash 的静态产物有没有长缓存（无 Cache-Control / max-age 偏短要点名）。
- 压缩实测：文本资源是否 gzip/br；有没有未压缩的大文件。
- legacy 包是否被现代浏览器误下载；大图是否该转 webp/avif。

## 三、无障碍（{分数}）
逐条列 `score:0` 的失败项 + 具体改法（label / 对比度 / 禁缩放 等）。

## 四、最佳实践（{分数}） / SEO（{分数}）
最佳实践扣分项（mixed content / 废弃 API / 控制台错误 等，区分自有 vs 三方）；SEO 同理。

## 瓶颈定位
一句话点出主短板（如"性能已绿，质量分被无障碍三项拖低"）。

## 优化建议（按收益排序，覆盖全维度）
1. 【高】<具体改动> —— 依据：<哪个指标/机会项>，预期收益：<量级>
2. 【中】...
3. 【低】...
（标注哪些是自有可控、哪些是第三方需反馈/代理）
```

> 性能/评分本来就好（各维度 90+、全绿）时别硬凑优化项——直说"无需优化"，把 unused 资源/缓存/压缩这类只减字节的列为「可选、收益低」即可，不要把锦上添花写成必须改。但**质量分（无障碍/最佳实践）的硬失败项即使性能满分也要如实列出**——它们往往改动小、收益明确，是"详细报告"最该给用户的落地项。

**降级方案（Lighthouse 跑不了时）**：页面有 debugger 陷阱又找不到 debug 后门，改用 Playwright `browser_evaluate` 读 `performance.getEntriesByType('navigation')` 与 `getEntriesByType('resource')`、`PerformanceObserver` 量 LCP——拿不到 Lighthouse 评分，但能拿首屏时间、资源体积、慢请求等真值。Playwright 默认不开 Debugger 域，`debugger` 是空操作，所以陷阱页它能跑。

### 容错 / 边界 / 全站批量测试（Node 脚本配方）

用户要「各种容错测试」「每个路由都看看」「清缓存/清 LocalStorage/登录态/CDN」时，用 MCP 一页页点太慢。改用 bundled 的 **Playwright 编程式脚本**（非 MCP），一条命令跑几十个页面 / 反复清存储 reload。三个脚本都**参数化**（传 baseURL，不硬编码站点），本地项目传 `http://127.0.0.1:{探测端口}`，线上传域名。

> **本机前提**：项目多半没装 `playwright`，脚本靠 `_pw.mjs` 自动回退到全局安装（`npm root -g`）。首次需 `npx playwright install chromium` 装内核。这些是**编程式 API**，和上面的 `browser_*` MCP 工具是两条路，别混。
>
> **⚠️ 后台运行必须用脚本绝对路径**：`run_in_background` 的 bash 继承的是**上一条命令 cd 到的目录**（常是项目根，不是 scripts 目录），`node route-audit.mjs ...` 会 `MODULE_NOT_FOUND`。后台跑一律写全路径，如 `node /Users/.../skills/fe-auto-test/scripts/route-audit.mjs ...`（或先在同一条命令里 `S=<绝对路径>` 再 `node "$S"`）。
>
> **http / https 都支持**：发请求统一走 `_http.mjs`，按 URL 协议自动分流（还处理了 family:4 强制 IPv4、brotli/gzip 手动解压两个坑），所以 `http://127.0.0.1:5173` 和线上域名都能测。但 `route-audit` / `ssr-status-sweep` 要靠 `/sitemap.xml` 列路由，**本地 dev server 通常没有 sitemap**——那时它们只测首页，要覆盖多路由得打线上域名。

**脚本目录**：`${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/fe-auto-test/scripts/`

| 脚本 | 干什么 |
|---|---|
| `_http.mjs` / `_pw.mjs` / `_lh.mjs` | 内部共用：HTTP 客户端 / playwright / lighthouse 的解析，不直接调 |
| `probe-headers.mjs` | 缓存压缩探针，被 `resource-report.py` 调用 |
| `http-headers.mjs` | CDN / 缓存 / 压缩 / SSR 冷启动 TTFB |
| `route-audit.mjs` | 逐路由抽样审计（渲染 + console + SEO meta） |
| `ssr-status-sweep.mjs` | 全站 SSR 状态清扫（抓 500） |
| `resilience-audit.mjs` | 容错 / 边界 / 守卫 / Hydration |

#### ① CDN / 缓存 / 压缩 / SSR 冷启动实测 —— `http-headers.mjs`

```bash
node http-headers.mjs <baseURL> [--cold] [--q='?debug=true']
```

- **为什么不用 curl**：本机 context-mode hook 拦 `curl`/`wget`（提示改走 ctx_execute），但**沙箱 fetch 连不上 Cloudflare**（ETIMEDOUT）。所以走 **node `https` 直连**，脚本已处理三个坑：`family:4` 强制 IPv4（否则 CF 的 IPv6 走不通挂起）、brotli 响应用 `zlib.brotliDecompressSync` 手动解压（`https` 不自动解压，不解压则 body 是二进制、正则抓不到资源名）、超时兜底。
- 拿 HTML 入口 / sitemap / robots / 抽样静态资源的 `cache-control`、`cdn-cache-control`、`content-encoding`、`x-vercel-cache`、`cf-cache-status`、HSTS。
- **判读**：带 hash 静态产物应 `max-age=31536000, immutable`；HTML 入口应短 `max-age` + `s-maxage`/`stale-while-revalidate`（发版即时生效 + 边缘缓存）；文本资源应 `br`。
- `--cold`：随机 query 强制绕过 CF 边缘缓存，测 **SSR 回源 TTFB**。`cf=MISS 且 TTFB>3s` = SSR 冷启动慢，**发版后 / 边缘缓存过期回源时首批用户会等这么久**（Lighthouse 偶发测出的 FCP 7s+ 常是这个，而非页面本身慢）。

#### ② 逐路由批量审计 —— `route-audit.mjs`

```bash
node route-audit.mjs <baseURL> [sampleCount=15] [--q='?debug=true']
```

- 从 `/sitemap.xml` 拉全部 URL，均匀抽样 N 条，逐个 Playwright 打开，一次性收集：渲染成功（`#app` children）、**去重后的业务 console 错误**（已排除广告/统计噪声）、每路由 SEO meta（title/description/canonical/og）是否齐全。
- **广告站坑**：AdSense 等长轮询会让 `networkidle` 永不达成、连 `domcontentloaded` 都被拖到 30s 超时。脚本用 `waitUntil:'commit'` + 短超时 `domcontentloaded` 兜底，**别用 networkidle**。
- **best-practices 低分甄别**：若逐路由「去重业务错误 = 无」但 Lighthouse best-practices 却很低（50 上下），根因基本是**第三方广告**（国内访问 Google 资源被墙 → 大量 `Failed to load resource` 控制台错误 + 第三方 cookie），不是站点自身代码。这类别算到站点头上。
- **⚠️ 抽样会漏坏路由**：`route-audit.mjs` 默认只抽样 20 条，**抓不全** SSR 500 这类「整条路由崩」的致命 bug（实测 tools 站 10 条路由 SSR 500，抽样只命中 1 条）。用户说「每个路由都看下 / 找出所有坏页」时，**必须**再跑下面的 `ssr-status-sweep.mjs` 做全量覆盖，不能只靠抽样下结论。

#### ②b 全站 SSR 状态清扫（全量，抓致命 500）—— `ssr-status-sweep.mjs`

```bash
node ssr-status-sweep.mjs <baseURL> [--q='?debug=true'] [--concurrency=8]
```

- 拉 `/sitemap.xml` 的**全部** URL，逐个 `GET`（**不开浏览器**，纯 `node:https`），只判 HTTP 状态码 + 抽 SSR 500 的错误首行，按错误提示归类汇总。几百条路由几十秒跑完，比 Playwright 快几十倍，可全量。
- **专治 SSR 500**：某些路由服务端**模块实例化/渲染就崩**，返回错误栈 HTML、无 `#app`，浏览器硬导航/爬虫拿到的是白屏且**被 Google 判为坏页 → 掉收录**。`<client-only>` 挡不住这类——崩在**路由 chunk 模块实例化**阶段，早于渲染。
- **最高频根因**：CJS 包（`gifenc`/`fflate`/`crypto-es`/`wasm-webp` 等）被**静态 `import`** 进路由 chunk，被 SSR 外部化后 Node 按严格 ESM 加载 CJS → `does not provide an export named 'X'`。**修法**：① 把该包加进 `vite.config.ts` 生产 `ssr.noExternal`（让 vite 构建期走它的 ESM 产物、解析具名导出，一行搞定，与已有 `fflate`/`crypto-es` 同款）；② 或组件内改 `await import('包名')` 懒加载。
- 用它做 baseline，修完再跑一次应「全站 200」。

#### ③ 容错 / 边界测试 —— `resilience-audit.mjs`

```bash
node resilience-audit.mjs <baseURL> [--q='?debug=true'] [--guard='/system,/user/center']
```

跑 5 个场景，正是用户要的「登录/刷新/清缓存/清 LocalStorage/已登录未登录」：

1. **正常首访**：打印 localStorage / sessionStorage / cookie 结构 —— 一眼看出**登录态、签名密钥、主题配置存在哪**（cookie vs localStorage vs sessionStorage）。
2. **清空所有存储后 reload**（等价隐身/清缓存/清 LocalStorage）：`children<=0` = 白屏缺陷；正常渲染 = 容错 OK。
3. **注入损坏存储数据后 reload**（脏 cookie / 非法 JSON / 非法主题值）：崩溃 = 容错缺陷。SSR 站这步常暴露 **Hydration mismatch**。
4. **未登录访问受保护路由**（`--guard` 指定，如 `/system,/user/center`）：看守卫是**重定向**（✅）、**停留渲染空壳**（⚠️ 该拦没拦）还是**报错**。这就是「已登录 vs 未登录差异」的核对。
5. **连续两次访问首页**：检 `Hydration completed but contains mismatches`。**SSR 站关键**——mismatch>0 说明 SSR 输出的 DOM 与客户端首帧不一致，Vue 丢弃 SSR 结果重新客户端渲染，**白白浪费 SSR + 可能首屏闪烁**。排查方向：主题 cookie 读取时机 / `Date` / `Math.random` / `import.meta.env.SSR` 条件渲染分支。

> **登录态说明**：脚本不含真实账号密码登录（没凭据）。它测的是**未登录降级 + 守卫 + 脏存储容错**。要测真实登录后行为，补 `browser_fill_form` 填登录页或预置有效 cookie 再复用 context。

> **有反调试的站**：这几个脚本走 Playwright，不开 Debugger 域，**不会触发 anti-debug 的 `debugger` 陷阱**，所以哪怕目标站测不了 Lighthouse，渲染 / 逐路由 / 容错 / CDN 缓存这些照样能测。若站点仍有拦截，用 `--q='?debug=true'` 之类的 debug 后门参数绕过。

## 操作原则

- **自己跑完整闭环、自己读结果、自己下结论**，不要问"要不要我打开浏览器"——需要真实渲染就直接走流程。
- 报错优先级：console error > snapshot 结构 > 截图。截图是给人看的旁证，定位问题主要靠前两个。
- 端口一律从脚本拿，绝不硬编码。
- 验证完务必清理截图 + 关掉自己起的服务，别留下后台进程和散落文件。
- 改完 skill 记得刷 cache 并重启会话（见 plugin-refresh skill）。
