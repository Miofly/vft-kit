# Vercel Operations Examples

实战示例集合，涵盖常见场景。

## 场景 1：完整的项目部署流程

从零开始创建项目并部署到生产环境。

```bash
#!/bin/bash
set -e

# 1. 创建项目
echo "Creating project..."
PROJECT_ID=$(node vercel-ops.js projects create \
  --name my-nextjs-app \
  --framework nextjs \
  --build-command "npm run build" \
  --output-directory ".next" \
  --json | jq -r '.id')

echo "Project created: $PROJECT_ID"

# 2. 链接 Git 仓库
echo "Linking Git repository..."
node vercel-ops.js projects link $PROJECT_ID \
  --repo "myorg/my-nextjs-app" \
  --branch main

# 3. 配置环境变量
echo "Setting environment variables..."
node vercel-ops.js env add $PROJECT_ID \
  --key DATABASE_URL \
  --value "postgresql://user:pass@host:5432/db" \
  --target production

node vercel-ops.js env add $PROJECT_ID \
  --key API_KEY \
  --value "secret-api-key-here" \
  --target production,preview

# 4. 触发生产部署
echo "Triggering production deployment..."
DEPLOYMENT_ID=$(node vercel-ops.js deployments create $PROJECT_ID \
  --target production \
  --json | jq -r '.id')

echo "Deployment ID: $DEPLOYMENT_ID"

# 5. 等待部署完成
echo "Waiting for deployment to be ready..."
while true; do
  STATE=$(node vercel-ops.js deployments get $DEPLOYMENT_ID --json | jq -r '.readyState')
  echo "Current state: $STATE"
  
  if [ "$STATE" = "READY" ]; then
    echo "✓ Deployment successful!"
    break
  elif [ "$STATE" = "ERROR" ]; then
    echo "✗ Deployment failed!"
    node vercel-ops.js logs get $DEPLOYMENT_ID
    exit 1
  fi
  
  sleep 5
done

# 6. 添加自定义域名
echo "Adding custom domain..."
node vercel-ops.js domains add $PROJECT_ID --domain myapp.com

# 7. 验证域名配置
echo "Verifying domain..."
node vercel-ops.js domains verify myapp.com

echo "✓ Setup complete!"
```

---

## 场景 2：多环境管理

为不同环境配置不同的环境变量。

```bash
#!/bin/bash

PROJECT_ID="prj_xxx"

# 生产环境变量
echo "Setting production environment..."
node vercel-ops.js env add $PROJECT_ID \
  --key NODE_ENV \
  --value production \
  --target production

node vercel-ops.js env add $PROJECT_ID \
  --key API_URL \
  --value "https://api.example.com" \
  --target production

# Preview 环境变量
echo "Setting preview environment..."
node vercel-ops.js env add $PROJECT_ID \
  --key NODE_ENV \
  --value preview \
  --target preview

node vercel-ops.js env add $PROJECT_ID \
  --key API_URL \
  --value "https://api-staging.example.com" \
  --target preview

# Development 环境变量
echo "Setting development environment..."
node vercel-ops.js env add $PROJECT_ID \
  --key NODE_ENV \
  --value development \
  --target development

node vercel-ops.js env add $PROJECT_ID \
  --key API_URL \
  --value "http://localhost:3001" \
  --target development

echo "✓ All environments configured"
```

---

## 场景 3：从 .env 文件批量导入

```bash
#!/bin/bash

# .env.production 文件内容示例
cat > .env.production << 'EOF'
DATABASE_URL=postgresql://user:pass@host:5432/db
REDIS_URL=redis://localhost:6379
API_KEY=secret-key-here
STRIPE_SECRET_KEY=sk_live_xxx
NEXT_PUBLIC_API_URL=https://api.example.com
EOF

# 导入到生产环境
node vercel-ops.js env import prj_xxx \
  --file .env.production \
  --target production

# .env.preview 文件
cat > .env.preview << 'EOF'
DATABASE_URL=postgresql://user:pass@staging-host:5432/db
REDIS_URL=redis://staging.redis:6379
API_KEY=staging-key-here
STRIPE_SECRET_KEY=sk_test_xxx
NEXT_PUBLIC_API_URL=https://api-staging.example.com
EOF

# 导入到 Preview 环境
node vercel-ops.js env import prj_xxx \
  --file .env.preview \
  --target preview
```

