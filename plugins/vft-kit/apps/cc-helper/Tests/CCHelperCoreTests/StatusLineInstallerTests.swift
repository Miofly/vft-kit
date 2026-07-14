import XCTest
@testable import CCHelperCore

final class StatusLineInstallerTests: XCTestCase {
    func test_wrapper_pipes_to_both_consumers() {
        let script = StatusLineInstaller.wrapperScript(
            originalCommand: "bun run hud.ts",
            islandStatuslinePath: "$HOME/.ping-island/bin/island-statusline"
        )
        XCTAssertTrue(script.contains("$HOME/.ping-island/bin/island-statusline"))
        XCTAssertTrue(script.contains("bun run hud.ts"))
        XCTAssertTrue(script.contains("input=$(cat)"))
    }

    func test_installed_replaces_command_and_returns_backup() {
        let settings: [String: Any] = ["statusLine": ["type": "command", "command": "ORIGINAL"]]
        let (updated, backup) = StatusLineInstaller.installed(into: settings, wrapperCommand: "WRAPPER")
        XCTAssertEqual(backup, "ORIGINAL")
        let sl = updated["statusLine"] as? [String: Any]
        XCTAssertEqual(sl?["command"] as? String, "WRAPPER")
        XCTAssertEqual(sl?["type"] as? String, "command")
    }

    func test_installed_no_existing_statusline() {
        let (updated, backup) = StatusLineInstaller.installed(into: [:], wrapperCommand: "WRAPPER")
        XCTAssertNil(backup)
        let sl = updated["statusLine"] as? [String: Any]
        XCTAssertEqual(sl?["command"] as? String, "WRAPPER")
    }

    func test_restored_puts_original_back() {
        let settings: [String: Any] = ["statusLine": ["type": "command", "command": "WRAPPER"]]
        let restored = StatusLineInstaller.restored(into: settings, originalCommand: "ORIGINAL")
        let sl = restored["statusLine"] as? [String: Any]
        XCTAssertEqual(sl?["command"] as? String, "ORIGINAL")
    }
}
