# 与私有 skill 的关系与常见问题

## 与私有 skill 的关系

本 skill 是**通用基础**,只提供"给我 username/token,我帮你 push kernel"的能力,不知道你的:
- 具体 kernel 名称/slug
- 业务逻辑(如双账号分摊配额、数据库账号池)
- 特定部署拓扑

私有项目应:
1. 创建私有 skill(如 `my-kaggle-deployment`)
2. 在私有 config.json 定义 kernels 映射、accounts 映射
3. 私有 skill 读自己的配置,从 `.secrets` 读 token,export 环境变量,再调本 skill

## 常见问题

**Q: 为什么不直接用 `kaggle` CLI?**
A: 本 skill 封装了重试逻辑、多账号切换、错误处理,比直接调 CLI 方便。

**Q: KGAT token 和 kaggle.json 的 key 是一样的吗?**
A: 是。Kaggle 2.x 的 API token 格式是 `KGAT_xxxx`,存在 `kaggle.json` 的 `key` 字段。

**Q: kernel push 失败怎么排查?**
A: 1) 检查 `kernel-metadata.json` 格式;2) 确认 slug 符合 Kaggle 命名规范(`kaggle-xxx`);3) 看日志里的具体错误(权限/quota/网络)。

**Q: 多账号场景如何避免 token 串用?**
A: 每次操作前明确 export KAGGLE_USERNAME/KAGGLE_KEY,覆盖环境;或用 `--account` 参数让脚本自动切换。
