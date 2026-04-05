import AppKit
import SwiftUI

final class TopCapsulePanel: NSPanel {
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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
