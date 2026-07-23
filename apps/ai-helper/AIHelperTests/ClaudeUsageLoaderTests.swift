import XCTest
@testable import Ping_Island

final class ClaudeUsageLoaderTests: XCTestCase {
    func testLoadParsesCachedRateLimits() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-helper-claude-usage-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("island-rate-limits.json")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let payload = """
        {
          "five_hour": {
            "used_percentage": 42,
            "resets_at": 1760000000
          },
          "seven_day": {
            "used_percentage": 17.5,
            "resets_at": 1760500000
          }
        }
        """
        try payload.write(to: cacheURL, atomically: true, encoding: .utf8)

        let snapshot = try ClaudeUsageLoader.load(from: cacheURL)

        XCTAssertEqual(snapshot?.fiveHour?.roundedUsedPercentage, 42)
        XCTAssertEqual(snapshot?.sevenDay?.roundedUsedPercentage, 18)
        XCTAssertEqual(snapshot?.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertNotNil(snapshot?.cachedAt)
    }

    func testLoadParsesUtilizationPayloadWithISO8601ResetDates() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-helper-claude-usage-iso-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("island-rate-limits.json")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let payload = """
        {
          "five_hour": {
            "utilization": 0,
            "resets_at": null
          },
          "seven_day": {
            "utilization": 23,
            "resets_at": "2026-02-09T12:00:00.462679+00:00"
          }
        }
        """
        try payload.write(to: cacheURL, atomically: true, encoding: .utf8)

        let snapshot = try ClaudeUsageLoader.load(from: cacheURL)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        XCTAssertEqual(snapshot?.fiveHour?.roundedUsedPercentage, 0)
        XCTAssertNil(snapshot?.fiveHour?.resetsAt)
        XCTAssertEqual(snapshot?.sevenDay?.roundedUsedPercentage, 23)
        XCTAssertEqual(snapshot?.sevenDay?.resetsAt, formatter.date(from: "2026-02-09T12:00:00.462679+00:00"))
    }

    func testLoadReturnsNilForMissingCacheFile() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-helper-claude-usage-missing-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("island-rate-limits.json")

        let snapshot = try ClaudeUsageLoader.load(from: cacheURL)

        XCTAssertNil(snapshot)
    }

    func testApiBillingUsageTreatsTotalUsageAsCents() {
        let usedPercentage = ClaudeUsageLoader.apiBillingUsedPercentage(
            totalUsage: 2_596.8254,
            hardLimitUSD: 200
        )

        XCTAssertEqual(usedPercentage, 12.984127, accuracy: 0.000001)
    }

    func testApiBillingUsageIsClampedToProgressRange() {
        XCTAssertEqual(
            ClaudeUsageLoader.apiBillingUsedPercentage(totalUsage: -1, hardLimitUSD: 200),
            0
        )
        XCTAssertEqual(
            ClaudeUsageLoader.apiBillingUsedPercentage(totalUsage: 50_000, hardLimitUSD: 200),
            100
        )
        XCTAssertEqual(
            ClaudeUsageLoader.apiBillingUsedPercentage(totalUsage: 100, hardLimitUSD: 0),
            0
        )
    }

    // MARK: 新鲜度判断(age / isStale)

    private func makeSnapshot(cachedAt: Date?) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            fiveHour: ClaudeUsageWindow(usedPercentage: 9, resetsAt: nil),
            sevenDay: ClaudeUsageWindow(usedPercentage: 20, resetsAt: nil),
            cachedAt: cachedAt
        )
    }

    func testAgeReturnsElapsedSecondsFromCachedAt() {
        let now = Date(timeIntervalSince1970: 1_784_400_000)
        let snapshot = makeSnapshot(cachedAt: now.addingTimeInterval(-120))
        XCTAssertEqual(try XCTUnwrap(snapshot.age(now: now)), 120, accuracy: 0.001)
    }

    func testAgeIsNilWhenCachedAtMissing() {
        XCTAssertNil(makeSnapshot(cachedAt: nil).age())
    }

    func testFreshSnapshotIsNotStale() {
        let now = Date(timeIntervalSince1970: 1_784_400_000)
        // 刚更新 30s,远低于 600s 阈值
        let snapshot = makeSnapshot(cachedAt: now.addingTimeInterval(-30))
        XCTAssertFalse(snapshot.isStale(now: now))
    }

    func testOldSnapshotIsStale() {
        let now = Date(timeIntervalSince1970: 1_784_400_000)
        // 15 分钟前更新,超过 600s 阈值 → 陈旧
        let snapshot = makeSnapshot(cachedAt: now.addingTimeInterval(-900))
        XCTAssertTrue(snapshot.isStale(now: now))
    }

    func testStalenessBoundaryIsExclusive() {
        let now = Date(timeIntervalSince1970: 1_784_400_000)
        let threshold = ClaudeUsageSnapshot.stalenessThreshold
        // 恰好等于阈值:不算陈旧(用 > 比较)
        XCTAssertFalse(makeSnapshot(cachedAt: now.addingTimeInterval(-threshold)).isStale(now: now))
        // 略超阈值:陈旧
        XCTAssertTrue(makeSnapshot(cachedAt: now.addingTimeInterval(-threshold - 1)).isStale(now: now))
    }

    func testMissingCachedAtIsTreatedAsFresh() {
        // 无 cachedAt 时保守视为未陈旧,避免误伤刚读出的正常数据
        XCTAssertFalse(makeSnapshot(cachedAt: nil).isStale())
    }

    func testLoadedSnapshotFromOldFileIsStale() throws {
        // 集成路径:真实文件 + 把 mtime 改老到 20 分钟前,验证 load→cachedAt→isStale 全链路
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-helper-claude-usage-stale-\(UUID().uuidString)", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("island-rate-limits.json")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try #"{"five_hour":{"used_percentage":9,"resets_at":1760000000}}"#
            .write(to: cacheURL, atomically: true, encoding: .utf8)
        let oldDate = Date().addingTimeInterval(-1200)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: cacheURL.path)

        let snapshot = try XCTUnwrap(try ClaudeUsageLoader.load(from: cacheURL))
        XCTAssertTrue(snapshot.isStale())
    }
}
