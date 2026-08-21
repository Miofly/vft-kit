---
name: dbx
description: >-
  操作 DBX（dbxio.com 的跨平台数据库客户端）：创建、测试和维护数据库连接，管理驱动，查看结构和数据，编写或执行 SQL，使用 DBX MCP，或在桌面 UI 中打开结果。用户提到 DBX、数据库连接、DBX 驱动管理、DBX SQL 编辑器或 DBX MCP 时使用；不用于无关的数据库 CLI 或其他同名 dbx 工具。
---

# DBX

DBX 是本地优先的数据库客户端。默认走 DBX MCP 的 stdio 路径，适合静默、可重复、不会抢前台的连接和查询操作；只有 MCP 不适用，或用户明确要求看桌面 UI，才操作 DBX Desktop。不要把 DBX 的本地配置数据库当成业务数据库直接改写。

官方文档（功能变化时先查）：

- <https://dbxio.com/cn/docs/getting-started>
- <https://dbxio.com/cn/docs/driver-management>
- <https://github.com/t8y2/dbx/blob/main/docs/content/docs/mcp.mdx>

## 路由

1. 先确认目标连接、数据库/Schema、动作（只读、写入、DDL、删除或导出）和结果形式。连接名相似时先列出连接并让用户指定，禁止猜生产目标。
2. 能用 MCP 时调用 DBX MCP：`dbx_list_connections` → `dbx_list_tables` / `dbx_describe_table` → `dbx_execute_query`。需要跨多步保持 `USE`、临时表、事务或会话变量时，先 `dbx_open_session`，结束后 `dbx_close_session`。
3. 需要桌面显示时用 `dbx_open_table` 或 `dbx_execute_and_show`；DBX Desktop 必须运行。MCP 的查询工具不一定需要桌面运行，Agent/JDBC、SSH、代理和外部驱动则依赖 DBX 中对应组件。
4. 当前宿主没有 `mcp__dbx__*` 工具时，使用随附的静默封装，不把密码放在 argv、日志或项目配置：

   ```bash
   DBXCTL="${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/dev-workflow/dbx/scripts/dbx-mcp.mjs"
   printf '%s' "$DB_PASSWORD" | node "$DBXCTL" add-mysql \
     --name 'wfly-spring-local' --host 'mysql6.sqlpub.com' --port 3311 \
     --username 'vftshare' --database 'spring_local' --password-stdin --probe
   ```

   脚本先列出现有连接：同名且目标一致时幂等跳过，目标不一致时失败；新增后自动执行 `SELECT 1 AS dbx_probe`。`DB_PASSWORD` 只在当前进程内从用户已授权的本地配置读取后通过 stdin 传入，禁止打印或写文件。

   默认使用 `npx -y @dbx-app/mcp-server`；已安装原生服务时可设置 `DBX_MCP_COMMAND=dbx-mcp-server`，并用 JSON 数组设置 `DBX_MCP_ARGS`。默认数据目录是 macOS 的 `~/Library/Application Support/com.dbx.app`，`DBX_DATA_DIR` 必须指向包含 `dbx.db` 的目录。

   只有用户要求让宿主长期配置 MCP 时，才写 `.mcp.json`；最小配置为：

   ```json
   {
     "mcpServers": {
       "dbx": {
         "command": "npx",
         "args": ["-y", "@dbx-app/mcp-server"]
       }
     }
   }
   ```

   连接白名单和执行模式在 DBX“设置 → MCP”中管理；不要把密码或权限变量写进项目配置。macOS 本地数据目录通常是 `~/Library/Application Support/com.dbx.app`，`DBX_DATA_DIR` 若要覆盖必须指向包含 `dbx.db` 的目录，而不是文件本身。
5. MCP 不适用或用户明确要求“在软件里操作”时，才打开 DBX Desktop（macOS 可用 `open -a DBX`），通过可用的桌面自动化能力定位稳定的菜单/按钮文字；不要依赖截图坐标。静默任务禁止把 DBX 置前、模拟键盘、改写系统剪贴板或使用固定坐标。每次导航、保存、切换连接后重新观察界面。

