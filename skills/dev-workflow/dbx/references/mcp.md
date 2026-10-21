# 官方文档与 MCP 路由（dbx）

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
     --name 'my-local-db' --host '127.0.0.1' --port 3306 \
     --username 'app_user' --database 'app_db' --password-stdin --probe
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
