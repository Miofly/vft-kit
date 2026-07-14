//  仿 ping-island 的常驻刘海:透明 NotchPanel + 同宽 NotchShape 覆盖。
//  panel 全屏宽、盖菜单栏、鼠标穿透;hover 用全局鼠标监听判断,进刘海矩形→展开,离开展开矩形→收起。

import AppKit
import SwiftUI
import Combine
import CCHelperCore

@MainActor
final class NotchPresentation: ObservableObject {
    @Published var isExpanded = false
    @Published var showRemaining = false   // false=已用%,true=剩余%
    let notchSize: CGSize
    let hasPhysicalNotch: Bool

    init(notchSize: CGSize, hasPhysicalNotch: Bool) {
        self.notchSize = notchSize
        self.hasPhysicalNotch = hasPhysicalNotch
    }
}

@MainActor
final class NotchUsageController {
    private let store: RateLimitStore
    private var panel: NotchPanel?
    private var presentation: NotchPresentation?
    private var monitors: [Any] = []

    private var notchHitRect: CGRect = .zero
    private var expandedHitRect: CGRect = .zero

    private let panelHeight: CGFloat = 260
    private let expandedWidth: CGFloat = 260
    private let expandedHeight: CGFloat = 156

    private var showRemaining: Bool
    private var hoverExpand: Bool

    init(store: RateLimitStore, showRemaining: Bool = false, hoverExpand: Bool = true) {
        self.store = store
        self.showRemaining = showRemaining
        self.hoverExpand = hoverExpand
    }

    /// 配置变更时无需重挂,直接更新显隐标志
    func apply(showRemaining: Bool, hoverExpand: Bool) {
        self.showRemaining = showRemaining
        self.hoverExpand = hoverExpand
        presentation?.showRemaining = showRemaining
        if !hoverExpand { setExpanded(false) }
    }

    func mount() {
        guard let screen = NSScreen.builtin ?? NSScreen.main else { return }
        let metrics = screen.notchMetrics
        let presentation = NotchPresentation(
            notchSize: metrics.size,
            hasPhysicalNotch: metrics.hasPhysicalNotch
        )
        presentation.showRemaining = showRemaining
        self.presentation = presentation

        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - panelHeight,
            width: screen.frame.width,
            height: panelHeight
        )
        let panel = NotchPanel(contentRect: frame)
        panel.contentView = NSHostingView(
            rootView: NotchUsageView(store: store, presentation: presentation)
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        // hover 命中矩形(屏幕全局坐标,原点左下)
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

    /// 撤下刘海(配置里关闭刘海显示时调用)
    func unmount() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        panel?.orderOut(nil)
        panel = nil
        presentation = nil
    }

    private func installMouseMonitors() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updateHover()
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.updateHover()
            return event
        }
        if let global { monitors.append(global) }
        if let local { monitors.append(local) }
        updateHover()
    }

    private func updateHover() {
        guard let presentation else { return }
        let mouse = NSEvent.mouseLocation

        if presentation.isExpanded {
            if !expandedHitRect.contains(mouse) {
                setExpanded(false)
            }
        } else if hoverExpand {
            if notchHitRect.insetBy(dx: -12, dy: -6).contains(mouse) {
                setExpanded(true)
            }
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard let presentation, presentation.isExpanded != expanded else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            presentation.isExpanded = expanded
        }
    }

    deinit {
        for m in monitors { NSEvent.removeMonitor(m) }
    }
}