---

## 场景 4：Blue-Green 部署

使用别名实现零停机部署。

```bash
#!/bin/bash

PROJECT_ID="prj_xxx"
PRODUCTION_ALIAS="myapp.com"

# 1. 创建新部署（Green）
echo "Creating new deployment..."
GREEN_DEPLOYMENT=$(node vercel-ops.js deployments create $PROJECT_ID \
  --target preview \
  --json | jq -r '.id')

# 2. 等待新部署就绪
echo "Waiting for green deployment..."
while true; do
  STATE=$(node vercel-ops.js deployments get $GREEN_DEPLOYMENT --json | jq -r '.readyState')
  if [ "$STATE" = "READY" ]; then
    break
  elif [ "$STATE" = "ERROR" ]; then
    echo "✗ Green deployment failed!"
    exit 1
  fi
  sleep 3
done

# 3. 获取 Green URL
GREEN_URL=$(node vercel-ops.js deployments get $GREEN_DEPLOYMENT --json | jq -r '.url')
echo "Green deployment ready at: https://$GREEN_URL"

# 4. 运行冒烟测试
echo "Running smoke tests..."
if curl -f -s "https://$GREEN_URL/api/health" > /dev/null; then
  echo "✓ Smoke tests passed"
else
  echo "✗ Smoke tests failed!"
  exit 1
fi

# 5. 获取当前生产部署（Blue）
BLUE_DEPLOYMENT=$(node vercel-ops.js deployments list \
  --project $PROJECT_ID \
  --json | jq -r '.deployments[] | select(.target=="production") | .uid' | head -1)

echo "Current production (blue): $BLUE_DEPLOYMENT"

# 6. 切换别名到新部署
echo "Switching traffic to green deployment..."
node vercel-ops.js aliases assign $GREEN_DEPLOYMENT --alias $PRODUCTION_ALIAS

echo "✓ Traffic switched to: $GREEN_DEPLOYMENT"

# 7. 监控一段时间
echo "Monitoring for 5 minutes..."
sleep 300

# 8. 如果一切正常，删除旧部署
echo "Checking health..."
if curl -f -s "https://$PRODUCTION_ALIAS/api/health" > /dev/null; then
  echo "✓ Green deployment stable, removing blue..."
  node vercel-ops.js deployments delete $BLUE_DEPLOYMENT
  echo "✓ Blue-Green deployment complete!"
else
  echo "✗ Issues detected! Rolling back..."
  node vercel-ops.js aliases assign $BLUE_DEPLOYMENT --alias $PRODUCTION_ALIAS
  echo "✓ Rolled back to blue deployment"
  exit 1
fi
```

---

## 场景 5：定期清理旧部署

节省存储空间和提高性能。

```bash
#!/bin/bash

PROJECT_ID="prj_xxx"
DAYS_TO_KEEP=30

# 计算截止时间戳（30天前）
CUTOFF_TIMESTAMP=$(date -d "$DAYS_TO_KEEP days ago" +%s)000

echo "Cleaning deployments older than $DAYS_TO_KEEP days..."

# 获取旧部署列表
OLD_DEPLOYMENTS=$(node vercel-ops.js deployments list \
  --project $PROJECT_ID \
  --json | jq -r ".deployments[] | select(.created < $CUTOFF_TIMESTAMP) | select(.target != \"production\") | .uid")

COUNT=0
for deployment in $OLD_DEPLOYMENTS; do
  echo "Deleting $deployment..."
  node vercel-ops.js deployments delete $deployment
  COUNT=$((COUNT + 1))
  sleep 0.5  # 避免触发限流
done

echo "✓ Deleted $COUNT old deployments"
```

---

## 场景 6：监控部署状态并告警

