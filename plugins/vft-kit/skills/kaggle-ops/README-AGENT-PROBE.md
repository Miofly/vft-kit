# Kaggle GPU 探测 - Agent 并发版本

## 快速开始

### 1. 准备账号文件

创建 `accounts.json`，格式：

```json
[
  {"username": "user1", "token": "KGAT_xxxxxxxxxxxx"},
  {"username": "user2", "token": "KGAT_yyyyyyyyyyyy"},
  {"username": "user3", "token": "KGAT_zzzzzzzzzzzz"}
]
```

### 2. 生成 Agent 任务

```bash
node scripts/probe-gpu-agent.mjs --accounts accounts.json --concurrency 8
```

这会：
- 为每个账号创建临时文件到 `.tmp-probe-accounts/`
- 输出 Agent 并发调用代码
- 保存元信息到 `probe-meta.json`

### 3. 在 Claude Code 中执行 Agent 任务

复制脚本输出的代码，在 Claude Code 中运行，例如：

```javascript
// 在 Claude Code 中执行
const results = await Promise.all([
  agent('探测账号 user1 GPU', { label: '账号1' }),
  agent('探测账号 user2 GPU', { label: '账号2' }),
  agent('探测账号 user3 GPU', { label: '账号3' })
]);
```

或者使用 Bash 后台任务：

```bash
node scripts/probe-gpu-worker.mjs --account-file .tmp-probe-accounts/account-1-user1.json &
node scripts/probe-gpu-worker.mjs --account-file .tmp-probe-accounts/account-2-user2.json &
node scripts/probe-gpu-worker.mjs --account-file .tmp-probe-accounts/account-3-user3.json &
wait
```

### 4. 收集结果

```bash
node scripts/collect-probe-results.mjs --dir .tmp-probe-accounts --output gpu-probe-report
```

生成：
- `gpu-probe-report.json` - 完整报告
- `gpu-probe-report.csv` - CSV 格式

### 5. 清理临时文件

```bash
rm -rf .tmp-probe-accounts
```

## 性能对比

假设 10 个账号，每个探测需要 3 分钟：

| 方式 | 时间 | 说明 |
|------|------|------|
| 顺序执行 | 30 分钟 | 10 × 3 |
| probe-gpu.mjs (并发=5) | 6 分钟 | 2 批 × 3 分钟 |
| **probe-gpu-agent.mjs** | **3-4 分钟** | **真正并行** ⭐ |

## 优势

✅ **更快**: Agent 真正并发，充分利用多核 CPU  
✅ **隔离**: 每个 Agent 独立进程，互不干扰  
✅ **可视**: Claude Code 中实时显示进度  
✅ **稳定**: 单个账号失败不影响其他账号  

## 脚本说明

### probe-gpu-agent.mjs

主控脚本，负责：
- 读取账号列表
- 创建临时文件
- 生成 Agent 调用代码
- 保存元信息

### probe-gpu-worker.mjs

Worker 脚本，每个 Agent 执行一个，负责：
- 探测单个账号的 GPU 可用性
- Push kernel 到 Kaggle
- 轮询状态
- 下载日志
- 输出结果到 `result-{username}.json`

### collect-probe-results.mjs

收集脚本，负责：
- 读取所有 `result-*.json`
- 分类统计（可用/无GPU/403/失败/未知）
- 生成汇总报告（JSON + CSV）

## 高级用法

### 限制账号数量

```bash
node scripts/probe-gpu-agent.mjs --accounts accounts.json --limit 5
```

### 指定 GPU 型号

```bash
node scripts/probe-gpu-agent.mjs --accounts accounts.json --accelerator NvidiaTeslaP100
```

### 自定义输出文件名

```bash
node scripts/collect-probe-results.mjs --dir .tmp-probe-accounts --output my-report
```

## 故障排查

### Agent 任务失败

检查 `.tmp-probe-accounts/result-{username}.json`，查看具体错误信息。

### 收集脚本找不到结果

确认：
1. Worker 脚本已全部执行完成
2. `.tmp-probe-accounts/` 目录下有 `result-*.json` 文件
3. 目录路径正确

### Kaggle API 超时

增加超时时间（修改 `probe-gpu-worker.mjs` 中的 `POLL_MAX_SEC`）：

```javascript
const POLL_MAX_SEC = 600; // 10 分钟
```

## 与原版 probe-gpu.mjs 的区别

| 特性 | probe-gpu.mjs | probe-gpu-agent.mjs |
|------|---------------|---------------------|
| 并发方式 | 自定义并发池（单进程） | Agent 多进程并发 |
| 适用环境 | 任何 Node.js 环境 | Claude Code 环境 |
| 执行速度 | 快 | **更快** ⭐ |
| 进程隔离 | 共享进程 | **完全隔离** ⭐ |
| 可视化 | 终端输出 | **Claude Code 进度显示** ⭐ |
| 推荐场景 | 命令行、CI/CD | **Claude Code 会话** ⭐ |

## 示例

查看完整示例：

```bash
node scripts/example-agent-probe.mjs
```

运行测试（模拟数据）：

```bash
node scripts/test-agent-probe.mjs
```

## 常见问题

**Q: 为什么要用 Agent 并发？**  
A: Agent 是真正的多进程并发，比单进程并发池快，且隔离性更好。

**Q: 可以混用两种方式吗？**  
A: 可以。`probe-gpu.mjs` 适合命令行环境，`probe-gpu-agent.mjs` 适合 Claude Code 环境。

**Q: Agent 并发数量有限制吗？**  
A: 建议 5-10 个并发，取决于系统资源和网络带宽。

**Q: 临时文件可以删除吗？**  
A: 收集完结果后可以删除 `.tmp-probe-accounts/`，建议保留一段时间以便排查问题。

## License

与父项目相同。
