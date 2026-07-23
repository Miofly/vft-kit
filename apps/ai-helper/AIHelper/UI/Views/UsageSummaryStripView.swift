import AppKit
import SwiftUI

struct UsageSummaryStripView: View {
    enum DisplayStyle {
        case numeric
        case battery
        case preferredBattery
    }

    enum BatteryHoverDetailStyle {
        case allProviders
        case currentWindow
    }

    enum BatteryPopoverPlacement {
        case below
        case above
    }

    let providers: [UsageSummaryProvider]
    var inline = false
    var alignment: HorizontalAlignment = .leading
    var displayStyle: DisplayStyle = .numeric
    var batteryHoverDetailStyle: BatteryHoverDetailStyle = .allProviders
    var batteryPopoverPlacement: BatteryPopoverPlacement = .below
    var locale: Locale = .current
    @State private var hoveredBatteryProviderID: String?

    var body: some View {
        Group {
            if inline {
                HStack(spacing: 6) {
                    ForEach(providers) { provider in
                        providerSection(provider)
                    }
                }
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ForEach(providers) { provider in
                            providerSection(provider)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func providerSection(_ provider: UsageSummaryProvider) -> some View {
        if inline {
            HStack(alignment: .center, spacing: 6) {
                Text(provider.title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.62))

                switch displayStyle {
                case .preferredBattery:
                    if let window = UsageSummaryPresenter.preferredBatteryWindow(for: provider) {
                        batteryWindowSection(
                            provider: provider,
                            window,
                            detailWindows: provider.windows
                        )
                    }
                case .battery:
                    ForEach(provider.windows, id: \.id) { window in
                        batteryWindowSection(
                            provider: provider,
                            window,
                            detailWindows: [window]
                        )
                    }
                case .numeric:
                    ForEach(provider.windows, id: \.id) { window in
                        numericWindowSection(window)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .center, spacing: 10) {
                Text(provider.title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.72))

                ForEach(provider.windows, id: \.id) { window in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(window.label)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.52))

                            Text(window.valueText)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(emphasisColor(for: window.severity))
                                .lineLimit(1)
                        }

                        if let resetText = window.resetText {
                            Text(resetText)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(backgroundColor(for: window.severity))
                    )
                }
            }
        }
    }

    private func batteryWindowSection(
        provider: UsageSummaryProvider,
        _ window: UsageSummaryWindow,
        detailWindows: [UsageSummaryWindow]
    ) -> some View {
        let detailProvider = UsageSummaryProvider(
            id: provider.id,
            title: provider.title,
            windows: detailWindows
        )
        let helpText = UsageSummaryPresenter.remainingHelpText(for: detailProvider, locale: locale)

        return HStack(spacing: 4) {
            Text(window.label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            BatteryQuotaIndicator(
                severity: window.severity,
                remainingPercentage: window.remainingPercentage
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(alignment: batteryPopoverAlignment) {
            if hoveredBatteryProviderID == hoverID(provider: provider, window: window) {
                batteryPopover(provider: provider, window: window)
                    .offset(x: 0, y: batteryPopoverOffsetY)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: batteryPopoverScaleAnchor)))
                    .allowsHitTesting(false)
                    .zIndex(100)
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredBatteryProviderID = hovering ? hoverID(provider: provider, window: window) : nil
            }
        }
        .accessibilityLabel(Text(helpText.replacingOccurrences(of: "\n", with: ", ")))
        .zIndex(hoveredBatteryProviderID == hoverID(provider: provider, window: window) ? 100 : 0)
    }

    private func numericWindowSection(_ window: UsageSummaryWindow) -> some View {
        HStack(spacing: 3) {
            Text(window.label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            Text(window.valueText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(emphasisColor(for: window.severity))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(backgroundColor(for: window.severity))
        )
        .help(window.resetText ?? "")
    }

    private func emphasisColor(for severity: UsageSummarySeverity) -> Color {
        switch severity {
        case .healthy:
            return Color(red: 0.42, green: 0.92, blue: 0.60)
        case .warning:
            return Color(red: 0.98, green: 0.82, blue: 0.32)
        case .critical:
            return Color(red: 0.98, green: 0.44, blue: 0.38)
        }
    }

    private func backgroundColor(for severity: UsageSummarySeverity) -> Color {
        switch severity {
        case .healthy:
            return Color(red: 0.26, green: 0.52, blue: 0.34).opacity(0.22)
        case .warning:
            return Color(red: 0.56, green: 0.42, blue: 0.14).opacity(0.24)
        case .critical:
            return Color(red: 0.52, green: 0.18, blue: 0.16).opacity(0.26)
        }
    }

    private func hoverID(provider: UsageSummaryProvider, window: UsageSummaryWindow) -> String {
        "\(provider.id)-\(window.id)"
    }

    private var batteryPopoverAlignment: Alignment {
        switch (batteryPopoverPlacement, alignment) {
        case (.above, .trailing):
            return .bottomTrailing
        case (.above, _):
            return .bottomLeading
        case (.below, .trailing):
            return .topTrailing
        case (.below, _):
            return .topLeading
        }
    }

    private var batteryPopoverOffsetY: CGFloat {
        switch batteryPopoverPlacement {
        case .above:
            return -18
        case .below:
            return 24
        }
    }

    private var batteryPopoverScaleAnchor: UnitPoint {
        switch (batteryPopoverPlacement, alignment) {
        case (.above, .trailing):
            return .bottomTrailing
        case (.above, _):
            return .bottomLeading
        case (.below, .trailing):
            return .topTrailing
        case (.below, _):
            return .topLeading
        }
    }

    @ViewBuilder
    private func batteryPopover(provider: UsageSummaryProvider, window: UsageSummaryWindow) -> some View {
        switch batteryHoverDetailStyle {
        case .allProviders:
            UsageBatteryDetailPopover(
                providers: providers,
                locale: locale
            )
        case .currentWindow:
            UsageBatteryCurrentWindowPopover(
                provider: provider,
                window: window,
                locale: locale
            )
        }
    }
}

private struct UsageBatteryCurrentWindowPopover: View {
    let provider: UsageSummaryProvider
    let window: UsageSummaryWindow
    let locale: Locale

    var body: some View {
        Text(remainingText)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(percentColor(for: window.remainingPercentage))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(OpaquePopoverBackground(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.42), radius: 12, y: 6)
            .accessibilityLabel(Text("\(provider.title) \(window.label) \(remainingText)"))
    }

    private var remainingText: String {
        let percentage = "\(Int(max(0, window.remainingPercentage).rounded()))%"
        switch locale.language.languageCode?.identifier {
        case "zh":
            return "剩余：\(percentage)"
        default:
            return "Left: \(percentage)"
        }
    }

    private func percentColor(for remainingPercentage: Double) -> Color {
        if remainingPercentage > 30 {
            return Color(red: 0.22, green: 0.86, blue: 0.45)
        }
        if remainingPercentage >= 10 {
            return Color(red: 0.96, green: 0.75, blue: 0.24)
        }
        return Color(red: 0.96, green: 0.30, blue: 0.28)
    }
}

private struct UsageBatteryDetailPopover: View {
    let providers: [UsageSummaryProvider]
    let locale: Locale

    var body: some View {
        content
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .padding(.vertical, 12)
            .frame(width: 148, alignment: .leading)
            .background(OpaquePopoverBackground(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.42), radius: 12, y: 6)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                VStack(alignment: .leading, spacing: 8) {
                    Text(provider.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(titleColor)

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(provider.windows, id: \.id) { window in
                            HStack(spacing: 5) {
                                Text(window.label)
                                    .frame(width: 24, alignment: .leading)

                                Text(remainingLabel)
                                    .frame(width: 38, alignment: .leading)

                                Text(remainingPercentText(for: window))
                                    .foregroundStyle(percentColor(for: window.remainingPercentage))
                                    .frame(width: 42, alignment: .trailing)
                            }
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.78))
                        }
                    }
                }

                if index < providers.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 1)
                }
            }
        }
    }

    private var titleColor: Color {
        Color(red: 0.92, green: 0.48, blue: 0.14)
    }

    private var remainingLabel: String {
        switch locale.language.languageCode?.identifier {
        case "zh":
            return "剩余:"
        default:
            return "left:"
        }
    }

    private func remainingPercentText(for window: UsageSummaryWindow) -> String {
        "\(Int(max(0, window.remainingPercentage).rounded()))%"
    }

    private func percentColor(for remainingPercentage: Double) -> Color {
        if remainingPercentage > 30 {
            return Color(red: 0.22, green: 0.86, blue: 0.45)
        }
        if remainingPercentage >= 10 {
            return Color(red: 0.96, green: 0.75, blue: 0.24)
        }
        return Color(red: 0.96, green: 0.30, blue: 0.28)
    }
}

