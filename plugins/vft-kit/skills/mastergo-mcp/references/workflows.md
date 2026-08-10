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
