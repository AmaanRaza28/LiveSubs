import AppKit
import SwiftUI

@MainActor
final class SubtitlePanelController {
    private let panel: SubtitlePanel

    init(model: AppModel) {
        let savedFrame = NSRect(x: 190, y: 90, width: 900, height: 150)
        panel = SubtitlePanel(
            contentRect: savedFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = NSHostingView(
            rootView: SubtitleOverlay().environment(model)
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.setFrameAutosaveName("LiveSubsSubtitlePanel")
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private final class SubtitlePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
