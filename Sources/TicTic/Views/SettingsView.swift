import AppKit
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case dictation = "Dictation"
    case vocabulary = "Vocabulary"
    case history = "History"
    case permissions = "Permissions"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: "sparkles"
        case .dictation: "waveform"
        case .vocabulary: "text.book.closed"
        case .history: "clock.arrow.circlepath"
        case .permissions: "hand.raised"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var selection: SettingsSection = .home

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    BrandMark(size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("tictic").font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("Voice, naturally.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)

                List(SettingsSection.allCases, selection: $selection) { section in
                    Label(section.rawValue, systemImage: section.icon).tag(section)
                }
                .listStyle(.sidebar)

                HStack(spacing: 7) {
                    Circle().fill((state.remainingSeconds ?? 300) > 0 ? .green : .orange).frame(width: 7, height: 7)
                    Text(state.remainingLabel)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 230)
        } detail: {
            Group {
                switch selection {
                case .home: HomeSettingsView(state: state)
                case .dictation: DictationSettingsView(state: state)
                case .vocabulary: VocabularyView(state: state)
                case .history: HistoryView(state: state)
                case .permissions: PermissionsView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
    }
}

private struct Page<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 27, weight: .bold, design: .rounded))
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                content
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(32)
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(.quaternary, lineWidth: 1) }
    }
}

private struct HomeSettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var preferences: Preferences

    init(state: AppState) {
        self.state = state
        preferences = state.preferences
    }

    var body: some View {
        Page(title: "Speak freely", subtitle: "Your words, ready wherever the cursor is.") {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.13, green: 0.10, blue: 0.18), Color(red: 0.30, green: 0.10, blue: 0.17)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                HStack(spacing: 23) {
                    BrandMark(size: 70)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hold \(preferences.hotkey.title) and speak")
                            .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text("Release to insert. Double-tap for hands-free mode.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Button(state.phase.isRecording ? "Stop" : "Try it") { state.toggleRecording() }
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                }
                .padding(26)
            }
            .frame(height: 130)

            HStack(spacing: 14) {
                MetricCard(icon: "character.bubble.fill", value: preferences.language.title, label: "Input language")
                MetricCard(icon: "textformat.abc", value: preferences.mode.title, label: "Output style")
                MetricCard(icon: "hourglass", value: state.remainingLabel, label: "Beta allowance")
            }

        }
    }
}