```bash
#!/bin/bash

PROJECT_ID="prj_xxx"
WEBHOOK_URL="https://hooks.slack.com/services/xxx"

# 创建部署
DEPLOYMENT_ID=$(node vercel-ops.js deployments create $PROJECT_ID \
  --target production \
  --json | jq -r '.id')

START_TIME=$(date +%s)

# 监控部署
while true; do
  DEPLOYMENT=$(node vercel-ops.js deployments get $DEPLOYMENT_ID --json)
  STATE=$(echo $DEPLOYMENT | jq -r '.readyState')
  URL=$(echo $DEPLOYMENT | jq -r '.url')
  
  ELAPSED=$(($(date +%s) - START_TIME))
  
  if [ "$STATE" = "READY" ]; then
    # 部署成功
    MESSAGE="✓ Deployment successful!\nURL: https://$URL\nTime: ${ELAPSED}s"
    curl -X POST -H 'Content-type: application/json' \
      --data "{\"text\":\"$MESSAGE\"}" \
      $WEBHOOK_URL
    echo "$MESSAGE"
    exit 0
    
  elif [ "$STATE" = "ERROR" ]; then
    # 部署失败
    LOGS=$(node vercel-ops.js logs get $DEPLOYMENT_ID | tail -20)
    MESSAGE="✗ Deployment failed!\nID: $DEPLOYMENT_ID\nLogs:\n$LOGS"
    curl -X POST -H 'Content-type: application/json' \
      --data "{\"text\":\"$MESSAGE\"}" \
      $WEBHOOK_URL
    echo "$MESSAGE"
    exit 1
    
  elif [ $ELAPSED -gt 600 ]; then
    # 超时（10分钟）
    MESSAGE="⚠️ Deployment timeout!\nID: $DEPLOYMENT_ID"
    curl -X POST -H 'Content-type: application/json' \
      --data "{\"text\":\"$MESSAGE\"}" \
      $WEBHOOK_URL
    node vercel-ops.js deployments cancel $DEPLOYMENT_ID
    exit 1
  fi
  
  echo "[$ELAPSED s] State: $STATE"
  sleep 5
done
```

---

## 场景 7：A/B 测试部署

为不同用户群体提供不同版本。

```bash
#!/bin/bash

PROJECT_ID="prj_xxx"

# 部署 A 版本
echo "Deploying version A..."
DEPLOYMENT_A=$(node vercel-ops.js deployments create $PROJECT_ID \
  --target preview \
  --json | jq -r '.id')

# 等待就绪
while [ "$(node vercel-ops.js deployments get $DEPLOYMENT_A --json | jq -r '.readyState')" != "READY" ]; do
  sleep 3
done

URL_A=$(node vercel-ops.js deployments get $DEPLOYMENT_A --json | jq -r '.url')
echo "Version A: https://$URL_A"

# 部署 B 版本（假设有不同的分支或配置）
echo "Deploying version B..."
DEPLOYMENT_B=$(node vercel-ops.js deployments create $PROJECT_ID \
  --target preview \
  --json | jq -r '.id')

while [ "$(node vercel-ops.js deployments get $DEPLOYMENT_B --json | jq -r '.readyState')" != "READY" ]; do
  sleep 3
done

URL_B=$(node vercel-ops.js deployments get $DEPLOYMENT_B --json | jq -r '.url')
echo "Version B: https://$URL_B"

# 设置别名（50/50 分流需要在 Vercel Dashboard 或 Edge Config 中配置）
node vercel-ops.js aliases assign $DEPLOYMENT_A --alias ab-test-a.myapp.com
node vercel-ops.js aliases assign $DEPLOYMENT_B --alias ab-test-b.myapp.com

echo "✓ A/B test deployments ready"
echo "  Version A: https://ab-test-a.myapp.com"
echo "  Version B: https://ab-test-b.myapp.com"
```

---

## 场景 8：CI/CD 集成

### GitHub Actions

```yaml
name: Deploy to Vercel

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
      
      - name: Install dependencies
        run: npm ci
      
      - name: Run tests
        run: npm test
      
      - name: Download vercel-ops
        run: |
          curl -O https://raw.githubusercontent.com/your-repo/vercel-ops/main/vercel-ops.js
      
      - name: Deploy to Vercel
        env:
          VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
        run: |
          DEPLOYMENT_ID=$(node vercel-ops.js deployments create ${{ secrets.PROJECT_ID }} \
            --target production \
            --json | jq -r '.id')
          
          echo "DEPLOYMENT_ID=$DEPLOYMENT_ID" >> $GITHUB_ENV
      
      - name: Wait for deployment
        env:
          VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
        run: |
          while true; do
            STATE=$(node vercel-ops.js deployments get $DEPLOYMENT_ID --json | jq -r '.readyState')
            
            if [ "$STATE" = "READY" ]; then
              echo "✓ Deployment successful!"
              break
            elif [ "$STATE" = "ERROR" ]; then
              echo "✗ Deployment failed!"
              node vercel-ops.js logs get $DEPLOYMENT_ID
              exit 1
            fi
            
            sleep 10
          done
      
      - name: Run smoke tests
        run: |
          URL=$(node vercel-ops.js deployments get $DEPLOYMENT_ID --json | jq -r '.url')
          curl -f "https://$URL/api/health"
```