private struct OpaquePopoverBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> OpaquePopoverBackingView {
        OpaquePopoverBackingView(cornerRadius: cornerRadius)
    }

    func updateNSView(_ nsView: OpaquePopoverBackingView, context: Context) {
        nsView.cornerRadius = cornerRadius
    }
}

private final class OpaquePopoverBackingView: NSView {
    var cornerRadius: CGFloat {
        didSet {
            layer?.cornerRadius = cornerRadius
        }
    }

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        true
    }

    override func layout() {
        super.layout()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = cornerRadius
    }
}

private struct BatteryQuotaIndicator: View {
    let severity: UsageSummarySeverity
    let remainingPercentage: Double

    private var fillLevel: CGFloat {
        CGFloat(min(100, max(0, remainingPercentage)) / 100)
    }

    private var fillColor: Color {
        switch severity {
        case .healthy:
            return Color(red: 0.42, green: 0.92, blue: 0.60)
        case .warning:
            return Color(red: 0.98, green: 0.82, blue: 0.32)
        case .critical:
            return Color(red: 0.98, green: 0.44, blue: 0.38)
        }
    }

    var body: some View {
        HStack(spacing: 1.5) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color.white.opacity(0.26), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )

                    let fillWidth = max(0, (proxy.size.width - 4) * fillLevel)
                    if fillWidth > 0 {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(fillColor)
                            .frame(width: max(1.5, fillWidth))
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                    }
                }
            }
            .frame(width: 18, height: 10)

            RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                .fill(Color.white.opacity(0.24))
                .frame(width: 1.8, height: 4.8)
        }
    }
}
