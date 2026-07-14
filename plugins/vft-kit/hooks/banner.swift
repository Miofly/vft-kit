// banner.swift —— Claude Code 通知的自绘横幅展示器（仿 macOS 原生通知）。
//
// 系统通知只在主屏(带菜单栏那块)弹，双屏时盯副屏就漏掉。本工具遍历屏幕，在每块屏的
// 右上角画一张仿原生风格的毛玻璃横幅：约 5 秒淡出自动关，鼠标点一下立即关。
// 纯展示器，不含业务逻辑——由 notify.mjs 传参调用。
//
// 用法: banner --title <s> [--subtitle <s>] [--message <s>] [--icon <path>]
//              [--duration <sec>] [--sound <name>] [--all-screens]
//   --all-screens : 画所有屏(两屏都弹，配合外部关掉原生通知)。默认只画副屏(补主屏原生的漏)。
//   --sound       : 关掉原生后由横幅补放系统提示音(NSSound 命名音: Hero/Glass/Basso/Ping...)。
// 没有可画的屏(单屏且非 --all-screens)时直接静默退出。
//
// 编译: swiftc -O banner.swift -o banner

import Cocoa

// MARK: - 参数解析

func parseArgs(_ argv: [String]) -> [String: String] {
    var out: [String: String] = [:]
    var i = 0
    while i < argv.count {
        let a = argv[i]
        if a.hasPrefix("--"), i + 1 < argv.count {
            out[String(a.dropFirst(2))] = argv[i + 1]
            i += 2
        } else {
            i += 1
        }
    }
    return out
}

let args = parseArgs(Array(CommandLine.arguments.dropFirst()))
let gTitle = args["title"] ?? "Claude Code"
let gSubtitle = args["subtitle"] ?? ""
let gMessage = args["message"] ?? ""
let gIconPath = args["icon"]
let gDuration = Double(args["duration"] ?? "5") ?? 5
let gSound = args["sound"] ?? ""
let gAllScreens = CommandLine.arguments.contains("--all-screens")

// MARK: - 目标屏幕
//
// 默认只画副屏(补主屏系统通知的漏)；--all-screens 时画所有屏(两屏都弹，且外部会关掉原生通知)。
// 主屏 = 带菜单栏那块，全局坐标原点为 (0,0)；NSScreen.main 是「当前聚焦」屏,不可靠,故按原点判断。

let allScreens = NSScreen.screens
let targetScreens = gAllScreens ? allScreens : allScreens.filter { $0.frame.origin != .zero }
if targetScreens.isEmpty { exit(0) }  // 没有可画的屏就静默跳过

// MARK: - 图标
//
// 优先用传入图标；否则复用 terminal-notifier 的同款 Terminal 图标(与主屏原生通知一模一样)，
// 跨 Homebrew 前缀(ARM /opt/homebrew、Intel /usr/local)探测；再退系统 Terminal.app；
// 最后画一个 Claude 橙色兜底图标。

func loadIcon(size: CGFloat) -> NSImage {
    // 1) 显式传入的图标优先
    if let p = gIconPath, let img = NSImage(contentsOfFile: p) { return img }
    // 2) 复用 terminal-notifier 的同款图标 → 与主屏原生通知一模一样(兼容 ARM / Intel 两种 brew 前缀)
    let brewPrefixes = ["/opt/homebrew", "/usr/local"]
    for prefix in brewPrefixes {
        let icns = "\(prefix)/opt/terminal-notifier/terminal-notifier.app/Contents/Resources/Terminal.icns"
        if let img = NSImage(contentsOfFile: icns) { return img }
    }
    // 3) 退到系统 Terminal.app 图标
    let termApp = "/System/Applications/Utilities/Terminal.app"
    if FileManager.default.fileExists(atPath: termApp) {
        return NSWorkspace.shared.icon(forFile: termApp)
    }
    // 4) 最后画一个 Claude 橙色兜底图标
    return makeFallbackIcon(size: size)
}

func makeFallbackIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let clip = NSBezierPath(roundedRect: rect, xRadius: size * 0.24, yRadius: size * 0.24)
    clip.addClip()
    // Claude 橙色渐变
    let grad = NSGradient(colors: [
        NSColor(srgbRed: 0.91, green: 0.49, blue: 0.30, alpha: 1),
        NSColor(srgbRed: 0.82, green: 0.34, blue: 0.22, alpha: 1),
    ])
    grad?.draw(in: rect, angle: -90)
    // 白色 sparkles 字形居中
    if let sym = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) {
        let conf = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .semibold)
        if let glyph = sym.withSymbolConfiguration(conf) {
            let gs = glyph.size
            let gr = NSRect(x: (size - gs.width) / 2, y: (size - gs.height) / 2, width: gs.width, height: gs.height)
            glyph.draw(in: gr)
            NSColor.white.set()
            gr.fill(using: .sourceAtop)  // 把字形染白
        }
    }
    img.unlockFocus()
    return img
}

// MARK: - 横幅面板

final class BannerController: NSObject, NSApplicationDelegate {
    let screens: [NSScreen]
    var panels: [NSPanel] = []
    let duration: Double

