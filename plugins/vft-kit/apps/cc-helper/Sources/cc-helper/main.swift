import AppKit

MainActor.assumeIsolated {
    // 单实例守卫:.app 被双击/登录项重复拉起时,已有实例则退出,避免双状态项抢占
    if let bundleID = Bundle.main.bundleIdentifier,
       NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
        exit(0)
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)  // LSUIElement:无 Dock 图标、无主窗口
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
