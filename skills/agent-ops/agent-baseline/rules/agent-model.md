
## 子 agent 选模型

- 装了 model-router（claude-model-router-hook）时，子 agent 的模型交给 router 自动选，不手写 `model`，除非要强制覆盖。
- 没装时调用 Agent 显式写 `model`：纯机械（下载、轮询、校验、搬运、清理）写 `haiku`；按清单执行但要少量判断的写 `sonnet`；其余（调研、评审、排查、设计、写代码）不写，继承主模型。`fork` 忽略这个参数。
