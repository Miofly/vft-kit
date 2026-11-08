# DBX 数据库客户端

DBX（dbxio.com）是本地优先的跨平台数据库客户端。默认走 DBX MCP 的 stdio 路径：静默、可重复、不抢前台；只有 MCP 不适用或用户明确要求看桌面 UI 才操作 DBX Desktop。

不要把 DBX 的本地配置数据库（`~/Library/Application Support/com.dbx.app/dbx.db`）当成业务数据库直接改写。它就是 SQLite，里面 `connections` 表只有 `id` + `config_json`，密码在 `connection_secrets` 表——只能读来做诊断，写连接必须走 MCP 或桌面端。

## 官方文档

- <https://dbxio.com/cn/docs/getting-started>
- <https://dbxio.com/cn/docs/driver-management>
- <https://github.com/t8y2/dbx/blob/main/docs/content/docs/mcp.mdx>

## 路由

1. 先确认目标连接、数据库/Schema、动作（只读、写入、DDL、删除或导出）和结果形式。连接名相似时先列出连接并让用户指定，禁止猜生产目标。
2. 能用 MCP 时调用 DBX MCP：`dbx_list_connections` → `dbx_list_tables` / `dbx_describe_table` → `dbx_execute_query`。需要跨多步保持 `USE`、临时表、事务或会话变量时，先 `dbx_open_session`，结束后 `dbx_close_session`。
3. 需要桌面显示时用 `dbx_open_table` 或 `dbx_execute_and_show`；DBX Desktop 必须运行。MCP 的查询工具不一定需要桌面运行，Agent/JDBC、SSH、代理和外部驱动则依赖 DBX 中对应组件。
4. 当前宿主没有 `mcp__dbx__*` 工具时，用随附的静默封装，不把密码放在 argv、日志或项目配置：

   ```bash
   SOFT_OPS="${VFT_KIT_DIR:-/path/to/vft-kit}/skills/workplace-tools/soft-ops"
   printf '%s' "$DB_PASSWORD" | node "$SOFT_OPS/scripts/dbx/dbx-mcp.mjs" add-mysql \
     --name 'my-local-db' --host '127.0.0.1' --port 3306 \
     --username 'app_user' --database 'app_db' --password-stdin --probe
   ```

   脚本先列出现有连接：同名且目标一致时幂等跳过，目标不一致时失败；新增后自动执行 `SELECT 1 AS dbx_probe`。密码只从 stdin 传入，禁止打印或写文件。

   默认用 `npx -y @dbx-app/mcp-server`；已装原生服务时设 `DBX_MCP_COMMAND=dbx-mcp-server`，用 JSON 数组设 `DBX_MCP_ARGS`（原生二进制要求 `DBX_MCP_ARGS='[]'`）。数据目录默认 macOS 的 `~/Library/Application Support/com.dbx.app`，`DBX_DATA_DIR` 必须指向包含 `dbx.db` 的目录而不是文件本身。

   只有用户要求让宿主长期配置 MCP 时才写 `.mcp.json`：

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

   连接白名单和执行模式在 DBX「设置 → MCP」管理；不要把密码或权限变量写进项目配置。
5. MCP 不适用或用户明确要求「在软件里操作」时，才打开 DBX Desktop（macOS `open -a DBX`），按稳定的菜单/按钮文字定位；不要依赖截图坐标。静默任务禁止把 DBX 置前、模拟键盘、改写剪贴板或使用固定坐标。每次导航、保存、切换连接后重新观察界面。

## 数据安全升级与本地密钥（DBX 0.6.x 起，2026-11-07 实测）

DBX 0.6.x 把连接密码、SQL history 等敏感配置改成用**本地加密密钥**加密，密钥存在 macOS Keychain（service=`com.dbx.app.secret-store.v1`，account=`local-data-encryption-key`）。升级后首次启动会强制走一遍迁移向导，不完成则 MCP 全部拒绝服务。

### 症状与对应解法

| 报错 | 含义 | 做法 |
|---|---|---|
| `DATA_MIGRATION_REQUIRED: open DBX Desktop or Web to complete the data security upgrade` | 迁移向导没跑过 | 升级到 ≥0.6.x 后重开桌面端，向导会自动弹出，点「开始迁移」 |
| `SECRET_KEY_UNAVAILABLE ... KEYRING_ACCESS_FAILED` | 迁移完成但当前进程读不到 Keychain 里的密钥 | 见下面「非 GUI 进程取密钥」 |
| `设置 → MCP` 显示「MCP Server 未安装」 | server 没装 | 点「安装」（`npm install -g @dbx-app/mcp-server@latest`） |

三个问题是独立的，可能同时存在；`DATA_MIGRATION_REQUIRED` 会遮住后面的，先把升级做完再排查下一个。

### 升级步骤（低版本没有入口，必须升到 0.6.x）

0.5.x 的设置里搜「安全」「密钥」都搜不到迁移项，`data_migrations` 表也是空的——**不是 bug，是这个功能 0.6.x 才有**。

