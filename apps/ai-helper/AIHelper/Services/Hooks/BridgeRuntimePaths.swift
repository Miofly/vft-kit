import Foundation

enum BridgeRuntimePaths {
    nonisolated static let appGroupIdentifier = "group.com.wfly.aihelper"
    nonisolated static let legacySocketPath = "/tmp/island.sock"
    nonisolated static let bridgeConfigEnvironmentKey = "PING_ISLAND_BRIDGE_CONFIG"
    nonisolated static let socketPathEnvironmentKey = "ISLAND_SOCKET_PATH"

    nonisolated private static let legacyConfigRelativePath = ".ai-helper/bridge-config.json"

    nonisolated static var socketPath: String {
#if APP_STORE
        runtimeDirectoryURL.appendingPathComponent("i.sock").path
#else
        legacySocketPath
#endif
    }

    nonisolated static var runtimeConfigURL: URL {
#if APP_STORE
        runtimeDirectoryURL.appendingPathComponent("c.json")
#else
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(legacyConfigRelativePath)
#endif
    }

    nonisolated static var runtimeDirectoryURL: URL {
#if APP_STORE
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return containerURL.appendingPathComponent("b", isDirectory: true)
        }
#endif
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ai-helper", isDirectory: true)
    }

    nonisolated static func prepareRuntimeDirectory() {
        try? FileManager.default.createDirectory(
            at: runtimeDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    nonisolated static var launcherEnvironment: [String: String] {
        [
            socketPathEnvironmentKey: socketPath,
            bridgeConfigEnvironmentKey: runtimeConfigURL.path
        ]
    }
}