## 桌面端常用流程

### 新建或修改连接

点击“新建连接”，选择数据库类型，填写主机、端口、用户名、数据库和密码；SQLite、DuckDB、Access 使用本地文件。支持 URL 的数据库可粘贴连接 URL，但保存前必须复核解析出的字段。需要私网访问时在“网络选项”配置 SSH Tunnel、HTTP/SOCKS5 代理或 TLS。

点击“测试”确认网络、凭据和权限。MCP 新增连接时用 `dbx_add_connection`，随后用 `dbx_execute_query` 执行只读探针；不要为了“测试”执行写入 SQL。报告时只说连接名、类型、主机/端口的非敏感部分和测试结果，不输出密码、完整 URL、SSH 私钥或连接字符串。

### wfly-spring 两库

用户说“wfly-spring 的两个数据库”时，默认只处理两个 `master` 数据源：

- `application-local.yaml` → `spring_local`，连接名 `wfly-spring-local`
- `application-dev.yaml` / `application-prod.yaml` → `vftdream`，连接名 `wfly-spring-prod`

从对应 JDBC URL 所在的 `master` 块读取 host、port、username、password；不要把 `slave` 的 `yjsydzm` 顺手加入，也不要把 profile 名 `dev` 当成非生产库。两个连接都添加后分别执行 `SELECT 1 AS dbx_probe`，再列出连接回读名称、类型、主机、端口和数据库。

### 驱动管理

内置 Rust 驱动可直接用；Oracle、KingbaseES、XuguDB、DuckDB 等可能需要原生 Agent，JDBC 数据库还需要匹配 Agent、JDBC 驱动和 JRE。进入“设置 → 驱动”或连接对话框的驱动提示安装，安装后回到连接重新测试。安装/更新/导入离线包属于环境变更，先确认目标数据库和 CPU/操作系统包；不要手工复制 Agent 文件，也不要把其他平台 ZIP 导入。

### 查询、数据和结构

- SQL 编辑器中先执行 `SELECT`、`EXPLAIN` 或元数据查询验证连接和范围，再执行变更。
- 查看数据优先使用表格的过滤、排序和 SQL 预览；编辑单元格、导入、传输、SQL 文件、Schema 同步前复核生成的 SQL 和影响行数。
- 结构排查按“表/视图/集合 → 列 → 索引/外键/触发器”逐层确认；不要因列表为空就假设连接失败，先确认当前数据库/Schema 和权限。
- 查询结果默认按 DBX/MCP 返回的行数上限处理；需要完整导出时使用用户指定的 DBX 导出流程或业务数据库原生备份，不循环扩大查询上限。

## 写入和生产保护

- 只读、诊断、计数、结构查看可直接执行。
- `INSERT`、`UPDATE`、`DELETE`、DDL、导入、传输、Schema 同步、删除连接或数据库前，先明确目标连接、SQL、筛选条件、预计影响范围和是否可回滚；用户未明确授权时停在预览/生成 SQL。
- 生产连接优先使用数据库只读账号和 DBX Read-only；启用 Production protection。若 DBX 或数据库要求二次确认，不能绕过。
- 变更前优先在事务、备份或临时对象中验证；执行后回读受影响行/结构和业务状态。超时不代表失败，先查询状态再重试，避免重复写入。
- MCP Settings 中只允许目标连接，默认 Read only 或 Data read/write；不要启用 Full access 作为捷径。

## 完成验证

每个操作都要报告“已完成 / 已跳过 / 被阻塞 / 未验证”。至少保留一条可复核证据：测试连接结果、查询结果摘要、影响行数、回读后的结构/状态或 DBX UI 中的成功状态。不要把 DBX 的本地 `dbx.db` 文件内容、凭据或敏感查询结果写入日志、提交或 skill 文件。
