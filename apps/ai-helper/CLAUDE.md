# ai-helper 项目规范

## 修改代码后的自动化流程（强制）

**每次修改 Swift 代码后，必须自动完成以下步骤，无需询问用户：**

1. **编译**：
   ```bash
   xcodebuild -project AIHelper.xcodeproj -scheme AIHelper -configuration Debug \
     -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
   ```

2. **关闭旧版本**：
   ```bash
   killall ai-helper 2>/dev/null || true
   sleep 1
   ```

3. **启动新版本**：
   ```bash
   open /Users/wfly/Library/Developer/Xcode/DerivedData/AIHelper-bsyeonxuiilceobxxuhhyvhyntlo/Build/Products/Debug/ai-helper.app
   ```

4. **验证启动**：
   ```bash
   sleep 2
   ps aux | grep "[a]i-helper" | grep -v grep
   ```

**例外情况：**
- 只修改配置文件（如 `defaults write`）不需要编译，只需重启应用
- 编译失败时报告错误，不要尝试启动

**报告格式：**
修改完成后一句话说明：「已编译并重启 ai-helper，新版本已生效。」

## 项目信息

- **Bundle ID**: `com.mrwhy.aihelper`（不是 `com.aihelper.app`）
- **编译产物路径**: `/Users/wfly/Library/Developer/Xcode/DerivedData/AIHelper-bsyeonxuiilceobxxuhhyvhyntlo/Build/Products/Debug/ai-helper.app`
- **配置存储**: `~/Library/Preferences/com.mrwhy.aihelper.plist`

## 通知系统

### 事件类型
- `completed`: 会话完成（进入 `waitingForInput`）
- `ended`: 会话结束（进入 `ended` 状态）
- `attention`: 需要介入（等待审批/回答问题）
- `error`: 工具执行失败
- `compacted`: 上下文压缩

### 关键文件
- **通知引擎**: `AIHelper/Services/Notify/BannerCompletionObserver.swift`
- **状态评估**: `AIHelper/UI/Views/SessionCompletionNotificationView.swift`
- **配置管理**: `AIHelper/Core/Settings.swift`

### 静默期机制
`ended` 事件采用 5 秒静默期检测，确保对话真正静止后才通知，避免工具任务完成时误报。
