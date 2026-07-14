import XCTest
@testable import CCHelperCore

@MainActor
final class RateLimitStoreTests: XCTestCase {
    func test_reload_parses_from_dataProvider() throws {
        let json = #"{"five_hour":{"used_percentage":42}}"#
        let store = RateLimitStore(
            path: "/unused",
            dataProvider: { _ in Data(json.utf8) }
        )
        store.reload()
        XCTAssertEqual(try XCTUnwrap(store.snapshot?.fiveHour?.usedPercentage), 42, accuracy: 0.001)
        XCTAssertNotNil(store.lastUpdated)
    }

    func test_isStale_when_no_data() {
        let store = RateLimitStore(path: "/unused", dataProvider: { _ in nil })
        store.reload()
        XCTAssertNil(store.snapshot)
        XCTAssertTrue(store.isStale)
    }

    func test_isStale_after_10_minutes() {
        let box = TimeBox(Date(timeIntervalSince1970: 1_000_000))
        let json = #"{"five_hour":{"used_percentage":10}}"#
        let store = RateLimitStore(
            path: "/unused",
            dataProvider: { _ in Data(json.utf8) },
            now: { box.value }
        )
        store.reload()
        XCTAssertFalse(store.isStale)
        box.value = box.value.addingTimeInterval(11 * 60)
        XCTAssertTrue(store.isStale)
    }
}

/// 线程安全的可变时间源,供测试推进"现在"。
private final class TimeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Date
    init(_ value: Date) { _value = value }
    var value: Date {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
