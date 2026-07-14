import Foundation

public enum UsageSeverity: Equatable, Sendable {
    case healthy, warning, critical
}

public struct RateLimitWindow: Equatable, Sendable {
    public let usedPercentage: Double
    public let resetsAt: Date?

    public init(usedPercentage: Double, resetsAt: Date?) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    public var remainingPercentage: Double {
        min(100, max(0, 100 - usedPercentage))
    }

    public var severity: UsageSeverity {
        severity(warning: 70, critical: 90)
    }

    /// 可配阈值版:已用 < warning 健康 / < critical 警告 / 否则危险
    public func severity(warning: Double, critical: Double) -> UsageSeverity {
        switch usedPercentage {
        case ..<warning: return .healthy
        case ..<critical: return .warning
        default: return .critical
        }
    }
}

public struct RateLimitSnapshot: Equatable, Sendable {
    public let fiveHour: RateLimitWindow?
    public let sevenDay: RateLimitWindow?

    public init(fiveHour: RateLimitWindow?, sevenDay: RateLimitWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    public var isEmpty: Bool {
        fiveHour == nil && sevenDay == nil
    }
}
