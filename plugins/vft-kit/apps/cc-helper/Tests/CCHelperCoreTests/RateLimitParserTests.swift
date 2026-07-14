import XCTest
@testable import CCHelperCore

final class RateLimitParserTests: XCTestCase {
    func test_parses_both_windows_with_iso_reset() throws {
        let json = """
        {"five_hour":{"used_percentage":42,"resets_at":"2026-07-14T18:00:00Z"},
         "seven_day":{"used_percentage":18.5,"resets_at":"2026-07-20T00:00:00Z"}}
        """
        let snap = RateLimitParser.parse(Data(json.utf8))
        XCTAssertEqual(try XCTUnwrap(snap?.fiveHour?.usedPercentage), 42, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snap?.sevenDay?.usedPercentage), 18.5, accuracy: 0.001)
        XCTAssertNotNil(snap?.fiveHour?.resetsAt)
    }

    func test_falls_back_to_utilization_key() throws {
        let json = #"{"five_hour":{"utilization":"55"}}"#
        let snap = RateLimitParser.parse(Data(json.utf8))
        XCTAssertEqual(try XCTUnwrap(snap?.fiveHour?.usedPercentage), 55, accuracy: 0.001)
        XCTAssertNil(snap?.sevenDay)
    }

    func test_parses_unix_seconds_reset() {
        let json = #"{"seven_day":{"used_percentage":10,"resets_at":1752000000}}"#
        let snap = RateLimitParser.parse(Data(json.utf8))
        XCTAssertEqual(snap?.sevenDay?.resetsAt, Date(timeIntervalSince1970: 1752000000))
    }

    func test_returns_nil_for_empty_or_garbage() {
        XCTAssertNil(RateLimitParser.parse(Data("{}".utf8)))
        XCTAssertNil(RateLimitParser.parse(Data("not json".utf8)))
    }
}
