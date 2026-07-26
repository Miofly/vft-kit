# CodeGraph 自动初始化规范 - 更新日志

## 概述

为 cc-baseline skill 添加了「CodeGraph 自动初始化」全局规范检查，确保用户在装了 codegraph CLI 的情况下，进入新项目时能自动建立代码知识图谱索引。

## 修改内容

### 1. 检查脚本 (`scripts/check.sh`)

#### 新增检测函数
```bash
claudemd_has_codegraph_auto_init()
```
- 位置：第 151-157 行（在 `claudemd_has_context7` 之前）
- 功能：检测全局 `~/.claude/CLAUDE.md` 是否包含 CodeGraph 自动初始化规范
- 匹配关键字：`codegraph.*自动`、`.codegraph.*自动建立`、`自动.*codegraph.*索引`、`codegraph.*新项目`

#### 新增条件检查逻辑
- 位置：第 246-252 行（在「外网操作代理兜底」之后、「context7 调用规范」之前）
- 条件：仅当 `codegraph` CLI 已安装时才检查（`if has_cmd codegraph`）
- 状态：
  - 已装 codegraph 且规范存在 → ✓ "全局规范含「CodeGraph 自动初始化」"
  - 已装 codegraph 但规范缺失 → ✗ "CodeGraph 自动初始化规范" + 修复命令
  - 未装 codegraph → "CodeGraph 自动初始化规范（codegraph 未装，无需配置）"

### 2. 技能文档 (`SKILL.md`)

#### 更新检查六类表格（第 41 行）
在「配置基线」类别的清单中增加：
```
**CodeGraph 自动初始化规范**（装了 codegraph CLI 时必需）
```

#### 更新各检查项作用速查表（第 93 行）
新增条目：
```markdown
| CodeGraph 自动初始化规范（条件必需） | codegraph CLI 已装时必需：进入新项目若没 .codegraph 目录就自动 init 建索引；没这条 = 装了 codegraph 却不自动用，退回慢速 grep+Read |
```

#### 新增关键实现细节说明（第 109 行后）
在「外网操作代理兜底」与「context7」之间插入完整的实现说明：
- 为什么需要这条规范
- 什么时候建索引（识别代码项目且无 `.codegraph/` 目录）
- 怎么建索引（`codegraph init` 命令及其行为）
- 注意事项（项目根目录、增量更新、非代码项目跳过）
- 检测函数实现细节
- 条件必需的判定逻辑

## 规范内容

新增的全局规范会在 `~/.claude/CLAUDE.md` 中追加如下内容：

```markdown
## CodeGraph 自动初始化

进入新项目时，若发现项目根目录（通过 git 仓库判断或当前工作目录）下没有 `.codegraph/` 目录，自动执行 `codegraph init` 建立代码知识图谱索引。好处：
- 从一开始就能用 `codegraph_explore` MCP 工具或 `codegraph explore "<query>"` shell 命令，一次返回相关符号的完整源码 + 调用链
- 避免退回到低效的 grep + Read 循环
- 动态派发（接口实现、虚函数）的调用路径 grep 跟不动，CodeGraph 能追踪

**什么时候建**：识别到这是一个代码项目（有 package.json / pom.xml / Cargo.toml / go.mod 等或明显的源码目录结构）且没有 `.codegraph/` 时，立即初始化。对于非代码目录（纯文档 / 配置仓库 / 个人笔记），跳过。

**怎么建**：在项目根目录运行 `codegraph init`（会自动识别语言、扫描源码、建立索引）。索引进 `.codegraph/` 目录（已在 .gitignore 模板中，不入版本控制）。对于大型仓库（10 万+ 行），首次索引可能需要几秒到几十秒；增量更新很快。

**注意事项**：
- 初始化前先确认是在项目根目录（git 根目录或主 build 文件所在目录），不要在子目录建索引
- 如果项目已有 `.codegraph/` 但索引陈旧（代码大改过），用 `codegraph update` 增量更新或 `codegraph init --force` 重建
- 非代码项目不要强制建索引（浪费时间且无收益）
```

## 设计思路

### 条件必需模式
采用与 context7、anysearch 相同的「条件必需」模式：
- codegraph CLI 本身是**必需工具**（第 1 类 CLI 工具检查）
- 但「自动初始化规范」是**条件必需**（只在已装 codegraph 时才要求）
- 未装 codegraph 时显示 `ok "无需配置"`，不影响退出码

### 触发时机
规范要求在以下情况下自动初始化：
1. 进入新项目（首次打开或切换到新目录）
2. 识别为代码项目（有典型构建文件或源码目录）
3. 项目根目录下没有 `.codegraph/` 目录

### 智能跳过
对以下情况不自动初始化：
- 非代码目录（纯文档、配置、笔记）
- 已有 `.codegraph/` 目录（索引已存在）
- 不在项目根目录（避免在子目录误建索引）

## 收益

1. **充分利用 CodeGraph**：装了 codegraph 的用户从一开始就能用知识图谱，不会因忘记初始化而退回低效的 grep+Read
2. **自动化体验**：无需手动记住在每个新项目跑 `codegraph init`
3. **智能判断**：只对代码项目初始化，不浪费资源在非代码目录
4. **与现有规范一致**：采用相同的条件必需模式，检查逻辑清晰

## 测试

运行 `bash scripts/check.sh` 验证：
- ✓ 检测函数正常工作
- ✓ 条件判断正确（已装 codegraph → 检查规范；未装 → 显示无需配置）
- ✓ 修复命令格式正确（可追加到 CLAUDE.md）
- ✓ 退出码逻辑符合预期

## 后续使用

用户在运行 cc-baseline 检查后，若看到此项缺失：
1. 会看到缺失原因：「codegraph CLI 已装时必需：进入新项目若没 .codegraph 目录就自动 init 建索引；没这条 = 装了 codegraph 却不自动用，退回慢速 grep+Read」
2. 可选择补齐：脚本已内嵌修复命令，用户确认后直接执行
3. 规范生效：下次进入新项目时，CC 会自动检测并初始化 CodeGraph 索引