private struct MetricCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).foregroundStyle(.tint).font(.title3)
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct DictationSettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var preferences: Preferences

    init(state: AppState) {
        self.state = state
        preferences = state.preferences
    }

    var body: some View {
        Page(title: "Dictation", subtitle: "Tune tictic to the way you speak and write.") {
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    SettingRow(title: "Language", subtitle: "Auto-detect works well for everyday switching") {
                        Picker("", selection: $preferences.language) {
                            ForEach(IndicLanguage.allCases) { Text($0.title).tag($0) }
                        }.frame(width: 190)
                    }
                    Divider()
                    SettingRow(title: "Output", subtitle: preferences.mode.subtitle) {
                        Picker("", selection: $preferences.mode) {
                            ForEach(TranscriptionMode.allCases) { Text($0.title).tag($0) }
                        }.frame(width: 190)
                    }
                    Divider()
                    SettingRow(title: "Global shortcut", subtitle: "Hold to dictate; double-tap to lock") {
                        Picker("", selection: $preferences.hotkey) {
                            ForEach(HotkeyChoice.allCases) { Text($0.title).tag($0) }
                        }.frame(width: 150)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Smart formatting with Sarvam 105B", isOn: $preferences.smartFormatting)
                    Text("Cleans punctuation and adapts your tone to the app. This uses an additional Sarvam request.")
                        .font(.caption).foregroundStyle(.secondary)
                    if preferences.smartFormatting {
                        SettingRow(title: "Writing style", subtitle: "Match the destination or choose a consistent voice") {
                            Picker("", selection: $preferences.writingStyle) {
                                ForEach(WritingStyle.allCases) { Text($0.title).tag($0) }
                            }.frame(width: 190)
                        }
                    }
                    Divider()
                    Toggle("Insert into the active text field", isOn: $preferences.pasteAutomatically)
                    Text(preferences.pasteAutomatically ? "tictic returns focus to the app where you started and types at the cursor." : "Finished transcripts are copied to the clipboard.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Toggle("Keep local transcript history", isOn: $preferences.saveHistory)
                    Text("Audio is always deleted after transcription. History contains text only.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct VocabularyView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var dictionary: PersonalDictionary
    @State private var spoken = ""
    @State private var written = ""
    @State private var kind: PersonalTerm.Kind = .replacement

    init(state: AppState) {
        self.state = state
        dictionary = state.dictionary
    }

    var body: some View {
        Page(title: "Vocabulary", subtitle: "Teach tictic your names, terminology, and reusable phrases.") {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Type", selection: $kind) {
                        ForEach(PersonalTerm.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    TextField(kind == .replacement ? "What tictic may hear (e.g. sarvam eye)" : "Trigger phrase (e.g. my meeting link)", text: $spoken)
                        .textFieldStyle(.roundedBorder)
                    TextField(kind == .replacement ? "Write it as (e.g. Sarvam AI)" : "Text to insert", text: $written, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                    HStack {
                        Text(kind == .shortcut ? "Say the trigger followed by “shortcut”, or say “insert” first." : "Corrections are applied locally before smart formatting.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Add") {
                            dictionary.add(spoken: spoken, written: written, kind: kind)
                            spoken = ""
                            written = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            if dictionary.terms.isEmpty {
                ContentUnavailableView("No personal terms", systemImage: "text.book.closed", description: Text("Add a correction or voice shortcut above."))
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(spacing: 10) {
                    ForEach(dictionary.terms) { term in
                        Card {
                            HStack(spacing: 13) {
                                Image(systemName: term.kind == .shortcut ? "bolt.fill" : "textformat")
                                    .foregroundStyle(.tint).frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(term.spoken).font(.headline)
                                    Text(term.written).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Text(term.kind.title).font(.caption2).foregroundStyle(.secondary)
                                Button(role: .destructive) { dictionary.remove(id: term.id) } label: {
                                    Image(systemName: "trash")
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct SettingRow<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            content
        }
    }
}

private struct HistoryView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var history: HistoryStore
    @State private var query = ""

    init(state: AppState) {
        self.state = state
        history = state.history
    }

    private var filtered: [TranscriptRecord] {
        query.isEmpty ? history.records : history.records.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Page(title: "History", subtitle: "Your recent words stay on this Mac.") {
            HStack {
                TextField("Search transcripts", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button("Clear", role: .destructive) { state.clearHistory() }
                    .disabled(history.records.isEmpty)
            }
            if filtered.isEmpty {
                ContentUnavailableView("No dictations yet", systemImage: "waveform", description: Text("Your saved transcripts will appear here."))
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { record in
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(record.text).textSelection(.enabled).lineLimit(5)
                                HStack {
                                    Text(record.createdAt, format: .dateTime.hour().minute())
                                    Text("·")
                                    Text("\(formatDuration(record.duration)) recording")
                                    Text("·")
                                    Text(record.mode.title)
                                    if let language = record.languageCode { Text("· \(language)") }
                                    Spacer()
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(record.text, forType: .string)
                                    } label: { Image(systemName: "doc.on.doc") }
                                    .buttonStyle(.plain).help("Copy")
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        if seconds < 60 { return "\(seconds) sec" }
        return "\(seconds / 60) min \(seconds % 60) sec"
    }
}

private struct PermissionsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Page(title: "Permissions", subtitle: "Two permissions let tictic listen and type anywhere.") {
            PermissionCard(
                icon: "mic.fill", title: "Microphone",
                detail: "Used only while the recorder is visible.",
                granted: state.microphoneGranted,
                action: state.requestMicrophonePermission
            )
            PermissionCard(
                icon: "cursorarrow.motionlines", title: "Accessibility",
                detail: "Detects the global shortcut and inserts text at your cursor.",
                granted: state.accessibilityGranted,
                action: state.requestAccessibilityPermission
            )
            Text("If a permission remains off, open System Settings → Privacy & Security and enable tictic, then return here.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct PermissionCard: View {
    let icon: String
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        Card {
            HStack(spacing: 15) {
                Image(systemName: icon).font(.title2).foregroundStyle(.tint)
                    .frame(width: 42, height: 42).background(.tint.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if granted {
                    Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Allow") { action() }.buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
