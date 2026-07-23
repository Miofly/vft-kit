import AppKit
import Combine

/// 「自绘横幅」展示模式的通知引擎。
///
/// banner 模式下不创建刘海 / 悬浮宠物窗口,所以刘海/悬浮各自的事件检测都不跑。
/// 本观察者始终存活地订阅 SessionMonitor,只在需要用户接手或会话真正结束后
/// 弹出毛玻璃横幅,避免工具调用/后台命令等中间态打扰用户。
@MainActor
final class BannerCompletionObserver {

    /// 横幅事件类型
    @MainActor
    private enum BannerEvent {
        case ended, attention

        var subtitle: String {
            switch self {
            case .ended:     return "对话结束"
            case .attention: return "需要介入"
            }
        }
        /// 强调色(副标题 + 图标)
        var accent: NSColor {
            switch self {
            case .ended:     return NSColor(srgbRed: 0.62, green: 0.66, blue: 0.74, alpha: 1)   // 灰蓝
            case .attention: return NSColor(srgbRed: 1.00, green: 0.72, blue: 0.25, alpha: 1)   // 橙
            }
        }
        /// 语义图标
        var symbolName: String {
            switch self {
            case .ended:     return "flag.checkered.circle.fill"
            case .attention: return "exclamationmark.circle.fill"
            }
        }
        var isEnabled: Bool {
            switch self {
            case .ended:     return AppSettings.bannerNotifyEnded
            case .attention: return AppSettings.bannerNotifyAttention
            }
        }
        func message(for session: SessionState) -> String {
            switch self {
            case .ended:
                return SessionCompletionPreviewBuilder.latestAssistantText(for: session) ?? "会话已结束。"
            case .attention:
                // 不用 latestAssistantText(会是 AskUserQuestion 的原始 JSON),给干净固定文案
                return "有会话在等待你处理(回答问题 / 审批)。"
            }
        }
    }

    private let sessionMonitor: SessionMonitor
    private let presenter = CCHelperBannerPresenter()
    private var cancellable: AnyCancellable?

    private var primed = false
    private var prevEndedIds = Set<String>()
    private var prevAttentionIds = Set<String>()
    private var recentBannerKeys: [String: Date] = [:]

    /// 追踪进入 ended 状态的时间戳，用于延迟通知确保对话真正静止
    private var endedTimestamps: [String: Date] = [:]
    private var endedNotificationWorkItems: [String: DispatchWorkItem] = [:]
    private var notifiedEndedIds = Set<String>()

    /// 对话结束后的静默期（秒），只有在这个时间内没有新活动才触发通知
    private let endedQuietPeriod: TimeInterval = 5.0

    init(sessionMonitor: SessionMonitor) {
        self.sessionMonitor = sessionMonitor
    }

    func start() {
        guard cancellable == nil else { return }
        primed = false
        cancellable = sessionMonitor.$instances
            .receive(on: RunLoop.main)
            .sink { [weak self] instances in
                MainActor.assumeIsolated { self?.handle(instances) }
            }
    }

    func stop() {
        cancellable = nil
        primed = false
    }

    // MARK: - 检测

    private struct Snapshot {
        var ended: Set<String>
        var attention: Set<String>
    }

    private func snapshot(_ instances: [SessionState]) -> Snapshot {
        Snapshot(
            ended: Set(instances.filter { $0.phase == .ended }.map(\.stableId)),
            attention: Set(instances
                .filter(SessionAttentionSoundEvaluator.shouldContributeToAttentionSoundEdge)
                .map(\.stableId))
        )
    }

