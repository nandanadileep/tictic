import SwiftUI

struct RecordingOverlay: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 13) {
            statusGlyph
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer()
                    if state.phase.isRecording {
                        Text(format(state.elapsed))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                if state.phase.isRecording {
                    Waveform(level: state.audioLevel)
                        .frame(height: 17)
                } else {
                    Text(state.statusMessage)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }

            if state.phase.isRecording {
                Button(action: state.cancelRecording) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 23, height: 23)
                }
                .buttonStyle(.plain)
                .background(.quaternary, in: Circle())
                .help("Cancel")
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 330, height: 66)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .padding(3)
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch state.phase {
        case let .recording(locked):
            ZStack {
                Circle().fill(Color(red: 0.95, green: 0.29, blue: 0.22).opacity(0.16))
                Image(systemName: locked ? "lock.fill" : "mic.fill")
                    .foregroundStyle(Color(red: 0.95, green: 0.29, blue: 0.22))
            }
        case .transcribing:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2)
        case .failure:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).font(.title2)
        case .idle:
            Image(systemName: "waveform")
        }
    }

    private var title: String {
        switch state.phase {
        case let .recording(locked): locked ? "Hands-free listening" : "Listening"
        case .transcribing: "Turning voice into text"
        case .success: "Done"
        case .failure: "Something needs attention"
        case .idle: "Vaani"
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

private struct Waveform: View {
    let level: Double

    var body: some View {
        HStack(spacing: 2.4) {
            ForEach(0..<34, id: \.self) { index in
                let wave = 0.25 + abs(sin(Double(index) * 0.72)) * 0.75
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(red: 1, green: 0.58, blue: 0.23), Color(red: 0.93, green: 0.2, blue: 0.3)],
                        startPoint: .bottom, endPoint: .top
                    ))
                    .frame(width: 3, height: max(3, 16 * level * wave))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