### GitLab CI

```yaml
deploy:
  stage: deploy
  image: node:18
  script:
    - npm ci
    - npm test
    - curl -O https://raw.githubusercontent.com/your-repo/vercel-ops/main/vercel-ops.js
    - |
      DEPLOYMENT_ID=$(node vercel-ops.js deployments create $PROJECT_ID \
        --target production \
        --json | jq -r '.id')
    - |
      while true; do
        STATE=$(node vercel-ops.js deployments get $DEPLOYMENT_ID --json | jq -r '.readyState')
        if [ "$STATE" = "READY" ]; then
          echo "✓ Deployment successful!"
          break
        elif [ "$STATE" = "ERROR" ]; then
          echo "✗ Deployment failed!"
          exit 1
        fi
        sleep 10
      done
  only:
    - main
  variables:
    VERCEL_TOKEN: $VERCEL_TOKEN
```

---

## 场景 9：跨团队项目管理

```bash
#!/bin/bash

# 切换到团队 A
export VERCEL_TEAM_ID="team_aaa"

echo "Team A projects:"
node vercel-ops.js --team-id $VERCEL_TEAM_ID projects list

# 切换到团队 B
export VERCEL_TEAM_ID="team_bbb"

echo "Team B projects:"
node vercel-ops.js --team-id $VERCEL_TEAM_ID projects list

# 或使用 profile
node vercel-ops.js --profile team-a projects list
node vercel-ops.js --profile team-b projects list
```

---

## 场景 10：备份环境变量

```bash
#!/bin/bash

PROJECT_ID="prj_xxx"
BACKUP_FILE="env-backup-$(date +%Y%m%d-%H%M%S).json"

# 备份
echo "Backing up environment variables..."
node vercel-ops.js env list $PROJECT_ID --json > $BACKUP_FILE

echo "✓ Backup saved to: $BACKUP_FILE"

# 恢复（需要解析 JSON 并重新添加）
echo "To restore, run:"
echo "  cat $BACKUP_FILE | jq -r '.envs[] | \"--key \" + .key + \" --value \" + .value + \" --target \" + (.target | join(\",\"))' | xargs -I {} node vercel-ops.js env add $PROJECT_ID {}"
```

---

## 实用技巧

### 1. 批量操作

```bash
# 批量删除 preview 部署
node vercel-ops.js deployments list --project prj_xxx --json | \
  jq -r '.deployments[] | select(.target=="preview") | .uid' | \
  xargs -I {} node vercel-ops.js deployments delete {}

# 批量更新环境变量（删除所有 OLD_ 前缀的变量）
node vercel-ops.js env list prj_xxx --json | \
  jq -r '.envs[] | select(.key | startswith("OLD_")) | .id' | \
  xargs -I {} node vercel-ops.js env remove prj_xxx {}
```

### 2. 监控脚本

```bash
# watch-deployment.sh
#!/bin/bash
DEPLOYMENT_ID=$1

watch -n 5 "node vercel-ops.js deployments get $DEPLOYMENT_ID --json | jq '{state: .readyState, url: .url, created: .created}'"
```

### 3. 快速别名

```bash
# 添加到 ~/.bashrc 或 ~/.zshrc
alias vercel="node /path/to/vercel-ops.js"
alias vdeploy="vercel deployments create"
alias vlist="vercel projects list"
alias venv="vercel env"
```

---

## 调试技巧

```bash
# 1. 查看详细日志
node vercel-ops.js --verbose projects list

# 2. 查看原始 API 响应
node vercel-ops.js projects list --json | jq '.'

# 3. 测试 token
node vercel-ops.js verify

# 4. 直接调用 API
node vercel-ops.js api GET /v9/projects --query "limit=5"

# 5. 查看部署日志（最近100条）
node vercel-ops.js logs get dpl_xxx --limit 100

# 6. 实时跟踪日志
node vercel-ops.js logs follow dpl_xxx
```
