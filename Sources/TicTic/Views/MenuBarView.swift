import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var preferences: Preferences
    @Environment(\.openWindow) private var openWindow

    init(state: AppState) {
        self.state = state
        preferences = state.preferences
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                BrandMark(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("tictic").font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(state.statusMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Circle()
                    .fill(state.hasAPIKey ? .green : .orange)
                    .frame(width: 7, height: 7)
            }
            .padding(14)

            Divider()

            VStack(spacing: 10) {
                Button(action: state.toggleRecording) {
                    HStack {
                        Image(systemName: state.phase.isRecording ? "stop.fill" : "mic.fill")
                        Text(state.phase.isRecording ? "Finish dictation" : "Start dictation")
                        Spacer()
                        Text(preferences.hotkey.title)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)

                HStack {
                    Label(preferences.language.title, systemImage: "character.bubble")
                    Spacer()
                    Text(preferences.mode.title).foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 4)
            }
            .padding(12)

            Divider()

            HStack {
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
        }
        .frame(width: 310)
    }
}

struct BrandMark: View {
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 1, green: 0.58, blue: 0.2), Color(red: 0.91, green: 0.18, blue: 0.37)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            HStack(spacing: size * 0.055) {
                ForEach([0.38, 0.65, 0.95, 0.65, 0.38], id: \.self) { height in
                    Capsule().fill(.white).frame(width: size * 0.06, height: size * height * 0.48)
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.93, green: 0.25, blue: 0.25).opacity(0.18), radius: 8, y: 4)
    }
}
