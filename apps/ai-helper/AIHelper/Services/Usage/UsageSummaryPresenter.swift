import Foundation

enum UsageSummarySeverity: Equatable {
    case healthy
    case warning
    case critical
}

struct UsageSummaryWindow: Equatable {
    let id: String
    let label: String
    let valueText: String
    let resetText: String?
    let resetsAt: Date?
    let severity: UsageSummarySeverity
    let remainingPercentage: Double

    nonisolated init(
        id: String,
        label: String,
        valueText: String,
        resetText: String?,
        resetsAt: Date? = nil,
        severity: UsageSummarySeverity,
        remainingPercentage: Double
    ) {
        self.id = id
        self.label = label
        self.valueText = valueText
        self.resetText = resetText
        self.resetsAt = resetsAt
        self.severity = severity
        self.remainingPercentage = remainingPercentage
    }
}

struct UsageSummaryProvider: Equatable, Identifiable {
    let id: String
    let title: String
    let windows: [UsageSummaryWindow]
}

enum UsageSummaryPresenter {
    nonisolated static func isSevenDayWindowLabel(_ label: String) -> Bool {
        let normalizedLabel = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedLabel == "7d" || normalizedLabel.hasPrefix("7d ")
    }

    nonisolated static func preferredBatteryWindow(for provider: UsageSummaryProvider) -> UsageSummaryWindow? {
        provider.windows.first { window in
            isSevenDayWindowLabel(window.label)
        } ?? provider.windows.last
    }

    nonisolated static func sevenDayWindow(
        forProviderID providerID: String,
        in providers: [UsageSummaryProvider]
    ) -> UsageSummaryWindow? {
        providers
            .first { $0.id == providerID }?
            .windows
            .first { isSevenDayWindowLabel($0.label) }
    }

    nonisolated static func remainingHelpText(
        for provider: UsageSummaryProvider,
        locale: Locale = .current
    ) -> String {
        let lines = provider.windows.map { window in
            let components = [
                window.label,
                remainingValueText(for: window.remainingPercentage, locale: locale)
            ]
            return components.joined(separator: " · ")
        }

        guard !lines.isEmpty else {
            return provider.title
        }

        return ([provider.title] + lines).joined(separator: "\n")
    }

    nonisolated static func providers(
        claudeSnapshot: ClaudeUsageSnapshot?,
        codexSnapshot: CodexUsageSnapshot?,
        mode: UsageValueMode,
        now: Date = .now,
        locale: Locale = .current
    ) -> [UsageSummaryProvider] {
        var providers: [UsageSummaryProvider] = []

        if let snapshot = claudeSnapshot, snapshot.isEmpty == false {
            var windows: [UsageSummaryWindow] = []
            // API Key 模式:fiveHour 装的是网关已用额度%,label 显示「已用」,无重置时间。
            let fiveHourLabel = snapshot.isApiBalance
                ? (locale.language.languageCode?.identifier == "zh" ? "已用" : "Used")
                : "5h"
            if let fiveHour = snapshot.fiveHour {
                windows.append(
                    UsageSummaryWindow(
                        id: "claude-5h",
                        label: fiveHourLabel,
                        valueText: valueText(for: fiveHour.usedPercentage, mode: mode, locale: locale),
                        resetText: resetText(for: fiveHour.resetsAt, now: now, locale: locale),
                        resetsAt: fiveHour.resetsAt,
                        severity: severity(forUsedPercentage: fiveHour.usedPercentage),
                        remainingPercentage: remainingPercentage(forUsedPercentage: fiveHour.usedPercentage)
                    )
                )
            }
            if let sevenDay = snapshot.sevenDay {
                windows.append(
                    UsageSummaryWindow(
                        id: "claude-7d",
                        label: "7d",
                        valueText: valueText(for: sevenDay.usedPercentage, mode: mode, locale: locale),
                        resetText: resetText(for: sevenDay.resetsAt, now: now, locale: locale),
                        resetsAt: sevenDay.resetsAt,
                        severity: severity(forUsedPercentage: sevenDay.usedPercentage),
                        remainingPercentage: remainingPercentage(forUsedPercentage: sevenDay.usedPercentage)
                    )
                )
            }
            if !windows.isEmpty {
                providers.append(
                    UsageSummaryProvider(
                        id: "claude",
                        title: "Claude",
                        windows: windows
                    )
                )
            }
        }

        if let snapshot = codexSnapshot, snapshot.isEmpty == false {
            let windows = snapshot.windows.map { window in
                UsageSummaryWindow(
                    id: "codex-\(window.key)",
                    label: window.label,
                    valueText: valueText(for: window.usedPercentage, mode: mode, locale: locale),
                    resetText: resetText(for: window.resetsAt, now: now, locale: locale),
                    resetsAt: window.resetsAt,
                    severity: severity(forUsedPercentage: window.usedPercentage),
                    remainingPercentage: remainingPercentage(forUsedPercentage: window.usedPercentage)
                )
            }

            if !windows.isEmpty {
                providers.append(
                    UsageSummaryProvider(
                        id: "codex",
                        title: "Codex",
                        windows: windows
                    )
                )
            }
        }

        return providers
    }

