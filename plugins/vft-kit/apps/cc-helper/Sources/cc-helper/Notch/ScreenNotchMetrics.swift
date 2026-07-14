//  照搬自 ping-island: PingIsland/Core/ScreenNotchMetrics.swift
//  用系统 safeArea + 辅助区宽度反推物理刘海尺寸。

import CoreGraphics

struct ScreenNotchMetrics: Equatable {
    static let fallbackClosedHeight: CGFloat = 32
    static let fallbackNotchWidth: CGFloat = 180
    static let fallbackSize = CGSize(width: 224, height: 38)

    let size: CGSize
    let hasPhysicalNotch: Bool

    var closedHeight: CGFloat {
        hasPhysicalNotch ? size.height : Self.fallbackClosedHeight
    }

    static func detect(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?
    ) -> ScreenNotchMetrics {
        let detectedHeight = ceil(safeAreaTop)
        guard detectedHeight > 0 else {
            return ScreenNotchMetrics(size: Self.fallbackSize, hasPhysicalNotch: false)
        }

        let leftPadding = max(0, auxiliaryTopLeftWidth ?? 0)
        let rightPadding = max(0, auxiliaryTopRightWidth ?? 0)
        let detectedWidth: CGFloat

        if leftPadding > 0, rightPadding > 0 {
            // 真实刘海宽 = 屏宽 - 左右菜单栏可用区。
            // 注意:不再套 max(fallbackNotchWidth, …) 下限——那会把真刘海(可能仅 ~141pt)
            // 强行撑到 180pt,导致内容外溢到真刘海之外、看起来变宽。直接用实测宽度贴合硬件刘海。
            detectedWidth = max(1, ceil(screenFrame.width - leftPadding - rightPadding))
        } else {
            detectedWidth = Self.fallbackNotchWidth
        }

        return ScreenNotchMetrics(
            size: CGSize(width: detectedWidth, height: detectedHeight),
            hasPhysicalNotch: true
        )
    }
}
