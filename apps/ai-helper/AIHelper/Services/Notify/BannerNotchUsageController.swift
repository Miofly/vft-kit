//  自绘横幅模式下的「刘海悬停用量」。
//  仅当本机有物理刘海时挂载:一个透明、鼠标穿透的顶部面板 + 全局鼠标监听。
//  鼠标划到刘海上 → 刘海下方展开一张用量卡(5h / 7d),移开收起。数据同菜单栏(ClaudeUsageLoader)。

import AppKit
import SwiftUI
import Combine

@MainActor
final class BannerNotchUsageStore: ObservableObject {
    @Published var snapshot: ClaudeUsageSnapshot?
    private var timer: Timer?
    private var lastFetch: Date = .distantPast
    private var fetching = false

    func start() {
        reload()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func stop() { timer?.invalidate(); timer = nil }

    /// 定时器每 2s 触发。订阅模式 load() 只读本地文件(毫秒级),保持每 2s 刷,划上刘海即新鲜。
    /// API 模式 load() 含同步网络请求(8s),既不能每 2s 打网关也不能占主线程:
    /// 节流成 ≥180s 查一次 + 丢后台线程,查完回主线程回填。
    private func reload() {
        if ClaudeUsageLoader.isApiKeyMode() {
            guard !fetching, Date().timeIntervalSince(lastFetch) >= 180 else { return }
            fetching = true
            lastFetch = Date()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let fresh = try? ClaudeUsageLoader.load()
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let fresh { self.snapshot = fresh }
                    self.fetching = false
                }
            }
        } else {
            snapshot = (try? ClaudeUsageLoader.load()) ?? snapshot
        }
    }
}

@MainActor
final class BannerNotchUsagePresentation: ObservableObject {
    @Published var expanded = false
    let notchSize: CGSize
    init(notchSize: CGSize) { self.notchSize = notchSize }
}

@MainActor
final class BannerNotchUsageController {
    private var panel: NSPanel?
    private let store = BannerNotchUsageStore()
    private var presentation: BannerNotchUsagePresentation?
    private var monitors: [Any] = []

    private var notchHitRect: CGRect = .zero
    private var expandedHitRect: CGRect = .zero

    private let panelHeight: CGFloat = 210
    private let expandedWidth: CGFloat = 288
    private let expandedHeight: CGFloat = 150

    /// 仅在有物理刘海时挂载
    func mount() {
        guard panel == nil, let screen = NSScreen.builtin ?? NSScreen.main else { return }
        let metrics = ScreenNotchMetrics.detect(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width
        )
        guard metrics.hasPhysicalNotch else { return }

        let presentation = BannerNotchUsagePresentation(notchSize: metrics.size)
        self.presentation = presentation
        store.start()

        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - panelHeight,
            width: screen.frame.width,
            height: panelHeight
        )
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true   // 穿透,纯展示;hover 用全局监听判断
        panel.contentView = NSHostingView(
            rootView: BannerNotchUsageView(store: store, presentation: presentation)
        )
        panel.orderFrontRegardless()
        self.panel = panel

        // 命中矩形(屏幕全局坐标,原点左下)
        notchHitRect = CGRect(
            x: screen.frame.midX - metrics.size.width / 2,
            y: screen.frame.maxY - metrics.size.height,
            width: metrics.size.width,
            height: metrics.size.height
        )
        expandedHitRect = CGRect(
            x: screen.frame.midX - expandedWidth / 2,
            y: screen.frame.maxY - expandedHeight,
            width: expandedWidth,
            height: expandedHeight
        )

        installMouseMonitors()
    }

    func unmount() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        store.stop()
        panel?.orderOut(nil)
        panel = nil
        presentation = nil
    }

    private func installMouseMonitors() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.updateHover() }
            return event
        }
        if let global { monitors.append(global) }
        if let local { monitors.append(local) }
        updateHover()
    }

    private func updateHover() {
        guard let presentation else { return }
        let mouse = NSEvent.mouseLocation
        if presentation.expanded {
            if !expandedHitRect.contains(mouse) { setExpanded(false) }
        } else {
            if notchHitRect.insetBy(dx: -8, dy: -4).contains(mouse) { setExpanded(true) }
        }
    }

    private func setExpanded(_ value: Bool) {
        guard let presentation, presentation.expanded != value else { return }
        let anim: Animation = value
            ? .spring(response: 0.40, dampingFraction: 0.82, blendDuration: 0)
            : .spring(response: 0.42, dampingFraction: 1.0, blendDuration: 0)
        withAnimation(anim) { presentation.expanded = value }
    }

    deinit {
        for m in monitors { NSEvent.removeMonitor(m) }
    }
}

// MARK: - SwiftUI

private struct BannerNotchUsageView: View {
    @ObservedObject var store: BannerNotchUsageStore
    @ObservedObject var presentation: BannerNotchUsagePresentation

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if presentation.expanded {
                card.transition(.asymmetric(
                    insertion: .scale(scale: 0.85, anchor: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer().frame(height: presentation.notchSize.height)   // 让位给刘海本体
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.42, green: 0.86, blue: 0.62))
                Text("Claude Code 用量")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                // 数据陈旧时给个角标提示,避免把旧快照误当实时用量
                if let note = staleNote {
                    Text(note)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            if store.snapshot?.isApiBalance == true {
                // API Key 模式:网关额度只有一个维度,显示单行「已用」(进度条=已用占比,与 5h/7d 一致)
                row("已用额度", store.snapshot?.fiveHour, stale: staleNote != nil)
            } else {
                row("5 小时", store.snapshot?.fiveHour, stale: staleNote != nil)
                row("7 天", store.snapshot?.sevenDay, stale: staleNote != nil)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .frame(width: 268, alignment: .leading)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    /// 陈旧提示文案:snapshot 超过阈值未更新时返回"Nm 前",否则 nil。
    private var staleNote: String? {
        guard let snapshot = store.snapshot, snapshot.isStale(), let age = snapshot.age() else { return nil }
        let m = Int(age / 60)
        return m > 0 ? "\(m)m 前" : "陈旧"
    }

    private func row(_ label: String, _ w: ClaudeUsageWindow?, stale: Bool = false) -> some View {
        // 陈旧时数字与进度条降为灰色,与菜单栏一致地示意"非实时"
        let staleGray = Color.white.opacity(0.4)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
                if let w {
                    Text("\(w.roundedUsedPercentage)%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(stale ? staleGray : color(w.usedPercentage))
                    if let reset = countdown(w.resetsAt) {
                        Text(reset)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                } else {
                    Text("无数据").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    if let w {
                        let frac = min(1, max(0, w.usedPercentage / 100))
                        Capsule().fill(stale ? staleGray : color(w.usedPercentage))
                            .frame(width: max(3, geo.size.width * frac))
                    }
                }
            }
            .frame(height: 5)
        }
    }

    private func color(_ used: Double) -> Color {
        switch used {
        case ..<70: return Color(red: 0.42, green: 0.86, blue: 0.62)
        case ..<90: return Color(red: 0.98, green: 0.82, blue: 0.32)
        default:    return Color(red: 0.98, green: 0.44, blue: 0.38)
        }
    }

    private func countdown(_ date: Date?) -> String? {
        guard let date else { return nil }
        let r = date.timeIntervalSinceNow
        if r <= 0 { return "已重置" }
        if r < 60 { return "<1m" }
        let m = Int(r / 60), d = m / 1440, h = (m % 1440) / 60, mm = m % 60
        return d > 0 ? "\(d)d \(h)h" : "\(h)h \(mm)m"
    }
}
