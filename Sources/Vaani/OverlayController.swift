import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayController {
    private let panel: NSPanel
    private var cancellable: AnyCancellable?

    init(state: AppState) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        panel.contentView = NSHostingView(rootView: RecordingOverlay(state: state))

        cancellable = state.$phase.sink { [weak self] phase in
            guard let self else { return }
            switch phase {
            case .idle: self.panel.orderOut(nil)
            default:
                self.positionPanel()
                self.panel.orderFrontRegardless()
            }
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY + 44
        ))
    }
}