    private func handle(_ instances: [SessionState]) {
        let snap = snapshot(instances)

        // 首帧只建基线,避免把历史状态全补弹一遍
        if !primed {
            apply(snap)
            primed = true
            return
        }

        // 总闸:临时静音时不弹
        guard !AppSettings.areReminderNotificationsSuppressed else {
            apply(snap)
            return
        }
        // 智能抑制:正在看终端时,只压低优先级事件(结束),避免盯着会话答题时反复被打扰;
        // 但「需要介入」必须立刻知道,不被终端可见性吞掉。
        // 【已禁用】用户要求注释掉智能抑制,改为始终弹通知
        let suppressLowPriority = false // AppSettings.smartSuppression && TerminalVisibilityDetector.isTerminalVisibleOnCurrentSpace()

        let newAttention = snap.attention.subtracting(prevAttentionIds)
        let newEnded = snap.ended.subtracting(prevEndedIds)

        // 更新 ended 状态的时间戳追踪
        let now = Date()
        for stableId in newEnded {
            endedTimestamps[stableId] = now
            notifiedEndedIds.remove(stableId)
            scheduleEndedNotification(for: stableId, endedAt: now)
        }

        // 清理已经不在 ended 状态的会话时间戳（可能状态回退了）
        let currentEndedIds = snap.ended
        endedTimestamps = endedTimestamps.filter { currentEndedIds.contains($0.key) }
        notifiedEndedIds = notifiedEndedIds.intersection(currentEndedIds)
        for (stableId, workItem) in endedNotificationWorkItems where !currentEndedIds.contains(stableId) {
            workItem.cancel()
        }
        endedNotificationWorkItems = endedNotificationWorkItems.filter { currentEndedIds.contains($0.key) }

        if !newAttention.isEmpty, BannerEvent.attention.isEnabled {
            fire(.attention, sessions: instances.filter { newAttention.contains($0.stableId) })
        } else if !suppressLowPriority {
            for (stableId, endedAt) in endedTimestamps where now.timeIntervalSince(endedAt) >= endedQuietPeriod {
                fireEndedIfStillQuiet(stableId: stableId, endedAt: endedAt)
            }
        }

        apply(snap)
    }

    private func apply(_ snap: Snapshot) {
        prevEndedIds = snap.ended
        prevAttentionIds = snap.attention
    }

    // MARK: - 呈现

    private func scheduleEndedNotification(for stableId: String, endedAt: Date) {
        endedNotificationWorkItems[stableId]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.endedNotificationWorkItems[stableId] = nil
                self?.fireEndedIfStillQuiet(stableId: stableId, endedAt: endedAt)
            }
        }
        endedNotificationWorkItems[stableId] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + endedQuietPeriod, execute: workItem)
    }

    private func fireEndedIfStillQuiet(stableId: String, endedAt: Date) {
        guard !AppSettings.areReminderNotificationsSuppressed else { return }
        guard BannerEvent.ended.isEnabled else { return }
        guard !notifiedEndedIds.contains(stableId) else { return }
        guard !(AppSettings.smartSuppression && TerminalVisibilityDetector.isTerminalVisibleOnCurrentSpace()) else {
            return
        }
        guard let session = sessionMonitor.instances.first(where: { $0.stableId == stableId }) else {
            return
        }
        guard session.phase == .ended else { return }
        guard session.lastActivity <= endedAt else { return }
        notifiedEndedIds.insert(stableId)
        fire(.ended, sessions: [session])
    }

    private func fire(_ event: BannerEvent, sessions: [SessionState]) {
        // 修复：不要用 lastActivity 排序，因为可能选错会话
        // 场景：第二个 tab 触发通知，但第一个 tab 的 lastActivity 更新，导致激活错误
        // 策略：优先使用触发事件的会话（通常只有 1 个），多个时选第一个
        guard let session = sessions.first else { return }

        let duration = AppSettings.bannerDurationSeconds
        let key = "\(event.subtitle):\(session.stableId)"
        let now = Date()
        if let last = recentBannerKeys[key], now.timeIntervalSince(last) < duration { return }
        recentBannerKeys[key] = now
        recentBannerKeys = recentBannerKeys.filter { now.timeIntervalSince($0.value) < 60 }

        presenter.show(CCHelperBannerPresenter.Content(
            title: session.projectName.isEmpty ? "ai-helper" : session.projectName,
            subtitle: event.subtitle,
            message: event.message(for: session),
            sound: "",   // 空 = 交给 ai-helper 自带阶段音效,横幅不重复播放
            allScreens: true,
            duration: duration,
            accent: event.accent,
            symbolName: event.symbolName,
            onActivate: {
                // 点击横幅 → 跳转到承载该会话的终端/IDE
                _ = await SessionLauncher.shared.activate(session)
            }
        ))
    }
}
