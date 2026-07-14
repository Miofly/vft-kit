//  自绘毛玻璃横幅(仿 macOS 原生通知)。移植自 vft-kit 的 banner.swift,
//  但作为常驻 App 内的 presenter,不再每次起独立进程。

import AppKit

/// 可点击关闭的容器视图
private final class ClickableBannerView: NSVisualEffectView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}

@MainActor
final class BannerPresenter {
    struct Content {
        var title: String
        var subtitle: String
        var message: String
        var iconPath: String?
        var sound: String
        var allScreens: Bool
        var duration: Double
    }

    private var activePanels = Set<NSPanel>()

    func show(_ c: Content) {
        // allScreens=false 时只画副屏(补主屏原生的漏);主屏 = 全局原点 (0,0)
        let screens = c.allScreens
            ? NSScreen.screens
            : NSScreen.screens.filter { $0.frame.origin != .zero }
        guard !screens.isEmpty else { return }

        playSound(c.sound)

        var panels: [NSPanel] = []
        for screen in screens {
            let panel = makePanel(on: screen, content: c)
            panels.append(panel)
            activePanels.insert(panel)
        }
        for panel in panels {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.42
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                panel.animator().alphaValue = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + c.duration) { [weak self] in
            for panel in panels { self?.dismiss(panel) }
        }
    }

    private func dismiss(_ panel: NSPanel) {
        guard activePanels.contains(panel) else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.activePanels.remove(panel)
        })
    }

    private func makePanel(on screen: NSScreen, content c: Content) -> NSPanel {
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
        if let l = makeLabel(c.subtitle, font: .systemFont(ofSize: 12), color: .secondaryLabelColor, maxLines: 1) {
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

        let vf = screen.frame
        let rect = NSRect(x: vf.maxX - cardW - margin, y: vf.maxY - cardH - margin, width: cardW, height: cardH)

        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.alphaValue = 0

        let blur = ClickableBannerView(frame: NSRect(x: 0, y: 0, width: cardW, height: cardH))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 21
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 0.5
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        blur.onClick = { [weak self, weak panel] in
            guard let panel else { return }
            self?.dismiss(panel)
        }

        let tint = NSView(frame: NSRect(x: 0, y: 0, width: cardW, height: cardH))
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.20).cgColor
        blur.addSubview(tint)

        let iconView = NSImageView(frame: NSRect(x: padH, y: (cardH - iconSize) / 2, width: iconSize, height: iconSize))
        iconView.image = loadIcon(size: iconSize, iconPath: c.iconPath)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        blur.addSubview(iconView)

        stack.frame = NSRect(x: textLeft, y: (cardH - textH) / 2, width: textW, height: textH)
        blur.addSubview(stack)

        panel.contentView = blur
        panel.orderFrontRegardless()
        return panel
    }

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
        let n = name.isEmpty || name == "default" ? "Ping" : name
        NSSound(named: NSSound.Name(n))?.play()
    }

    private func loadIcon(size: CGFloat, iconPath: String?) -> NSImage {
        if let p = iconPath, !p.isEmpty {
            let expanded = (p as NSString).expandingTildeInPath
            if let img = NSImage(contentsOfFile: expanded) { return img }
        }
        for prefix in ["/opt/homebrew", "/usr/local"] {
            let icns = "\(prefix)/opt/terminal-notifier/terminal-notifier.app/Contents/Resources/Terminal.icns"
            if let img = NSImage(contentsOfFile: icns) { return img }
        }
        let termApp = "/System/Applications/Utilities/Terminal.app"
        if FileManager.default.fileExists(atPath: termApp) {
            return NSWorkspace.shared.icon(forFile: termApp)
        }
        return makeFallbackIcon(size: size)
    }

    private func makeFallbackIcon(size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        NSBezierPath(roundedRect: rect, xRadius: size * 0.24, yRadius: size * 0.24).addClip()
        NSGradient(colors: [
            NSColor(srgbRed: 0.91, green: 0.49, blue: 0.30, alpha: 1),
            NSColor(srgbRed: 0.82, green: 0.34, blue: 0.22, alpha: 1),
        ])?.draw(in: rect, angle: -90)
        if let sym = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) {
            let conf = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .semibold)
            if let glyph = sym.withSymbolConfiguration(conf) {
                let gs = glyph.size
                let gr = NSRect(x: (size - gs.width) / 2, y: (size - gs.height) / 2, width: gs.width, height: gs.height)
                glyph.draw(in: gr)
                NSColor.white.set()
                gr.fill(using: .sourceAtop)
            }
        }
        img.unlockFocus()
        return img
    }
}
