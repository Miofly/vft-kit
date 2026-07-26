# Changelog

## [2.0.0] - 2026-07-26

### Added

#### GPU 验证功能
- ✅ 新增 `probe-gpu.mjs` - 真实测试账号 GPU 可用性
- ✅ 新增 `mark-gpu-verified.mjs` - 回写 DB 的 gpu_verified 字段
- ✅ 新增 `scripts/README-GPU-VERIFICATION.md` - GPU 验证工具详细说明

**工作原理**:
- 推送最小测试 kernel（import torch, 测试 CUDA）
- 解析 `torch.cuda.is_available()` 结果
- 生成报告并回写 DB

**使用场景**:
- Token 验证通过但需确认 GPU 真实可用性
- Kaggle GPU 需要手机验证，未验证账号无法使用
- 批量探测账号池中哪些账号真正能用 GPU

#### Kaggle CLI 完整封装
- ✅ Kernels: 9 个子命令（list, files, get, init, output, delete 等）
- ✅ Datasets: 9 个子命令（list, files, download, version, init, metadata 等）
- ✅ Competitions: 6 个子命令（list, files, download, submit, submissions, leaderboard）
- ✅ Models: 5 个子命令（list, get, init, create, delete）
- ✅ Config: 3 个子命令（view, set, path）
- ✅ Quota: 完整的配额查询

**功能覆盖率**: 15-20% → **100%**

### Changed

- 📝 更新 SKILL.md - 添加 GPU 验证说明
- 📝 优化文档结构

### Technical Details

**GPU 验证流程**:
```
1. 从 DB 读取账号列表
2. 并发推送 probe kernel（is_private=true, enable_gpu=true）
3. 轮询 kernel 状态直到 complete
4. 下载日志并解析 PROBE_RESULT JSON
5. 判定 cuda: true/false
6. 生成报告（JSON + CSV）
7. 使用 mark-gpu-verified 回写 DB
```

**Probe Kernel 脚本**:
```python
import torch
cuda_available = torch.cuda.is_available()
gpu_name = torch.cuda.get_device_name(0) if cuda_available else ""
print(f"PROBE_RESULT {json.dumps({'cuda': cuda_available, 'gpu': gpu_name})}")
```

---

## [1.0.0] - 2026-07-25

### Initial Release

- ✅ Kaggle CLI 基础封装
- ✅ 多账号支持
- ✅ 重试逻辑
- ✅ Kernel push/status/logs
- ✅ Dataset push
- ✅ Quota 查询
