import Foundation
import Combine

@MainActor
public final class RateLimitStore: ObservableObject {
    @Published public private(set) var snapshot: RateLimitSnapshot?
    @Published public private(set) var lastUpdated: Date?

    private let path: String
    private let dataProvider: @Sendable (String) -> Data?
    private let now: @Sendable () -> Date
    private var watcher: FileWatcher?

    // 节流:文件被高频重写(多会话在 7↔8% 边界抖动)时,最多每 minReloadInterval 应用一次,消除闪烁
    private let minReloadInterval: TimeInterval = 1.5
    private var lastReloadAt: Date = .distantPast
    private var reloadScheduled = false

    public init(
        path: String = "/tmp/island-rate-limits.json",
        dataProvider: (@Sendable (String) -> Data?)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.path = path
        self.dataProvider = dataProvider ?? { p in
            try? Data(contentsOf: URL(fileURLWithPath: p))
        }
        self.now = now
    }

    public func start() {
        reload()
        lastReloadAt = now()
        let watcher = FileWatcher(path: path) { [weak self] in
            Task { @MainActor in self?.scheduleReload() }
        }
        watcher.start()
        self.watcher = watcher
    }

    /// 节流版重载:立即或延后到「上次重载 + minReloadInterval」,把高频文件变更压成最多每 1.5s 一次
    private func scheduleReload() {
        let elapsed = now().timeIntervalSince(lastReloadAt)
        if elapsed >= minReloadInterval {
            lastReloadAt = now()
            reload()
        } else if !reloadScheduled {
            reloadScheduled = true
            let delay = minReloadInterval - elapsed
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.reloadScheduled = false
                self.lastReloadAt = self.now()
                self.reload()
            }
        }
    }

    public func reload() {
        guard let data = dataProvider(path),
              let parsed = RateLimitParser.parse(data) else {
            snapshot = nil
            return
        }
        snapshot = parsed
        lastUpdated = now()
    }

    public var isStale: Bool {
        guard let lastUpdated, snapshot != nil else { return true }
        return now().timeIntervalSince(lastUpdated) > 10 * 60
    }
}
