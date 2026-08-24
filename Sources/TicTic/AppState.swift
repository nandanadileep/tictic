import AppKit
import AVFoundation
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var phase: RecordingPhase = .idle
    @Published var audioLevel: Double = 0
    @Published var elapsed: TimeInterval = 0
    @Published var statusMessage = "Ready"
    @Published var apiKeyDraft = ""
    @Published private(set) var hasAPIKey = false
    @Published private(set) var microphoneGranted = false
    @Published private(set) var accessibilityGranted = false

    let preferences: Preferences
    let history: HistoryStore
    let dictionary: PersonalDictionary

    private let recorder = AudioRecorder()
    private let client = SarvamClient()
    private var hotkeyMonitor: GlobalHotkeyMonitor
    private var overlayController: OverlayController?
    private var destination: TextDestination?
    private var startedAt: Date?
    private var keyDownAt: Date?
    private var pendingQuickRelease: DispatchWorkItem?
    private var locked = false
    private var elapsedTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(preferences: Preferences? = nil, history: HistoryStore? = nil, dictionary: PersonalDictionary? = nil) {
        let resolvedPreferences = preferences ?? Preferences()
        self.preferences = resolvedPreferences
        self.history = history ?? HistoryStore()
        self.dictionary = dictionary ?? PersonalDictionary()
        hotkeyMonitor = GlobalHotkeyMonitor(hotkey: resolvedPreferences.hotkey)
        hasAPIKey = !(KeychainStore.loadAPIKey() ?? "").isEmpty

        resolvedPreferences.$hotkey
            .dropFirst()
            .sink { [weak self] choice in
                self?.hotkeyMonitor.update(choice)
                _ = self?.hotkeyMonitor.start()
            }
            .store(in: &cancellables)
    }

    func start() {
        overlayController = OverlayController(state: self)
        refreshPermissions()
        hotkeyMonitor.onKeyDown = { [weak self] in self?.handleHotkeyDown() }
        hotkeyMonitor.onKeyUp = { [weak self] in self?.handleHotkeyUp() }
        if !hotkeyMonitor.start() {
            statusMessage = "Accessibility permission needed"
        }
    }

    func refreshPermissions() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = TextInserter.isAccessibilityTrusted()
    }

    func requestMicrophonePermission() {
        Task {
            microphoneGranted = await recorder.requestPermission()
            if !microphoneGranted { statusMessage = "Microphone access is off" }
        }
    }

    func requestAccessibilityPermission() {
        _ = TextInserter.isAccessibilityTrusted(prompt: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshPermissions()
            _ = self?.hotkeyMonitor.start()
        }
    }

    func saveAPIKey() {
        do {
            try KeychainStore.saveAPIKey(apiKeyDraft)
            apiKeyDraft = ""
            hasAPIKey = true
            statusMessage = "API key saved securely"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func removeAPIKey() {
        KeychainStore.removeAPIKey()
        hasAPIKey = false
        statusMessage = "API key removed"
    }

    func toggleRecording() {
        if phase.isRecording { finishRecording() } else { beginRecording(locked: true) }
    }

    func cancelRecording() {
        pendingQuickRelease?.cancel()
        recorder.cancel()
        stopElapsedTimer()
        locked = false
        phase = .idle
        statusMessage = "Cancelled"
    }

    func clearHistory() { history.clear() }

    private func handleHotkeyDown() {
        if case .transcribing = phase { return }
        if locked, phase.isRecording {
            finishRecording()
            return
        }

        let now = Date()
        if let pendingQuickRelease, !pendingQuickRelease.isCancelled {
            pendingQuickRelease.cancel()
            self.pendingQuickRelease = nil
            locked = true
            phase = .recording(locked: true)
            statusMessage = "Hands-free · tap shortcut to finish"
            return
        }

        keyDownAt = now
        if !phase.isRecording { beginRecording(locked: false) }
    }

    private func handleHotkeyUp() {
        guard phase.isRecording, !locked else { return }
        let heldFor = Date().timeIntervalSince(keyDownAt ?? Date())
        if heldFor >= 0.36 {
            finishRecording()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.locked else { return }
            self.finishRecording()
            self.pendingQuickRelease = nil
        }
        pendingQuickRelease = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    private func beginRecording(locked: Bool) {
        guard !phase.isRecording else { return }
        guard hasAPIKey else {
            statusMessage = "Add your Sarvam API key in Settings"
            phase = .failure(statusMessage)
            resetAfterDelay()
            return
        }

        // Capture the target before permission checks or overlays can change focus.
        destination = TextInserter.captureDestination()

        Task {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                microphoneGranted = await recorder.requestPermission()
            } else {
                microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            }
            guard microphoneGranted else {
                statusMessage = "Allow microphone access in System Settings"
                phase = .failure(statusMessage)
                resetAfterDelay()
                return
            }
            do {
                startedAt = Date()
                elapsed = 0
                self.locked = locked
                try recorder.start { [weak self] level in self?.audioLevel = level }
                phase = .recording(locked: locked)
                statusMessage = locked ? "Hands-free · tap shortcut to finish" : "Listening · release to finish"
                startElapsedTimer()
            } catch {
                phase = .failure(error.localizedDescription)
                statusMessage = error.localizedDescription
                resetAfterDelay()
            }
        }
    }

    private func finishRecording() {
        pendingQuickRelease?.cancel()
        pendingQuickRelease = nil
        guard phase.isRecording else { return }
        let segments = recorder.stop()
        let duration = Date().timeIntervalSince(startedAt ?? Date())
        stopElapsedTimer()
        locked = false

        guard duration >= 0.35, !segments.isEmpty else {
            recorder.cleanupFiles()
            phase = .idle
            statusMessage = "Ready"
            return
        }

        phase = .transcribing
        statusMessage = segments.count > 1 ? "Transcribing \(segments.count) parts…" : "Transcribing…"
        let language = preferences.language
        let mode = preferences.mode
        let shouldPaste = preferences.pasteAutomatically
        let shouldSave = preferences.saveHistory
        let shouldPolish = preferences.smartFormatting
        let writingStyle = preferences.writingStyle
        let capturedDestination = destination

        Task {
            defer { recorder.cleanupFiles() }
            do {
                guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else {
                    throw AppError.missingAPIKey
                }
                var parts: [String] = []
                var detectedLanguage: String?
                for segment in segments {
                    let result = try await client.transcribe(
                        audioURL: segment,
                        apiKey: apiKey,
                        language: language,
                        mode: mode
                    )
                    let cleaned = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty { parts.append(cleaned) }
                    detectedLanguage = detectedLanguage ?? result.languageCode
                }
                let rawText = parts.joined(separator: " ")
                guard !rawText.isEmpty else { throw AppError.emptyTranscript }
                let processed = dictionary.process(rawText)
                let text: String
                if shouldPolish && !processed.expandedShortcut {
                    statusMessage = "Polishing for \(capturedDestination?.applicationName ?? "this app")…"
                    text = (try? await client.polish(
                            processed.text,
                            apiKey: apiKey,
                            style: writingStyle,
                            applicationName: capturedDestination?.applicationName,
                            vocabulary: dictionary.promptSummary
                        )) ?? processed.text
                } else {
                    text = processed.text
                }

                if shouldPaste {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    let inserted = await TextInserter.insert(text, destination: capturedDestination)
                    if inserted {
                        statusMessage = "Inserted into \(capturedDestination?.applicationName ?? "the active app")"
                    } else {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        statusMessage = "Copied — press ⌘V to paste"
                    }
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                if shouldSave {
                    history.add(TranscriptRecord(
                        id: UUID(), text: text, languageCode: detectedLanguage,
                        mode: mode, createdAt: Date(), duration: duration
                    ))
                }
                phase = .success(text)
                if !shouldPaste { statusMessage = "Copied" }
                resetAfterDelay(seconds: 1.4)
            } catch {
                phase = .failure(error.localizedDescription)
                statusMessage = error.localizedDescription
                resetAfterDelay(seconds: 3)
            }
        }
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func resetAfterDelay(seconds: TimeInterval = 2) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, !self.phase.isRecording else { return }
            self.phase = .idle
            self.statusMessage = "Ready"
        }
    }
}

enum AppError: LocalizedError {
    case missingAPIKey
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your Sarvam API key in Settings."
        case .emptyTranscript: "No speech was detected."
        }
    }
}
