---
name: vercel-ops
description: >-
  通用 Vercel API 操作封装：projects CRUD、deployments 管理(创建/查询/取消/重新部署)、domains CRUD、环境变量 CRUD、logs 查询、aliases 管理、teams 管理、Edge Config CRUD、Blob 存储操作、Serverless Functions、Cron Jobs、webhooks、监控指标、通用 API 透传。
  零依赖(Node 18+)，多 profile 支持。token 从环境变量或配置文件读取，环境变量优先于 config file。
  子命令：verify、projects、deployments、domains、env、logs、aliases、teams、edge-config、blob、functions、crons、webhooks、monitoring、api。
  适合任何 Vercel 账号，不含私有信息。使用场景：部署项目、查看部署状态、管理环境变量、配置域名、查询日志、管理团队、操作 Edge Config、Blob 存储、Serverless Functions、定时任务等。
---

# vercel-ops

通用 Vercel API 操作封装。**可开源、不含私有信息。** 适合任何需要管理 Vercel 项目/部署/域名/环境变量的场景。

## 特性

- ✅ **多 profile 支持**：一个脚本管理多个 Vercel 账号，`--profile <name>` 切换
- ✅ **零依赖**：Node 18+ 内置 fetch
- ✅ **密钥外部化**：token 从环境变量或配置文件读，不 hardcode
- ✅ **全功能覆盖**：涵盖 Vercel 所有主要 API（20+ 子命令）
- ✅ **通用 API 透传**：任何 Vercel API endpoint 都能打（`api` 子命令）

## Prerequisites

### 1. VERCEL_TOKEN

所有操作需要 Vercel Access Token。**按优先级查找，用第一个找到的**：

```
1. 环境变量（最高优先级）
   export VERCEL_TOKEN=your-token-here

2. 配置文件（见下方 "Optional config"）
   读取 <profile>.json 的 access_token 字段
```

**Token 权限要求**（根据你的操作）：
- 项目操作：需要对应 team 的项目访问权限
- 部署操作：需要部署权限
- 域名操作：需要域名管理权限
- 环境变量：需要环境变量编辑权限

**首次设置**：复制本目录下 `config.example.json` 到你选择的位置（项目根或 `~/.config/vercel/`），填入 token：

```json
{
  "access_token": "your-token-here",
  "team_id": "your-team-id-here",
  "team_slug": "your-team-slug"
}
```

### 2. Optional: Config file

配置文件路径查找顺序：
1. `--config <path>` 参数指定
2. `./vercel-config.json`（项目根）
3. `~/.config/vercel/config.json`（用户配置目录）

配置文件支持多 profile：

```json
{
  "default": {
    "access_token": "vcp_xxx",
    "team_id": "team_xxx",
    "team_slug": "my-team"
  },
  "production": {
    "access_token": "vcp_yyy",
    "team_id": "team_yyy",
    "team_slug": "prod-team"
  }
}
```

使用时：`node vercel-ops.js --profile production projects list`

## Usage

基本语法：

```bash
node vercel-ops.js <command> <subcommand> [options]
```

通用选项：
- `--profile <name>` - 使用指定 profile（默认 "default"）
- `--config <path>` - 指定配置文件路径
- `--team-id <id>` - 覆盖配置中的 team ID
- `--json` - 输出原始 JSON（不格式化）
- `--verbose` - 显示详细日志

## Commands

### 1. verify - 验证 token

验证 token 有效性并显示账号信息。

```bash
# 基础验证
node vercel-ops.js verify

# 指定 profile
node vercel-ops.js verify --profile production
```

### 2. projects - 项目管理

管理 Vercel 项目。

```bash
# 列出所有项目
node vercel-ops.js projects list

# 获取项目详情
node vercel-ops.js projects get <project-name-or-id>

# 创建项目
node vercel-ops.js projects create --name my-project --framework nextjs

# 更新项目
node vercel-ops.js projects update <project-id> --build-command "npm run build"

# 删除项目
node vercel-ops.js projects delete <project-id>

# 链接 Git 仓库
node vercel-ops.js projects link <project-id> --repo "owner/repo" --branch main
```

### 3. deployments - 部署管理

管理部署。

