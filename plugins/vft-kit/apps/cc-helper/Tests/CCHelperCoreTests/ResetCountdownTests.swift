import XCTest
@testable import CCHelperCore

final class ResetCountdownTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func test_nil_input_returns_nil() {
        XCTAssertNil(ResetCountdown.text(until: nil, now: now))
    }

    func test_multi_day_uses_d_h() {
        let future = now.addingTimeInterval(3 * 86_400 + 4 * 3_600)
        XCTAssertEqual(ResetCountdown.text(until: future, now: now), "3d 4h")
    }

    func test_within_day_uses_h_m() {
        let future = now.addingTimeInterval(2 * 3_600 + 13 * 60)
        XCTAssertEqual(ResetCountdown.text(until: future, now: now), "2h 13m")
    }

    func test_under_one_minute() {
        XCTAssertEqual(ResetCountdown.text(until: now.addingTimeInterval(30), now: now), "<1m")
    }

    func test_past_is_reset() {
        XCTAssertEqual(ResetCountdown.text(until: now.addingTimeInterval(-10), now: now), "已重置")
    }
}
