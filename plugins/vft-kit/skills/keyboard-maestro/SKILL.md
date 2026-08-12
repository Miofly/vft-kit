---
name: keyboard-maestro
description: >-
  在 macOS 上创建、导入、运行、查询和管理 Keyboard Maestro 宏与自动化。用户提到 Keyboard Maestro、KM 宏、kmmacros、定时执行 Shell/AppleScript、快捷键、Typed String、宏组、变量/字典、执行或编辑宏、导入导出、启停或删除宏、通过 AppleScript/CLI/kmtrigger 控制 Keyboard Maestro 时使用。覆盖 Keyboard Maestro 11 的官方 Editor/Engine 脚本接口和任意原生 Action XML；不要直接修改 Keyboard Maestro Macros.plist 或 Variables.sqlite。
---

# Keyboard Maestro

使用 Keyboard Maestro 官方 CLI、AppleScript SDEF 与 `.kmmacros` 导入接口管理自动化。高频操作优先调用随附 `kmctl.mjs`；长尾对象、动作和窗口能力读取 [references/scripting-api.md](references/scripting-api.md) 后调用官方接口。

## 开始前

1. 运行只读自检：

   ```bash
   node "${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/keyboard-maestro/scripts/kmctl.mjs" doctor
   ```

2. 若插件根环境变量不存在，从当前 Skill 路径定位脚本，或直接使用脚本绝对路径。
3. 首次控制可能触发 macOS“隐私与安全性 -> 自动化”授权；未授权时停止并让用户完成授权。
4. 先确认目标宏/宏组的名称和 UID。写操作前说明影响；删除、执行未知 Action XML、启用含触发器的导入宏前必须获得明确确认。
5. `--enable`、`--yes`、`--dry-run` 等布尔选项只使用裸 flag，不传 `true/false`；CLI 会拒绝未知、不适用或多余参数。

## 常用操作

```bash
KMCTL="${VFT_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}/skills/keyboard-maestro/scripts/kmctl.mjs"

node "$KMCTL" list
node "$KMCTL" hotkeys --all
node "$KMCTL" show <UID>
node "$KMCTL" run <宏名或UID> --parameter '参数'
node "$KMCTL" var-get <变量名>
node "$KMCTL" var-set <变量名> <值>
node "$KMCTL" calculate '1+2'
node "$KMCTL" tokens '%LongDate%'
node "$KMCTL" edit <宏名或UID>
node "$KMCTL" enable <UID> true
```

`run` 默认同步等待；需要异步时加 `--async`。执行 Action XML 时用 `run --action-file <action.plist>`，并将其视为任意代码执行。

## 新增定时 Shell 宏

**必须先检查是否存在私有层 Skill**。若 `vft-ai:keyboard-maestro-private` 存在，优先读取并遵循其中的固定宏组、前置宏等规则；否则根据用户环境（截图、明确指示）确定目标宏组。

先 dry-run 检查结构和命令文本，再导入。默认导入后保持禁用；只有用户明确要求立即生效时才加 `--enable`。

```bash
# 先 dry-run 验证
node "$KMCTL" add-daily-shell \
  --name '每日任务' \
  --command '/absolute/path/to/task.sh' \
  --time 09:00 \
  --group 'target-group' \
  --dry-run

# 确认无误后正式创建
node "$KMCTL" add-daily-shell \
  --name '每日任务' \
  --command '/absolute/path/to/task.sh' \
  --time 09:00 \
  --group 'target-group'
```

- `--days` 是周位掩码，默认 `127`（每天）；这是 KM 11.0.3 实机格式。
- Shell Action 默认是非登录环境，命令使用绝对路径；复杂脚本写入独立文件，并在文件内声明 shebang、PATH 和错误处理。
- 到点时 Mac 睡眠不会保证补跑；锁屏时纯 Shell 通常可运行，UI 动作可能失败。
- 脚本通过 JSON 对象和 `plutil` 生成 XML，再调用 `importMacros`；绝不拼接用户输入到 AppleScript，也不直接写主宏库。

## 导入、导出和删除

```bash
node "$KMCTL" import ./macro.kmmacros          # 默认强制禁用
node "$KMCTL" import ./macro.kmmacros --enable # 明确确认后使用
node "$KMCTL" export <UID> ./backup.kmmacros
node "$KMCTL" delete <UID> --yes
```

- 导入未知文件前先检查 XML 中的 Shell、文件、网络、剪贴板和 UI 动作。
- 删除只接受 UID；脚本先备份到 `~/Documents/Keyboard Maestro Backups/` 再删除。
- 不按名称删除，避免重名误删。不要直接编辑 `~/Library/Application Support/Keyboard Maestro/Keyboard Maestro Macros.plist` 或变量 SQLite。

## 完整能力

当 `kmctl` 没有对应子命令时，读取 [references/scripting-api.md](references/scripting-api.md)，用固定 AppleScript 程序加 `argv` 传参调用 Editor/Engine SDEF。包括宏组、宏、触发器、Action/Action List、分支、字典、文本表达式、窗口、偏好设置、URL scheme、原生 Action XML 等全部官方可脚本化能力。

不得猜测未记录的 `keyboardmaestro:` URL 路由或 XML 字段。升级 Keyboard Maestro 后先重新读取应用包内 `Editor.sdef`、`Engine.sdef` 并用 dry-run fixture 验证格式。

## 完成验证

1. 再运行 `doctor`、`list`，确认版本、宏 UID 和目标状态。
2. 新增/导入后运行 `show <UID>`，核对触发时间、天掩码、Shell 文本和 enabled 状态；需要原始 plist XML 时加 `--xml`。
3. 未获执行授权时不要为了测试而运行用户宏；只做结构和状态验证。
4. 汇报宏名、UID、宏组、触发器、启用状态和备份路径，不输出敏感变量值。