```bash
# 列出部署
node vercel-ops.js deployments list --project <project-name>

# 获取部署详情
node vercel-ops.js deployments get <deployment-id>

# 创建部署（从 Git）
node vercel-ops.js deployments create <project-id> --target production

# 取消部署
node vercel-ops.js deployments cancel <deployment-id>

# 重新部署
node vercel-ops.js deployments redeploy <deployment-id> --target production

# 删除部署
node vercel-ops.js deployments delete <deployment-id>
```

### 4. domains - 域名管理

管理自定义域名。

```bash
# 列出项目的域名
node vercel-ops.js domains list --project <project-id>

# 添加域名
node vercel-ops.js domains add <project-id> --domain example.com

# 验证域名
node vercel-ops.js domains verify <domain>

# 删除域名
node vercel-ops.js domains remove <domain>

# 获取域名配置
node vercel-ops.js domains get <domain>
```

### 5. env - 环境变量

管理环境变量。

```bash
# 列出环境变量
node vercel-ops.js env list <project-id>

# 添加环境变量
node vercel-ops.js env add <project-id> --key API_KEY --value secret123 --target production

# 更新环境变量
node vercel-ops.js env update <project-id> <env-id> --value newsecret

# 删除环境变量
node vercel-ops.js env remove <project-id> <env-id>

# 批量导入（从 .env 文件）
node vercel-ops.js env import <project-id> --file .env.production --target production
```

### 6. logs - 日志查询

查询部署日志。

```bash
# 获取部署日志
node vercel-ops.js logs get <deployment-id>

# 实时跟踪日志
node vercel-ops.js logs follow <deployment-id>

# 按时间范围查询
node vercel-ops.js logs get <deployment-id> --since 1h --until now

# 按来源过滤
node vercel-ops.js logs get <deployment-id> --source build --source static
```

### 7. aliases - 别名管理

管理部署别名。

```bash
# 列出别名
node vercel-ops.js aliases list

# 创建别名
node vercel-ops.js aliases assign <deployment-id> --alias myapp.vercel.app

# 删除别名
node vercel-ops.js aliases remove <alias>
```

### 8. teams - 团队管理

管理团队。

```bash
# 列出团队
node vercel-ops.js teams list

# 获取团队详情
node vercel-ops.js teams get <team-id>

# 列出团队成员
node vercel-ops.js teams members <team-id>

# 邀请成员
node vercel-ops.js teams invite <team-id> --email user@example.com --role MEMBER
```

### 9. edge-config - Edge Config 管理

管理 Edge Config 存储。

```bash
# 列出 Edge Config
node vercel-ops.js edge-config list

# 创建 Edge Config
node vercel-ops.js edge-config create --name my-config

# 获取配置项
node vercel-ops.js edge-config get <config-id> --key mykey

# 设置配置项
node vercel-ops.js edge-config set <config-id> --key mykey --value myvalue

# 删除配置项
node vercel-ops.js edge-config delete <config-id> --key mykey

# 批量更新
node vercel-ops.js edge-config update <config-id> --file config.json
```

### 10. blob - Blob 存储

管理 Vercel Blob 存储。

```bash
# 列出 Blob stores
node vercel-ops.js blob list

# 创建 Blob store
node vercel-ops.js blob create --name my-store

# 上传文件
node vercel-ops.js blob put <store-id> --key path/to/file --file local.txt

# 下载文件
node vercel-ops.js blob get <store-id> --key path/to/file --output local.txt

# 删除文件
node vercel-ops.js blob delete <store-id> --key path/to/file

# 列出文件
node vercel-ops.js blob list-keys <store-id> --prefix path/
```

### 11. functions - Serverless Functions

管理 Serverless Functions。

```bash
# 列出 functions
node vercel-ops.js functions list <deployment-id>

# 获取 function 详情
node vercel-ops.js functions get <deployment-id> <function-path>

# 查看 function 日志
node vercel-ops.js functions logs <deployment-id> <function-path>

# 触发 function
node vercel-ops.js functions invoke <deployment-id> <function-path> --data '{"key":"value"}'
```

### 12. crons - Cron Jobs

管理定时任务。

```bash
# 列出 cron jobs
node vercel-ops.js crons list <project-id>

# 创建 cron job
node vercel-ops.js crons create <project-id> --path /api/cron --schedule "0 0 * * *"

# 更新 cron job
node vercel-ops.js crons update <project-id> <cron-id> --schedule "0 12 * * *"

# 删除 cron job
node vercel-ops.js crons delete <project-id> <cron-id>

# 手动触发
node vercel-ops.js crons trigger <project-id> <cron-id>
```

