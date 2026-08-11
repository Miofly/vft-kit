---
name: cc-switch-add-provider
description: 安全地把第三方模型接口新增到或修正到 macOS CC Switch 的 Claude Code 供应商列表，支持 Anthropic Messages、OpenAI Chat Completions、OpenAI Responses 协议，自动备份 SQLite 数据库、复用同名供应商、提示疑似重复项、保留当前供应商并校验写入结果。用户说“给 CC Switch 添加供应商/模型/API”“把这个接口加到 cc-switch”“修正 CC Switch 里现有供应商的协议、地址、Key 或模型映射”时使用。
---

# CC Switch 添加供应商

使用 `scripts/upsert_provider.py` 修改 `~/.cc-switch/cc-switch.db`。只处理 Claude Code 供应商；Codex/Gemini 的配置结构不同，不要复用本脚本。

## 流程

1. 确认 CC Switch 已安装，并读取实际版本、数据库路径与 `providers` 表结构。
2. 在不输出完整 Key 的前提下，先验证上游模型列表和最小请求。OpenAI Chat 供应商还应验证一次自动工具调用。
3. 检查同名供应商以及相同地址 + 模型的候选项。疑似重复时复用原记录，不新增副本。
4. 退出 CC Switch 后执行脚本；脚本拒绝在 CC Switch 运行时写库。
5. 重开 CC Switch，重新读取数据库，确认名称、协议、地址、模型、当前供应商和数据库权限。

默认不切换当前供应商。只有用户明确要求“启用/切换”时，才在 CC Switch 中启用新供应商并验证实际 Claude Code 路由。

## 执行

把 Key 放进临时环境变量，不要写入命令参数、仓库或日志：

```bash
export CC_SWITCH_API_KEY='<api-key>'
python3 "<skill-dir>/scripts/upsert_provider.py" \
  --name 'Qwen 3.8 Max' \
  --base-url 'https://dashscope.aliyuncs.com/compatible-mode/v1' \
  --model 'qwen3.8-max' \
  --api-format openai_chat
unset CC_SWITCH_API_KEY
```

脚本会把标准 OpenAI 地址末尾的 `/v1` 规范为 CC Switch 需要的上游前缀，避免形成 `/v1/v1/chat/completions`。

若脚本报告相同地址 + 模型的疑似重复项，核对后显式复用：

```bash
python3 "<skill-dir>/scripts/upsert_provider.py" \
  --name 'Qwen 3.8 Max' \
  --base-url 'https://dashscope.aliyuncs.com/compatible-mode/v1' \
  --model 'qwen3.8-max' \
  --api-format openai_chat \
  --replace-id '<existing-provider-id>'
```

可选参数：

- `--auth-field ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY`：第三方 OpenAI 兼容接口默认使用 `ANTHROPIC_AUTH_TOKEN`。
- `--db <path>`：覆盖默认数据库路径，用于其他安装位置或隔离验证。
- `--dry-run`：只显示 create/update 计划，不备份、不写库。
- `--self-test`：在临时数据库执行创建、更新、去重和备份自检。

## 安全边界

- 禁止回显完整 Key；输出只报告 Key 是否存在。
- 每次写入前必须备份数据库，备份和数据库权限都收紧为 `600`。
- 更新供应商时保留其未知配置、插件、hooks 和当前启用状态，只改目标接口字段。
- 不删除其他供应商，不自动切换，不自动开启本地路由。
- OpenAI Chat/Responses 接入 Claude Code 必须依赖 CC Switch 本地路由做协议转换；直接写成 `anthropic` 会失败。
