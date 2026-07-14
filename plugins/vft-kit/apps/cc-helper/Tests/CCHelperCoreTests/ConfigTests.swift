import XCTest
@testable import CCHelperCore

final class ConfigTests: XCTestCase {
    func test_partial_json_falls_back_to_defaults() throws {
        // 只给一个字段,其余应回落默认值
        let json = #"{"menuBarShowRemaining": true, "warningThreshold": 60}"#
        let cfg = try JSONDecoder().decode(CCHelperConfig.self, from: Data(json.utf8))
        XCTAssertTrue(cfg.menuBarShowRemaining)
        XCTAssertEqual(cfg.warningThreshold, 60, accuracy: 0.001)
        // 未提供的字段用默认
        XCTAssertTrue(cfg.menuBarEnabled)
        XCTAssertEqual(cfg.criticalThreshold, 90, accuracy: 0.001)
        XCTAssertTrue(cfg.notifyAllScreens)
        XCTAssertEqual(cfg.notifyTaskComplete.sound, "Hero")
    }

    func test_roundtrip_encode_decode() throws {
        var cfg = CCHelperConfig()
        cfg.notchEnabled = true
        cfg.notifyAllScreens = false
        cfg.bannerDurationSeconds = 8
        cfg.notifyTaskError.sound = "Funk"
        let data = try JSONEncoder().encode(cfg)
        let back = try JSONDecoder().decode(CCHelperConfig.self, from: data)
        XCTAssertEqual(cfg, back)
    }

    @MainActor
    func test_store_saves_and_loads_from_disk() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cc-helper-\(UUID().uuidString)/config.json")
        defer { try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent()) }

        let store = ConfigStore(url: tmp)
        store.config.notchEnabled = true          // didSet 自动落盘
        store.config.bannerDurationSeconds = 7

        let reloaded = ConfigStore(url: tmp)
        XCTAssertTrue(reloaded.config.notchEnabled)
        XCTAssertEqual(reloaded.config.bannerDurationSeconds, 7, accuracy: 0.001)
    }
}
