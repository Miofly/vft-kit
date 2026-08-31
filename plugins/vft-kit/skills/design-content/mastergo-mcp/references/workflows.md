# MasterGo MCP 工作流

仅在实际操作设计稿时读取本文件。工具名以当前 MCP 暴露结果为准；缺少预期工具时先运行 `doctor`，不要凭空替代。

## Vibe：本机画布

### 读取选区或生成代码

1. 用选区读取工具取得节点 ID、结构和截图；没有选区就请用户在 MasterGo 中选中目标。
2. 先获取设计规范或变量，复用团队库组件与 token。
3. 生成代码后在本地运行并做浏览器验证；需要回写画布时再进入同步流程。

常见工具：`get_guidelines`、`get_selection_code`、`get_selection_image`、`get_variables`、团队库/组件查询工具。

### 新建或最小修改

1. 新页面先读取规范，再调用 `design_page`；修改现有设计先定位精确节点 ID。
2. 单次调用只承担一个可验证改动：新增用 `agent_update_node`，替换用 `agent_replace_node`，删除用 `agent_remove_node`。
3. 回读目标节点或截图；跨多个节点的改动用 `get_design_diff` 核对。

删除节点或变量前必须确认当前请求含明确删除授权和精确目标；已经明确授权时直接执行并验证，不重复询问。

### HTML 全量同步

1. 启动并验证本地 Vue/React 页面，等待数据和字体稳定。
2. 获取最终渲染的静态 HTML/CSS；不要提交组件源文件、开发服务器 URL 或未完成页面。
3. 明确目标文件/页面/根节点和覆盖范围。当前请求没有覆盖授权时先确认；已有“全量同步/覆盖”等明确授权时直接继续。
4. 调用 `agent_sync_design`，再用 `get_design_diff`、截图或目标节点回读验证。
5. 若连接中断，不重试写入；先检查配置 URL 和实际监听端口，恢复当前文件连接后重新读取目标。

### 变量与组件

- 先 `get_variables`，按精确 collection/variable ID 更新；不要凭同名批量匹配。
- 新建、修改后回读变量值和作用域；删除后确认引用影响。
- 查团队库或组件时先获取列表/元数据，再请求具体组件，避免全量拉取。

## Magic：链接读取与 D2C

1. 解析 `https://<domain>/file/<fileId>?layer_id=<layerId>` 或 `/goto/<shortLink>`；保留用户给出的域名，禁止强改为公网域名。
2. 先调用 `getMeta` / `getDesignSections` 确认文件、页面、layer 和规则。
3. 按目标选择最小工具（工具名以 `tools/list` 实际返回为准；0.2.8 实测为 `getDsl`、`getMeta`、`getDesignSections`、`getPageLayers`、`extractSvg`、`getD2c`、`getComponentLink`、`getComponentGenerator`、`applyDesign`）：
   - 结构或还原代码：`getDsl`
   - SVG：`extractSvg`
   - 页面下的画板清单：`getPageLayers`
4. 默认 `json`；重复样式多、追求省 token 时用 `yaml` 或 `tree`。文本逐字还原优先 `json`。
5. “没有权限”时依次核对 Token 是否存在、账户是否团队版、文件是否在团队项目而非草稿箱；不要反复重试或输出凭据。

### 短链 `/goto/xxx`

工具参数里的 `shortLink` 是客户端解析的，**裸 HTTP 接口不认**，直接传返回 `invalid fileId: empty`。自己解一次 301 就能同时拿到 `fileId` 和 `layer_id`，省掉开浏览器：

```bash
curl -s -o /dev/null -w '%{redirect_url}\n' 'https://<domain>/goto/<code>'
```

### 链接没有 layer_id 时（`needsCanvasVisit`）

`getPageLayers` 可能返回 `totalLayers: 0`、`needsCanvasVisit: true`，提示“请在 MasterGo 中打开该文件并切换到目标页面”。这是**服务端图层缓存为空**，不是权限问题——`getMeta` 同时返回空 `<info></info>`。

不要停在这里让用户去点，也不要反复重试同一个调用。**实测用浏览器打开画布并不会把这个缓存刷起来**（它由 MasterGo 官方客户端上报），但 `getDsl(fileId, layerId)` 只要有 layerId 就能正常返回。所以正确路径是自己去画布里取 ID：

1. 用浏览器打开该文件页面（登录态见对应私有 skill），等 `window.mg.document` 就绪。
2. 跑 `scripts/enumerate-containers.js` 拿到 `pages[].children[].id`，那就是 layerId（形如 `9:2990`）。
3. 用 `fileId + layerId` 调 `getDsl` / `extractSvg`，绕开页面级缓存。

页面是懒加载的：非当前页的 `children` 可能为空，用它的 `pageId` 重新打开一次 `?page_id=<pageId>` 再枚举。可直接拼图层链接 `https://<domain>/file/<fileId>?page_id=<pageId>&layer_id=<layerId>`。

Magic 是远程读取/D2C，不用于修改本机画布。需要写画布时切回 Vibe，并先恢复本地连接。

## Browser：Canvas 只读回退

