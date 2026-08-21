# Vercel Operations Troubleshooting

常见问题及解决方案。

---

## 认证问题

### 问题：Token 无效

**症状**:
```
API Error (401): Invalid token
```

**解决方案**:

1. **验证 token**:
```bash
node vercel-ops.js verify
```

2. **检查环境变量**:
```bash
echo $VERCEL_TOKEN
```

3. **检查配置文件**:
```bash
cat ~/.config/vercel/config.json
# 或
cat ./vercel-config.json
```

4. **重新生成 token**:
   - 访问 https://vercel.com/account/tokens
   - 创建新的 Access Token
   - 更新环境变量或配置文件

5. **检查 token 权限范围**:
   - 确保 token 有足够的权限
   - 团队操作需要 team-scoped token

---

### 问题：Team ID 不匹配

**症状**:
```
API Error (403): Forbidden
You don't have access to this project
```

**解决方案**:

1. **列出所有团队**:
```bash
node vercel-ops.js teams list
```

2. **检查当前使用的 team ID**:
```bash
node vercel-ops.js verify
```

3. **显式指定 team ID**:
```bash
node vercel-ops.js --team-id team_xxx projects list
```

4. **更新配置文件**:
```json
{
  "default": {
    "access_token": "vcp_xxx",
    "team_id": "team_xxx",
    "team_slug": "my-team"
  }
}
```

---

## 网络问题

### 问题：连接超时

**症状**:
```
Error: fetch failed
cause: ConnectTimeoutError
```

**解决方案**:

1. **检查网络连接**:
```bash
ping api.vercel.com
```

2. **检查代理设置**:
```bash
echo $HTTP_PROXY
echo $HTTPS_PROXY
```

3. **临时禁用代理**:
```bash
unset HTTP_PROXY HTTPS_PROXY
node vercel-ops.js projects list
```

4. **使用代理**:
```bash
export HTTPS_PROXY=http://proxy.example.com:8080
node vercel-ops.js projects list
```

---

### 问题：DNS 解析失败

**症状**:
```
Error: getaddrinfo ENOTFOUND api.vercel.com
```

**解决方案**:

1. **检查 DNS**:
```bash
nslookup api.vercel.com
# 或
dig api.vercel.com
```

2. **更换 DNS 服务器**:
```bash
# macOS
sudo networksetup -setdnsservers Wi-Fi 8.8.8.8 8.8.4.4

# Linux
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

3. **使用 /etc/hosts**（临时方案）:
```bash
# 添加 Vercel API IP（需要先查询真实IP）
echo "76.76.21.21 api.vercel.com" | sudo tee -a /etc/hosts
```

---

### 问题：Rate Limiting

**症状**:
```
API Error (429): Too Many Requests
```

**解决方案**:

1. **检查剩余配额**:
   响应头会包含：
   - `X-RateLimit-Limit`: 总限制
   - `X-RateLimit-Remaining`: 剩余次数
   - `X-RateLimit-Reset`: 重置时间

2. **添加延迟**:
```bash
# 批量操作时添加延迟
for project in $(node vercel-ops.js projects list --json | jq -r '.projects[].id'); do
  node vercel-ops.js deployments list --project $project
  sleep 1  # 每次请求后等待1秒
done
```

3. **使用 --verbose 查看重试**:
```bash
node vercel-ops.js --verbose projects list
```

脚本会自动重试（指数退避），但频繁操作仍需手动控制。

---

## 部署问题

### 问题：部署卡在 BUILDING 状态

**症状**:
部署长时间停留在 `BUILDING` 状态，超过预期时间。

**解决方案**:

1. **查看构建日志**:
```bash
node vercel-ops.js logs get dpl_xxx --source build
```

2. **检查构建配置**:
```bash
node vercel-ops.js projects get prj_xxx --json | jq '{
  buildCommand: .buildCommand,
  outputDirectory: .outputDirectory,
  installCommand: .installCommand
}'
```

3. **取消并重新部署**:
```bash
node vercel-ops.js deployments cancel dpl_xxx
node vercel-ops.js deployments create prj_xxx --target production
```

4. **检查构建超时**:
   - 免费账号：最长 45 分钟
   - Pro 账号：最长 90 分钟
   - 如果超时，优化构建脚本或升级账号

---

### 问题：部署失败（ERROR 状态）

**症状**:
```
State: ERROR
```

**解决方案**:

1. **查看完整日志**:
```bash
node vercel-ops.js logs get dpl_xxx
```

2. **常见错误及解决**:

   **a. 构建命令失败**:
   ```
   Error: Command "npm run build" exited with 1
   ```
   - 本地运行 `npm run build` 复现
   - 检查依赖是否完整
   - 检查 Node 版本是否匹配

   **b. 输出目录不存在**:
   ```
   Error: No Output Directory named ".next" found
   ```
   - 检查 `outputDirectory` 配置
   - 确保构建命令生成了该目录

   **c. 环境变量缺失**:
   ```
   Error: DATABASE_URL is not defined
   ```
   - 添加缺失的环境变量:
   ```bash
   node vercel-ops.js env add prj_xxx --key DATABASE_URL --value "xxx" --target production
   ```

   **d. 依赖安装失败**:
   ```
   Error: npm ERR! 404 Not Found
   ```
   - 检查 package.json 中的依赖版本
   - 使用 `package-lock.json` 锁定版本

---

### 问题：部署成功但页面 404

**症状**:
部署状态为 READY，但访问页面返回 404。

**解决方案**:

1. **检查输出目录**:
```bash
node vercel-ops.js projects get prj_xxx --json | jq '.outputDirectory'
```

2. **检查根目录**:
```bash
node vercel-ops.js projects get prj_xxx --json | jq '.rootDirectory'
```

3. **检查框架配置**:
```bash
node vercel-ops.js projects get prj_xxx --json | jq '.framework'
```

4. **查看部署文件**:
   访问 `https://<deployment-url>/_logs` 查看部署的文件结构

