import AppKit
import SwiftUI

/// 管理原生应用生命周期，并负责顶部全宽窗口与岛体命中区域。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = StatusStore()
    private var panel: TopCapsulePanel?
    private var hostingView: PassThroughHostingView<CapsuleRootView>?
    private var screenObserver: Any?

    /// 启动常驻应用，创建全宽顶部窗口并展示岛体视图。
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        let windowHeight: CGFloat = 420
        let windowFrame = NSRect(
            x: frame.minX,
            y: frame.maxY - windowHeight,
            width: frame.width,
            height: windowHeight
        )

        let panel = TopCapsulePanel(contentRect: windowFrame)
        let hostingView = PassThroughHostingView(rootView: CapsuleRootView(store: store))
        self.panel = panel
        self.hostingView = hostingView

        panel.delegate = self
        hostingView.frame = NSRect(origin: .zero, size: windowFrame.size)
        panel.contentView = hostingView
        panel.setFrame(windowFrame, display: true)

        store.onLayoutChange = { [weak self] in
            self?.updateHitTestRect()
            self?.syncPanelActivation()
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.repositionWindow()
            }
        }

        repositionWindow()
        panel.orderFrontRegardless()
    }

    /// 在应用退出前移除屏幕变化观察者。
    func applicationWillTerminate(_ notification: Notification) {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    /// 在屏幕变化后重设窗口尺寸与位置，并同步命中区域。
    private func repositionWindow() {
        guard let panel else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let frame = screen.frame
        let windowHeight: CGFloat = 420
        let windowFrame = NSRect(
            x: frame.minX,
            y: frame.maxY - windowHeight,
            width: frame.width,
            height: windowHeight
        )

        panel.setFrame(windowFrame, display: true)
        hostingView?.frame = NSRect(origin: .zero, size: windowFrame.size)
        updateHitTestRect()
    }

    /// 将可点击区域限制在居中的岛体范围内，其他顶部区域继续透传。
    private func updateHitTestRect() {
        guard let hostingView else { return }

        hostingView.hitTestRect = { [weak self, weak hostingView] in
            guard let self, let hostingView else { return .zero }
            let bounds = hostingView.bounds
            let islandSize = store.preferredPanelSize
            let x = (bounds.width - islandSize.width) / 2
            let y = bounds.height - islandSize.height
            return CGRect(x: x, y: y, width: islandSize.width, height: islandSize.height)
        }
    }

    /// 在展开和收起之间同步面板焦点，让失焦收起可以稳定触发。
    private func syncPanelActivation() {
        guard let panel else { return }

        if store.isExpanded {
            panel.orderFrontRegardless()
            panel.makeKey()
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// 在面板失去焦点时自动收起，保持与参考实现一致的交互模型。
    func windowDidResignKey(_ notification: Notification) {
        store.collapse()
    }
}
