import XCTest
@testable import Ping_Island

final class UsageMenuBarCodexPresenterTests: XCTestCase {
    func testHeadlinePrefersSevenDayWindow() {
        let snapshot = makeSnapshot(windows: [
            makeWindow(key: "primary", label: "5h", usedPercentage: 31, windowMinutes: 300),
            makeWindow(key: "secondary", label: "7d", usedPercentage: 22, windowMinutes: 10_080)
        ])

        XCTAssertEqual(UsageMenuBarCodexPresenter.headlineWindow(in: snapshot)?.key, "secondary")
    }

    func testHeadlineFallsBackToLongestWindow() {
        let snapshot = makeSnapshot(windows: [
            makeWindow(key: "short", label: "1h", usedPercentage: 31, windowMinutes: 60),
            makeWindow(key: "long", label: "1d", usedPercentage: 22, windowMinutes: 1_440)
        ])

        XCTAssertEqual(UsageMenuBarCodexPresenter.headlineWindow(in: snapshot)?.key, "long")
    }

    func testDetailWindowsAreOrderedFromShortestToLongest() {
        let snapshot = makeSnapshot(windows: [
            makeWindow(key: "secondary", label: "7d", usedPercentage: 22, windowMinutes: 10_080),
            makeWindow(key: "primary", label: "5h", usedPercentage: 31, windowMinutes: 300)
        ])

        XCTAssertEqual(
            UsageMenuBarCodexPresenter.detailWindows(in: snapshot).map(\.key),
            ["primary", "secondary"]
        )
    }

    func testCompactTokenCountUsesStableShortUnits() {
        XCTAssertEqual(UsageMenuBarCodexPresenter.compactTokenCount(999), "999")
        XCTAssertEqual(UsageMenuBarCodexPresenter.compactTokenCount(1_250), "1.3K")
        XCTAssertEqual(UsageMenuBarCodexPresenter.compactTokenCount(1_000_000), "1M")
        XCTAssertEqual(UsageMenuBarCodexPresenter.compactTokenCount(1_234_567), "1.2M")
    }

    private func makeSnapshot(windows: [CodexUsageWindow]) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            sourceFilePath: "/tmp/rollout.jsonl",
            capturedAt: nil,
            planType: "plus",
            limitID: "codex",
            windows: windows
        )
    }

    private func makeWindow(
        key: String,
        label: String,
        usedPercentage: Double,
        windowMinutes: Int
    ) -> CodexUsageWindow {
        CodexUsageWindow(
            key: key,
            label: label,
            usedPercentage: usedPercentage,
            leftPercentage: 100 - usedPercentage,
            windowMinutes: windowMinutes,
            resetsAt: nil
        )
    }
}
