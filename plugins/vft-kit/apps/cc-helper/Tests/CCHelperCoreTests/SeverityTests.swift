import XCTest
@testable import CCHelperCore

final class SeverityTests: XCTestCase {
    private func window(_ used: Double) -> RateLimitWindow {
        RateLimitWindow(usedPercentage: used, resetsAt: nil)
    }

    func test_healthy_below_70() {
        XCTAssertEqual(window(0).severity, .healthy)
        XCTAssertEqual(window(69.9).severity, .healthy)
    }

    func test_warning_between_70_and_90() {
        XCTAssertEqual(window(70).severity, .warning)
        XCTAssertEqual(window(89.9).severity, .warning)
    }

    func test_critical_at_or_above_90() {
        XCTAssertEqual(window(90).severity, .critical)
        XCTAssertEqual(window(100).severity, .critical)
    }

    func test_remaining_percentage_clamped() {
        XCTAssertEqual(window(30).remainingPercentage, 70, accuracy: 0.001)
        XCTAssertEqual(window(120).remainingPercentage, 0, accuracy: 0.001)
    }

    func test_snapshot_isEmpty() {
        XCTAssertTrue(RateLimitSnapshot(fiveHour: nil, sevenDay: nil).isEmpty)
        XCTAssertFalse(RateLimitSnapshot(fiveHour: window(10), sevenDay: nil).isEmpty)
    }
}
