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

        Window("tictic", id: "settings") {
            SettingsView(state: state)
                .frame(minWidth: 790, minHeight: 590)
                .onAppear { state.refreshPermissions() }
        }
        .defaultSize(width: 860, height: 650)
        .windowResizability(.contentMinSize)
    }

    init() {
        let appState = AppState()
        _state = StateObject(wrappedValue: appState)
        DispatchQueue.main.async { appState.start() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
