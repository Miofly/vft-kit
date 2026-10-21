# Keyboard Maestro 11 脚本接口

本参考以本机 Keyboard Maestro 11.0.3 应用包内的 SDEF 为准。升级后重新读取：

```bash
/Applications/Keyboard\ Maestro.app/Contents/Resources/en.lproj/Editor.sdef
/Applications/Keyboard\ Maestro.app/Contents/MacOS/Keyboard\ Maestro\ Engine.app/Contents/Resources/en.lproj/Engine.sdef
```

## 接口选择

| 任务 | 接口 |
|---|---|
| 创建、结构编辑、导入、导出、启停、删除、选择、打开编辑器 | `Keyboard Maestro` Editor AppleScript |
| 执行、变量、字典、表达式、Token、搜索、运行状态 | `Keyboard Maestro Engine` AppleScript |
| 同步/异步执行宏或 Action XML | 应用内 `keyboardmaestro` CLI |
| URL 触发 | `kmtrigger://macro=<编码名称或UID>&value=<编码参数>` |
| 当前版本可由 KM 原生 Action 表达的 GUI、剪贴板、文件、网络、Shell 等动作 | 生成/导入或执行 KM 原生 Action XML |

Editor/Engine SDEF 没有独立的 clipboard/pasteboard 命令。剪贴板能力必须使用 KM Clipboard Action；不要虚构命令。

## Editor 完整能力

标准命令：`open`、`close`、`quit`、`count`、`delete`、`duplicate`、`exists`、`make`、`move`、`select`、`edit`。SDEF 中的 `save`、`print` 和 `document` 定义被注释，不能当成可用接口。

专用命令：

| 命令 | 用途 |
|---|---|
| `setMacroEnable <name/UID> enable <boolean>` | 启停宏组或宏 |
| `editMacro <name/UID>` | 在编辑器中打开宏组或宏 |
| `selectedMacros` | 返回编辑器当前选择的 UID 列表 |
| `selectAction <integer UID>` | 选择 Action |
| `importMacros <URL/XML> [disabled boolean]` | 导入 `.kmmacros` 或宏 XML |
| `deleteMacro <UID/唯一名称>` | 删除宏 |
| `deleteMacroGroup <UID/唯一名称>` | 删除宏组 |
| `reload` | 重载宏 |
| `show preference pane <name>` | 打开偏好设置面板 |
| `geturl <keyboardmaestro: URL>` | 处理 Editor URL；具体路由未在本机资源中公开，不得猜测 |

对象模型：

- `application`：提供 `global macro group`、`disabled group holder`、`selected macro groups`、`selected macros`，并包含宏组、智能组和宏。
- `macro group`：`id/name/selected/creation date/modification date/size/enabled/disabled on this Mac/available application xml/available window xml/activation xml/display in menu bar xml/xml/group xml`，包含 `macro`。
- `smart group`：`id/name/selected/creation date/modification date/search strings/xml`。
- `disabled macro group holder`：只读 `id/name/selected`。
- `macro`：`id/name/selected/enabled/creation date/modification date/used date/size/macro group/xml`，包含 `trigger` 与 `action`。
- `trigger`：可读 `description`，可读写 `xml`。
- `action`：`id/name/enabled/xml/disclosed/timeout/failure/notes/color`，包含嵌套 Action、case、then/else/try/catch Action List。
- `action list`、`case entry`：可读写 `xml`，包含 Action。
- `window`：标准窗口属性以及编辑器专用 `editing/divider` 属性；有效 SDEF 没有 `document` 对象。

创建和结构编辑优先使用标准 `make`、`duplicate`、`move` 与对象的 XML 属性。传入固定 AppleScript，动态值只放 `argv`：

```applescript
on run argv
  set macroID to item 1 of argv
  tell application "Keyboard Maestro"
    set targetMacro to first macro whose id is macroID
    set enabled of targetMacro to false
    return xml of targetMacro
  end tell
end run
```

## Engine 完整能力

