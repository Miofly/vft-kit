//  照搬自 ping-island: PingIsland/UI/Window/NotchWindow.swift(精简版)
//  透明、无边框、非激活、盖在菜单栏之上、鼠标穿透。hover 用全局监听,不靠窗口自己收事件。

import AppKit

final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        level = .mainMenu + 3
        allowsToolTipsWhenApplicationIsInactive = true
        ignoresMouseEvents = true            // 纯展示,全靠全局鼠标监听判断 hover
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
