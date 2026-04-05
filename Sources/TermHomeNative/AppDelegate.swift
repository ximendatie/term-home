import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = StatusStore()
    private var panel: TopCapsulePanel?
    private var screenObserver: Any?

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

    func applicationWillTerminate(_ notification: Notification) {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

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
