//
//  TerminalSessionFocuser.swift
//  AIHelper
//
//  Focuses a specific terminal tab/session using stable terminal identifiers when
//  the host app supports scripting, falling back to TTY matching when needed.
//

import AppKit
import Foundation
import os.log

actor TerminalSessionFocuser {
    static let shared = TerminalSessionFocuser()
    private let logger = Logger(subsystem: "com.wfly.aihelper", category: "TerminalFocus")
    private let iTermSelectionRetryDelayNanoseconds: UInt64 = 250_000_000

    struct GhosttyTerminalSnapshot: Equatable {
        let terminalSessionIdentifier: String
        let workingDirectory: String?
        let title: String?
    }

    private init() {}

    func focusSession(
        terminalPid: Int,
        tty: String?,
        candidateProcessIDs: [Int] = [],
        sessionId: String? = nil,
        clientInfo: SessionClientInfo? = nil,
        workspacePath: String? = nil,
        launchURL: String? = nil,
        remoteHostHint: String? = nil
    ) async -> Bool {
        guard let appInfo = await MainActor.run(body: {
            NSRunningApplication(processIdentifier: pid_t(terminalPid)).map {
                (
                    bundleIdentifier: $0.bundleIdentifier,
                    localizedName: $0.localizedName
                )
            }
        }) else {
            logger.debug("No running app found for terminal pid \(terminalPid, privacy: .public)")
            await FocusDiagnosticsStore.shared.record(
                "TerminalFocus no-running-app terminalPid=\(terminalPid) tty=\(tty ?? "nil") sessionId=\(sessionId ?? "nil")"
            )
            return false
        }

        let bundleIdentifier = appInfo.bundleIdentifier ?? ""
        let localizedName = appInfo.localizedName ?? ""
        let logTTY = tty ?? "unknown"

        logger.debug("Attempting scripted focus terminalPid=\(terminalPid, privacy: .public) bundle=\(bundleIdentifier, privacy: .public) tty=\(logTTY, privacy: .public)")
        await FocusDiagnosticsStore.shared.record(
            "TerminalFocus start terminalPid=\(terminalPid) bundle=\(bundleIdentifier) tty=\(logTTY) sessionId=\(sessionId ?? "nil") clientSession=\(clientInfo?.terminalSessionIdentifier ?? "nil") iTermSession=\(clientInfo?.iTermSessionIdentifier ?? "nil")"
        )

        if let profile = ClientProfileRegistry.ideExtensionProfile(
            bundleIdentifier: bundleIdentifier,
            appName: localizedName
        ), IDEExtensionInstaller.isInstalled(profile) {
            let activatedIDEWindow: Bool
            if profile.prefersWorkspaceWindowRouting {
                activatedIDEWindow = await SessionLauncher.routeIDEWorkspaceWindow(
                    detectedBundleIdentifier: bundleIdentifier,
                    appName: localizedName,
                    workspacePath: workspacePath,
                    fallbackLaunchURL: launchURL,
                    additionalBundleIdentifiers: profile.localAppBundleIdentifiers
                )
            } else {
                activatedIDEWindow = await MainActor.run {
                    guard let app = NSRunningApplication(processIdentifier: pid_t(terminalPid)) else {
                        return false
                    }

                    if app.isHidden {
                        app.unhide()
                    }

                    return app.activate(options: [])
                }
            }

            if activatedIDEWindow {
                _ = await SessionLauncher.waitForIDEWindowActivation(
                    bundleIdentifiers: [bundleIdentifier] + profile.localAppBundleIdentifiers
                )
            }

            let pids = candidateProcessIDs.isEmpty ? [terminalPid] : candidateProcessIDs
            if await focusWithExtension(
                profile: profile,
                processIDs: pids,
                tty: tty,
                sessionId: sessionId,
                clientInfo: clientInfo,
                workspacePath: workspacePath
            ) {
                logger.debug("Focused IDE terminal via URI extension profile=\(profile.id, privacy: .public) pids=\(String(describing: pids), privacy: .public)")
                await FocusDiagnosticsStore.shared.record(
                    "TerminalFocus ide-extension success profile=\(profile.id) terminalPid=\(terminalPid)"
                )
                return true
            }
        }

        switch bundleIdentifier {
        case "com.apple.Terminal":
            guard let tty else {
                logger.debug("No tty available for Terminal bundle \(bundleIdentifier, privacy: .public); skipping AppleScript fallback")
                await FocusDiagnosticsStore.shared.record(
                    "TerminalFocus terminal skip-no-tty terminalPid=\(terminalPid)"
                )
                return false
            }
            guard await TerminalAutomationPermissionCoordinator.shared.ensurePermissionIfNeeded(
                terminalPid: terminalPid,
                bundleIdentifier: bundleIdentifier,
                sessionId: sessionId
            ) else {
                logger.debug("Automation permission unavailable for Terminal bundle \(bundleIdentifier, privacy: .public)")
                await FocusDiagnosticsStore.shared.record(
                    "TerminalFocus terminal skip-no-automation-permission terminalPid=\(terminalPid) sessionId=\(sessionId ?? "nil")"
                )
                return false
            }
            return await runAppleScript(lines: terminalScriptLines(for: tty))
        case "com.googlecode.iterm2":
            let iTermSessionIdentifier = clientInfo?.iTermSessionIdentifier ?? clientInfo?.terminalSessionIdentifier
            guard let selector = iTermScriptSelector(
                for: tty,
                sessionIdentifier: iTermSessionIdentifier,
                titleHint: remoteHostHint
            ) else {
                logger.debug("No iTerm session identifier or tty available for bundle \(bundleIdentifier, privacy: .public); skipping AppleScript fallback")
                await FocusDiagnosticsStore.shared.record(
                    "TerminalFocus iterm skip-no-selector terminalPid=\(terminalPid) tty=\(tty ?? "nil") sessionIdentifier=\(iTermSessionIdentifier ?? "nil")"
                )
                return false
            }

            await FocusDiagnosticsStore.shared.record(
                "TerminalFocus iterm applescript terminalPid=\(terminalPid) tty=\(tty ?? "nil") normalizedSessionIdentifier=\(normalizedITermSessionIdentifier(iTermSessionIdentifier) ?? "nil")"
            )
            guard await TerminalAutomationPermissionCoordinator.shared.ensurePermissionIfNeeded(
                terminalPid: terminalPid,
                bundleIdentifier: bundleIdentifier,
                sessionId: sessionId
            ) else {
                logger.debug("Automation permission unavailable for iTerm bundle \(bundleIdentifier, privacy: .public)")
                await FocusDiagnosticsStore.shared.record(
                    "TerminalFocus iterm skip-no-automation-permission terminalPid=\(terminalPid) sessionId=\(sessionId ?? "nil")"
                )
                return false
            }
            return await focusITermSession(terminalPid: terminalPid, selector: selector)
        case "com.mitchellh.ghostty":
            let ghosttyTerminalIdentifier = clientInfo?.terminalSessionIdentifier
            await FocusDiagnosticsStore.shared.record(
                "TerminalFocus ghostty applescript terminalPid=\(terminalPid) terminalIdentifier=\(ghosttyTerminalIdentifier ?? "nil") workspacePath=\(workspacePath ?? "nil")"
            )
            guard await TerminalAutomationPermissionCoordinator.shared.ensurePermissionIfNeeded(
                terminalPid: terminalPid,
                bundleIdentifier: bundleIdentifier,
                sessionId: sessionId
            ) else {
                logger.debug("Automation permission unavailable for Ghostty bundle \(bundleIdentifier, privacy: .public)")
                await FocusDiagnosticsStore.shared.record(
                    "TerminalFocus ghostty skip-no-automation-permission terminalPid=\(terminalPid) sessionId=\(sessionId ?? "nil")"
                )
                return false
            }
            return await focusGhosttyTerminal(
                bundleIdentifier: bundleIdentifier,
                terminalPid: terminalPid,
                terminalSessionIdentifier: ghosttyTerminalIdentifier,
                workspacePath: workspacePath,
                titleHint: remoteHostHint
            )
        case "com.cmuxterm.app":
            // cmux is based on Ghostty, reuse Ghostty focus logic
            let cmuxTerminalIdentifier = clientInfo?.terminalSessionIdentifier
            await FocusDiagnosticsStore.shared.record(
                "TerminalFocus cmux applescript terminalPid=\(terminalPid) terminalIdentifier=\(cmuxTerminalIdentifier ?? "nil") workspacePath=\(workspacePath ?? "nil")"
            )
            guard await TerminalAutomationPermissionCoordinator.shared.ensurePermissionIfNeeded(
                terminalPid: terminalPid,
                bundleIdentifier: bundleIdentifier,
                sessionId: sessionId
            ) else {
                logger.debug("Automation permission unavailable for cmux bundle \(bundleIdentifier, privacy: .public)")
                await FocusDiagnosticsStore.shared.record(
                    "TerminalFocus cmux skip-no-automation-permission terminalPid=\(terminalPid) sessionId=\(sessionId ?? "nil")"
                )
                return false
            }
            return await focusGhosttyTerminal(
                bundleIdentifier: bundleIdentifier,
                terminalPid: terminalPid,
                terminalSessionIdentifier: cmuxTerminalIdentifier,
                workspacePath: workspacePath,
                titleHint: remoteHostHint
            )
        case "io.appmakes.otty":
            // Otty 虽是 Ghostty 换皮,但脚本词汇仿 Terminal.app(tab + selected),
            // 无 Ghostty 的 terminal/focus 动词,故走独立聚焦:按 tty / 工作目录选中 tab。
            await FocusDiagnosticsStore.shared.record(
                "TerminalFocus otty applescript terminalPid=\(terminalPid) tty=\(tty ?? "nil") workspacePath=\(workspacePath ?? "nil")"
            )
            guard await TerminalAutomationPermissionCoordinator.shared.ensurePermissionIfNeeded(
                terminalPid: terminalPid,
                bundleIdentifier: bundleIdentifier,
                sessionId: sessionId
            ) else {
                logger.debug("Automation permission unavailable for Otty bundle \(bundleIdentifier, privacy: .public)")
                await FocusDiagnosticsStore.shared.record(
                    "TerminalFocus otty skip-no-automation-permission terminalPid=\(terminalPid) sessionId=\(sessionId ?? "nil")"
                )
                return false
            }
            // 优先走 otty CLI(tab list --json + tab focus <id>)——otty 的 AppleScript
            // tty 恒空、cwd 同项目重复,只有 CLI 能拿到 tab 标题精确定位。
            if await focusOttyTabViaCLI(
                terminalPid: terminalPid,
                workspacePath: workspacePath,
                titleHint: remoteHostHint
            ) {
                return true
            }
            return await focusOttyTab(
                bundleIdentifier: bundleIdentifier,
                terminalPid: terminalPid,
                tty: tty,
                workspacePath: workspacePath
            )
        default:
            logger.debug("No scripted focuser for bundle \(bundleIdentifier, privacy: .public)")
            await FocusDiagnosticsStore.shared.record(
                "TerminalFocus unsupported bundle=\(bundleIdentifier) terminalPid=\(terminalPid)"
            )
            return false
        }
    }

    func focusHostedSession(
        sessionId: String? = nil,
        clientInfo: SessionClientInfo,
        workspacePath: String? = nil
    ) async -> Bool {
        let detectedBundleIdentifier = clientInfo.terminalBundleIdentifier ?? clientInfo.bundleIdentifier
        let appName = clientInfo.originator ?? clientInfo.name
        guard let profile = ClientProfileRegistry.ideExtensionProfile(
            bundleIdentifier: detectedBundleIdentifier,
            appName: appName
        ), IDEExtensionInstaller.isInstalled(profile) else {
            return false
        }

        return await focusWithExtension(
            profile: profile,
            processIDs: [],
            tty: nil,
            sessionId: sessionId,
            clientInfo: clientInfo,
            workspacePath: workspacePath
        )
    }

    private func focusWithExtension(
        profile: ManagedIDEExtensionProfile,
        processIDs: [Int],
        tty: String?,
        sessionId: String?,
        clientInfo: SessionClientInfo?,
        workspacePath: String?
    ) async -> Bool {
        var queryItems = processIDs
            .filter { $0 > 0 }
            .map { URLQueryItem(name: "pid", value: String($0)) }

        if let sessionId = sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sessionId.isEmpty {
            queryItems.append(URLQueryItem(name: "sessionId", value: sessionId))
        }

        if let normalizedTTY = tty?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/dev/", with: ""),
           !normalizedTTY.isEmpty {
            queryItems.append(URLQueryItem(name: "tty", value: normalizedTTY))
        }

        let resolvedWorkspacePath = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolvedWorkspacePath, !resolvedWorkspacePath.isEmpty {
            queryItems.append(URLQueryItem(name: "cwd", value: resolvedWorkspacePath))
        }

        if let processName = clientInfo?.processName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !processName.isEmpty {
            queryItems.append(URLQueryItem(name: "processName", value: processName))
        }

        if let terminalSessionIdentifier = clientInfo?.terminalSessionIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !terminalSessionIdentifier.isEmpty {
            queryItems.append(URLQueryItem(name: "terminalSessionId", value: terminalSessionIdentifier))
        }

        if let iTermSessionIdentifier = clientInfo?.iTermSessionIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !iTermSessionIdentifier.isEmpty {
            queryItems.append(URLQueryItem(name: "iTermSessionId", value: iTermSessionIdentifier))
        }

        guard !queryItems.isEmpty,
              let url = IDEExtensionInstaller.makeURI(
                profile: profile,
                path: "/focus",
                queryItems: queryItems
              ) else {
            return false
        }

        return await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }

    private func runAppleScript(lines: [String]) async -> Bool {
        guard let output = await runAppleScriptWithOutput(lines: lines) else {
            return false
        }
        return output == "ok"
    }

    private func runAppleScriptWithOutput(lines: [String]) async -> String? {
        let preview = lines.joined(separator: " | ")
        logger.debug("Running AppleScript: \(preview, privacy: .public)")
        await FocusDiagnosticsStore.shared.record("TerminalFocus applescript-run \(preview)")

        return await MainActor.run {
            let source = lines.joined(separator: "\n")
            var errorInfo: NSDictionary?
            guard let script = NSAppleScript(source: source) else {
                logger.error("Failed to create AppleScript object")
                Task {
                    await FocusDiagnosticsStore.shared.record("TerminalFocus applescript-create-failed")
                }
                return nil
            }

            let result = script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                logger.error("AppleScript failed: \(String(describing: errorInfo), privacy: .public)")
                Task {
                    await FocusDiagnosticsStore.shared.record(
                        "TerminalFocus applescript-error \(String(describing: errorInfo))"
                    )
                }
                return nil
            }

            let output = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            logger.debug("AppleScript success result=\(output, privacy: .public)")
            Task {
                await FocusDiagnosticsStore.shared.record("TerminalFocus applescript-result \(output)")
            }
            return output
        }
    }

    func frontmostGhosttyTerminalSnapshot() async -> GhosttyTerminalSnapshot? {
        let frontmostBundleId = await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
        // cmux is based on Ghostty and uses the same AppleScript interface
        // (Otty 虽是 Ghostty fork,但脚本词汇仿 Terminal.app、且 tab id 非 UUID,不走此快照)
        guard let frontmostBundleId else {
            return nil
        }
        let normalizedFrontmostBundleId = frontmostBundleId.lowercased()
        let isGhosttyFrontmost = normalizedFrontmostBundleId == "com.mitchellh.ghostty"
            || normalizedFrontmostBundleId == "com.cmuxterm.app"
        guard isGhosttyFrontmost else {
            return nil
        }

        guard let output = await runAppleScriptWithOutput(
            lines: Self.ghosttyFrontmostTerminalSnapshotScriptLines(bundleIdentifier: frontmostBundleId)
        ),
              output != "not-found" else {
            return nil
        }

        return Self.parseGhosttyTerminalSnapshot(output)
    }

    private func terminalScriptLines(for tty: String) -> [String] {
        let normalizedTTY = tty.replacingOccurrences(of: "/dev/", with: "")
        let fullTTY = "/dev/\(normalizedTTY)"

        return [
            "set shortTTY to \"\(normalizedTTY)\"",
            "set fullTTY to \"\(fullTTY)\"",
            "tell application id \"com.apple.Terminal\"",
            "repeat with theWindow in windows",
            "repeat with theTab in tabs of theWindow",
            "set tabTTY to tty of theTab",
            "if tabTTY is shortTTY or tabTTY is fullTTY then",
            "set selected of theTab to true",
            "set frontmost of theWindow to true",
            "activate",
            "return \"ok\"",
            "end if",
            "end repeat",
            "end repeat",
            "return \"not-found\"",
            "end tell"
        ]
    }

    private func focusITermSession(terminalPid: Int, selector: ITermScriptSelector) async -> Bool {
        let restoreResult = await runAppleScript(lines: iTermRestoreScriptLines(for: selector))
        await FocusDiagnosticsStore.shared.record(
            "TerminalFocus iterm restore-result terminalPid=\(terminalPid) success=\(restoreResult)"
        )
        guard restoreResult else {
            return false
        }

        let waitResult = await SessionLauncher.waitForIDEWindowActivation(
            bundleIdentifiers: ["com.googlecode.iterm2"],
            timeoutNanoseconds: iTermSelectionRetryDelayNanoseconds
        )
        await FocusDiagnosticsStore.shared.record(
            "TerminalFocus iterm wait-visible terminalPid=\(terminalPid) success=\(waitResult)"
        )

        let selectionLines = iTermSelectionScriptLines(for: selector)
        if await runAppleScript(lines: selectionLines) {
            await FocusDiagnosticsStore.shared.record(
                "TerminalFocus iterm select-result terminalPid=\(terminalPid) success=true attempt=1"
            )
            return true
        }

        await FocusDiagnosticsStore.shared.record(
            "TerminalFocus iterm select-result terminalPid=\(terminalPid) success=false attempt=1"
        )
        try? await Task.sleep(nanoseconds: iTermSelectionRetryDelayNanoseconds)

        let retryResult = await runAppleScript(lines: selectionLines)
        await FocusDiagnosticsStore.shared.record(
            "TerminalFocus iterm select-result terminalPid=\(terminalPid) success=\(retryResult) attempt=2"
        )
        return retryResult
    }

    private func focusGhosttyTerminal(
        bundleIdentifier: String,
        terminalPid: Int,
        terminalSessionIdentifier: String?,
        workspacePath: String?,
        titleHint: String?
    ) async -> Bool {
        let result = await runAppleScript(lines: Self.ghosttySelectionScriptLines(
            terminalSessionIdentifier: Self.normalizedGhosttyTerminalIdentifier(terminalSessionIdentifier),
            workspacePath: workspacePath,
            titleHint: titleHint,
            bundleIdentifier: bundleIdentifier
        ))
        await FocusDiagnosticsStore.shared.record(
            "TerminalFocus ghostty select-result terminalPid=\(terminalPid) bundle=\(bundleIdentifier) success=\(result)"
        )
        return result
    }

    private func focusOttyTab(
        bundleIdentifier: String,
        terminalPid: Int,
        tty: String?,
        workspacePath: String?
    ) async -> Bool {
        let result = await runAppleScript(lines: Self.ottySelectionScriptLines(
            tty: tty,
            workspacePath: workspacePath,
            bundleIdentifier: bundleIdentifier
        ))
        await FocusDiagnosticsStore.shared.record(
            "TerminalFocus otty select-result terminalPid=\(terminalPid) bundle=\(bundleIdentifier) success=\(result)"
        )
        return result
    }

    // MARK: - Otty CLI 精确切换

    /// otty 的 AppleScript tty 恒空、working directory 同项目重复,且一个 tab 里常有多个
    /// 分屏 pane(每个 pane 跑一个 CC 会话),tab focus 切不进具体 pane。
    /// 改用 otty 官方控制 CLI:`pane list --json` 拿每个 pane 的 id/cwd/process(=会话标题),
    /// `pane focus <id>` 切到具体分屏(会自动带出所属 tab)。
    /// 匹配:① cwd 唯一命中 → 直接切;② 同 cwd 多 pane → 用标题(剥掉 otty 状态前缀)唯一命中切;
    /// 都不唯一 → 返回 false,交回 AppleScript 兜底(至少 activate)。
    private func focusOttyTabViaCLI(
        terminalPid: Int,
        workspacePath: String?,
        titleHint: String?
    ) async -> Bool {
        guard let cliPath = Self.ottyCLIPath() else {
            await FocusDiagnosticsStore.shared.record(
                "TerminalFocus otty-cli skip-no-binary terminalPid=\(terminalPid)"
            )
            return false
        }

        guard let listOutput = await Self.runProcess(
            executable: cliPath,
            arguments: ["pane", "list", "--json"]
        ), let panes = Self.parseOttyPanes(json: listOutput), !panes.isEmpty else {
            await FocusDiagnosticsStore.shared.record(
                "TerminalFocus otty-cli skip-list-failed terminalPid=\(terminalPid)"
            )
            return false
        }

        guard let paneId = Self.selectOttyPaneId(
            panes: panes,
            workspacePath: workspacePath,
            titleHint: titleHint
        ) else {
            await FocusDiagnosticsStore.shared.record(
                "TerminalFocus otty-cli no-unique-match terminalPid=\(terminalPid) cwd=\(workspacePath ?? "nil") title=\(titleHint ?? "nil") paneCount=\(panes.count)"
            )
            return false
        }

        let focusOK = await Self.runProcess(
            executable: cliPath,
            arguments: ["pane", "focus", paneId, "--quiet"]
        ) != nil
        // focus 后把 otty 提到前台
        if focusOK {
            await MainActor.run {
                NSRunningApplication(processIdentifier: pid_t(terminalPid))?
                    .activate(options: [.activateAllWindows])
            }
        }
        await FocusDiagnosticsStore.shared.record(
            "TerminalFocus otty-cli focus terminalPid=\(terminalPid) pane=\(paneId) success=\(focusOK)"
        )
        return focusOK
    }

    struct OttyPane {
        let id: String
        let cwd: String
        let title: String
    }

    /// 解析 `otty pane list --json` 输出。pane 的 `process` 字段即 CC 会话标题。
    static func parseOttyPanes(json: String) -> [OttyPane]? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["data"] as? [[String: Any]] else {
            return nil
        }
        return arr.compactMap { item in
            guard let id = item["id"] as? String, !id.isEmpty else { return nil }
            return OttyPane(
                id: id,
                cwd: (item["cwd"] as? String) ?? "",
                title: (item["process"] as? String) ?? ""
            )
        }
    }

    /// 按 cwd → 标题 的顺序选出唯一 pane id;无法唯一定位返回 nil。
    static func selectOttyPaneId(
        panes: [OttyPane],
        workspacePath: String?,
        titleHint: String?
    ) -> String? {
        let cwd = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cwdMatches: [OttyPane]
        if let cwd, !cwd.isEmpty {
            cwdMatches = panes.filter { $0.cwd == cwd }
        } else {
            cwdMatches = panes
        }
        if cwdMatches.count == 1 { return cwdMatches[0].id }

        let pool = cwdMatches.isEmpty ? panes : cwdMatches
        if let hint = normalizedOttyTitle(titleHint), !hint.isEmpty {
            let titleMatches = pool.filter { pane in
                guard let t = normalizedOttyTitle(pane.title), !t.isEmpty else { return false }
                return t == hint || t.contains(hint) || hint.contains(t)
            }
            if titleMatches.count == 1 { return titleMatches[0].id }
        }
        return nil
    }

    /// 剥掉 otty 给标题加的状态字形前缀(✳ / spinner ⠦⠧… / 空白),便于与会话标题比较。
    static func normalizedOttyTitle(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let statusGlyphs = Set("✳✶✦✧⠁⠂⠄⡀⢀⠠⠐⠈⠿⠻⠽⠾⠷⠯⠟⠏⠛⠹⠸⠼⠴⠦⠧⠇◐◓◑◒●○◍◌⣾⣽⣻⢿⡿⣟⣯⣷")
        var s = Substring(raw)
        while let first = s.first, first.isWhitespace || statusGlyphs.contains(first) {
            s = s.dropFirst()
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// otty 控制 CLI 路径:优先固定路径,回退到已运行 app 包内。
    static func ottyCLIPath() -> String? {
        let fixed = "/Applications/Otty.app/Contents/MacOS/otty-cli"
        if FileManager.default.isExecutableFile(atPath: fixed) { return fixed }
        if let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "io.appmakes.otty"
        ) {
            let candidate = appURL.appendingPathComponent("Contents/MacOS/otty-cli").path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// 跑一个短命进程,3s 超时,成功(exit 0)返回 stdout,失败返回 nil。
    static func runProcess(executable: String, arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: timeout)

            process.terminationHandler = { proc in
                timeout.cancel()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            do {
                try process.run()
            } catch {
                timeout.cancel()
                continuation.resume(returning: nil)
            }
        }
    }

    private struct ITermScriptSelector {
        let sessionIdentifier: String?
        let tty: String?
        let titleHint: String?
    }

    private nonisolated func iTermScriptSelector(
        for tty: String?,
        sessionIdentifier: String?,
        titleHint: String? = nil
    ) -> ITermScriptSelector? {
        let normalizedSessionIdentifier = normalizedITermSessionIdentifier(sessionIdentifier)
        let normalizedTTY = tty?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/dev/", with: "")
        let usableTTY = normalizedTTY?.isEmpty == false ? normalizedTTY : nil
        let usableSessionIdentifier = normalizedSessionIdentifier?.isEmpty == false
            ? normalizedSessionIdentifier
            : nil
        let usableTitleHint: String?
        if usableTTY == nil && usableSessionIdentifier == nil,
           let trimmedTitleHint = titleHint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedTitleHint.isEmpty {
            usableTitleHint = trimmedTitleHint
        } else {
            usableTitleHint = nil
        }

        guard usableSessionIdentifier != nil || usableTTY != nil || usableTitleHint != nil else {
            return nil
        }

        return ITermScriptSelector(
            sessionIdentifier: usableSessionIdentifier,
            tty: usableTTY,
            titleHint: usableTitleHint
        )
    }

    private nonisolated func iTermRestoreScriptLines(for selector: ITermScriptSelector) -> [String] {
        if selector.tty == nil,
           selector.sessionIdentifier == nil,
           selector.titleHint?.isEmpty == false {
            return iTermUniqueTitleScriptLines(selector: selector, restoreWindowOnly: true)
        }

        var lines: [String] = [
            "tell application id \"com.googlecode.iterm2\"",
            "repeat with theWindow in windows",
            "repeat with theTab in tabs of theWindow",
            "repeat with theSession in sessions of theTab"
        ]

        appendITermSelectorMatch(lines: &lines, selector: selector) {
            [
                "set targetWindowId to (id of theWindow)",
                "set resolvedWindow to first window whose id is targetWindowId",
                "set miniaturized of resolvedWindow to false",
                "select resolvedWindow",
                "activate",
                "return \"ok\""
            ]
        }

        lines.append(contentsOf: [
            "end repeat",
            "end repeat",
            "end repeat",
            "return \"not-found\"",
            "end tell"
        ])

        return lines
    }

    private nonisolated func iTermSelectionScriptLines(for selector: ITermScriptSelector) -> [String] {
        if selector.tty == nil,
           selector.sessionIdentifier == nil,
           selector.titleHint?.isEmpty == false {
            return iTermUniqueTitleScriptLines(selector: selector, restoreWindowOnly: false)
        }

        var lines: [String] = [
            "tell application id \"com.googlecode.iterm2\"",
            "repeat with theWindow in windows",
            "repeat with theTab in tabs of theWindow",
            "repeat with theSession in sessions of theTab"
        ]

        appendITermSelectorMatch(lines: &lines, selector: selector) {
            [
                "set targetWindowId to (id of theWindow)",
                "set resolvedWindow to first window whose id is targetWindowId",
                "select theTab",
                "select theSession",
                "select resolvedWindow",
                "activate",
                "return \"ok\""
            ]
        }

        lines.append(contentsOf: [
            "end repeat",
            "end repeat",
            "end repeat",
            "return \"not-found\"",
            "end tell"
        ])

        return lines
    }

    private nonisolated func appendITermSelectorMatch(
        lines: inout [String],
        selector: ITermScriptSelector,
        body: () -> [String]
    ) {
        if let usableSessionIdentifier = selector.sessionIdentifier {
            lines.append(contentsOf: [
                "try",
                "if (id of theSession as text) is \"\(usableSessionIdentifier)\" then"
            ])
            lines.append(contentsOf: body())
            lines.append(contentsOf: [
                "end if",
                "end try"
            ])
        }

        if let usableTTY = selector.tty {
            let fullTTY = "/dev/\(usableTTY)"
            lines.append(contentsOf: [
                "set sessionTTY to tty of theSession",
                "if sessionTTY is \"\(usableTTY)\" or sessionTTY is \"\(fullTTY)\" then"
            ])
            lines.append(contentsOf: body())
            lines.append("end if")
        }
    }

    private nonisolated func iTermUniqueTitleScriptLines(
        selector: ITermScriptSelector,
        restoreWindowOnly: Bool
    ) -> [String] {
        guard let titleHint = selector.titleHint else {
            return []
        }

        let body: [String]
        if restoreWindowOnly {
            body = [
                "set targetWindowId to (id of theWindow)",
                "set resolvedWindow to first window whose id is targetWindowId",
                "set miniaturized of resolvedWindow to false",
                "select resolvedWindow",
                "activate",
                "return \"ok\""
            ]
        } else {
            body = [
                "set targetWindowId to (id of theWindow)",
                "set resolvedWindow to first window whose id is targetWindowId",
                "select theTab",
                "select theSession",
                "select resolvedWindow",
                "activate",
                "return \"ok\""
            ]
        }

        var lines: [String] = [
            "tell application id \"com.googlecode.iterm2\"",
            "set targetHint to \(Self.appleScriptStringLiteral(titleHint))",
            "set matchingSessionIDs to {}",
            "repeat with theWindow in windows",
            "repeat with theTab in tabs of theWindow",
            "repeat with theSession in sessions of theTab",
            "try",
            "set sessionName to (name of theSession as text)",
            "if sessionName contains targetHint then",
            "copy (id of theSession as text) to end of matchingSessionIDs",
            "end if",
            "end try",
            "end repeat",
            "end repeat",
            "end repeat",
            "if (count of matchingSessionIDs) is not 1 then",
            "return \"not-found\"",
            "end if",
            "set targetSessionID to item 1 of matchingSessionIDs",
            "repeat with theWindow in windows",
            "repeat with theTab in tabs of theWindow",
            "repeat with theSession in sessions of theTab",
            "try",
            "if (id of theSession as text) is targetSessionID then"
        ]

        lines.append(contentsOf: body)
        lines.append(contentsOf: [
            "end if",
            "end try",
            "end repeat",
            "end repeat",
            "end repeat",
            "return \"not-found\"",
            "end tell"
        ])

        return lines
    }

    static func iTermSelectionScriptLinesForTesting(tty: String?, sessionIdentifier: String?) -> [String] {
        let focuser = TerminalSessionFocuser.shared
        guard let selector = focuser.iTermScriptSelector(for: tty, sessionIdentifier: sessionIdentifier) else {
            return []
        }
        return focuser.iTermSelectionScriptLines(for: selector)
    }

    static func iTermSelectionScriptLinesForTesting(
        tty: String?,
        sessionIdentifier: String?,
        titleHint: String?
    ) -> [String] {
        let focuser = TerminalSessionFocuser.shared
        guard let selector = focuser.iTermScriptSelector(
            for: tty,
            sessionIdentifier: sessionIdentifier,
            titleHint: titleHint
        ) else {
            return []
        }
        return focuser.iTermSelectionScriptLines(for: selector)
    }

    static func ghosttySelectionScriptLines(
        terminalSessionIdentifier: String?,
        workspacePath: String?,
        titleHint: String? = nil,
        bundleIdentifier: String = "com.mitchellh.ghostty"
    ) -> [String] {
        var lines = [
            "tell application id \(appleScriptStringLiteral(bundleIdentifier))"
        ]

        if let terminalSessionIdentifier = normalizedGhosttyTerminalIdentifier(terminalSessionIdentifier) {
            lines.append(contentsOf: [
                "set targetTerminalID to \(appleScriptStringLiteral(terminalSessionIdentifier))",
                "try",
                "set targetTerminal to first terminal whose id is targetTerminalID",
                "focus targetTerminal",
                "return \"ok\"",
                "end try"
            ])
        }

        if let workspacePath = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workspacePath.isEmpty {
            let projectName = URL(fileURLWithPath: workspacePath).lastPathComponent
            lines.append(contentsOf: [
                "set targetPath to \(appleScriptStringLiteral(workspacePath))",
                "set targetName to \(appleScriptStringLiteral(projectName))",
                "set exactMatches to every terminal whose working directory is targetPath",
                "if (count of exactMatches) is 1 then",
                "focus (item 1 of exactMatches)",
                "return \"ok\"",
                "end if",
                "set pathMatches to every terminal whose working directory contains targetPath",
                "if (count of pathMatches) is 1 then",
                "focus (item 1 of pathMatches)",
                "return \"ok\"",
                "end if",
                "if targetName is not \"\" then",
                "set nameMatches to every terminal whose name contains targetName",
                "if (count of nameMatches) is 1 then",
                "focus (item 1 of nameMatches)",
                "return \"ok\"",
                "end if",
                "end if"
            ])
        }

        if let titleHint = titleHint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !titleHint.isEmpty {
            lines.append(contentsOf: [
                "set remoteTitleHint to \(appleScriptStringLiteral(titleHint))",
                "set titleMatches to every terminal whose name contains remoteTitleHint",
                "if (count of titleMatches) is 1 then",
                "focus (item 1 of titleMatches)",
                "return \"ok\"",
                "end if"
            ])
        }

        lines.append(contentsOf: [
            "activate",
            "return \"ok\"",
            "end tell"
        ])

        return lines
    }

    /// Otty 的 AppleScript 字典仿 Terminal.app:tab 类带 tty / working directory,
    /// tab 的 `selected` 属性可写(置 true 即切到该 tab)。按 tty → 工作目录(唯一匹配)
    /// 选中会话所在 tab,并把其所在窗口提到最前;都没命中则只 activate。
    static func ottySelectionScriptLines(
        tty: String?,
        workspacePath: String?,
        bundleIdentifier: String = "io.appmakes.otty"
    ) -> [String] {
        let ttyName = tty?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/dev/", with: "") ?? ""
        let targetPath = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let lines = [
            "tell application id \(appleScriptStringLiteral(bundleIdentifier))",
            "set ttyName to \(appleScriptStringLiteral(ttyName))",
            "set targetPath to \(appleScriptStringLiteral(targetPath))",
            "set matchedTab to missing value",
            "set matchedWindow to missing value",
            "set matchCount to 0",
            // 第一优先:tty 精确命中(Otty 有时不上报 tty,命中就直接切)
            "if ttyName is not \"\" then",
            "repeat with w in windows",
            "repeat with t in tabs of w",
            "set tv to \"\"",
            "try",
            "set tv to (tty of t) as text",
            "end try",
            "if tv is not \"\" and tv ends with ttyName then",
            "set selected of t to true",
            "try",
            "set index of w to 1",
            "end try",
            "activate",
            "return \"ok\"",
            "end if",
            "end repeat",
            "end repeat",
            "end if",
            // 次优先:工作目录唯一匹配
            "if targetPath is not \"\" then",
            "repeat with w in windows",
            "repeat with t in tabs of w",
            "set cw to \"\"",
            "try",
            "set cw to (working directory of t) as text",
            "end try",
            "if cw is targetPath then",
            "set matchCount to matchCount + 1",
            "set matchedTab to t",
            "set matchedWindow to w",
            "end if",
            "end repeat",
            "end repeat",
            "if matchCount is 1 then",
            "set selected of matchedTab to true",
            "try",
            "set index of matchedWindow to 1",
            "end try",
            "activate",
            "return \"ok\"",
            "end if",
            "end if",
            // 兜底:切不到具体 tab 也至少把 Otty 拉到前台
            "activate",
            "return \"ok\"",
            "end tell"
        ]

        return lines
    }

    static func ghosttyFrontmostTerminalSnapshotScriptLines(
        bundleIdentifier: String = "com.mitchellh.ghostty"
    ) -> [String] {
        [
            "tell application id \(appleScriptStringLiteral(bundleIdentifier))",
            "try",
            "set targetWindow to front window",
            "set targetTab to selected tab of targetWindow",
            "set targetTerminal to focused terminal of targetTab",
            "set targetTerminalID to (id of targetTerminal as text)",
            "set targetWorkingDirectory to \"\"",
            "try",
            "set targetWorkingDirectory to (working directory of targetTerminal as text)",
            "end try",
            "set targetTerminalName to \"\"",
            "try",
            "set targetTerminalName to (name of targetTerminal as text)",
            "end try",
            "return targetTerminalID & linefeed & targetWorkingDirectory & linefeed & targetTerminalName",
            "on error",
            "return \"not-found\"",
            "end try",
            "end tell"
        ]
    }

    static func parseGhosttyTerminalSnapshot(_ output: String) -> GhosttyTerminalSnapshot? {
        let lines = output.components(separatedBy: .newlines)
        guard let terminalSessionIdentifier = sanitizedNonEmpty(lines.first) else {
            return nil
        }

        let workingDirectory = lines.count > 1 ? sanitizedNonEmpty(lines[1]) : nil
        let title = lines.count > 2 ? sanitizedNonEmpty(lines[2]) : nil
        return GhosttyTerminalSnapshot(
            terminalSessionIdentifier: terminalSessionIdentifier,
            workingDirectory: workingDirectory,
            title: title
        )
    }

    static func normalizedGhosttyTerminalIdentifier(_ terminalSessionIdentifier: String?) -> String? {
        guard let trimmedIdentifier = terminalSessionIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmedIdentifier.isEmpty else {
            return nil
        }

        guard UUID(uuidString: trimmedIdentifier.uppercased()) != nil else {
            return nil
        }

        return trimmedIdentifier.uppercased()
    }

    static func ghosttyWorkingDirectoryMatches(
        snapshotWorkingDirectory: String?,
        workspacePath: String?
    ) -> Bool {
        guard let normalizedSnapshot = normalizedComparablePath(snapshotWorkingDirectory),
              let normalizedWorkspace = normalizedComparablePath(workspacePath) else {
            return false
        }

        if normalizedSnapshot == normalizedWorkspace {
            return true
        }

        return normalizedSnapshot.hasPrefix(normalizedWorkspace + "/")
            || normalizedWorkspace.hasPrefix(normalizedSnapshot + "/")
    }

    private static func normalizedComparablePath(_ value: String?) -> String? {
        guard let trimmed = sanitizedNonEmpty(value) else {
            return nil
        }

        let standardized = URL(fileURLWithPath: trimmed).resolvingSymlinksInPath().standardizedFileURL.path
        return NSString(string: standardized).standardizingPath.lowercased()
    }

    private static func sanitizedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private nonisolated func normalizedITermSessionIdentifier(_ sessionIdentifier: String?) -> String? {
        guard let rawValue = sessionIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawValue.isEmpty else {
            return nil
        }

        if let suffix = rawValue.split(separator: ":", omittingEmptySubsequences: false).last,
           !suffix.isEmpty {
            return String(suffix)
        }

        return rawValue
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