1. 查最新版：`curl -s https://dl.dbxio.com/releases/latest/latest.json | python3 -c "import json,sys;print(json.load(sys.stdin)['version'])"`，macOS arm64 包地址在同文件 `platforms.darwin-aarch64-app.url`（当前 `DBX_<版本>_arm64.app.tar.gz`，约 46MB）。
2. 下载后 `tar xzf`，用 `codesign -dv` 确认 `Authority=Developer ID Application: xianbin yin (TVDM965TDL)`，`codesign --verify` 返回 0。
3. 备份 `/Applications/DBX.app`，`osascript -e 'tell application "DBX" to quit'`（可能返回 -128 表示用户取消，改用 `kill` 或确认进程数已为 0），再替换、`xattr -dr com.apple.quarantine`。
4. 启动后向导自动出现：**第 1 步页面内容比窗口高，「开始迁移」按钮在视口外拿不到 AX token**，先按两次 Tab 让整页重排，再读一次 window state 就能拿到按钮 token。点「开始迁移」→ 迁移秒级完成、显示「迁移已完成且密文验证通过」→ 点「进入 DBX」。**备份目录 `dbx-secret-migration-<uuid>` 先留着**，确认所有连接能连上再删。

### 非 GUI 进程取密钥（MCP / CLI）

`dbx-mcp --authorize-keychain` 在终端里反复报 `KEYRING_ACCESS_FAILED: existing DBX Keychain key cannot be authorized: The user name or passphrase you entered is not correct`（Keychain 已解锁、`security find-generic-password` 明文能读出，说明是二进制自身的 keychain 授权路径不通）。**不要再试**。

可靠做法是把密钥经 `DBX_SECRET_KEY` 环境变量传给子进程：

```bash
DBX_SECRET_KEY="$(security find-generic-password -s com.dbx.app.secret-store.v1 -g 2>&1 \
  | sed -n 's/^password: "\(.*\)"$/\1/p')" node scripts/dbx/dbx-mcp.mjs list
```

`scripts/dbx/dbx-mcp.mjs` 已内置这段：环境里没有 `DBX_SECRET_KEY` / `DBX_SECRET_KEY_FILE` 时，自动从 Keychain 取一次再传给 MCP 子进程，密钥只在进程内存里，不打印、不落盘。也支持 `DBX_SECRET_KEY_FILE` 指向一个 0600 文件（headless / Linux 用）。

注意 `security` 把 `password: "…"` 打在 **stderr**，只读 stdout 拿不到；脚本用 `2>&1` 合并后再按行匹配。

### 桌面端流程

### 新建或修改连接

点「新建连接」，选数据库类型，填主机、端口、用户名、数据库和密码；SQLite、DuckDB、Access 用本地文件。支持 URL 的数据库可粘贴连接 URL，但保存前必须复核解析出的字段。需要私网访问时在「网络选项」配 SSH Tunnel、HTTP/SOCKS5 代理或 TLS。

点「测试」确认网络、凭据和权限。MCP 新增连接用 `dbx_add_connection`，随后用 `dbx_execute_query` 执行只读探针；不要为了「测试」执行写入 SQL。报告只说连接名、类型、主机/端口的非敏感部分和测试结果，不输出密码、完整 URL、SSH 私钥或连接字符串。

### 多环境连接

用户要求配多个环境时，先从项目实际配置读每个环境的 `master` 数据源，逐个确认连接名、主机、端口、数据库和权限；不要按 profile 名猜环境，也不要顺手加未要求的副本或从库。每个连接加完执行 `SELECT 1 AS dbx_probe`，再列出连接回读名称、类型、主机、端口和数据库。

### 驱动管理

内置 Rust 驱动直接用；Oracle、KingbaseES、XuguDB、DuckDB 等可能需要原生 Agent，JDBC 数据库还需要匹配 Agent、JDBC 驱动和 JRE。进入「设置 → 驱动」或连接对话框的驱动提示安装，装完回连接重新测试。安装/更新/导入离线包属于环境变更，先确认目标数据库和 CPU/操作系统包；不要手工复制 Agent 文件，也不要把其他平台 ZIP 导入。

### 查询、数据和结构

- SQL 编辑器里先执行 `SELECT`、`EXPLAIN` 或元数据查询验证连接和范围，再执行变更。
- 查数据优先用表格的过滤、排序和 SQL 预览；编辑单元格、导入、传输、SQL 文件、Schema 同步前复核生成的 SQL 和影响行数。
- 结构排查按「表/视图/集合 → 列 → 索引/外键/触发器」逐层确认；不要因列表为空就假设连接失败，先确认当前数据库/Schema 和权限。
- 查询结果默认按 DBX/MCP 返回的行数上限处理；需要完整导出时用用户指定的 DBX 导出流程或业务数据库原生备份，不循环扩大查询上限。

## 写入、生产保护与完成验证

- 只读、诊断、计数、结构查看可直接执行。
- `INSERT`、`UPDATE`、`DELETE`、DDL、导入、传输、Schema 同步、删除连接或数据库前，先明确目标连接、SQL、筛选条件、预计影响范围和是否可回滚；用户未明确授权时停在预览/生成 SQL。
- 生产连接优先用数据库只读账号和 DBX Read-only；启用 Production protection。DBX 或数据库要求二次确认时不能绕过。
- 变更前优先在事务、备份或临时对象里验证；执行后回读受影响行/结构和业务状态。超时不代表失败，先查状态再重试，避免重复写入。
- MCP Settings 里只允许目标连接，默认 Read only 或 Data read/write；不要用 Full Access 当捷径。
- 每个操作报告「已完成 / 已跳过 / 被阻塞 / 未验证」，至少留一条可复核证据：测试连接结果、查询结果摘要、影响行数、回读后的结构/状态或 UI 中的成功状态。不要把 `dbx.db` 内容、凭据或敏感查询结果写进日志、提交或 skill 文件。
