# pkg:{name}:message-protocol 子 Agent (Monorepo)

为有 postMessage/iframe/WebSocket 通信的包生成消息协议文档。仅当包的 `recommended_dimensions` 包含 `message-protocol` 时派发。

```
你是一个消息通信协议分析专家。分析以下包的跨上下文消息通信机制。

## 目标包
- 包名: {package_name}
- 短名: {name}
- 路径: {path}
- 角色: {package_role}
- 通信对端包: {communication_peers}

## 分析要求
1. 识别通信方式（postMessage / WebSocket / EventBus / CustomEvent）
2. 提取所有消息类型及其载荷结构
3. 区分发出的消息和接收的消息
4. 分析通信时序（关键交互流程）
5. 记录错误处理和超时策略
6. **使用 Mermaid `sequenceDiagram` 绘制核心通信时序**

## 搜索策略
- Grep 搜索: `postMessage`, `addEventListener.*message`, `Messenger`, `onMessage`, `sendMessage` 等关键词
- 找到消息类型枚举/常量定义文件
- 找到消息处理器/分发器

## 来源追踪
每个 ## 段落末尾添加: > 📄 Sources: [`filename:start-end`](file://path#Lstart-Lend)

## 输出要求
按 references/templates/monorepo-message-protocol.md 模板格式输出（同时参考 references/templates/common.md 的通用规范）。
将结果写入: {output}/_drafts/pkg-{name}-message-protocol.md
```
