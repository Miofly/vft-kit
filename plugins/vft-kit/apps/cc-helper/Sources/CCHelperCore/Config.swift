import Foundation
import Combine

/// 单个通知类型的开关 + 声音
public struct NotifyTypeConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var sound: String
    public init(enabled: Bool, sound: String) {
        self.enabled = enabled
        self.sound = sound
    }
}

/// cc-helper 全局配置。所有字段带默认值,解码用 decodeIfPresent 容错(旧配置/缺字段不炸)。
public struct CCHelperConfig: Codable, Equatable, Sendable {
    // 通用
    public var launchAtLogin: Bool = false
    public var dataSourcePath: String = "/tmp/island-rate-limits.json"

    // 用量显示
    public var menuBarEnabled: Bool = true
    public var menuBarShowRemaining: Bool = false   // false=已用%,true=剩余%
    public var showFiveHour: Bool = true
    public var showSevenDay: Bool = true
    public var notchEnabled: Bool = false
    public var notchShowRemaining: Bool = false
    public var notchHoverExpand: Bool = true
    public var warningThreshold: Double = 70
    public var criticalThreshold: Double = 90

    // 通知
    public var notificationsEnabled: Bool = true
    public var notifyAllScreens: Bool = true         // true=双屏,false=仅主屏
    public var useNativeNotification: Bool = false    // true=系统原生,false=自绘横幅
    public var bannerDurationSeconds: Double = 5
    public var debounceSeconds: Double = 5
    public var iconPath: String = ""
    public var notifyTaskComplete = NotifyTypeConfig(enabled: true, sound: "Hero")
    public var notifyTaskError = NotifyTypeConfig(enabled: true, sound: "Basso")
    public var notifyWaitingForInput = NotifyTypeConfig(enabled: true, sound: "default")
    public var notifyConversationComplete = NotifyTypeConfig(enabled: true, sound: "Glass")

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = CCHelperConfig()
        d.launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        d.dataSourcePath = try c.decodeIfPresent(String.self, forKey: .dataSourcePath) ?? d.dataSourcePath
        d.menuBarEnabled = try c.decodeIfPresent(Bool.self, forKey: .menuBarEnabled) ?? d.menuBarEnabled
        d.menuBarShowRemaining = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowRemaining) ?? d.menuBarShowRemaining
        d.showFiveHour = try c.decodeIfPresent(Bool.self, forKey: .showFiveHour) ?? d.showFiveHour
        d.showSevenDay = try c.decodeIfPresent(Bool.self, forKey: .showSevenDay) ?? d.showSevenDay
        d.notchEnabled = try c.decodeIfPresent(Bool.self, forKey: .notchEnabled) ?? d.notchEnabled
        d.notchShowRemaining = try c.decodeIfPresent(Bool.self, forKey: .notchShowRemaining) ?? d.notchShowRemaining
        d.notchHoverExpand = try c.decodeIfPresent(Bool.self, forKey: .notchHoverExpand) ?? d.notchHoverExpand
        d.warningThreshold = try c.decodeIfPresent(Double.self, forKey: .warningThreshold) ?? d.warningThreshold
        d.criticalThreshold = try c.decodeIfPresent(Double.self, forKey: .criticalThreshold) ?? d.criticalThreshold
        d.notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? d.notificationsEnabled
        d.notifyAllScreens = try c.decodeIfPresent(Bool.self, forKey: .notifyAllScreens) ?? d.notifyAllScreens
        d.useNativeNotification = try c.decodeIfPresent(Bool.self, forKey: .useNativeNotification) ?? d.useNativeNotification
        d.bannerDurationSeconds = try c.decodeIfPresent(Double.self, forKey: .bannerDurationSeconds) ?? d.bannerDurationSeconds
        d.debounceSeconds = try c.decodeIfPresent(Double.self, forKey: .debounceSeconds) ?? d.debounceSeconds
        d.iconPath = try c.decodeIfPresent(String.self, forKey: .iconPath) ?? d.iconPath
        d.notifyTaskComplete = try c.decodeIfPresent(NotifyTypeConfig.self, forKey: .notifyTaskComplete) ?? d.notifyTaskComplete
        d.notifyTaskError = try c.decodeIfPresent(NotifyTypeConfig.self, forKey: .notifyTaskError) ?? d.notifyTaskError
        d.notifyWaitingForInput = try c.decodeIfPresent(NotifyTypeConfig.self, forKey: .notifyWaitingForInput) ?? d.notifyWaitingForInput
        d.notifyConversationComplete = try c.decodeIfPresent(NotifyTypeConfig.self, forKey: .notifyConversationComplete) ?? d.notifyConversationComplete
        self = d
    }
}

/// 配置的加载/保存/发布。设置窗口改 config → 自动落盘 + 通知各模块。
@MainActor
public final class ConfigStore: ObservableObject {
    @Published public var config: CCHelperConfig {
        didSet {
            guard !isLoading, config != oldValue else { return }
            save()
        }
    }

    private let url: URL
    private var isLoading = false

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cc-helper/config.json")
        self.config = CCHelperConfig()
        load()
    }

    public func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CCHelperConfig.self, from: data) else {
            return
        }
        config = decoded
    }

    public func save() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: url)
        } catch {
            // 落盘失败不致命
        }
    }
}
