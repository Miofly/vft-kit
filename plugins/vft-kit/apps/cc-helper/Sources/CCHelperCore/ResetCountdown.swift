import Foundation

public enum ResetCountdown {
    public static func text(until date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 { return "已重置" }
        if remaining < 60 { return "<1m" }

        let totalMinutes = Int(remaining / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }
        return "\(hours)h \(minutes)m"
    }
}
