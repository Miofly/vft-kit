import AppKit
import Combine
import ServiceManagement
import CCHelperCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, SettingsActions {
    let configStore = ConfigStore()
    private var store: RateLimitStore!

    private var notchController: NotchUsageController?
    private var notifyController: NotificationController?
    private var settingsWindow: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var infoItem5h: NSMenuItem?
    private var infoItem7d: NSMenuItem?
    private var lastMenuBarSignature: String?

    private var config: CCHelperConfig { configStore.config }

    // MARK: 路径
    private let islandStatuslinePath = "$HOME/.ping-island/bin/island-statusline"
    private var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cc-helper", isDirectory: true)
    }
    private var legacyBackupURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cc-notch-usage/statusline-backup.txt")
    }
    private var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }
    private var backupURL: URL { supportDir.appendingPathComponent("statusline-backup.txt") }
    private var wrapperURL: URL { supportDir.appendingPathComponent("bin/statusline-wrapper.sh") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = RateLimitStore(path: config.dataSourcePath)
        store.start()
        buildMenu()
        applyConfig()

        // 通知控制器常驻消费事件(决策状态需连续),是否真弹由配置在内部把关
        let controller = NotificationController(config: { [weak self] in
            self?.configStore.config ?? CCHelperConfig()
        })
        controller.start()
        notifyController = controller

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshMenuBar() }
            .store(in: &cancellables)
        configStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.applyConfig() }
            .store(in: &cancellables)
    }

    // MARK: 应用配置(菜单栏/刘海/自启,配置一变就重跑)

    private func applyConfig() {
        // 菜单栏显隐
        statusItem?.isVisible = config.menuBarEnabled
        lastMenuBarSignature = nil   // 强制重绘(用/剩余、阈值可能变了)
        refreshMenuBar()

        // 刘海开关 + 显隐配置
        if config.notchEnabled, notchController == nil {
            let c = NotchUsageController(store: store,
                                        showRemaining: config.notchShowRemaining,
                                        hoverExpand: config.notchHoverExpand)
            c.mount()
            notchController = c
        } else if !config.notchEnabled, let c = notchController {
            c.unmount()
            notchController = nil
        } else if let c = notchController {
            c.apply(showRemaining: config.notchShowRemaining, hoverExpand: config.notchHoverExpand)
        }

        // 登录自启
        let enabled = SMAppService.mainApp.status == .enabled
        if config.launchAtLogin != enabled {
            try? config.launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    // MARK: 菜单栏

    private func buildMenu() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let info5h = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let info7d = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(info5h)
        menu.addItem(info7d)
        infoItem5h = info5h
        infoItem7d = info7d
        menu.addItem(.separator())

        addItem(menu, "设置…", #selector(openSettings), key: ",")
        menu.addItem(.separator())
        addItem(menu, "退出 cc-helper", #selector(quit), key: "q")

        statusItem.menu = menu
        self.statusItem = statusItem
        updateInfoItems()
        refreshMenuBar()

        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshMenuBar() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(configStore: configStore, actions: self)
        }
        settingsWindow?.show()
    }

    // MARK: 菜单栏用量文字

    private func refreshMenuBar() {
        guard let button = statusItem?.button else { return }
        let signature = menuBarSignature()
        guard signature != lastMenuBarSignature else { return }
        lastMenuBarSignature = signature

        let text = usageAttributedString()
        let textSize = text.size()
        let padding: CGFloat = 2
        let imageSize = NSSize(width: ceil(textSize.width) + padding * 2, height: ceil(textSize.height))

        let image = NSImage(size: imageSize)
        image.lockFocus()
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            text.draw(at: NSPoint(x: padding, y: 0))
        }
        image.unlockFocus()
        image.isTemplate = false

        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
    }

    private func displayValue(_ window: RateLimitWindow) -> Int {
        let v = config.menuBarShowRemaining ? window.remainingPercentage : window.usedPercentage
        return Int(v.rounded())
    }

    private func severity(_ window: RateLimitWindow) -> UsageSeverity {
        window.severity(warning: config.warningThreshold, critical: config.criticalThreshold)
    }

    private func menuBarSignature() -> String {
        func part(_ w: RateLimitWindow?) -> String {
            guard let w else { return "--" }
            return "\(displayValue(w))-\(severity(w))"
        }
        let s = store?.snapshot
        return "\(config.showFiveHour ? part(s?.fiveHour) : "")|\(config.showSevenDay ? part(s?.sevenDay) : "")|\(store?.isStale ?? true)|\(config.menuBarShowRemaining)"
    }

    private func usageAttributedString() -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let dim = NSColor.secondaryLabelColor
        let alpha: CGFloat = (store?.isStale ?? true) ? 0.5 : 1
        let result = NSMutableAttributedString()

        func append(_ str: String, _ color: NSColor) {
            result.append(NSAttributedString(string: str, attributes: [
                .foregroundColor: color.withAlphaComponent(alpha), .font: font
            ]))
        }
        func windowChunk(_ label: String, _ window: RateLimitWindow?, trailingGap: Bool) {
            append(label + " ", dim)
            if let window {
                append("\(displayValue(window))%", menuBarColor(severity(window)))
            } else {
                append("--", dim)
            }
            if trailingGap { append("  ", dim) }
        }

        let s = store?.snapshot
        if s != nil {
            let showBoth = config.showFiveHour && config.showSevenDay
            if config.showFiveHour { windowChunk("5h", s?.fiveHour, trailingGap: showBoth) }
            if config.showSevenDay { windowChunk("7d", s?.sevenDay, trailingGap: false) }
            if !config.showFiveHour && !config.showSevenDay { append("cc-helper", dim) }
        } else {
            append("CC 用量待接入", dim)
        }
        return result
    }

    // MARK: 菜单顶部只读信息

    @objc func quit() { NSApp.terminate(nil) }

    func menuNeedsUpdate(_ menu: NSMenu) { updateInfoItems() }

    private func updateInfoItems() {
        infoItem5h?.attributedTitle = infoAttributed("5 小时", store?.snapshot?.fiveHour)
        infoItem7d?.attributedTitle = infoAttributed("7 天", store?.snapshot?.sevenDay)
    }

    private func infoAttributed(_ label: String, _ window: RateLimitWindow?) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let result = NSMutableAttributedString()
        func add(_ text: String, _ color: NSColor) {
            result.append(NSAttributedString(string: text, attributes: [.foregroundColor: color, .font: font]))
        }
        guard let window else {
            add("\(label)：无数据", .secondaryLabelColor)
            return result
        }
        add("\(label)：", .labelColor)
        add("已用 \(Int(window.usedPercentage.rounded()))%", menuItemColor(severity(window)))
        if let reset = ResetCountdown.text(until: window.resetsAt) {
            add(" · \(reset) 后重置", .secondaryLabelColor)
        }
        return result
    }

    private func menuItemColor(_ severity: UsageSeverity) -> NSColor {
        switch severity {
        case .healthy: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    private func menuBarColor(_ severity: UsageSeverity) -> NSColor {
        switch severity {
        case .healthy: return NSColor(srgbRed: 0.20, green: 0.98, blue: 0.55, alpha: 1)
        case .warning: return NSColor(srgbRed: 1.00, green: 0.82, blue: 0.20, alpha: 1)
        case .critical: return NSColor(srgbRed: 1.00, green: 0.40, blue: 0.38, alpha: 1)
        }
    }

    @discardableResult
    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - SettingsActions

    func statusLineInstalled() -> Bool {
        guard let raw = try? Data(contentsOf: settingsURL),
              let settings = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let cmd = (settings["statusLine"] as? [String: Any])?["command"] as? String else {
            return false
        }
        return cmd.contains("statusline-wrapper.sh")
    }

    func installStatusLineWrapper() {
        do {
            let raw = try Data(contentsOf: settingsURL)
            guard var settings = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
                alert("无法解析 ~/.claude/settings.json"); return
            }
            let original = (settings["statusLine"] as? [String: Any])?["command"] as? String

            let wrapper = StatusLineInstaller.wrapperScript(
                originalCommand: original ?? "cat >/dev/null",
                islandStatuslinePath: islandStatuslinePath)
            try FileManager.default.createDirectory(at: wrapperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(wrapper.utf8).write(to: wrapperURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperURL.path)

            let (updated, backup) = StatusLineInstaller.installed(into: settings, wrapperCommand: wrapperURL.path)
            settings = updated
            if let backup, !backup.contains("statusline-wrapper.sh") {
                try Data(backup.utf8).write(to: backupURL)
            }
            let out = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .withoutEscapingSlashes])
            try out.write(to: settingsURL)
            alert("已安装。重开 Claude Code 会话生效。")
        } catch {
            alert("安装失败:\(error.localizedDescription)")
        }
    }

    func restoreStatusLine() {
        var original = (try? String(contentsOf: backupURL, encoding: .utf8)) ?? ""
        if original.isEmpty { original = (try? String(contentsOf: legacyBackupURL, encoding: .utf8)) ?? "" }
        guard !original.isEmpty else { alert("没有找到备份,无法还原"); return }
        do {
            let raw = try Data(contentsOf: settingsURL)
            guard let settings = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
                alert("无法解析 settings.json"); return
            }
            let restored = StatusLineInstaller.restored(into: settings, originalCommand: original)
            let out = try JSONSerialization.data(withJSONObject: restored, options: [.prettyPrinted, .withoutEscapingSlashes])
            try out.write(to: settingsURL)
            alert("已还原原 statusLine。")
        } catch {
            alert("还原失败:\(error.localizedDescription)")
        }
    }

    private var notifyShimURL: URL { supportDir.appendingPathComponent("bin/notify-shim.sh") }
    private let notifyEvents = ["Stop", "PostToolUse", "PreToolUse", "PermissionRequest"]

    func installNotifyHook() {
        do {
            // 1) 写 shim:读 CC 事件 stdin,原子落到 ~/.cc-helper/events/ 队列
            //    必须先写临时文件再 mv 改名——否则 kqueue 在文件「创建瞬间」就触发,
            //    App 会读到还没写完的空文件、解析失败而丢弃事件(竞态)。mv 是原子的,
            //    watcher 只会看到写完整的 .json。
            let shim = """
            #!/bin/bash
            d="$HOME/.cc-helper/events"
            mkdir -p "$d"
            tmp="$d/.tmp-$$-$RANDOM"
            cat > "$tmp"
            mv -f "$tmp" "$d/evt-$(date +%s)-$$-$RANDOM.json"
            """
            try FileManager.default.createDirectory(at: notifyShimURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(shim.utf8).write(to: notifyShimURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notifyShimURL.path)

            // 2) 注册进 settings.json 的 hooks(4 个事件),去重后追加
            let raw = (try? Data(contentsOf: settingsURL)) ?? Data("{}".utf8)
            guard var settings = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else {
                alert("无法解析 ~/.claude/settings.json"); return
            }
            var hooks = settings["hooks"] as? [String: Any] ?? [:]
            let command = "bash \"\(notifyShimURL.path)\""
            for event in notifyEvents {
                var groups = hooks[event] as? [[String: Any]] ?? []
                // 去重:移掉已有的 notify-shim 组
                groups.removeAll { group in
                    guard let inner = group["hooks"] as? [[String: Any]] else { return false }
                    return inner.contains { ($0["command"] as? String)?.contains("notify-shim.sh") == true }
                }
                groups.append(["hooks": [["type": "command", "command": command, "timeout": 5]]])
                hooks[event] = groups
            }
            settings["hooks"] = hooks

            let out = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .withoutEscapingSlashes])
            try out.write(to: settingsURL)
            alert("通知 hook 已安装(Stop/PostToolUse/PreToolUse/PermissionRequest)。重开 Claude Code 会话生效。")
        } catch {
            alert("安装通知 hook 失败:\(error.localizedDescription)")
        }
    }

    private func alert(_ text: String) {
        let a = NSAlert()
        a.messageText = text
        a.runModal()
    }
}
