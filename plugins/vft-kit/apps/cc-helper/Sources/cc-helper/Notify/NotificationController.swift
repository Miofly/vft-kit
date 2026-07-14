//  通知总控:CC 事件队列 → 决策 → 防抖 → 自绘横幅 / 系统原生。全部受配置控制。

import AppKit
import CCHelperCore

@MainActor
final class NotificationController {
    private let configProvider: () -> CCHelperConfig
    private let decider = NotificationDecider()
    private let banner = BannerPresenter()
    private var watcher: DirectoryWatcher?
    private var lastFire: [NotificationKind: Date] = [:]

    /// CC hook shim 把事件 JSON 落到这个队列目录
    static var eventsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cc-helper/events", isDirectory: true)
    }

    init(config: @escaping () -> CCHelperConfig) {
        self.configProvider = config
    }

    func start() {
        try? FileManager.default.createDirectory(at: Self.eventsDir, withIntermediateDirectories: true)
        processPending()
        let dir = Self.eventsDir.path
        let w = DirectoryWatcher(path: dir) { [weak self] in
            Task { @MainActor in self?.processPending() }
        }
        w.start()
        watcher = w
    }

    func stop() {
        watcher?.stop()
        watcher = nil
    }

    private func processPending() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.eventsDir,
                                                      includingPropertiesForKeys: [.creationDateKey]) else { return }
        // 按创建时间顺序处理,保证 turn 事件次序正确
        let sorted = files.filter { $0.pathExtension == "json" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a < b
        }
        for file in sorted {
            defer { try? fm.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file),
                  let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let event = payload["hook_event_name"] as? String else { continue }
            handle(event: event, payload: payload)
        }
    }

    private func handle(event: String, payload: [String: Any]) {
        // 决策要一直跑(累计 turn 状态),但只有开启通知才真弹
        guard let decision = decider.decide(event: event, payload: payload) else { return }
        let config = configProvider()
        guard config.notificationsEnabled else { return }

        let (title, subtitle, typeConfig) = meta(for: decision.kind, config: config)
        guard typeConfig.enabled else { return }
        guard passesDebounce(decision.kind, seconds: config.debounceSeconds) else { return }

        if config.useNativeNotification {
            showNative(title: title, subtitle: subtitle, message: decision.message,
                       sound: typeConfig.sound, group: "claude-code-\(decision.kind.rawValue)",
                       iconPath: config.iconPath)
        } else {
            banner.show(BannerPresenter.Content(
                title: title, subtitle: subtitle, message: decision.message,
                iconPath: config.iconPath, sound: typeConfig.sound,
                allScreens: config.notifyAllScreens, duration: config.bannerDurationSeconds))
        }
    }

    private func passesDebounce(_ kind: NotificationKind, seconds: Double) -> Bool {
        guard seconds > 0 else { return true }
        let now = Date()
        if let last = lastFire[kind], now.timeIntervalSince(last) < seconds { return false }
        lastFire[kind] = now
        return true
    }

    private func meta(for kind: NotificationKind, config: CCHelperConfig) -> (String, String, NotifyTypeConfig) {
        switch kind {
        case .taskComplete:        return ("Claude Code", "任务完成 ✅", config.notifyTaskComplete)
        case .taskError:           return ("Claude Code", "任务失败 ❌", config.notifyTaskError)
        case .waitingForInput:     return ("Claude Code", "等待您的输入 ⏸️", config.notifyWaitingForInput)
        case .conversationComplete:return ("Claude Code", "对话已完成 💬", config.notifyConversationComplete)
        }
    }

    private func showNative(title: String, subtitle: String, message: String,
                            sound: String, group: String, iconPath: String) {
        // 优先 terminal-notifier,失败退 osascript
        let tn = Process()
        tn.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var args = ["terminal-notifier", "-title", title, "-subtitle", subtitle,
                    "-message", message, "-sound", sound, "-group", group]
        // 同款图标(与 notify.mjs 一致):同 group 通知会原地替换而非堆叠
        let expanded = (iconPath as NSString).expandingTildeInPath
        if !iconPath.isEmpty, FileManager.default.fileExists(atPath: expanded) {
            args += ["-contentImage", expanded]
        }
        tn.arguments = args
        do {
            try tn.run()
        } catch {
            let script = "display notification \"\(message)\" with title \"\(title)\" subtitle \"\(subtitle)\""
            let osa = Process()
            osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            osa.arguments = ["-e", script]
            try? osa.run()
        }
    }
}
