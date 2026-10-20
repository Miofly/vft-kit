# 子命令（kaggle-cli.mjs）

## 子命令

### kernel push
Push kernel 到 Kaggle:
```bash
# 基础用法(从当前目录读 kernel-metadata.json)
node "<skill-dir>/scripts/kaggle-cli.mjs" kernel push

# 指定目录
node "<skill-dir>/scripts/kaggle-cli.mjs" kernel push --dir /path/to/kernel

# 指定账号
node "<skill-dir>/scripts/kaggle-cli.mjs" kernel push --account test --dir /path/to/kernel

# 重试配置
node "<skill-dir>/scripts/kaggle-cli.mjs" kernel push --retries 5 --retry-delay 3000
```

**重试逻辑**:网络瞬断(connection reset/timeout)自动重试;Kaggle API 500 错误也重试;其他错误(404/权限)不重试。

### kernel status
查询 kernel 运行状态:
```bash
node "<skill-dir>/scripts/kaggle-cli.mjs" kernel status <username>/<kernel-slug>
node "<skill-dir>/scripts/kaggle-cli.mjs" kernel status <username>/<kernel-slug> --account test
```

返回:running / complete / error / queued 等。

### kernel logs
拉取 kernel 日志:
```bash
node "<skill-dir>/scripts/kaggle-cli.mjs" kernel logs <username>/<kernel-slug>
node "<skill-dir>/scripts/kaggle-cli.mjs" kernel logs <username>/<kernel-slug> --save logs.txt
```

### dataset push
Push dataset 到 Kaggle:
```bash
node "<skill-dir>/scripts/kaggle-cli.mjs" dataset push --dir /path/to/dataset
node "<skill-dir>/scripts/kaggle-cli.mjs" dataset push --dir /path/to/dataset --account test
```

需要目录下有 `dataset-metadata.json`。

### quota
查询账号 GPU 配额:
```bash
node "<skill-dir>/scripts/kaggle-cli.mjs" quota
node "<skill-dir>/scripts/kaggle-cli.mjs" quota --account test
```

返回:已用时长 / 剩余时长 / 周期重置时间。
