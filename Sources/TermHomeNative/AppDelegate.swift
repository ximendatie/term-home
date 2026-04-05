import AppKit
import SwiftUI

/// 管理原生应用生命周期，并负责顶部胶囊窗口的定位。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = StatusStore()
    private var panel: TopCapsulePanel?
    private var screenObserver: Any?

    /// 启动常驻应用，绑定状态存储与窗口，并显示顶部胶囊。
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panel = TopCapsulePanel(rootView: CapsuleRootView(store: store))
        self.panel = panel

        store.onLayoutChange = { [weak self] in
            self?.layoutPanel(animated: true)
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.layoutPanel(animated: false)
            }
        }

        layoutPanel(animated: false)
        panel.orderFrontRegardless()
    }

    /// 在应用退出前移除屏幕变化观察者。
    func applicationWillTerminate(_ notification: Notification) {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    /// 根据当前屏幕和展开状态重新计算胶囊窗口位置与尺寸。
    private func layoutPanel(animated: Bool) {
        guard let panel else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let width: CGFloat = store.isExpanded ? 520 : 360
        let height: CGFloat = store.isExpanded ? 196 : 56
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.midX - width / 2,
            y: frame.maxY - height - 10
        )
        let target = NSRect(origin: origin, size: NSSize(width: width, height: height))

        if animated {
            panel.animator().setFrame(target, display: true)
        } else {
            panel.setFrame(target, display: true)
        }
    }
}