### 13. webhooks - Webhook 管理

管理 webhooks。

```bash
# 列出 webhooks
node vercel-ops.js webhooks list

# 创建 webhook
node vercel-ops.js webhooks create --url https://example.com/hook --events deployment.created

# 删除 webhook
node vercel-ops.js webhooks delete <webhook-id>

# 测试 webhook
node vercel-ops.js webhooks test <webhook-id>
```

### 14. monitoring - 监控指标

查询监控数据。

```bash
# 获取项目分析数据
node vercel-ops.js monitoring analytics <project-id> --from 2024-01-01 --to 2024-01-31

# 获取带宽使用
node vercel-ops.js monitoring bandwidth <team-id> --from 2024-01-01

# 获取构建时长
node vercel-ops.js monitoring build-time <project-id> --from 2024-01-01

# 获取错误率
node vercel-ops.js monitoring errors <project-id> --from 2024-01-01
```

### 15. api - 通用 API 透传

直接调用任意 Vercel API endpoint。

```bash
# GET 请求
node vercel-ops.js api GET /v9/projects

# POST 请求
node vercel-ops.js api POST /v13/deployments --data '{"name":"my-project"}'

# DELETE 请求
node vercel-ops.js api DELETE /v9/projects/prj_xxx

# 带查询参数
node vercel-ops.js api GET /v9/projects --query 'limit=10&teamId=team_xxx'
```

## Examples

### Example 1: 创建项目并部署

```bash
# 1. 创建项目
node vercel-ops.js projects create --name my-nextjs-app --framework nextjs

# 2. 链接 Git 仓库
node vercel-ops.js projects link prj_xxx --repo "myorg/my-nextjs-app" --branch main

# 3. 触发部署
node vercel-ops.js deployments create prj_xxx --target production

# 4. 查看部署状态
node vercel-ops.js deployments get dpl_xxx
```

### Example 2: 管理环境变量

```bash
# 添加 API key
node vercel-ops.js env add prj_xxx --key API_KEY --value secret123 --target production

# 添加数据库 URL
node vercel-ops.js env add prj_xxx --key DATABASE_URL --value postgres://... --target production,preview

# 批量导入
node vercel-ops.js env import prj_xxx --file .env.production --target production
```

### Example 3: 域名配置

```bash
# 添加自定义域名
node vercel-ops.js domains add prj_xxx --domain myapp.com

# 验证域名（检查 DNS 记录）
node vercel-ops.js domains verify myapp.com

# 设置别名
node vercel-ops.js aliases assign dpl_xxx --alias myapp.vercel.app
```

### Example 4: Edge Config 管理

```bash
# 创建 Edge Config
node vercel-ops.js edge-config create --name feature-flags

# 设置功能开关
node vercel-ops.js edge-config set ecfg_xxx --key new_feature --value true

# 批量更新
cat > config.json << EOF
{
  "feature_a": true,
  "feature_b": false,
  "max_items": 100
}
EOF
node vercel-ops.js edge-config update ecfg_xxx --file config.json
```

### Example 5: 查询部署日志

```bash
# 获取最新部署的日志
DEPLOYMENT=$(node vercel-ops.js deployments list --project my-app --json | jq -r '.deployments[0].uid')
node vercel-ops.js logs get $DEPLOYMENT

# 只看构建日志
node vercel-ops.js logs get $DEPLOYMENT --source build

# 实时跟踪
node vercel-ops.js logs follow $DEPLOYMENT
```

## Error Handling

脚本遵循标准错误处理：
- Exit code 0：成功
- Exit code 1：通用错误（无效参数、配置错误等）
- Exit code 2：API 错误（401 未授权、404 未找到等）
- Exit code 3：网络错误

错误信息格式：

```json
{
  "error": {
    "code": "unauthorized",
    "message": "Invalid token",
    "statusCode": 401
  }
}
```

## Multi-Profile Workflow

管理多个 Vercel 账号：

```bash
# 配置文件结构
cat > ~/.config/vercel/config.json << EOF
{
  "personal": {
    "access_token": "vcp_personal_xxx",
    "team_id": null
  },
  "work": {
    "access_token": "vcp_work_xxx",
    "team_id": "team_work_xxx",
    "team_slug": "my-company"
  }
}
EOF

# 使用个人账号
node vercel-ops.js --profile personal projects list

# 使用工作账号
node vercel-ops.js --profile work projects list
```

