import Foundation
import IslandShared

@MainActor
final class LifecycleCoordinator {
    private let appModel: AppModel
    private let approvalCoordinator: ApprovalCoordinator
    private let sessionStore: SessionStore
    private let socketServer: SocketServer
    private let terminalLocator: AppleTerminalLocator
    private let hookInstaller: HookInstaller
    private let claudeAdapter: ClaudeProviderAdapter
    private let codexAdapter: CodexProviderAdapter

    init(appModel: AppModel) {
        self.appModel = appModel
        let approvalCoordinator = ApprovalCoordinator()
        let terminalLocator = AppleTerminalLocator()
        let sessionStore = SessionStore { snapshot in
            appModel.update(snapshot: snapshot)
        }
        let socketServer = SocketServer(
            socketPath: "/tmp/island.sock",
            sessionStore: sessionStore,
            approvalCoordinator: approvalCoordinator
        )
        let hookInstaller = HookInstaller()
        let codexMonitor = CodexAppServerMonitor(
            sessionStore: sessionStore,
            noteDidChange: { note in
                appModel.codexStatusNote = note
            }
        )

        self.approvalCoordinator = approvalCoordinator
        self.terminalLocator = terminalLocator
        self.sessionStore = sessionStore
        self.socketServer = socketServer
        self.hookInstaller = hookInstaller
        self.claudeAdapter = ClaudeProviderAdapter(installer: hookInstaller)
        self.codexAdapter = CodexProviderAdapter(installer: hookInstaller, monitor: codexMonitor)
        appModel.bind(
            sessionStore: sessionStore,
            approvalCoordinator: approvalCoordinator,
            socketServer: socketServer,
            terminalLocator: terminalLocator
        )
    }

    func start() {
        Task {
            do {
                try await claudeAdapter.installHooks()
                try await codexAdapter.installHooks()
                try await socketServer.start()
                await claudeAdapter.startMonitoring()
                await codexAdapter.startMonitoring()
            } catch {
                appModel.codexStatusNote = "Startup error: \(error.localizedDescription)"
            }
        }
    }

    func stop() {
        Task {
            await socketServer.stop()
            await codexAdapter.monitor.stop()
        }
    }
}
