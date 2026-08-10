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
3. 按目标选择最小工具：
   - 结构或还原代码：`getDsl`
   - SVG：`getDesignSvgs` / `extractSvg`
   - 文本：`getDesignTexts`
   - 组件开发流程：`getComponentWorkflow`
4. 默认 `json`；重复样式多、追求省 token 时用 `yaml` 或 `tree`。文本逐字还原优先 `json`。
5. “没有权限”时依次核对 Token 是否存在、账户是否团队版、文件是否在团队项目而非草稿箱；不要反复重试或输出凭据。

Magic 是远程读取/D2C，不用于修改本机画布。需要写画布时切回 Vibe，并先恢复本地连接。

## Browser：Canvas 只读回退

MasterGo 编辑器和原型预览主要渲染在 Canvas 上，普通 `curl`、DOM 抓取或网页转 Markdown 只能得到页面外壳。MCP 不适合当前目标或没有暴露所需读取工具时，可用浏览器打开真实页面，确认 `window.mg.document` 就绪后执行以下公开脚本：

- `scripts/enumerate-containers.js`：枚举页面和顶层画板并过滤连接线；原型页疑似有单一外层容器时同时返回 `nestedCandidate`，先核对它确实是包装层，再把 `DRILL_SINGLE_WRAPPER` 改为 `true` 重跑。
- `scripts/extract-text.js`：递归提取每个画板的界面文案与便签批注；确认外层容器后使用同一钻层开关，可用 `PAGE_ID` 和 `MAX_LEN` 控制范围。
- `scripts/measure-layout.js`：填写真实 `BOARD_ID`，读取直接子级布局、嵌套文本、颜色、圆角和相邻间距；可用 `NAMES`、`Y_MIN`、`Y_MAX` 缩小范围。

把脚本完整的 `() => { ... }` 作为浏览器 evaluate 函数执行，并直接返回数据。不要把隔离环境的 `filename` 当作可供本机读取的输出；返回过大时按页面、画板或 y 区间分批。

不要仅凭“唯一顶层节点且有多个子节点”自动钻层：它也可能是合法的单画板。布局脚本只为横向范围重叠且垂直不重叠的直接子级计算 gap；横排、重叠或 `NAMES` 跨层筛选只返回原始 bbox。

这一路径只读，不等价于 Vibe 写画布。读取后的实现仍需在目标项目运行并做浏览器验证；设计坐标换算应依据实际画板宽度和项目的 viewport/rem 配置，不能固定假设 1080 或直接等同 CSS px。
