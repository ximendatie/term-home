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
        ignoresMouseEvents = true
    }

    /// 允许面板在需要时成为键窗口。
    override var canBecomeKey: Bool { true }
    /// 阻止面板成为应用主窗口。
    override var canBecomeMain: Bool { false }

    /// 当展开态点击到岛体外部区域时，将事件透传给下层窗口。
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .leftMouseUp ||
            event.type == .rightMouseDown || event.type == .rightMouseUp {
            let locationInWindow = event.locationInWindow

            if let contentView, contentView.hitTest(locationInWindow) == nil {
                let screenLocation = convertPoint(toScreen: locationInWindow)
                ignoresMouseEvents = true

                DispatchQueue.main.async { [weak self] in
                    self?.repostMouseEvent(event, at: screenLocation)
                }
                return
            }
        }

        super.sendEvent(event)
    }

    /// 将岛体外部的鼠标事件重新投递给底层窗口。
    private func repostMouseEvent(_ event: NSEvent, at screenLocation: NSPoint) {
        guard let screen = NSScreen.main else { return }
        let screenHeight = screen.frame.height
        let cgPoint = CGPoint(x: screenLocation.x, y: screenHeight - screenLocation.y)

        let mouseType: CGEventType
        switch event.type {
        case .leftMouseDown: mouseType = .leftMouseDown
        case .leftMouseUp: mouseType = .leftMouseUp
        case .rightMouseDown: mouseType = .rightMouseDown
        case .rightMouseUp: mouseType = .rightMouseUp
        default: return
        }

        let mouseButton: CGMouseButton =
            event.type == .rightMouseDown || event.type == .rightMouseUp ? .right : .left

        if let cgEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: mouseType,
            mouseCursorPosition: cgPoint,
            mouseButton: mouseButton
        ) {
            cgEvent.post(tap: .cghidEventTap)
        }
    }
}
