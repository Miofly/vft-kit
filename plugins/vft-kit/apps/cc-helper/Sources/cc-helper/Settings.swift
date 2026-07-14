import SwiftUI
import AppKit
import CCHelperCore

/// 设置窗口需要回调 App 执行的动作(statusLine / hook 安装等副作用)
@MainActor
protocol SettingsActions: AnyObject {
    func installStatusLineWrapper()
    func restoreStatusLine()
    func installNotifyHook()
    func statusLineInstalled() -> Bool
    func quit()
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let configStore: ConfigStore
    private weak var actions: SettingsActions?

    init(configStore: ConfigStore, actions: SettingsActions) {
        self.configStore = configStore
        self.actions = actions
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(store: configStore, actions: actions)
        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = "cc-helper 设置"
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.setContentSize(NSSize(width: 460, height: 520))
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    weak var actions: SettingsActions?

    var body: some View {
        TabView {
            GeneralTab(store: store)
                .tabItem { Label("通用", systemImage: "gearshape") }
            UsageTab(store: store)
                .tabItem { Label("用量", systemImage: "chart.bar") }
            NotifyTab(store: store)
                .tabItem { Label("通知", systemImage: "bell") }
            PipelineTab(actions: actions)
                .tabItem { Label("数据管道", systemImage: "cable.connector") }
            AboutTab(actions: actions)
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 520)
    }
}

// MARK: - 通用

private struct GeneralTab: View {
    @ObservedObject var store: ConfigStore
    var body: some View {
        Form {
            Toggle("开机自启(登录时启动)", isOn: $store.config.launchAtLogin)
            Section("数据源") {
                TextField("用量快照文件路径", text: $store.config.dataSourcePath)
                    .textFieldStyle(.roundedBorder)
                Text("由 statusLine 落盘的 rate_limits 快照,默认 /tmp/island-rate-limits.json")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - 用量

private struct UsageTab: View {
    @ObservedObject var store: ConfigStore
    var body: some View {
        Form {
            Section("菜单栏") {
                Toggle("在菜单栏显示用量", isOn: $store.config.menuBarEnabled)
                Picker("显示", selection: $store.config.menuBarShowRemaining) {
                    Text("已用 %").tag(false)
                    Text("剩余 %").tag(true)
                }
                Toggle("显示 5 小时窗口", isOn: $store.config.showFiveHour)
                Toggle("显示 7 天窗口", isOn: $store.config.showSevenDay)
            }
            Section("刘海") {
                Toggle("在刘海显示用量", isOn: $store.config.notchEnabled)
                Picker("刘海显示", selection: $store.config.notchShowRemaining) {
                    Text("已用 %").tag(false)
                    Text("剩余 %").tag(true)
                }.disabled(!store.config.notchEnabled)
                Toggle("hover 展开详情", isOn: $store.config.notchHoverExpand)
                    .disabled(!store.config.notchEnabled)
            }
            Section("颜色阈值(按已用 %)") {
                Stepper("警告 ≥ \(Int(store.config.warningThreshold))%",
                        value: $store.config.warningThreshold, in: 10...95, step: 5)
                Stepper("危险 ≥ \(Int(store.config.criticalThreshold))%",
                        value: $store.config.criticalThreshold, in: 20...100, step: 5)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - 通知

private let soundOptions = ["default", "Hero", "Glass", "Basso", "Ping", "Funk",
                            "Submarine", "Blow", "Bottle", "Frog", "Morse", "Pop",
                            "Purr", "Sosumi", "Tink"]

private struct NotifyTab: View {
    @ObservedObject var store: ConfigStore
    var body: some View {
        Form {
            Section {
                Toggle("启用通知", isOn: $store.config.notificationsEnabled)
                Picker("弹屏范围", selection: $store.config.notifyAllScreens) {
                    Text("仅主屏(单屏)").tag(false)
                    Text("所有屏(双屏)").tag(true)
                }
                Picker("样式", selection: $store.config.useNativeNotification) {
                    Text("自绘横幅").tag(false)
                    Text("系统原生").tag(true)
                }
                Stepper("横幅停留 \(Int(store.config.bannerDurationSeconds)) 秒",
                        value: $store.config.bannerDurationSeconds, in: 2...15, step: 1)
                Stepper("防抖 \(Int(store.config.debounceSeconds)) 秒",
                        value: $store.config.debounceSeconds, in: 0...30, step: 1)
            }
            .disabled(!store.config.notificationsEnabled)

            Section("分类型") {
                notifyRow("任务完成 ✅", $store.config.notifyTaskComplete)
                notifyRow("任务失败 ❌", $store.config.notifyTaskError)
                notifyRow("等待输入 ⏸️", $store.config.notifyWaitingForInput)
                notifyRow("对话完成 💬", $store.config.notifyConversationComplete)
            }
            .disabled(!store.config.notificationsEnabled)
        }
        .formStyle(.grouped)
        .padding()
    }

    private func notifyRow(_ label: String, _ binding: Binding<NotifyTypeConfig>) -> some View {
        HStack {
            Toggle(label, isOn: binding.enabled)
            Spacer()
            Picker("", selection: binding.sound) {
                ForEach(soundOptions, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 130)
            .disabled(!binding.wrappedValue.enabled)
        }
    }
}

// MARK: - 数据管道

private struct PipelineTab: View {
    weak var actions: SettingsActions?
    @State private var installed = false
    var body: some View {
        Form {
            Section("statusLine(用量数据来源)") {
                HStack {
                    Text("状态")
                    Spacer()
                    Text(installed ? "已安装 ✅" : "未安装")
                        .foregroundStyle(installed ? .green : .secondary)
                }
                Button("安装 / 更新 statusLine wrapper") { actions?.installStatusLineWrapper(); refresh() }
                Button("还原 statusLine") { actions?.restoreStatusLine(); refresh() }
            }
            Section("通知 hook") {
                Button("安装 / 更新 通知 hook") { actions?.installNotifyHook() }
                Text("把 CC 事件转发给 cc-helper 以弹通知")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { refresh() }
    }
    private func refresh() { installed = actions?.statusLineInstalled() ?? false }
}

// MARK: - 关于

private struct AboutTab: View {
    weak var actions: SettingsActions?
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 44)).foregroundStyle(.orange)
            Text("cc-helper").font(.title2).bold()
            Text("Claude Code 助手 · 用量显示 + 通知")
                .font(.callout).foregroundStyle(.secondary)
            Button("退出 cc-helper") { actions?.quit() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
