import AppKit
import SwiftUI

/// 作为胶囊 / notch 宿主窗口使用的无边框顶层面板。
final class TopCapsulePanel: NSPanel {
    /// 创建承载 SwiftUI 胶囊内容的透明面板。
    init(rootView: some View) {
        super.init(
            contentRect: .init(x: 0, y: 0, width: 360, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        contentView = NSHostingView(rootView: rootView)
    }

    /// 允许面板在需要时接收键盘事件。
    override var canBecomeKey: Bool { true }
    /// 防止面板变成应用的主文档窗口。
    override var canBecomeMain: Bool { false }
}
