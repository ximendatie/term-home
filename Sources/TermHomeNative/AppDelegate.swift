import AppKit
import SwiftUI

/// 管理原生应用生命周期，并负责顶部全宽窗口与岛体命中区域。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = StatusStore()
    private var panel: TopCapsulePanel?
    private var hostingView: PassThroughHostingView<CapsuleRootView>?
    private var screenObserver: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

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
        syncPanelActivation()
        installGlobalMouseMonitor()
        installLocalMouseMonitor()
    }

    /// 在应用退出前移除屏幕变化观察者。
    func applicationWillTerminate(_ notification: Notification) {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
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
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: false)
            panel.makeKey()
        } else {
            panel.ignoresMouseEvents = true
            panel.orderFrontRegardless()
        }
    }

    /// 安装全局鼠标监听，在收起态命中岛体时展开，在展开态点击外部时收起。
    private func installGlobalMouseMonitor() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseDown(screenPoint: self?.screenPoint(for: event) ?? event.locationInWindow)
            }
        }
    }

    /// 安装本地鼠标监听，保证当前 app 激活时也能遵循同一套交互规则。
    private func installLocalMouseMonitor() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleMouseDown(screenPoint: self.screenPoint(for: event))
            }
            return event
        }
    }

    /// 统一将本地或全局鼠标事件转换为屏幕坐标，避免窗口内点击被误判为外部点击。
    private func screenPoint(for event: NSEvent) -> NSPoint {
        if let window = event.window {
            return window.convertPoint(toScreen: event.locationInWindow)
        }
        return event.locationInWindow
    }

    /// 统一处理鼠标点击的展开和收起逻辑。
    private func handleMouseDown(screenPoint: NSPoint) {
        guard let panel else { return }
        let screenHitRect = hitTestRectInScreenCoordinates(for: panel)

        if store.isExpanded {
            guard !store.shouldIgnoreImmediateCollapse() else { return }
            guard !screenHitRect.contains(screenPoint) else { return }
            store.collapse()
            return
        }

        guard screenHitRect.contains(screenPoint) else { return }
        store.expand()
    }

    /// 将当前岛体命中区域转换为屏幕坐标，供全局交互逻辑复用。
    private func hitTestRectInScreenCoordinates(for panel: TopCapsulePanel) -> CGRect {
        guard let hostingView else { return .zero }
        let hitRect = hostingView.hitTestRect()
        let windowFrame = panel.frame
        return CGRect(
            x: windowFrame.minX + hitRect.minX,
            y: windowFrame.minY + hitRect.minY,
            width: hitRect.width,
            height: hitRect.height
        )
    }

    /// 在面板失去焦点时自动收起，保持与参考实现一致的交互模型。
    func windowDidResignKey(_ notification: Notification) {
        guard store.isExpanded else { return }
        guard !store.shouldIgnoreImmediateCollapse() else { return }
        store.collapse()
    }
}