MasterGo 编辑器和原型预览主要渲染在 Canvas 上，普通 `curl`、DOM 抓取或网页转 Markdown 只能得到页面外壳。MCP 不适合当前目标、没有暴露所需读取工具，或上一节的 `needsCanvasVisit` 让 Magic 拿不到 layerId 时，可用浏览器打开真实页面，确认 `window.mg.document` 就绪后执行以下公开脚本：

- `scripts/enumerate-containers.js`：枚举页面和顶层画板并过滤连接线；原型页疑似有单一外层容器时同时返回 `nestedCandidate`，先核对它确实是包装层，再把 `DRILL_SINGLE_WRAPPER` 改为 `true` 重跑。
- `scripts/extract-text.js`：递归提取每个画板的界面文案与便签批注；确认外层容器后使用同一钻层开关，可用 `PAGE_ID` 和 `MAX_LEN` 控制范围。
- `scripts/measure-layout.js`：填写真实 `BOARD_ID`，读取直接子级布局、嵌套文本、颜色、圆角和相邻间距；可用 `NAMES`、`Y_MIN`、`Y_MAX` 缩小范围。
- `scripts/collect-export-nodes.js`：列出被标记为切图的节点（有 `exportSettings` 的节点 + `SLICE` 节点），返回每个节点的格式、倍率和后缀。传 `{ rootId }` 限定画板，不传就是整页。

### 导出切图

画布里的节点带 `exportAsync({ format, constraint })`（MasterGo 插件 API，同源页面可直接调），返回字节流——这才是设计师标注的那份切图，截图和 DSL 里的图片填充 URL 都替代不了：填充 URL 只有位图底图，图标那类矢量切图取不到。流程是 `collect-export-nodes.js` 找节点 → 逐个 `exportAsync` → 字节转 base64 传回落盘。

**格式默认 PNG。** 导出设置里没写格式、或用户没点名要别的格式时，一律导 PNG（带透明通道，图标和整屏都适用）。只有用户明确要 SVG / JPG，或目标节点是纯矢量且下游要直接内联时才换。

**Magic MCP 导不了位图切图。** 它的工具集（`getDsl` / `getMeta` / `getDesignSections` / `getPageLayers` / `extractSvg` / `getD2c` / `getComponentLink` / `getComponentGenerator` / `applyDesign`）只有 `extractSvg` 出图，且只出矢量。位图切图必须走画布，MCP 装没装都一样。

四个必须知道的行为：

- **导出尺寸按渲染边界算，不是图层框。** 带 backdrop-filter / 投影的节点会把效果外扩范围一起导出，36×36 的按钮可能出来 216×216（内容居中，四周透明）。要精确尺寸就让设计师加切片框，或导出后自己裁。
- **文件名后缀别叠加。** 导出设置里的 `fileName` 字段（`isSuffix: true`）通常已经是 `@3x`，再按倍率自动补一次就成了 `_@3x@3x`。
- **headless 下 `exportAsync` 会静默返回空白图。** Playwright 默认拉的是 `chromium_headless_shell`，没有可用 WebGL，画布纹理根本没渲染：导出**不报错**，尺寸也对，但字节数极小（1080×970 的图出来 4 KB、768×220 的按钮 1 KB），打开是全透明。别当成「设计师标错切图」。跳到 layer 链接聚焦画板也没用，这是渲染后端的问题不是可视区问题。装完整 chromium（`npx playwright install chromium`）走 `--headed` 可能解决，但下载常卡；卡住就直接换下面的原图路径，别干等。
- **`SLICE` 节点导出本来就可能是空的。** 切片框自身没有填充和子节点，导不导得出取决于实现，别把它的空白当作上一条的证据——先拿一个带图片填充的叶子节点验证。

**空白时的正解：取原图 + 本地合成。** 图片填充节点的 `fills[].imageRef` 能直接换回设计师上传的原始资源，分辨率通常比切图还高（实测月亮 3368×3464、按钮 1781×883）：

```js
const img = await window.mg.getImageByHref(imageRef);
const bytes = await img.getBytesAsync();   // Uint8Array，转 base64 传回落盘
```

多图层的切图区（辉光 + 主体 + 装饰）就把每层原图按几何关系用 ffmpeg 叠起来。几何用**绝对坐标差**算，别直接用 `node.x/y`（那是相对父级的）：递归累加父级偏移拿到画板绝对坐标，再减去切片框的绝对坐标，得到每层在切图内的落点；图层的 `opacity` 用 `colorchannelmixer=aa=` 还原，`scaleMode: STRETCH` 就把原图缩到图层框尺寸。

把脚本完整的 `() => { ... }` 作为浏览器 evaluate 函数执行，并直接返回数据。不要把隔离环境的 `filename` 当作可供本机读取的输出；返回过大时按页面、画板或 y 区间分批。

不要仅凭“唯一顶层节点且有多个子节点”自动钻层：它也可能是合法的单画板。布局脚本只为横向范围重叠且垂直不重叠的直接子级计算 gap；横排、重叠或 `NAMES` 跨层筛选只返回原始 bbox。

这一路径只读，不等价于 Vibe 写画布。读取后的实现仍需在目标项目运行并做浏览器验证；设计坐标换算应依据实际画板宽度和项目的 viewport/rem 配置，不能固定假设 1080 或直接等同 CSS px。
