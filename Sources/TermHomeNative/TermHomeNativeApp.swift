import SwiftUI

/// 原生 macOS 壳层目标的应用入口。
@main
struct TermHomeNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// 保持应用场景最小化，因为悬浮面板由 AppKit 直接管理。
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
