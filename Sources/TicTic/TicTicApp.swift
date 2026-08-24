import AppKit
import SwiftUI

@main
struct TicTicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state: AppState

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Image(systemName: state.phase.isRecording ? "waveform.circle.fill" : "waveform.circle")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        let appState = AppState()
        _state = StateObject(wrappedValue: appState)
        AppDelegate.appState = appState
        DispatchQueue.main.async { appState.start() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    static var appState: AppState?

    private var settingsWindow: NSWindow?

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async { [weak self] in self?.showSettingsWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    func showSettingsWindow() {
        guard let state = Self.appState else { return }
        state.refreshPermissions()

        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 650),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "tictic"
            window.minSize = NSSize(width: 790, height: 590)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("tictic.settings")
            window.contentView = NSHostingView(rootView: SettingsView(state: state))
            window.center()
            settingsWindow = window
        }

        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
