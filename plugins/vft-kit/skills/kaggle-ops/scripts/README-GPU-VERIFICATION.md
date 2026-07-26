# GPU 验证工具说明

## 概述

GPU 验证工具用于测试 Kaggle 账号是否真正能使用 GPU。

### 为什么需要 GPU 验证？

**问题**:
- Token 能鉴权 ≠ 能使用 GPU
- `gpu_remaining_seconds=30h` 只是配额元数据
- Kaggle GPU 需要手机验证，未验证账号返回配额但实际不能用

**解决方案**:
推送最小测试 kernel，真实检测 `torch.cuda.is_available()`

---

## 工具说明

### 1. probe-gpu.mjs

**功能**: 探测账号 GPU 真实可用性

**用法**:
```bash
# 测试单个账号
node probe-gpu.mjs --env=local --user=username

# 测试前10个账号
node probe-gpu.mjs --env=local --limit=10 --concurrency=3

# 测试全量账号
node probe-gpu.mjs --env=local --concurrency=5
```

**参数**:
- `--env=local/dev` - 数据库环境
- `--limit=N` - 只测试前 N 个账号
- `--concurrency=N` - 并发数（建议 3-5）
- `--user=xxx` - 只测试指定账号
- `--accelerator=NvidiaTeslaT4` - 指定 GPU 型号

**输出**:
```
总计: 71
✅ GPU 可用: 28
❌ 无 GPU(未手机验证): 43
🚫 push 403: 0
💥 push 失败: 0

报告: gpu-probe-report.json
      gpu-probe-report.csv
```

---

### 2. mark-gpu-verified.mjs

**功能**: 根据探测报告回写 DB 的 gpu_verified 字段

**用法**:
```bash
# Dry-run（不回写）
node mark-gpu-verified.mjs --env=local

# 真实回写
node mark-gpu-verified.mjs --env=local --apply

# 指定报告文件
node mark-gpu-verified.mjs --env=local --report=/path/to/report.json --apply
```

**参数**:
- `--env=local/dev` - 数据库环境
- `--apply` - 真实回写（否则只是 dry-run）
- `--report=path` - 指定报告文件（默认 gpu-probe-report-t4.json 或 gpu-probe-report.json）

**回写内容**:
- `gpu_verified=1` - GPU 可用
- `gpu_verified=0` - GPU 不可用
- `accelerator` - GPU 型号（如 Tesla T4）
- `model` - GPU 型号名称
- `count` - GPU 数量
- `capability` - GPU 计算能力（如 7.5）
- `checked_at` - 检测时间

---

## 完整工作流

```bash
# 第1步：探测 GPU
node probe-gpu.mjs --env=local --concurrency=5

# 第2步：查看报告
cat gpu-probe-report.json

# 第3步：回写 DB
node mark-gpu-verified.mjs --env=local --apply

# 第4步：验证结果
mysql ... -e "SELECT 
  SUM(CASE WHEN gpu_verified=1 THEN 1 ELSE 0 END) as GPU可用,
  SUM(CASE WHEN gpu_verified=0 THEN 1 ELSE 0 END) as GPU不可用
FROM tools_kaggle_account;"
```

---

## Probe Kernel 原理

### 测试脚本

```python
import json, sys
try:
    import torch
    ok = torch.cuda.is_available()
    name = torch.cuda.get_device_name(0) if ok else ""
    cap = ".".join(map(str, torch.cuda.get_device_capability(0))) if ok else ""
    count = torch.cuda.device_count() if ok else 0
    print("PROBE_RESULT " + json.dumps({
        "cuda": ok, 
        "gpu": name, 
        "cap": cap, 
        "count": count
    }))
except Exception as e:
    print("PROBE_RESULT " + json.dumps({"cuda": False, "err": str(e)}))
```

### 执行流程

```
1. 设置 KAGGLE_API_TOKEN 环境变量
2. 推送 probe kernel (is_private=true, enable_gpu=true)
3. 轮询 kernel 状态 (running → complete)
4. 下载并解析日志
5. 提取 PROBE_RESULT JSON
6. 判定 cuda: true/false
```

---

## 报告格式

### gpu-probe-report.json

```json
{
  "env": "local",
  "accelerator": null,
  "at": "2026-07-26T10:13:39.565Z",
  "results": [
    {
      "username": "account1",
      "push": "ok",
      "status": "COMPLETE",
      "cuda": true,
      "gpu": "Tesla T4",
      "cap": "7.5",
      "count": 1,
      "note": ""
    },
    {
      "username": "account2",
      "push": "ok",
      "status": "COMPLETE",
      "cuda": false,
      "gpu": "",
      "cap": "",
      "count": 0,
      "note": ""
    }
  ]
}
```

### gpu-probe-report.csv

```csv
username,push,status,cuda,gpu,cap,count,note
account1,ok,COMPLETE,true,Tesla T4,7.5,1,
account2,ok,COMPLETE,false,,,0,
```

---

## 注意事项

1. **耗时较长**: 每账号 ~1 分钟，71 个账号约 15 分钟（并发5）
2. **网络依赖**: 需要访问 Kaggle API，建议使用代理
3. **并发控制**: 建议并发 3-5，过高可能触发限流
4. **报告校验**: mark-gpu-verified 会校验报告与 DB 账号集合一致
5. **不修改 enabled**: enabled 是人工开关，探测结果不会永久禁用账号

---

## 常见问题

### Q: 为什么不能只查询配额？

A: `gpu_remaining_seconds` 只是元数据，未手机验证的账号照样返回配额，但实际运行时 `torch.cuda.is_available()` 返回 False。

### Q: 为什么有的账号 token 有效但无 GPU？

A: Kaggle GPU / public kernel / internet 都需要手机验证。泄露账号池中大部分账号未验证。

### Q: 可以加速探测吗？

A: 可以提高并发数（--concurrency），但过高会触发 Kaggle 限流。建议 3-5。

### Q: 报告可以复用吗？

A: 可以。使用 mark-gpu-verified --report 指定历史报告。但建议定期重新探测（账号状态可能变化）。

---

**更新时间**: 2026-07-26
