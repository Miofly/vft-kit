
## 子 agent 选模型

- 调用 Agent 时显式写 `model`：纯机械（下载、轮询、校验、搬运、清理）写 `haiku`；按清单执行但要少量判断的写 `sonnet`；调研、评审、排查、设计、写代码不写，继承主模型。`fork` 忽略这个参数。漏写时 model-router（补丁版 claude-model-router-hook）按任务类型补：机械活注入 haiku，其余不动。
- 子 agent 启动本身就要约 40k token（规范、工具定义），几条命令能做完的活直接在主会话跑，不为它开子 agent。
