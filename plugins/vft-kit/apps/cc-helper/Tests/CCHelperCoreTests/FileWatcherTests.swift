import XCTest
@testable import CCHelperCore

final class FileWatcherTests: XCTestCase {
    func test_fires_on_write() throws {
        let path = NSTemporaryDirectory() + "fw-\(UUID().uuidString).json"
        FileManager.default.createFile(atPath: path, contents: Data("{}".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let fired = expectation(description: "onChange fired")
        fired.assertForOverFulfill = false
        let watcher = FileWatcher(path: path) { fired.fulfill() }
        watcher.start()
        defer { watcher.stop() }

        // 给 kqueue 一点挂载时间后写入
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            try? "updated".write(toFile: path, atomically: false, encoding: .utf8)
        }
        wait(for: [fired], timeout: 3)
    }
}
