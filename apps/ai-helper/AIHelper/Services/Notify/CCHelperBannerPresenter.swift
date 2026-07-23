//  自绘毛玻璃横幅(用于「自绘横幅」展示模式 IslandSurfaceMode.banner)。
//  由 BannerCompletionObserver 驱动。
//
//  交互主路径走「全局 + 本地鼠标监听 + 命中面板矩形」(与刘海悬停同一套可靠机制),
//  面板 sendEvent 只做兜底,覆盖 accessory app + 非激活面板偶发漏掉 mouseUp 的情况:
//   · 划到横幅上 → 暂停自动关闭;移开 1.5s 后关
//   · 点 × → 关整组(所有屏);点正文 → 跳转终端 + 关整组;拖动 → 移动并记住位置
//  自动关闭用 DispatchWorkItem。sound 为空则不播放(交给阶段音效)。

import AppKit

private final class BannerPanel: NSPanel {
    var mouseEventHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { false }   // 不抢焦点;交互走全局监听

    override func sendEvent(_ event: NSEvent) {
        let handled: Bool = switch event.type {
        case .mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            mouseEventHandler?(event) ?? false
        default:
            false
        }

        guard !handled else { return }
        super.sendEvent(event)
    }
}

private final class BannerVisualEffectView: NSVisualEffectView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class CCHelperBannerPresenter {
    struct Content {
        var title: String
        var subtitle: String
        var message: String
        var sound: String
        var allScreens: Bool
        var duration: Double
        var accent: NSColor = .secondaryLabelColor
        var symbolName: String = "sparkles"
        var onActivate: (() async -> Void)? = nil
    }

    /// 单个屏幕上的一张横幅
    private final class Binding {
        let panel: NSPanel
        let closeRectInView: CGRect          // × 命中区(面板内坐标,左下原点)
        let cardW: CGFloat
        let cardH: CGFloat
        let defaultTopRightX: CGFloat         // 该屏默认卡片右上角 X
        let defaultTopRightY: CGFloat
        init(panel: NSPanel, closeRectInView: CGRect, cardW: CGFloat, cardH: CGFloat, dtrX: CGFloat, dtrY: CGFloat) {
            self.panel = panel; self.closeRectInView = closeRectInView
            self.cardW = cardW; self.cardH = cardH
            self.defaultTopRightX = dtrX; self.defaultTopRightY = dtrY
        }
        func containsMouse(_ p: NSPoint) -> Bool { panel.frame.contains(p) }
        func closeRectScreen() -> CGRect {
            CGRect(x: panel.frame.minX + closeRectInView.minX,
                   y: panel.frame.minY + closeRectInView.minY,
                   width: closeRectInView.width, height: closeRectInView.height)
        }
    }

    /// 一次 show 的一组横幅(多屏),关/悬停/自动关作用于整组
    private final class BannerGroup {
        var bindings: [Binding] = []
        var onActivate: (() async -> Void)?
        var dismissWork: DispatchWorkItem?     // 软定时:hover 可暂停
        var hardWork: DispatchWorkItem?        // 硬兜底:永不取消,到点必关(防卡死)
        var dismissed = false
    }

    private var groups: [BannerGroup] = []

    // 交互状态
    private struct Interaction {
        let group: BannerGroup
        let binding: Binding
        let startMouse: NSPoint
        let startOrigin: NSPoint
        let inClose: Bool
        var didDrag: Bool
    }
    private var interaction: Interaction?

    // 鼠标监听
    private var monitors: [Any] = []

    // 记住的位置(卡片右上角相对屏幕右上角的偏移)
    private static let offsetXKey = "aiHelperBannerOffsetX"
    private static let offsetYKey = "aiHelperBannerOffsetY"
    static var savedOffset: CGPoint {
        get {
            let d = UserDefaults.standard
            return CGPoint(x: d.double(forKey: offsetXKey), y: d.double(forKey: offsetYKey))
        }
        set {
            let d = UserDefaults.standard
            d.set(newValue.x, forKey: offsetXKey)
            d.set(newValue.y, forKey: offsetYKey)
        }
    }

    // MARK: 展示

