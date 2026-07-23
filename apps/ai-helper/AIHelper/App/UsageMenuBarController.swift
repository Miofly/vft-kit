//
//  UsageMenuBarController.swift
//  ai-helper(fork 自 ai-helper 后新增)
//
//  在菜单栏显示 Claude 与 Codex 用量,点开菜单看剩余% + 重置倒计时。
//  数据分别来自 ClaudeUsageLoader 的缓存/API 和 CodexUsageLoader 的本地 rollout 快照。
//  渲染方式抄自 cc-helper:文字画成图片交给状态栏,保证彩色 + 垂直居中。
//

import AppKit

enum UsageMenuBarCodexPresenter {
    nonisolated static func headlineWindow(in snapshot: CodexUsageSnapshot?) -> CodexUsageWindow? {
        guard let snapshot, !snapshot.isEmpty else { return nil }
        return snapshot.windows.first {
            UsageSummaryPresenter.isSevenDayWindowLabel($0.label)
        } ?? detailWindows(in: snapshot).last
    }

    nonisolated static func detailWindows(in snapshot: CodexUsageSnapshot?) -> [CodexUsageWindow] {
        guard let snapshot else { return [] }
        return snapshot.windows.sorted { lhs, rhs in
            if lhs.windowMinutes == rhs.windowMinutes {
                return lhs.key < rhs.key
            }
            return lhs.windowMinutes < rhs.windowMinutes
        }
    }

    nonisolated static func compactTokenCount(_ count: Int) -> String {
        let value = max(0, count)
        if value >= 1_000_000 {
            return compactNumber(Double(value) / 1_000_000) + "M"
        }
        if value >= 1_000 {
            return compactNumber(Double(value) / 1_000) + "K"
        }
        return String(value)
    }

    private nonisolated static func compactNumber(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded.rounded() == rounded
            ? String(Int(rounded))
            : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }
}

private final class UsageInfoMenuItemView: NSView {
    private static let rowHeight: CGFloat = 24
    private static let titleLeading: CGFloat = 36
    private static let trailing: CGFloat = 16
    private static let segmentGap: CGFloat = 3

    private let labelField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: Self.rowHeight))
        setupField(labelField)
        setupField(valueField)
        addSubview(labelField)
        addSubview(valueField)

        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.titleLeading),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueField.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: Self.segmentGap),
            valueField.firstBaselineAnchor.constraint(equalTo: labelField.firstBaselineAnchor),
            valueField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.trailing)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(label: String, value: String, valueColor: NSColor) {
        configure(label: label, valueSegments: [(value, valueColor)])
    }

    func configure(label: String, valueSegments: [(String, NSColor)]) {
        let font = Self.menuInfoFont()
        labelField.stringValue = label
        labelField.font = font
        labelField.textColor = .labelColor
        valueField.font = font

        let valueText = NSMutableAttributedString()
        for (text, color) in valueSegments {
            valueText.append(NSAttributedString(
                string: text,
                attributes: [.font: font, .foregroundColor: color]
            ))
        }
        valueField.attributedStringValue = valueText

        let width = ceil(labelField.intrinsicContentSize.width
            + valueField.intrinsicContentSize.width
            + Self.titleLeading
            + Self.segmentGap
            + Self.trailing)
        setFrameSize(NSSize(width: max(260, width), height: Self.rowHeight))
    }

    private func setupField(_ field: NSTextField) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.allowsDefaultTighteningForTruncation = true
    }

    private static func menuInfoFont() -> NSFont {
        let base = NSFont.menuFont(ofSize: 0)
        let desc = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
            ]]
        ])
        return NSFont(descriptor: desc, size: base.pointSize) ?? base
    }
}

