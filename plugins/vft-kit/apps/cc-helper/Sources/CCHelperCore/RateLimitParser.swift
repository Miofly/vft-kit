import Foundation

public enum RateLimitParser {
    public static func parse(_ data: Data) -> RateLimitSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any] else {
            return nil
        }
        let snapshot = RateLimitSnapshot(
            fiveHour: window(from: payload["five_hour"]),
            sevenDay: window(from: payload["seven_day"])
        )
        return snapshot.isEmpty ? nil : snapshot
    }

    private static func window(from value: Any?) -> RateLimitWindow? {
        guard let dict = value as? [String: Any],
              let percentage = number(dict["used_percentage"]) ?? number(dict["utilization"]) else {
            return nil
        }
        return RateLimitWindow(usedPercentage: percentage, resetsAt: date(dict["resets_at"]))
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    private static func date(_ value: Any?) -> Date? {
        switch value {
        case let n as NSNumber:
            return Date(timeIntervalSince1970: n.doubleValue)
        case let s as String:
            if let seconds = Double(s) {
                return Date(timeIntervalSince1970: seconds)
            }
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = withFraction.date(from: s) { return d }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return plain.date(from: s)
        default:
            return nil
        }
    }
}