| 命令 | 用途 |
|---|---|
| `do script <name/UID/Action plist> [with parameter text]` | 执行宏或 Action XML并返回结果 |
| `gethotkeys [asstring] [getall]` | 查询可用热键/Typed String 或全部活动宏 |
| `getmacros [asstring]` | 查询宏组与宏 |
| `getvariable <name> [instance]` | 读取变量；11.0.3 实测“不存在”和“空值”都返回空字符串，SDEF 只承诺返回 text |
| `setvariable <name> [instance] to <value>` | 写变量 |
| `reload` | 重载宏 |
| `executing` | 是否有宏正在执行 |
| `calculate <expression> [instance]` | 计算 KM 表达式 |
| `process tokens <text> [instance]` | 展开 KM Token |
| `search <input> for <search> replace <replacement> [...]` | 字符串或正则替换 |
| `count found in <input> for <search> [...]` | 统计匹配数 |
| `found in <input> for <search> [...]` | 判断是否匹配 |
| `play sound <file> [soundeffect] [volume]` | 播放声音 |
| `getappdetails` | 返回 Engine 技术信息 plist |
| `geturl <kmtrigger: URL>` | 处理触发 URL |

Engine 对象模型：

- 标准有效命令：`open`、`close`、`quit`、`count`、`delete`、`duplicate`、`exists`、`make`、`move`。
- `variable`：`id/name/value`，值可读写。
- `dictionary`：`id/name`，包含 `dictionary key`。
- `dictionary key`：`id/name/value`，值可读写。
- 标准应用和窗口；SDEF 中的 `document` 定义被注释。

变量、字典和 `KMINSTANCE` 属于运行时状态。写入或删除前确认作用域，读取结果不要泄露凭据。

## 官方 CLI 与 URL

```bash
KMCLI='/Applications/Keyboard Maestro.app/Contents/MacOS/keyboardmaestro'
"$KMCLI" --version
"$KMCLI" [-a|--async] [-e|--edit] [-p|--parameter VALUE] [-v|--verbose] <宏名/UID/Action XML>
```

- `-p -` 从 stdin 读参数。
- 默认同步等待；`--async` 不等待。
- `--edit` 打开宏、宏组或智能组。
- `kmtrigger://macro=<URL编码名称或UID>&value=<URL编码参数>` 可触发宏。
- `do script`、CLI Action XML 和 `kmtrigger:` 都可能执行 Shell、删文件或发网络请求，按代码执行审查。

## `.kmmacros` 与 Action XML

Editor 的 `xml` 属性和 `.kmmacros` 均是 plist XML。11.0.3 的真实导出文件及导入回环验证表明：单个宏的 `xml` 是 dict，但可导入文件顶层为宏组数组，宏位于对应宏组的 `Macros` 数组；导出或备份单宏时使用 `[{...group, Macros: [macro]}]`。这不是 SDEF 公布的稳定 schema，升级后必须重新验证。创建数据时先构造 JSON/plist 对象，再由 `/usr/bin/plutil` 转成 XML；不要用 `sed`、字符串模板或未转义拼接生成 XML。

KM 11.0.3 每日定时触发器字段：

```json
{
  "ExecuteType": "Time",
  "MacroTriggerType": "Time",
  "TimeHour": 9,
  "TimeMinutes": 0,
  "WhichDays": 127
}
```

Shell Action 的关键字段是 `MacroActionType=ExecuteShellScript`、`Text`、`UseText=true`。具体 XML 字段不是稳定公开协议；升级后从一个由当前版本编辑器导出的最小 fixture 重新验证。

安全导入顺序：

1. 检查所有 Action 和 Trigger。
2. `importMacros ... disabled true`。
3. 按 UID 查询并读取 `xml`，核对名称、触发器和动作内容。
4. 移入目标宏组。
5. 只有用户明确同意后才启用。

## 危险操作

- `delete`、`deleteMacro`、`deleteMacroGroup`：优先 UID，删除前导出 XML。
- 写 `trigger.xml`、`action.xml`、`action list.xml`：错误 XML 会直接改变宏结构。
- `importMacros disabled false`：触发器可能立刻生效。
- `setvariable`、字典键写入：会改变全局或指定实例状态。
- `reload`、`close`、`quit`：会影响加载状态、运行中的宏或窗口。
- 不直接写主宏 plist/SQLite；合法 API 操作会由 Keyboard Maestro 自己持久化。

## 只读诊断

```bash
osascript -e 'tell application "Keyboard Maestro" to get version'
osascript -e 'tell application "Keyboard Maestro" to count macro groups'
osascript -e 'tell application "Keyboard Maestro Engine" to calculate "1+2"'
osascript -e 'tell application "Keyboard Maestro Engine" to count variables'
/Applications/Keyboard\ Maestro.app/Contents/MacOS/keyboardmaestro --help
```