@MainActor
final class UsageMenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var infoItem5h: NSMenuItem?
    private var infoItem7d: NSMenuItem?
    private var infoItemCodexPrimary: NSMenuItem?
    private var infoItemCodexSecondary: NSMenuItem?
    private var infoView5h: UsageInfoMenuItemView?
    private var infoView7d: UsageInfoMenuItemView?
    private var infoViewCodexPrimary: UsageInfoMenuItemView?
    private var infoViewCodexSecondary: UsageInfoMenuItemView?
    private var lastSignature: String?
    private var snapshot: ClaudeUsageSnapshot?
    private var codexSnapshot: CodexUsageSnapshot?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let info5h = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let info7d = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let infoCodexPrimary = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let infoCodexSecondary = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let infoView5h = UsageInfoMenuItemView()
        let infoView7d = UsageInfoMenuItemView()
        let infoViewCodexPrimary = UsageInfoMenuItemView()
        let infoViewCodexSecondary = UsageInfoMenuItemView()
        info5h.view = infoView5h
        info7d.view = infoView7d
        infoCodexPrimary.view = infoViewCodexPrimary
        infoCodexSecondary.view = infoViewCodexSecondary
        info5h.isEnabled = true
        info7d.isEnabled = true
        infoCodexPrimary.isEnabled = true
        infoCodexSecondary.isEnabled = true
        menu.addItem(info5h)
        menu.addItem(info7d)
        menu.addItem(infoCodexPrimary)
        menu.addItem(infoCodexSecondary)
        infoItem5h = info5h
        infoItem7d = info7d
        infoItemCodexPrimary = infoCodexPrimary
        infoItemCodexSecondary = infoCodexSecondary
        self.infoView5h = infoView5h
        self.infoView7d = infoView7d
        self.infoViewCodexPrimary = infoViewCodexPrimary
        self.infoViewCodexSecondary = infoViewCodexSecondary
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "退出 ai-helper", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item

        reload()
        // 状态项刚放进菜单栏时 appearance 还没落定(深色壁纸→DarkAqua),labelColor 会先解析成暗色。
        // 分多次延迟强制重绘(绕过签名去重),直到取到菜单栏真正的 appearance,标签才是白色。
        for delay in [0.05, 0.2, 0.5, 1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.forceRefresh() }
        }
        // 每 3 分钟轮询用量文件(值变了才重绘,开销很小)
        let t = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSettings() {
        SettingsWindowController.shared.present()
    }

    private func reload() {
        // API 模式下 load() 含同步网络请求(8s 超时),必须丢到后台线程,
        // 否则点开菜单/轮询会冻结主线程卡死菜单栏。查完回主线程刷新。
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fresh = try? ClaudeUsageLoader.load()
            let codexFresh = try? CodexUsageLoader.load()
            DispatchQueue.main.async {
                guard let self else { return }
                if let fresh { self.snapshot = fresh }
                if let codexFresh { self.codexSnapshot = codexFresh }
                self.refresh()
                self.updateInfoItems()
            }
        }
    }

    /// 强制重绘(绕过签名去重):用于启动时 appearance 落定后刷新标签颜色
    private func forceRefresh() {
        lastSignature = nil
        refresh()
    }

    // MARK: 菜单栏文字(Claude + Codex 已用%,画成图片)

    private func refresh() {
        guard let button = statusItem?.button else { return }
        let sig = signature()
        guard sig != lastSignature else { return }
        lastSignature = sig

        // 画一张「恰好贴合文字」的图,交给 NSStatusItem 自动垂直居中(原始 5h/7d 就是这么对齐的)。
        // 关键:画布高度 = 文字自然高度,不要自定固定高度、不要手算 y 偏移 —— 那才是之前错位的根源。
        let text = usageAttributedString()
        let size = text.size()
        let pad: CGFloat = 2
        let image = NSImage(size: NSSize(width: ceil(size.width) + pad * 2, height: ceil(size.height)))
        image.lockFocus()
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            text.draw(at: NSPoint(x: pad, y: 0))
        }
        image.unlockFocus()
        image.isTemplate = false
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
    }

    private func signature() -> String {
        // 把菜单栏 appearance 纳入签名:深/浅色切换或壁纸变化时强制重绘,标签色随之翻转
        let appr = statusItem?.button?.effectiveAppearance.name.rawValue ?? ""
        func part(_ w: ClaudeUsageWindow?) -> String { w.map { "\($0.roundedUsedPercentage)" } ?? "--" }
        let codexPart = codexSnapshot?.windows
            .map { "\($0.key):\($0.roundedUsedPercentage)" }
            .joined(separator: ",") ?? "--"
        let codexTokens = codexSnapshot?.tokenUsage?.totalTokens ?? 0
        // 陈旧状态纳入签名:数据从新鲜变陈旧(或反之)时强制重绘,数字随之变灰/复原
        let stale = snapshot?.isStale() == true ? "1" : "0"
        return "\(appr)|\(part(snapshot?.fiveHour))|\(part(snapshot?.sevenDay))|\(codexPart)|\(codexTokens)|\(stale)"
    }

    private func usageAttributedString() -> NSAttributedString {
        // 关键:中文「已用」不在等宽数字字体里,会回退到 PingFang,baseline 与 SF 等宽体不一致 → 同行错位。
        // 解决:从普通 system font 派生一个「带等宽数字特性」的字体,中英文共用同一字型家族,baseline 一致。
        let base = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let desc = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
            ]]
        ])
        let font = NSFont(descriptor: desc, size: 13) ?? base
        let labelCol = NSColor.labelColor          // 5h/7d 标签用主文字色,菜单栏上清晰可读
        let dim = NSColor.secondaryLabelColor

        let result = NSMutableAttributedString()
        func add(_ s: String, _ c: NSColor) {
            result.append(NSAttributedString(string: s, attributes: [.foregroundColor: c, .font: font]))
        }
        // 数据陈旧时数字统一用灰色,示意"这不是实时值",避免把旧快照误当当前用量
        let stale = snapshot?.isStale() == true
        func chunk(_ label: String, _ w: ClaudeUsageWindow?, gap: Bool) {
            add(label + " ", labelCol)
            if let w { add("\(w.roundedUsedPercentage)%", stale ? dim : barColor(w.usedPercentage)) }
            else { add("--", labelCol) }
            if gap { add("  ", dim) }
        }
        if let snapshot, snapshot.isApiBalance, let w = snapshot.fiveHour {
            // API Key 模式:网关已用额度%,颜色按用量判红黄绿(与 5h/7d 一致)
            add("已用 ", labelCol)
            add("\(w.roundedUsedPercentage)%", stale ? dim : barColor(w.usedPercentage))
        } else if let snapshot, !snapshot.isEmpty {
            chunk("5h", snapshot.fiveHour, gap: true)
            chunk("7d", snapshot.sevenDay, gap: false)
        }

        if let codexWindow = UsageMenuBarCodexPresenter.headlineWindow(in: codexSnapshot) {
            if result.length > 0 { add("  ·  ", dim) }
            add("CX \(codexWindow.label) ", labelCol)
            add("\(codexWindow.roundedUsedPercentage)%", barColor(codexWindow.usedPercentage))
        } else if let tokenUsage = codexSnapshot?.tokenUsage {
            if result.length > 0 { add("  ·  ", dim) }
            add("CX ", labelCol)
            add(UsageMenuBarCodexPresenter.compactTokenCount(tokenUsage.totalTokens), labelCol)
        }

        if result.length == 0 {
            // 两个来源都无数据时显示产品名,避免空白状态项。
            add("ai-helper", labelCol)
        }
        return result
    }

    // MARK: 菜单顶部:点开看剩余% + 重置倒计时

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateInfoItems()   // 先用现有数据立即渲染,避免点开菜单空白
        reload()            // 后台异步拉最新数据(不等 3 分钟轮询),查完回主线程再刷一次
    }

    private func updateInfoItems() {
        // Claude 与 Codex 分开决定显隐,避免某一侧无数据时误伤另一侧。
        if let snapshot, snapshot.isApiBalance, let w = snapshot.fiveHour {
            infoItem5h?.isHidden = false
            infoItem7d?.isHidden = true
            let remaining = max(0, 100 - Int(w.usedPercentage.rounded()))
            infoView5h?.configure(
                label: "CC 已用额度:",
                value: "\(w.roundedUsedPercentage)% · 剩余 \(remaining)%",
                valueColor: menuColor(w.usedPercentage)
            )
        } else if (snapshot == nil || snapshot?.isEmpty == true), ClaudeUsageLoader.isApiKeyMode() {
            // API Key 模式但查不到余额（非 one-api 网关等）：只隐藏 Claude 菜单项。
            infoItem5h?.isHidden = true
            infoItem7d?.isHidden = true
        } else {
            infoItem5h?.isHidden = false
            infoItem7d?.isHidden = false
            // 陈旧时在两行末尾追加"· 已陈旧 Nm 前",告诉用户数据多久没更新了。
            let staleNote: String? = {
                guard let snapshot, snapshot.isStale(), let age = snapshot.age() else { return nil }
                let m = Int(age / 60)
                return m > 0 ? "已陈旧 · \(m)m 前更新" : "已陈旧"
            }()
            configureInfoView(infoView5h, label: "CC 5h", snapshot?.fiveHour, staleNote: staleNote)
            configureInfoView(infoView7d, label: "CC 7d", snapshot?.sevenDay, staleNote: staleNote)
        }

        updateCodexInfoItems()
    }

    private func updateCodexInfoItems() {
        let windows = UsageMenuBarCodexPresenter.detailWindows(in: codexSnapshot)
        let rows = [
            (infoItemCodexPrimary, infoViewCodexPrimary),
            (infoItemCodexSecondary, infoViewCodexSecondary)
        ]

        if windows.isEmpty, let tokenUsage = codexSnapshot?.tokenUsage {
            rows[0].0?.isHidden = false
            rows[1].0?.isHidden = true
            rows[0].1?.configure(
                label: "Codex 最近会话:",
                value: "\(UsageMenuBarCodexPresenter.compactTokenCount(tokenUsage.totalTokens)) Tokens",
                valueColor: .labelColor
            )
            return
        }

        for (index, row) in rows.enumerated() {
            guard windows.indices.contains(index) else {
                row.0?.isHidden = true
                continue
            }
            row.0?.isHidden = false
            configureCodexInfoView(row.1, windows[index])
        }
    }

    private func configureCodexInfoView(_ view: UsageInfoMenuItemView?, _ window: CodexUsageWindow) {
        let remaining = max(0, Int(window.leftPercentage.rounded()))
        var segments: [(String, NSColor)] = [
            ("已用 \(window.roundedUsedPercentage)% · 剩余 \(remaining)%", menuColor(window.usedPercentage))
        ]
        if let reset = countdown(window.resetsAt) {
            segments.append((" · \(reset)", .secondaryLabelColor))
        }
        view?.configure(label: "Codex \(window.label):", valueSegments: segments)
    }

    private func configureInfoView(
        _ view: UsageInfoMenuItemView?,
        label: String,
        _ w: ClaudeUsageWindow?,
        staleNote: String? = nil
    ) {
        guard let w else {
            view?.configure(label: "\(label):", value: "无数据", valueColor: .secondaryLabelColor)
            return
        }
        let stale = staleNote != nil
        let remaining = max(0, 100 - Int(w.usedPercentage.rounded()))
        var segments: [(String, NSColor)] = [
            ("剩余 \(remaining)%", stale ? .secondaryLabelColor : menuColor(w.usedPercentage))
        ]
        if let reset = countdown(w.resetsAt) {
            segments.append((" · \(reset)", .secondaryLabelColor))
        }
        if let staleNote {
            segments.append((" · \(staleNote)", .tertiaryLabelColor))
        }
        view?.configure(label: "\(label):", valueSegments: segments)
    }

    // MARK: 颜色 / 倒计时

    private func barColor(_ used: Double) -> NSColor {
        switch used {
        case ..<70: return NSColor(srgbRed: 0.20, green: 0.98, blue: 0.55, alpha: 1)
        case ..<90: return NSColor(srgbRed: 1.00, green: 0.82, blue: 0.20, alpha: 1)
        default:    return NSColor(srgbRed: 1.00, green: 0.40, blue: 0.38, alpha: 1)
        }
    }
    private func menuColor(_ used: Double) -> NSColor {
        switch used {
        case ..<70: return .systemGreen
        case ..<90: return .systemOrange
        default:    return .systemRed
        }
    }
    private func countdown(_ date: Date?) -> String? {
        guard let date else { return nil }
        let r = date.timeIntervalSinceNow
        if r <= 0 { return "已重置" }
        let dur: String
        if r < 60 { dur = "<1m" }
        else {
            let m = Int(r / 60), d = m / (60 * 24), h = (m % (60 * 24)) / 60, mm = m % 60
            dur = d > 0 ? "\(d)d \(h)h" : "\(h)h \(mm)m"
        }
        return "\(dur) 后重置"
    }
}
