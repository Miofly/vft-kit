import XCTest
@testable import Ping_Island

final class UsageMenuBarCodexPresenterTests: XCTestCase {
    func testHeadlineRequiresApiBillingUsage() {
        let snapshot = makeSnapshot(windows: [
            makeWindow(key: "primary", label: "5h", usedPercentage: 31, windowMinutes: 300),
            makeWindow(key: "secondary", label: "7d", usedPercentage: 22, windowMinutes: 10_080)
        ])

        XCTAssertNil(UsageMenuBarCodexPresenter.headlineWindow(in: snapshot))
    }

    func testHeadlineReturnsApiBalanceWindow() {
        let snapshot = makeSnapshot(
            apiBillingUsage: APIBillingUsage(totalUsage: 8_000, hardLimitUSD: 600),
            windows: [
                makeWindow(key: "api_balance", label: "额度", usedPercentage: 13, windowMinutes: 0)
            ]
        )

        XCTAssertEqual(UsageMenuBarCodexPresenter.headlineWindow(in: snapshot)?.key, "api_balance")
    }

    func testDetailWindowsHideNonBalanceWindows() {
        let snapshot = makeSnapshot(windows: [
            makeWindow(key: "primary", label: "5h", usedPercentage: 31, windowMinutes: 300)
        ])

        XCTAssertTrue(UsageMenuBarCodexPresenter.detailWindows(in: snapshot).isEmpty)
    }

    private func makeSnapshot(
        apiBillingUsage: APIBillingUsage? = nil,
        windows: [CodexUsageWindow]
    ) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            sourceFilePath: "/tmp/rollout.jsonl",
            capturedAt: nil,
            planType: "plus",
            limitID: "codex",
            apiBillingUsage: apiBillingUsage,
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