---

## 域名问题

### 问题：域名验证失败

**症状**:
```
verified: false
misconfigured: true
```

**解决方案**:

1. **检查 DNS 记录**:
```bash
node vercel-ops.js domains verify example.com --json | jq '.misconfigured'
```

2. **查看需要的 DNS 配置**:
```bash
dig example.com
# 应该指向 Vercel 的 IP：76.76.21.21 或 CNAME: cname.vercel-dns.com
```

3. **常见 DNS 配置**:

   **方式 1：A 记录**
   ```
   A    @    76.76.21.21
   ```

   **方式 2：CNAME（推荐）**
   ```
   CNAME    @    cname.vercel-dns.com
   ```

   **子域名**:
   ```
   CNAME    www    cname.vercel-dns.com
   ```

4. **等待 DNS 传播**:
```bash
# 检查 DNS 是否生效
nslookup example.com
# 或使用第三方工具
# https://dnschecker.org
```

通常需要等待 5 分钟到 48 小时。

---

### 问题：域名已被其他项目使用

**症状**:
```
API Error (409): Domain is already in use
```

**解决方案**:

1. **查找占用该域名的项目**:
```bash
# 遍历所有项目
for project in $(node vercel-ops.js projects list --json | jq -r '.projects[].id'); do
  echo "Checking $project..."
  node vercel-ops.js domains list --project $project --json | \
    jq -r ".domains[] | select(.name==\"example.com\") | \"Found in project: $project\""
done
```

2. **从旧项目删除域名**:
```bash
node vercel-ops.js domains remove example.com
```

3. **添加到新项目**:
```bash
node vercel-ops.js domains add prj_new --domain example.com
```

---

## 环境变量问题

### 问题：环境变量不生效

**症状**:
应用中读取到的环境变量是 `undefined`。

**解决方案**:

1. **检查变量是否存在**:
```bash
node vercel-ops.js env list prj_xxx
```

2. **检查 target 配置**:
```bash
node vercel-ops.js env list prj_xxx --json | \
  jq '.envs[] | select(.key=="API_KEY") | .target'
```

确保包含你部署的环境（production / preview / development）。

3. **检查变量类型**:
```bash
node vercel-ops.js env list prj_xxx --json | \
  jq '.envs[] | {key: .key, type: .type}'
```

类型说明：
- `encrypted`: 加密存储，所有环境可见
- `secret`: 敏感值，构建时不可见（运行时可见）
- `plain`: 明文存储
- `system`: 系统变量

4. **客户端变量必须加前缀**:

Next.js / Create React App 等框架要求客户端变量有特定前缀：
- Next.js: `NEXT_PUBLIC_`
- CRA: `REACT_APP_`
- Vite: `VITE_`

```bash
# 错误（客户端读不到）
node vercel-ops.js env add prj_xxx --key API_URL --value "https://api.example.com"

# 正确
node vercel-ops.js env add prj_xxx --key NEXT_PUBLIC_API_URL --value "https://api.example.com"
```

5. **重新部署**:
环境变量更改后需要重新部署才能生效：
```bash
node vercel-ops.js deployments create prj_xxx --target production
```

---

### 问题：环境变量包含特殊字符

**症状**:
包含 `$`, `"`, `\n` 等特殊字符的变量值被截断或转义错误。

**解决方案**:

1. **使用 JSON 字符串**:
```bash
# Bash 中正确转义
node vercel-ops.js env add prj_xxx \
  --key DATABASE_URL \
  --value 'postgresql://user:p@ss$word@host:5432/db'
```

2. **多行值**（如私钥）:
```bash
# 方法1：使用 \n
node vercel-ops.js env add prj_xxx \
  --key PRIVATE_KEY \
  --value "-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----"

# 方法2：从文件读取
VALUE=$(cat private.key)
node vercel-ops.js env add prj_xxx --key PRIVATE_KEY --value "$VALUE"
```