    func show(_ c: Content) {
        let screens = c.allScreens
            ? NSScreen.screens
            : NSScreen.screens.filter { $0.frame.origin != .zero }
        let targetScreens = screens.isEmpty ? NSScreen.screens : screens
        guard !targetScreens.isEmpty else { return }

        installMonitorsIfNeeded()
        playSound(c.sound)

        let group = BannerGroup()
        group.onActivate = c.onActivate
        let maxLife = max(c.duration, 5) + 12
        for screen in targetScreens {
            let built = makePanel(on: screen, content: c)
            group.bindings.append(built)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.42
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                built.panel.animator().alphaValue = 1
            }
            // 终极兜底:强引用该 panel,到点直接 orderOut,不依赖 presenter/group/监听/动画。
            // 即使上面所有逻辑都出岔子,横幅也一定会在 maxLife 秒后消失,绝不卡死。
            let panel = built.panel
            DispatchQueue.main.asyncAfter(deadline: .now() + maxLife) { panel.orderOut(nil) }
        }
        groups.append(group)
        scheduleDismiss(group, after: c.duration)
        // 硬兜底:无论 hover / 交互 / 漏掉的 mouseUp,最迟这么久必关,防止卡死
        let hard = DispatchWorkItem { [weak self, weak group] in
            guard let group else { return }
            self?.dismiss(group)
        }
        group.hardWork = hard
        DispatchQueue.main.asyncAfter(deadline: .now() + max(c.duration, 5) + 12, execute: hard)
    }

    // MARK: 自动关闭(DispatchWorkItem)

    private func scheduleDismiss(_ group: BannerGroup, after seconds: TimeInterval) {
        group.dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak group] in
            guard let group else { return }
            self?.dismiss(group)
        }
        group.dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelDismiss(_ group: BannerGroup) {
        group.dismissWork?.cancel()
        group.dismissWork = nil
    }

    private func dismiss(_ group: BannerGroup) {
        guard !group.dismissed else { return }
        group.dismissed = true
        cancelDismiss(group)
        group.hardWork?.cancel(); group.hardWork = nil
        groups.removeAll { $0 === group }
        for b in group.bindings {
            let panel = b.panel
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                panel.animator().alphaValue = 0
            }
            // 不依赖动画 completionHandler(实测有时不触发):直接定时 orderOut
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { panel.orderOut(nil) }
        }
        if groups.isEmpty { removeMonitors() }
    }

    // MARK: 鼠标监听(全局 + 本地)

    private func installMonitorsIfNeeded() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e) }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e) }
            return e
        }) { monitors.append(l) }
    }

    private func removeMonitors() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        interaction = nil
    }

    private func handle(_ e: NSEvent) {
        switch e.type {
        case .mouseMoved:       updateHover()
        case .leftMouseDown:    beginInteraction()
        case .leftMouseDragged: updateDrag()
        case .leftMouseUp:      endInteraction()
        default: break
        }
    }

    private func updateHover() {
        guard interaction?.didDrag != true else { return }   // 仅正在拖动时不处理 hover
        let mouse = NSEvent.mouseLocation
        for group in groups where !group.dismissed {
            let hovering = group.bindings.contains { $0.containsMouse(mouse) }
            if hovering {
                cancelDismiss(group)                          // 在上面 → 不关
            } else if group.dismissWork == nil {
                scheduleDismiss(group, after: 1.5)            // 移开 → 1.5s 后关
            }
        }
    }

    private func beginInteraction() {
        let mouse = NSEvent.mouseLocation
        for group in groups where !group.dismissed {
            if let b = group.bindings.first(where: { $0.containsMouse(mouse) }) {
                interaction = Interaction(
                    group: group, binding: b,
                    startMouse: mouse, startOrigin: b.panel.frame.origin,
                    inClose: b.closeRectScreen().contains(mouse), didDrag: false
                )
                cancelDismiss(group)
                return
            }
        }
    }

    private func updateDrag() {
        guard var it = interaction else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - it.startMouse.x
        let dy = mouse.y - it.startMouse.y
        if abs(dx) > 4 || abs(dy) > 4 { it.didDrag = true; interaction = it }
        if it.didDrag {
            it.binding.panel.setFrameOrigin(NSPoint(x: it.startOrigin.x + dx, y: it.startOrigin.y + dy))
        }
    }

    private func endInteraction() {
        guard let it = interaction else { return }
        interaction = nil

        if it.didDrag {
            let o = it.binding.panel.frame.origin
            Self.savedOffset = CGPoint(
                x: o.x + it.binding.cardW - it.binding.defaultTopRightX,
                y: o.y + it.binding.cardH - it.binding.defaultTopRightY
            )
            scheduleDismiss(it.group, after: 1.5)
        } else if it.inClose {
            dismiss(it.group)                 // 点 × → 关整组
        } else {
            // 点正文 → 立即关闭 + 后台执行跳转（不等待完成，避免卡住横幅）
            dismiss(it.group)
            if let onActivate = it.group.onActivate {
                Task { await onActivate() }
            }
        }
    }

    // MARK: 组装单张横幅

    private func makePanel(on screen: NSScreen, content c: Content) -> Binding {
        let cardW: CGFloat = 330, padH: CGFloat = 16, padV: CGFloat = 9
        let iconSize: CGFloat = 38, gap: CGFloat = 12, margin: CGFloat = 18
        let textLeft = padH + iconSize + gap
        let textW = cardW - textLeft - padH

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = true
        if let l = makeLabel(c.title, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor, maxLines: 1) {
            stack.addArrangedSubview(l)
        }
        if let l = makeLabel(c.subtitle, font: .systemFont(ofSize: 12, weight: .semibold), color: c.accent, maxLines: 1) {
            stack.addArrangedSubview(l)
        }
        if let l = makeLabel(c.message, font: .systemFont(ofSize: 12), color: .labelColor, maxLines: 2) {
            l.preferredMaxLayoutWidth = textW
            stack.addArrangedSubview(l)
        }
        stack.frame = NSRect(x: 0, y: 0, width: textW, height: 400)
        stack.layoutSubtreeIfNeeded()
        let textH = min(stack.fittingSize.height, 400)
        let cardH = max(iconSize, textH) + padV * 2

        let vf = screen.visibleFrame
        let offset = Self.savedOffset
        var originX = vf.maxX - margin - cardW + offset.x
        var originY = vf.maxY - margin - cardH + offset.y
        originX = min(max(originX, vf.minX + 8), vf.maxX - cardW - 8)
        originY = min(max(originY, vf.minY + 8), vf.maxY - cardH - 8)
        let rect = NSRect(x: originX, y: originY, width: cardW, height: cardH)

        let panel = BannerPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.mouseEventHandler = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return true
        }
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.alphaValue = 0

        let cardRect = NSRect(x: 0, y: 0, width: cardW, height: cardH)
        let blur = BannerVisualEffectView(frame: cardRect)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 21
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 0.5
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        // behind-window 毛玻璃背景由 window server 渲染，不受 layer.cornerRadius/masksToBounds 裁剪，
        // 只有 maskImage 能把它裁成圆角。少了它，圆角外仍填满矩形毛玻璃且 hasShadow 会画出矩形阴影。
        blur.maskImage = Self.roundedMaskImage(cornerRadius: 21)

        let tint = NSView(frame: cardRect)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.20).cgColor
        blur.addSubview(tint)

        let iconView = NSImageView(frame: NSRect(x: padH, y: (cardH - iconSize) / 2, width: iconSize, height: iconSize))
        iconView.image = makeSymbolIcon(c.symbolName, accent: c.accent, size: iconSize)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        blur.addSubview(iconView)

        stack.frame = NSRect(x: textLeft, y: (cardH - textH) / 2, width: textW, height: textH)
        blur.addSubview(stack)

        let closeSize: CGFloat = 17
        let closeRect = NSRect(x: cardW - closeSize - 8, y: cardH - closeSize - 8, width: closeSize, height: closeSize)
        let closeIcon = NSImageView(frame: closeRect)
        let closeConf = NSImage.SymbolConfiguration(pointSize: closeSize, weight: .semibold)
        closeIcon.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭")?
            .withSymbolConfiguration(closeConf)
        closeIcon.contentTintColor = NSColor.white.withAlphaComponent(0.6)
        closeIcon.imageScaling = .scaleProportionallyUpOrDown
        blur.addSubview(closeIcon)

        panel.contentView = blur
        panel.orderFrontRegardless()

        return Binding(
            panel: panel,
            closeRectInView: closeRect.insetBy(dx: -7, dy: -7),   // × 命中区放大好点
            cardW: cardW, cardH: cardH,
            dtrX: vf.maxX - margin, dtrY: vf.maxY - margin
        )
    }

    // MARK: 工具

    private func makeLabel(_ text: String, font: NSFont, color: NSColor, maxLines: Int) -> NSTextField? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        let f = NSTextField(labelWithString: t)
        f.font = font
        f.textColor = color
        f.lineBreakMode = .byTruncatingTail
        f.maximumNumberOfLines = maxLines
        f.cell?.usesSingleLineMode = maxLines == 1
        return f
    }

    private func playSound(_ name: String) {
        guard !name.isEmpty else { return }
        let n = name == "default" ? "Ping" : name
        NSSound(named: NSSound.Name(n))?.play()
    }

    /// 可拉伸的圆角矩形蒙版，用于裁剪 NSVisualEffectView 的 behind-window 毛玻璃。
    /// capInsets 保证任意尺寸下四角圆度不变、直边不被拉伸。
    private static func roundedMaskImage(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        image.resizingMode = .stretch
        return image
    }

    private func makeSymbolIcon(_ name: String, accent: NSColor, size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        NSBezierPath(roundedRect: rect, xRadius: size * 0.26, yRadius: size * 0.26).addClip()
        accent.withAlphaComponent(0.22).setFill()
        rect.fill()
        if let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            let conf = NSImage.SymbolConfiguration(pointSize: size * 0.56, weight: .bold)
            if let glyph = sym.withSymbolConfiguration(conf) {
                let gs = glyph.size
                let gr = NSRect(x: (size - gs.width) / 2, y: (size - gs.height) / 2, width: gs.width, height: gs.height)
                glyph.draw(in: gr)
                accent.set()
                gr.fill(using: .sourceAtop)
            }
        }
        img.unlockFocus()
        return img
    }

    deinit {
        for m in monitors { NSEvent.removeMonitor(m) }
    }
}
