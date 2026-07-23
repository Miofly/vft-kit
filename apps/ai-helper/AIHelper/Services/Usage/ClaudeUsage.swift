import Foundation

struct ClaudeUsageWindow: Equatable, Codable, Sendable {
    let usedPercentage: Double
    let resetsAt: Date?

    var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }
}

struct ClaudeUsageSnapshot: Equatable, Codable, Sendable {
    let fiveHour: ClaudeUsageWindow?
    let sevenDay: ClaudeUsageWindow?
    let cachedAt: Date?
    /// API Key 模式:窗口是网关余额(fiveHour 装「已用%」),下游据此把 label 显示成「余额」而非「5h/7d」。
    var isApiBalance: Bool = false

    /// 数据文件超过该时长未更新即视为陈旧(通常意味着 Claude Code 未运行 / 状态栏长期未刷新,
    /// 此时轮询读到的还是旧快照,不能当成实时用量)。3 分钟轮询 + 状态栏可能几分钟不刷,取 10 分钟。
    static let stalenessThreshold: TimeInterval = 600

    nonisolated
    var isEmpty: Bool {
        let hasFiveHour: Bool = if case .some = fiveHour { true } else { false }
        let hasSevenDay: Bool = if case .some = sevenDay { true } else { false }
        return !hasFiveHour && !hasSevenDay
    }

    /// 距上次写入文件的时长(秒);无 cachedAt(读文件属性失败)时返回 nil。
    nonisolated
    func age(now: Date = Date()) -> TimeInterval? {
        guard let cachedAt else { return nil }
        return now.timeIntervalSince(cachedAt)
    }

    /// 数据是否已陈旧。无 cachedAt 时保守地视为"未陈旧",避免误伤刚读出的正常数据。
    nonisolated
    func isStale(threshold: TimeInterval = stalenessThreshold, now: Date = Date()) -> Bool {
        guard let age = age(now: now) else { return false }
        return age > threshold
    }
}

enum ClaudeUsageLoader {
    nonisolated static let defaultCacheURL = URL(fileURLWithPath: "/tmp/island-rate-limits.json")

    /// 读 ~/.claude/settings.json 的 env 段。
    private nonisolated static func claudeEnv() -> [String: Any]? {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = json["env"] as? [String: Any] else { return nil }
        return env
    }

    /// 检测是否使用 API Key 模式（非官方 Claude 账号登录）
    nonisolated static func isApiKeyMode() -> Bool {
        guard let env = claudeEnv() else { return false }
        // 有 ANTHROPIC_AUTH_TOKEN 或 ANTHROPIC_BASE_URL 就认为是 API Key 模式
        return env["ANTHROPIC_AUTH_TOKEN"] != nil || env["ANTHROPIC_BASE_URL"] != nil
    }

    /// 查 New API 网关(one-api 系)的 billing 接口,把当前 token 的「已用/总额」折算成 ClaudeUsageWindow。
    /// 端点:{BASE_URL}/v1/dashboard/billing/{subscription,usage}。非该形态网关会静默失败返回 nil。
    nonisolated static func loadApiBalance() -> ClaudeUsageSnapshot? {
        guard let env = claudeEnv(),
              let token = env["ANTHROPIC_AUTH_TOKEN"] as? String, !token.isEmpty,
              let base = env["ANTHROPIC_BASE_URL"] as? String, !base.isEmpty,
              let baseURL = URL(string: base) else { return nil }

        func getJSON(_ path: String) -> [String: Any]? {
            var req = URLRequest(url: baseURL.appendingPathComponent(path),
                                 timeoutInterval: 8)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let sem = DispatchSemaphore(value: 0)
            var result: [String: Any]?
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                defer { sem.signal() }
                guard let data,
                      (resp as? HTTPURLResponse)?.statusCode == 200,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }
                result = obj
            }.resume()
            _ = sem.wait(timeout: .now() + 9)
            return result
        }

        guard let sub = getJSON("v1/dashboard/billing/subscription"),
              let total = number(from: sub["hard_limit_usd"]), total > 0,
              let usage = getJSON("v1/dashboard/billing/usage"),
              let used = number(from: usage["total_usage"]) else { return nil }

        let usedPct = apiBillingUsedPercentage(totalUsage: used, hardLimitUSD: total)
        return ClaudeUsageSnapshot(
            fiveHour: ClaudeUsageWindow(usedPercentage: usedPct, resetsAt: nil),
            sevenDay: nil,
            cachedAt: Date(),
            isApiBalance: true
        )
    }

    nonisolated static func apiBillingUsedPercentage(totalUsage: Double, hardLimitUSD: Double) -> Double {
        guard hardLimitUSD > 0 else { return 0 }
        // OpenAI-compatible billing usage returns total_usage in cents, while
        // subscription hard_limit_usd is in dollars.
        let usedUSD = totalUsage / 100
        // used_percentage 供进度条复用;超支(>100%)夹到 100 以免进度条溢出。
        return min(100, max(0, usedUSD / hardLimitUSD * 100))
    }

    nonisolated static func load(from url: URL = defaultCacheURL) throws -> ClaudeUsageSnapshot? {
        // API Key 模式:没有 5h/7d rate limit 概念,忽略 /tmp 里可能残留的订阅期旧文件,
        // 改查网关 billing 显示余额(查不到则不显示,不回退到陈旧的订阅文件)。
        guard !(url == defaultCacheURL && isApiKeyMode()) else { return loadApiBalance() }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else {
            return nil
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let cachedAt = attributes?[.modificationDate] as? Date
        let snapshot = ClaudeUsageSnapshot(
            fiveHour: usageWindow(for: "five_hour", in: payload),
            sevenDay: usageWindow(for: "seven_day", in: payload),
            cachedAt: cachedAt
        )

        return snapshot.isEmpty ? nil : snapshot
    }

    private nonisolated static func usageWindow(for key: String, in payload: [String: Any]) -> ClaudeUsageWindow? {
        guard let window = payload[key] as? [String: Any],
              let rawPercentage = number(from: window["used_percentage"])
                ?? number(from: window["utilization"]) else {
            return nil
        }

        return ClaudeUsageWindow(
            usedPercentage: rawPercentage,
            resetsAt: date(from: window["resets_at"])
        )
    }

    private nonisolated static func number(from value: Any?) -> Double? {
        switch value {
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private nonisolated static func date(from value: Any?) -> Date? {
        switch value {
        case let value as NSNumber:
            return Date(timeIntervalSince1970: value.doubleValue)
        case let value as String:
            if let seconds = Double(value) {
                return Date(timeIntervalSince1970: seconds)
            }

            let formatterWithFractionalSeconds = ISO8601DateFormatter()
            formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatterWithFractionalSeconds.date(from: value) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        default:
            return nil
        }
    }
}
