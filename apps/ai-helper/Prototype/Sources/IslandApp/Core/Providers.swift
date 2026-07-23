import Foundation
import IslandShared

protocol AgentProviderAdapter: Sendable {
    func installHooks() async throws
    func repairHooksIfNeeded() async
    func startMonitoring() async
    func submitInterventionResponse(_ response: InterventionDecision, request: InterventionRequest) async throws
}

struct ClaudeProviderAdapter: AgentProviderAdapter {
    let installer: HookInstaller

    func installHooks() async throws {
        try installer.installClaudeAssets()
    }

    func repairHooksIfNeeded() async {
        try? installer.installClaudeAssets()
    }

    func startMonitoring() async {}

    func submitInterventionResponse(_ response: InterventionDecision, request: InterventionRequest) async throws {}
}

actor CodexProviderAdapter: AgentProviderAdapter {
    let installer: HookInstaller
    let monitor: CodexAppServerMonitor

    init(installer: HookInstaller, monitor: CodexAppServerMonitor) {
        self.installer = installer
        self.monitor = monitor
    }

    func installHooks() async throws {
        try installer.installCodexAssets()
    }

    func repairHooksIfNeeded() async {
        try? installer.installCodexAssets()
    }

    func startMonitoring() async {
        await monitor.start()
    }

    func submitInterventionResponse(_ response: InterventionDecision, request: InterventionRequest) async throws {
        try await monitor.submit(response: response, for: request)
    }
}
