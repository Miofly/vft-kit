# Vercel REST API Reference

完整的 Vercel API 端点参考，按功能分类。

## 基础信息

- **Base URL**: `https://api.vercel.com`
- **认证**: `Authorization: Bearer <token>`
- **Rate Limiting**: 
  - 免费账号: 100 requests/10 seconds
  - Pro/Enterprise: 更高限制

## API 版本

Vercel API 使用版本化端点（v1, v2, v6, v9, v10, v13 等）。不同版本可能同时存在，选择最新稳定版本。

---

## 用户与认证

### GET /v2/user
获取当前用户信息。

**Response**:
```json
{
  "user": {
    "id": "usr_xxx",
    "username": "user",
    "email": "user@example.com",
    "name": "User Name",
    "createdAt": 1234567890
  }
}
```

---

## 项目 (Projects)

### GET /v9/projects
列出所有项目。

**Query Parameters**:
- `teamId` (string): Team ID
- `limit` (number): 每页数量 (默认 20)
- `since` (number): 时间戳，获取之后的项目
- `until` (number): 时间戳，获取之前的项目

**Response**:
```json
{
  "projects": [
    {
      "id": "prj_xxx",
      "name": "my-project",
      "framework": "nextjs",
      "buildCommand": "npm run build",
      "outputDirectory": ".next",
      "installCommand": "npm install",
      "devCommand": "npm run dev",
      "rootDirectory": "/",
      "nodeVersion": "18.x",
      "createdAt": 1234567890,
      "updatedAt": 1234567890
    }
  ],
  "pagination": {
    "count": 20,
    "next": 1234567890
  }
}
```

### GET /v9/projects/:idOrName
获取单个项目详情。

**Path Parameters**:
- `idOrName` (string): 项目 ID 或名称

### POST /v9/projects
创建新项目。

**Body**:
```json
{
  "name": "my-project",
  "framework": "nextjs",
  "buildCommand": "npm run build",
  "outputDirectory": ".next",
  "installCommand": "npm install",
  "devCommand": "npm run dev",
  "rootDirectory": "/"
}
```

### PATCH /v9/projects/:id
更新项目配置。

**Body**: 同 POST，但所有字段可选。

### DELETE /v9/projects/:id
删除项目。

### POST /v9/projects/:id/link
链接 Git 仓库。

**Body**:
```json
{
  "type": "github",
  "repo": "owner/repo",
  "productionBranch": "main"
}
```

---

## 部署 (Deployments)

### GET /v6/deployments
列出部署。

**Query Parameters**:
- `teamId` (string)
- `projectId` (string): 过滤特定项目
- `limit` (number)
- `since` (number)
- `until` (number)
- `state` (string): BUILDING, READY, ERROR, CANCELED

**Response**:
```json
{
  "deployments": [
    {
      "uid": "dpl_xxx",
      "name": "my-project",
      "url": "my-project-hash.vercel.app",
      "state": "READY",
      "readyState": "READY",
      "target": "production",
      "created": 1234567890,
      "createdAt": 1234567890,
      "ready": 1234567900
    }
  ]
}
```

### GET /v13/deployments/:id
获取部署详情。

### POST /v13/deployments
创建新部署。

**Body**:
```json
{
  "name": "my-project",
  "target": "production",
  "gitSource": {
    "type": "github",
    "repo": "owner/repo",
    "ref": "main"
  }
}
```

或重新部署：
```json
{
  "deploymentId": "dpl_xxx",
  "target": "production"
}
```

### PATCH /v12/deployments/:id/cancel
取消部署。

### DELETE /v13/deployments/:id
删除部署。

---

## 域名 (Domains)

### GET /v9/projects/:projectId/domains
列出项目的域名。

**Response**:
```json
{
  "domains": [
    {
      "name": "example.com",
      "verified": true,
      "createdAt": 1234567890,
      "updatedAt": 1234567890
    }
  ]
}
```

### POST /v10/projects/:projectId/domains
添加域名。

**Body**:
```json
{
  "name": "example.com"
}
```

### GET /v6/domains/:domain/config
获取域名配置和验证状态。

**Response**:
```json
{
  "verified": true,
  "misconfigured": false,
  "nameservers": ["ns1.vercel-dns.com", "ns2.vercel-dns.com"]
}
```

### DELETE /v6/domains/:domain
删除域名。

### GET /v5/domains/:domain
获取域名详情。

---

## 环境变量 (Environment Variables)

### GET /v9/projects/:projectId/env
列出环境变量。

**Response**:
```json
{
  "envs": [
    {
      "id": "env_xxx",
      "key": "API_KEY",
      "value": "encrypted_value",
      "type": "encrypted",
      "target": ["production", "preview"],
      "createdAt": 1234567890,
      "updatedAt": 1234567890
    }
  ]
}
```

### POST /v10/projects/:projectId/env
创建环境变量。

**Body**:
```json
{
  "key": "API_KEY",
  "value": "secret123",
  "type": "encrypted",
  "target": ["production", "preview", "development"]
}
```