3. **Base64 编码**（推荐）:
```bash
# 编码
VALUE=$(cat private.key | base64)
node vercel-ops.js env add prj_xxx --key PRIVATE_KEY_B64 --value "$VALUE"

# 应用中解码
# const privateKey = Buffer.from(process.env.PRIVATE_KEY_B64, 'base64').toString('utf-8');
```

---

## 日志问题

### 问题：日志为空或不完整

**症状**:
```bash
node vercel-ops.js logs get dpl_xxx
# 返回空或只有部分日志
```

**解决方案**:

1. **检查日志来源**:
```bash
node vercel-ops.js logs get dpl_xxx --source build
node vercel-ops.js logs get dpl_xxx --source static
node vercel-ops.js logs get dpl_xxx --source lambda
```

2. **增加日志数量**:
```bash
node vercel-ops.js logs get dpl_xxx --limit 1000
```

3. **使用时间范围**:
```bash
# 最近1小时
node vercel-ops.js logs get dpl_xxx --since $(date -d '1 hour ago' +%s)000

# 特定时间段
node vercel-ops.js logs get dpl_xxx \
  --since 1640000000000 \
  --until 1640003600000
```

4. **实时跟踪**:
```bash
node vercel-ops.js logs follow dpl_xxx
```

---

## 性能问题

### 问题：脚本运行缓慢

**症状**:
命令执行时间过长，超过预期。

**解决方案**:

1. **减少请求数量**:
```bash
# 不好：多次请求
for project in $(node vercel-ops.js projects list --json | jq -r '.projects[].id'); do
  node vercel-ops.js projects get $project
done

# 好：一次获取所有
node vercel-ops.js projects list --json | jq '.projects[]'
```

2. **使用分页**:
```bash
# 只获取需要的数量
node vercel-ops.js projects list --limit 10
```

3. **并行执行**（谨慎，可能触发限流）:
```bash
# 使用 GNU parallel
node vercel-ops.js projects list --json | \
  jq -r '.projects[].id' | \
  parallel -j 5 "node vercel-ops.js deployments list --project {}"
```

4. **缓存结果**:
```bash
# 缓存项目列表
node vercel-ops.js projects list --json > projects-cache.json

# 后续使用缓存
cat projects-cache.json | jq '.projects[] | select(.name=="my-project")'
```

---

## 常见错误码

| Code | 错误 | 可能原因 | 解决方案 |
|------|------|---------|---------|
| 400 | Bad Request | 请求参数格式错误 | 检查参数格式，使用 --json 查看原始响应 |
| 401 | Unauthorized | Token 无效或过期 | 重新生成 token |
| 403 | Forbidden | 权限不足 | 检查 token 权限和 team ID |
| 404 | Not Found | 资源不存在 | 检查 ID 是否正确 |
| 409 | Conflict | 资源冲突 | 删除已存在的资源或使用不同名称 |
| 429 | Too Many Requests | 请求过于频繁 | 添加延迟，等待限流重置 |
| 500 | Internal Server Error | Vercel 服务器错误 | 稍后重试，或联系 Vercel 支持 |
| 502 | Bad Gateway | 网关错误 | 稍后重试 |
| 503 | Service Unavailable | 服务暂时不可用 | 等待服务恢复 |

---

## 调试技巧

### 1. 启用详细日志

```bash
node vercel-ops.js --verbose projects list
```

会显示：
- API 请求 URL
- 请求方法和 body
- 响应时间

### 2. 查看原始 API 响应

```bash
node vercel-ops.js projects list --json | jq '.'
```

### 3. 使用 API 命令直接调试

```bash
# 直接调用 API
node vercel-ops.js api GET /v9/projects --query "limit=1"

# 使用 curl 对比
curl -H "Authorization: Bearer $VERCEL_TOKEN" \
  "https://api.vercel.com/v9/projects?limit=1"
```

### 4. 检查网络请求

```bash
# macOS/Linux
tcpdump -i any -n host api.vercel.com

# 或使用 Charles/Fiddler 等代理工具
```

### 5. 测试配置

```bash
# 创建测试脚本
cat > test-config.sh << 'EOF'
#!/bin/bash
set -x

echo "1. Checking token..."
node vercel-ops.js verify

echo "2. Listing projects..."
node vercel-ops.js projects list --limit 1

echo "3. Checking teams..."
node vercel-ops.js teams list

echo "✓ All tests passed"
EOF

chmod +x test-config.sh
./test-config.sh
```

---

## 获取帮助

如果以上方案都无法解决问题：

1. **查看官方文档**:
   https://vercel.com/docs/rest-api

2. **使用 --verbose 收集日志**:
```bash
node vercel-ops.js --verbose <command> 2>&1 | tee debug.log
```

3. **检查 Vercel 状态**:
   https://www.vercel-status.com

4. **联系 Vercel 支持**:
   https://vercel.com/support

5. **提交 Issue**:
   附上：
   - 完整命令
   - 错误信息
   - `--verbose` 输出
   - Node 版本（`node --version`）
   - 操作系统
