# codex-baseline CC-Switch 认证同步设计

## 目标

执行 `codex-baseline` 时，自动把 CC-Switch 当前 Codex 提供商的 API Key 与 Base URL 安全同步到 macOS 钥匙串，并通过 `~/.zshrc` 注入后续新终端进程。除这一项常设授权外，其他基线检查继续保持只读。

## 结构

- 新增 `scripts/sync-cc-switch-openai-env.sh`：负责发现活动认证、写入钥匙串、维护 zsh 托管块和脱敏回报。
- 新增 `scripts/run.sh`：先执行同步脚本，再执行现有 `check.sh`。
- 保留 `check.sh` 为纯检查器；`SKILL.md` 改为调用 `run.sh`，并明确认证同步是唯一自动修复例外。

## 数据流

1. 从 `${CODEX_HOME:-$HOME/.codex}/auth.json` 读取非空 `OPENAI_API_KEY`。
2. 从 `${CODEX_HOME:-$HOME/.codex}/config.toml` 读取当前提供商的 `base_url`。
3. 若活动文件缺字段，再从 `~/.cc-switch/cc-switch.db` 的当前 Codex 提供商回退读取。
4. 把值写入当前用户的 macOS Keychain 服务项 `CC_SWITCH_CODEX_API_KEY` 和 `CC_SWITCH_CODEX_BASE_URL`。
5. 在 `${ZDOTDIR:-$HOME}/.zshrc` 维护唯一的 `vft-kit` 托管块，通过 `security find-generic-password` 动态导出 `OPENAI_API_KEY` 与 `OPENAI_BASE_URL`。

任何输出都不得包含完整 Key。允许输出同步状态、Key 长度和 Base URL 主机名。

## 幂等与兼容

- 重复执行更新同名 Keychain 项，不追加重复 zsh 块。
- CC-Switch 切换当前提供商后，下次执行覆盖旧值。
- 迁移本机现有的无结束标记配置块，避免重复导出。
- 没有 CC-Switch、字段不完整、缺少 `security` 或非 macOS 时，只打印警告并继续基线检查。
- 同步失败不吞掉原 `check.sh` 的结果；`run.sh` 始终运行检查器，并以检查器退出码为基准。

## 测试

- 使用临时 `HOME`、临时 `CODEX_HOME` 和 PATH 中的伪 `security` 命令，避免读写真实密钥。
- RED：先证明当前 `codex-baseline` 不会创建 Keychain 项或 zsh 注入块。
- GREEN：覆盖首次同步、重复运行、提供商切换、缺字段降级、日志无密钥、检查器仍被调用。
- 运行 shell 语法检查、Skill 目录校验和真实本机脱敏验收。
- 更新本地 marketplace 插件版本并重装 Codex 插件缓存；验证源与 cache 内容一致。当前会话仍使用旧注入内容，最终提示重启会话。

## 非目标

- 不验证第三方提供商是否兼容 OpenAI 全部 API。
- 不修改 `~/.codex/config.toml`、CC-Switch 数据库或其他基线缺失项。
- 不在仓库、shell 配置、测试夹具或日志中保存明文 Key。
