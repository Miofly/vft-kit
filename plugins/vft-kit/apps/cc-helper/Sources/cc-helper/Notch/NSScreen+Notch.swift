//  照搬自 ping-island: PingIsland/Core/Ext+NSScreen.swift

import AppKit

extension NSScreen {
    var notchMetrics: ScreenNotchMetrics {
        ScreenNotchMetrics.detect(
            screenFrame: frame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeftWidth: auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: auxiliaryTopRightArea?.width
        )
    }

    var notchSize: CGSize { notchMetrics.size }

    var isBuiltinDisplay: Bool {
        guard let n = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(n) != 0
    }

    static var builtin: NSScreen? {
        screens.first(where: { $0.isBuiltinDisplay }) ?? NSScreen.main
    }

    var hasPhysicalNotch: Bool { notchMetrics.hasPhysicalNotch }
}
