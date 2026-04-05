import AppKit
import SwiftUI

/// 只在岛体实际区域接收点击，其余区域透传到底层窗口的 HostingView。
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var hitTestRect: () -> CGRect = { .zero }

    /// 只让岛体矩形内的区域响应鼠标事件。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitTestRect().contains(point) else {
            return nil
        }
        return super.hitTest(point)
    }
}

/// 作为顶部全宽透明宿主使用的无边框面板。
final class TopCapsulePanel: NSPanel {
    /// 创建覆盖屏幕顶部的透明面板。
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
        hidesOnDeactivate = false
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        level = .mainMenu + 3
        allowsToolTipsWhenApplicationIsInactive = true
    }

    /// 允许面板在需要时成为键窗口。
    override var canBecomeKey: Bool { true }
    /// 阻止面板成为应用主窗口。
    override var canBecomeMain: Bool { false }
}