    init(screens: [NSScreen], duration: Double) {
        self.screens = screens
        self.duration = duration
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        playSound()
        for screen in screens { panels.append(makePanel(on: screen)) }
        // 原地淡入(不做位移动画，多屏下最稳，绝不错位)。加长时长 + 平滑缓出曲线(easeOutExpo 风)，更丝滑。
        for panel in panels {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.42
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                panel.animator().alphaValue = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.dismissAll()
        }
    }

    func makeLabel(_ text: String, font: NSFont, color: NSColor, maxLines: Int) -> NSTextField? {
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

    func makePanel(on screen: NSScreen) -> NSPanel {
        // 版式常量(对齐 macOS 原生通知的尺寸/圆角/紧凑度)
        let cardW: CGFloat = 330
        let padH: CGFloat = 16
        let padV: CGFloat = 9
        let iconSize: CGFloat = 38
        let gap: CGFloat = 12
        let marginX: CGFloat = 18    // 距屏幕右边缘
        let marginTop: CGFloat = 12  // 距菜单栏下方(配合 visibleFrame，比贴顶更靠下、更像原生)

        let textLeft = padH + iconSize + gap
        let textW = cardW - textLeft - padH

        // 文本竖排(标题/副标题/正文) → 先量高度,卡片按内容收紧
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = true
        if let l = makeLabel(gTitle, font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor, maxLines: 1) {
            stack.addArrangedSubview(l)
        }
        if let l = makeLabel(gSubtitle, font: .systemFont(ofSize: 12, weight: .regular), color: .secondaryLabelColor, maxLines: 1) {
            stack.addArrangedSubview(l)
        }
        if let l = makeLabel(gMessage, font: .systemFont(ofSize: 12, weight: .regular), color: .labelColor, maxLines: 2) {
            l.preferredMaxLayoutWidth = textW
            stack.addArrangedSubview(l)
        }
        stack.frame = NSRect(x: 0, y: 0, width: textW, height: 400)
        stack.layoutSubtreeIfNeeded()
        let textH = min(stack.fittingSize.height, 400)

        let cardH = max(iconSize, textH) + padV * 2

        // 右上角定位。用 visibleFrame(排除菜单栏/Dock)让横幅落在菜单栏下方，更像原生、也更靠下。
        let vf = screen.visibleFrame
        let rect = NSRect(x: vf.maxX - cardW - marginX, y: vf.maxY - cardH - marginTop, width: cardW, height: cardH)

        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.alphaValue = 0

        // 毛玻璃卡片(.hudWindow 深色材质 + 细描边)
        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: cardW, height: cardH))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 21
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 0.5
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor

        // 淡黑罩：压掉毛玻璃对背景色的穿透(否则顶边会吸上后面窗口的颜色)，统一成原生那种沉稳深灰
        let tint = NSView(frame: NSRect(x: 0, y: 0, width: cardW, height: cardH))
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.20).cgColor
        blur.addSubview(tint)

        // 图标(垂直居中；icns/兜底图标自带圆角形状，不再二次裁剪)
        let iconView = NSImageView(frame: NSRect(x: padH, y: (cardH - iconSize) / 2, width: iconSize, height: iconSize))
        iconView.image = loadIcon(size: iconSize)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        blur.addSubview(iconView)

        // 文本(垂直居中)
        stack.frame = NSRect(x: textLeft, y: (cardH - textH) / 2, width: textW, height: textH)
        blur.addSubview(stack)

        // 点一下立即关
        blur.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(onClick(_:))))

        panel.contentView = blur
        panel.orderFrontRegardless()  // 已在 rect(右上角)就位，alpha=0 等待淡入
        return panel
    }

    @objc func onClick(_ sender: NSClickGestureRecognizer) {
        if let view = sender.view, let panel = view.window as? NSPanel {
            fadeOut(panel) { [weak self] in
                self?.panels.removeAll { $0 == panel }
                if self?.panels.isEmpty == true { NSApp.terminate(nil) }
            }
        }
    }

    func dismissAll() {
        guard !panels.isEmpty else { NSApp.terminate(nil); return }
        let group = DispatchGroup()
        for panel in panels { group.enter(); fadeOut(panel) { group.leave() } }
        group.notify(queue: .main) { NSApp.terminate(nil) }
    }

    // 关掉原生通知后声音也没了，这里由横幅补放系统提示音。
    // NSSound 认命名系统音(Hero/Glass/Basso/Ping...)；'default'/空 退到 Ping。
    func playSound() {
        let name = gSound.isEmpty || gSound == "default" ? "Ping" : gSound
        NSSound(named: NSSound.Name(name))?.play()
    }

    // 原地淡出(平滑缓入缓出)
    func fadeOut(_ panel: NSPanel, done: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.38
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            done()
        })
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // 不进 Dock、不抢焦点
let controller = BannerController(screens: targetScreens, duration: gDuration)
app.delegate = controller

// 安全阀:无论如何 duration+2s 后强制退出,绝不残留进程
DispatchQueue.main.asyncAfter(deadline: .now() + gDuration + 2) { NSApp.terminate(nil) }

app.run()