## Integration with Other Tools

### 与 vercel-mcp 配合

vercel-mcp 需要 OAuth 认证，适合交互式操作。本 skill 使用 API token，适合自动化和 CI/CD：

```bash
# vercel-mcp: 交互式部署
# (通过 MCP 工具)

# vercel-ops: 脚本化部署
node vercel-ops.js deployments create prj_xxx --target production
```

### CI/CD 集成

```yaml
# GitHub Actions 示例
- name: Deploy to Vercel
  env:
    VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
  run: |
    node vercel-ops.js deployments create $PROJECT_ID --target production
    
- name: Wait for deployment
  run: |
    DEPLOYMENT_ID=$(node vercel-ops.js deployments list --project $PROJECT_ID --json | jq -r '.deployments[0].uid')
    while [ "$(node vercel-ops.js deployments get $DEPLOYMENT_ID --json | jq -r '.readyState')" != "READY" ]; do
      echo "Waiting for deployment..."
      sleep 5
    done
```

## Troubleshooting

### Token 无效

```bash
# 验证 token
node vercel-ops.js verify

# 检查环境变量
echo $VERCEL_TOKEN

# 检查配置文件
cat ~/.config/vercel/config.json
```

### Team ID 问题

某些操作需要 team ID：

```bash
# 获取 team ID
node vercel-ops.js teams list --json | jq -r '.teams[] | "\(.name): \(.id)"'

# 在配置文件中设置
# 或使用 --team-id 参数
node vercel-ops.js --team-id team_xxx projects list
```

### API 限流

Vercel API 有速率限制。遇到 429 错误时：

```bash
# 脚本会自动重试（指数退避）
# 或手动添加延迟
for project in $(node vercel-ops.js projects list --json | jq -r '.projects[].id'); do
  node vercel-ops.js deployments list --project $project
  sleep 1
done
```

## Notes

- **所有 API 调用都经过 team scope 验证**（如果配置了 team_id）
- **敏感数据（token、环境变量值）永不记录到日志**
- **支持 Vercel API v9/v13 等多版本**（根据 endpoint 自动选择）
- **幂等操作**：多次执行相同命令（如添加已存在的环境变量）会返回 409 或跳过

## Advanced Usage

### 批量操作

```bash
# 批量删除旧部署
node vercel-ops.js deployments list --project prj_xxx --json | \
  jq -r '.deployments[] | select(.createdAt < '$(date -d "30 days ago" +%s)' * 1000) | .uid' | \
  xargs -I {} node vercel-ops.js deployments delete {}

# 批量更新环境变量
for env_id in $(node vercel-ops.js env list prj_xxx --json | jq -r '.envs[] | select(.key | startswith("OLD_")) | .id'); do
  node vercel-ops.js env remove prj_xxx $env_id
done
```

### 监控脚本

```bash
#!/bin/bash
# 监控部署状态
PROJECT_ID="prj_xxx"

while true; do
  STATUS=$(node vercel-ops.js deployments list --project $PROJECT_ID --json | jq -r '.deployments[0].state')
  echo "[$(date)] Deployment status: $STATUS"
  
  if [ "$STATUS" = "READY" ]; then
    echo "Deployment successful!"
    break
  elif [ "$STATUS" = "ERROR" ]; then
    echo "Deployment failed!"
    node vercel-ops.js logs get $(node vercel-ops.js deployments list --project $PROJECT_ID --json | jq -r '.deployments[0].uid')
    exit 1
  fi
  
  sleep 10
done
```

## Architecture

脚本架构：
- 单文件 Node.js 脚本（`vercel-ops.js`）
- 零外部依赖（只用 Node 18+ 内置 API）
- 模块化设计（每个子命令独立函数）
- 统一错误处理和重试逻辑
- 支持流式输出（日志跟踪）

## Contributing

可开源项目，欢迎贡献：
- 添加新的子命令
- 改进错误处理
- 添加测试用例
- 优化性能

## References

详细 API 文档见：
- `references/vercel-api.md` - 完整 Vercel REST API 参考
- `references/examples.md` - 更多使用示例
- `references/troubleshooting.md` - 常见问题解决方案
