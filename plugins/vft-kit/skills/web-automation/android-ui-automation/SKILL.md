---
name: android-ui-automation
description: "通过 ADB 与 uiautomator2/u2cli 检查和操控已连接的 Android 真机，包括语义定位、点击、滑动、输入、截图、状态等待与应用调试；适用于手机操作、真机复现及登录或支付流程验证。"
---

# Android 真机自动化

优先使用 `uiautomator2` 自带的 `u2cli` 常驻服务：语义定位准确，连续命令复用设备连接。纯 ADB 是免安装兜底；`scrcpy` 只用于用户人工接管；除非用户明确需要完整测试工程，否则不引入 Appium。

## 操作边界

- 用户要求查看或操作手机时，可执行范围内的导航、输入和测试；真实付款最终确认、发送、发布、删除数据、安装/卸载应用、清空应用数据及修改账号或系统安全设置仍需明确授权。
- 不为自动化开启无障碍服务或“开关控制”。`uiautomator2` 通过 ADB 调试能力工作。
- 登录验证码、扫码、2FA、锁屏凭据和真实付款确认交给用户。人工接管期间不并发发送 ADB/u2cli 输入；用户说继续后先重新读取前台页面。
- `app-clear`、卸载、强停全部应用属于破坏性操作。执行前精确确认包名和影响；不得用模糊匹配或批量目标。
- 不输出输入框里的密码、Token、Cookie 或其他敏感值。日志开启详细动作与耗时记录，但对敏感参数脱敏。

## 快速路径

1. 用 `adb devices -l` 确认在线设备。只有一台时直接使用；多台时必须选定序列号并给每条 `u2cli`/`adb` 命令传 `-s`。
2. 运行 `u2cli server-status`；服务未运行时执行 `u2cli start-server`。若 `u2cli` 不存在，按官方 [uiautomator2](https://github.com/openatx/uiautomator2) 文档安装，并说明会安装本机 Python 包及启动设备侧自动化服务。受管设备不允许安装时直接走纯 ADB。
3. 动作前读取 `app-current` 和一次 `dump-hierarchy`，确认当前包名、Activity 与目标页面；前台不符时停止，避免误点系统设置或其他应用。
4. 定位顺序固定为：完整 `resource-id` → `content-desc` → 精确文本 → 文本包含/结构关系 → 截图坐标。选择器必须唯一；零个或多个匹配都不点击。
5. 将一段确定流程放在同一次命令执行中。点击后用 `wait`/`exists` 等目标状态，出现即继续；不要用固定 `sleep 5` 代替条件等待。
6. 普通步骤用 UI 层级回读。只在无语义控件、结果歧义、高风险确认前和最终结果处截图。
7. 完成以状态证据为准：点击成功不等于业务成功。按任务组合 UI 文案、当前 Activity、应用日志、网络/接口或服务端订单结果验证。

常用命令：

```bash
DEVICE_SERIAL='<adb serial>'

u2cli -s "$DEVICE_SERIAL" app-current
u2cli -s "$DEVICE_SERIAL" dump-hierarchy
u2cli -s "$DEVICE_SERIAL" exists --resource-id 'com.example:id/submit' --timeout 2
u2cli -s "$DEVICE_SERIAL" click --resource-id 'com.example:id/submit'
u2cli -s "$DEVICE_SERIAL" wait --text '完成' --timeout 10
u2cli -s "$DEVICE_SERIAL" screenshot '/absolute/path/final.png'
```

截图写入用户或项目指定目录；否则使用 `${ANDROID_UI_OUTPUT_DIR:-$HOME/.cache/vft-kit/android-ui-automation}`。文件名描述页面和阶段，禁止散落到仓库根目录。

## 视觉兜底

UI 层级找不到目标时：

1. 用 `u2cli screenshot` 或 `adb exec-out screencap -p` 取得当前原始分辨率截图。
2. 同时读取窗口尺寸、旋转方向和前台应用。
3. 视觉识别后只点击目标中心；旋转、弹窗或布局变化后不得复用旧坐标。
4. 点击后立即通过 UI 层级或新截图验证结果。无法建立唯一目标时停止，不猜坐标。

纯 ADB 兜底可用 `adb shell uiautomator dump` 获取层级，再通过 `adb exec-out cat` 读取 XML。它每次会重新启动 UiAutomator，适合一次性检查，不用于高频循环。

## 登录与支付

- 测试支付先选最低档，并在继续前证明面板明确标记为测试、Sandbox 或 Mock。
- 测试面板可按用户已授权的测试目标选择成功/失败并 Fulfill；真实支付默认停在最终确认前。
- 支付后同时等待前端终态并核对订单/余额或服务端回调；只看到“已提交”属于进行中，不得报告入账成功。

## 人工接管

本机存在 `scrcpy` 时可用于低延迟人工操作。交接前说明手机当前页面和用户需要完成的动作；用户完成后关闭或暂停控制，再由 `app-current`、UI 层级和截图重新建立状态。