    nonisolated static func shouldShowSummary(
        for route: IslandExpandedRoute,
        showUsage: Bool,
        providers: [UsageSummaryProvider]
    ) -> Bool {
        guard showUsage, !providers.isEmpty else {
            return false
        }

        switch route {
        case .sessionList, .hoverDashboard, .chat:
            return true
        case .attentionNotification, .completionNotification:
            return false
        }
    }

    nonisolated static func valueText(
        for usedPercentage: Double,
        mode: UsageValueMode,
        locale: Locale = .current
    ) -> String {
        switch mode {
        case .used:
            return "\(Int(usedPercentage.rounded()))%"
        case .remaining:
            let remaining = max(0, 100 - usedPercentage)
            return remainingValueText(for: remaining, locale: locale)
        }
    }

    nonisolated static func remainingValueText(
        for remainingPercentage: Double,
        locale: Locale = .current
    ) -> String {
        let remaining = max(0, remainingPercentage)
        return "\(Int(remaining.rounded()))% \(localizedRemainingLabel(locale: locale))"
    }

    nonisolated static func resetText(
        for date: Date?,
        now: Date = .now,
        locale: Locale = .current
    ) -> String? {
        guard let date,
              let duration = remainingDurationString(until: date, now: now) else {
            return nil
        }

        switch locale.language.languageCode?.identifier {
        case "zh":
            return "\(duration) 后重置"
        default:
            return "Resets in \(duration)"
        }
    }

    nonisolated static func remainingDurationString(until date: Date, now: Date = .now) -> String? {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else {
            return nil
        }

        let totalMinutes = seconds / 60
        let days = totalMinutes / 1_440
        let remainingMinutesAfterDays = totalMinutes % 1_440
        let hours = remainingMinutesAfterDays / 60
        let minutes = remainingMinutesAfterDays % 60

        if days > 0, hours > 0 {
            return "\(days)d \(hours)h"
        }
        if days > 0 {
            return "\(days)d"
        }
        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "<1m"
    }

    nonisolated static func severity(forUsedPercentage usedPercentage: Double) -> UsageSummarySeverity {
        let remainingPercentage = remainingPercentage(forUsedPercentage: usedPercentage)
        if remainingPercentage > 30 {
            return .healthy
        }
        if remainingPercentage >= 10 {
            return .warning
        }
        return .critical
    }

    nonisolated static func shouldShowFloatingBolt(for window: UsageSummaryWindow) -> Bool {
        window.remainingPercentage < 60
    }

    private nonisolated static func remainingPercentage(forUsedPercentage usedPercentage: Double) -> Double {
        max(0, 100 - usedPercentage)
    }

    private nonisolated static func localizedRemainingLabel(locale: Locale) -> String {
        switch locale.language.languageCode?.identifier {
        case "zh":
            return "剩余"
        default:
            return "left"
        }
    }
}