**Types**:
- `encrypted`: 加密存储（推荐）
- `plain`: 明文存储
- `secret`: 敏感值（构建时不可见）
- `system`: 系统变量

### PATCH /v9/projects/:projectId/env/:envId
更新环境变量。

**Body**:
```json
{
  "value": "new_value",
  "target": ["production"]
}
```

### DELETE /v9/projects/:projectId/env/:envId
删除环境变量。

---

## 日志 (Logs)

### GET /v2/deployments/:id/events
获取部署事件日志。

**Query Parameters**:
- `limit` (number): 最多返回数量
- `since` (number): 时间戳，获取之后的日志
- `until` (number): 时间戳，获取之前的日志
- `source` (string): 过滤来源 (build, static, lambda, edge)

**Response**:
```json
[
  {
    "type": "stdout",
    "created": 1234567890,
    "text": "Build log message",
    "payload": {
      "text": "Build log message"
    }
  }
]
```

---

## 别名 (Aliases)

### GET /v4/aliases
列出别名。

**Response**:
```json
{
  "aliases": [
    {
      "uid": "als_xxx",
      "alias": "myapp.vercel.app",
      "deploymentId": "dpl_xxx",
      "createdAt": 1234567890
    }
  ]
}
```

### POST /v2/deployments/:id/aliases
为部署分配别名。

**Body**:
```json
{
  "alias": "myapp.vercel.app"
}
```

### DELETE /v2/aliases/:alias
删除别名。

---

## 团队 (Teams)

### GET /v2/teams
列出用户所属团队。

**Response**:
```json
{
  "teams": [
    {
      "id": "team_xxx",
      "slug": "my-team",
      "name": "My Team",
      "created": "2024-01-01T00:00:00.000Z",
      "createdAt": 1234567890
    }
  ]
}
```

### GET /v2/teams/:teamId
获取团队详情。

### GET /v2/teams/:teamId/members
列出团队成员。

**Response**:
```json
{
  "members": [
    {
      "uid": "usr_xxx",
      "username": "user",
      "email": "user@example.com",
      "role": "OWNER",
      "created": 1234567890
    }
  ]
}
```

**Roles**:
- `OWNER`: 所有者
- `MEMBER`: 成员
- `VIEWER`: 只读

### POST /v1/teams/:teamId/members
邀请成员。

**Body**:
```json
{
  "email": "user@example.com",
  "role": "MEMBER"
}
```

---

## Edge Config (v1)

### GET /v1/edge-config
列出 Edge Config 存储。

### POST /v1/edge-config
创建 Edge Config。

**Body**:
```json
{
  "slug": "my-config"
}
```

### GET /v1/edge-config/:id/items
获取配置项。

### POST /v1/edge-config/:id/items
批量更新配置项。

**Body**:
```json
{
  "items": [
    {
      "operation": "create",
      "key": "feature_flag",
      "value": true
    },
    {
      "operation": "update",
      "key": "max_items",
      "value": 100
    },
    {
      "operation": "delete",
      "key": "old_setting"
    }
  ]
}
```

---

## Blob Storage

### GET /v1/blob
列出 Blob stores。

### POST /v1/blob
创建 Blob store。

### PUT /blob/:pathname
上传文件（需要预签名 URL）。

### GET /blob/:pathname
下载文件。

### DELETE /blob/:pathname
删除文件。

---

## Webhooks

### GET /v1/webhooks
列出 webhooks。

### POST /v1/webhooks
创建 webhook。

**Body**:
```json
{
  "url": "https://example.com/webhook",
  "events": ["deployment.created", "deployment.succeeded", "deployment.failed"]
}
```

**可用事件**:
- `deployment.created`
- `deployment.succeeded`
- `deployment.failed`
- `deployment.ready`
- `project.created`
- `project.removed`

### DELETE /v1/webhooks/:id
删除 webhook。

---

## 监控与分析

### GET /v1/analytics
获取分析数据。

**Query Parameters**:
- `projectId` (string)
- `from` (number): 开始时间戳
- `to` (number): 结束时间戳

### GET /v1/bandwidth-usage
获取带宽使用情况。

### GET /v1/builds/time
获取构建时长统计。

---

## 错误代码

| Code | Description |
|------|-------------|
| 400 | Bad Request - 请求参数错误 |
| 401 | Unauthorized - Token 无效或过期 |
| 403 | Forbidden - 权限不足 |
| 404 | Not Found - 资源不存在 |
| 409 | Conflict - 资源冲突（如域名已存在） |
| 429 | Too Many Requests - 请求过于频繁 |
| 500 | Internal Server Error - 服务器错误 |

## Rate Limiting

响应头：
- `X-RateLimit-Limit`: 限制数量
- `X-RateLimit-Remaining`: 剩余次数
- `X-RateLimit-Reset`: 重置时间戳

遇到 429 时，建议指数退避重试：
1. 第一次：等待 1s
2. 第二次：等待 2s
3. 第三次：等待 4s

---

## 参考链接

- 官方文档: https://vercel.com/docs/rest-api
- API Explorer: https://vercel.com/docs/rest-api/endpoints
- SDK: https://github.com/vercel/vercel/tree/main/packages/client
