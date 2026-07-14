import SwiftUI
import CCHelperCore

/// 严重度 → 颜色(与 ping-island 一致)
func severityColor(_ severity: UsageSeverity) -> Color {
    switch severity {
    case .healthy: return Color(red: 0.42, green: 0.92, blue: 0.60)
    case .warning: return Color(red: 0.98, green: 0.82, blue: 0.32)
    case .critical: return Color(red: 0.98, green: 0.44, blue: 0.38)
    }
}

/// 仿 ping-island 的刘海视图:黑色 NotchShape 同宽覆盖物理刘海;
/// 折叠态把两个用量数字塞进刘海左右槽,hover 展开时向下长出详情卡。
struct NotchUsageView: View {
    @ObservedObject var store: RateLimitStore
    @ObservedObject var presentation: NotchPresentation

    private var notchSize: CGSize { presentation.notchSize }
    private var closedHeight: CGFloat { max(24, notchSize.height) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            content
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: presentation.isExpanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if presentation.isExpanded {
            expanded
        } else {
            collapsed
        }
    }

    // MARK: 折叠态(同物理刘海宽度覆盖)

    private var collapsed: some View {
        HStack(spacing: 0) {
            numberSlot(store.snapshot?.fiveHour, align: .leading)
            Spacer(minLength: 0)
            numberSlot(store.snapshot?.sevenDay, align: .trailing)
        }
        .padding(.horizontal, 14)   // 避开下圆角与中央摄像头
        .frame(width: notchSize.width, height: closedHeight)
        .background(.black)
        .clipShape(NotchShape(topCornerRadius: 6, bottomCornerRadius: 14))
        .opacity(store.isStale ? 0.55 : 1)
    }

    private func numberSlot(_ window: RateLimitWindow?, align: Alignment) -> some View {
        Group {
            if let window {
                let value = presentation.showRemaining ? window.remainingPercentage : window.usedPercentage
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(severityColor(window.severity))
            } else {
                Text("--")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: 30, alignment: align)
    }

    // MARK: 展开态(刘海下方长出详情卡)

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer().frame(height: notchSize.height)   // 顶部让位给刘海本体
            Text("Claude Code 用量")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            detailRow("5h", store.snapshot?.fiveHour)
            detailRow("7d", store.snapshot?.sevenDay)
            if store.isStale {
                Text("无活跃会话 · 最后快照")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .frame(width: 260, alignment: .leading)
        .background(.black)
        .clipShape(NotchShape(topCornerRadius: 12, bottomCornerRadius: 20))
    }

    private func detailRow(_ tag: String, _ window: RateLimitWindow?) -> some View {
        HStack(spacing: 8) {
            Text(tag)
                .frame(width: 26, alignment: .leading)
                .foregroundStyle(.white.opacity(0.6))
            if let window {
                Text("已用 \(Int(window.usedPercentage.rounded()))%")
                    .foregroundStyle(severityColor(window.severity))
                Spacer(minLength: 0)
                if let reset = ResetCountdown.text(until: window.resetsAt) {
                    Text(reset).foregroundStyle(.white.opacity(0.55))
                }
            } else {
                Text("无数据").foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
    }
}
