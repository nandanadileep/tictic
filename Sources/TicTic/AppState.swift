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
    @Published var accessCodeDraft = ""
    @Published private(set) var hasAccessCode = false
    @Published private(set) var remainingSeconds: Double?
    @Published private(set) var isCheckingAccessCode = false
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
        hasAccessCode = !(KeychainStore.loadAccessCode() ?? "").isEmpty

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
        if hasAccessCode { refreshUsage() }
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

    func saveAccessCode() {
        let candidate = accessCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !candidate.isEmpty else { return }
        isCheckingAccessCode = true
        statusMessage = "Checking beta access code…"
        Task {
            defer { isCheckingAccessCode = false }
            do {
                let usage = try await client.usage(accessCode: candidate)
                try KeychainStore.saveAccessCode(candidate)
                accessCodeDraft = ""
                hasAccessCode = true
                remainingSeconds = usage.remainingSeconds
                statusMessage = usage.remainingSeconds > 0 ? "Beta access ready" : "Beta allowance used"
            } catch {
                hasAccessCode = false
                remainingSeconds = nil
                statusMessage = error.localizedDescription
            }
        }
    }

    func removeAccessCode() {
        KeychainStore.removeAccessCode()
        hasAccessCode = false
        remainingSeconds = nil
        statusMessage = "Beta access code removed"
    }

    var remainingLabel: String {
        guard let remainingSeconds else { return hasAccessCode ? "Checking…" : "5 min beta" }
        let seconds = max(0, Int(remainingSeconds.rounded(.down)))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60)) left"
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
        guard hasAccessCode else {
            statusMessage = "Add your beta access code in Settings"
            phase = .failure(statusMessage)
            resetAfterDelay()
            return
        }
        if let remainingSeconds, remainingSeconds < 0.5 {
            statusMessage = "Your five-minute beta allowance has been used"
            phase = .failure(statusMessage)
            resetAfterDelay(seconds: 3)
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
                guard let accessCode = KeychainStore.loadAccessCode(), !accessCode.isEmpty else {
                    throw AppError.missingAccessCode
                }
                var parts: [String] = []
                var detectedLanguage: String?
                var formatToken: String?
                let segmentDuration = min(26, max(0.25, duration / Double(segments.count)))
                for segment in segments {
                    let result = try await client.transcribe(
                        audioURL: segment,
                        accessCode: accessCode,
                        language: language,
                        mode: mode,
                        durationSeconds: segmentDuration
                    )
                    let cleaned = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty { parts.append(cleaned) }
                    detectedLanguage = detectedLanguage ?? result.languageCode
                    formatToken = result.formatToken ?? formatToken
                    remainingSeconds = result.remainingSeconds ?? remainingSeconds
                }
                let rawText = parts.joined(separator: " ")
                guard !rawText.isEmpty else { throw AppError.emptyTranscript }
                let processed = dictionary.process(rawText)
                let preparedText: String
                if shouldPolish, !processed.expandedShortcut, let formatToken {
                    statusMessage = "Polishing for \(capturedDestination?.applicationName ?? "this app")…"
                    do {
                        preparedText = try await client.polish(
                            processed.text,
                            accessCode: accessCode,
                            formatToken: formatToken,
                            mode: mode,
                            style: writingStyle,
                            applicationName: capturedDestination?.applicationName,
                            vocabulary: dictionary.promptSummary
                        )
                    } catch {
                        if mode == .translit, SarvamClient.containsNativeIndicScript(processed.text) { throw error }
                        preparedText = processed.text
                    }
                } else {
                    preparedText = processed.text
                }

                let text: String
                if mode == .translit,
                   !processed.expandedShortcut,
                   SarvamClient.containsNativeIndicScript(preparedText),
                   let formatToken {
                    statusMessage = "Converting to English letters…"
                    text = try await client.romanize(
                        preparedText,
                        accessCode: accessCode,
                        formatToken: formatToken,
                        vocabulary: dictionary.promptSummary
                    )
                } else {
                    text = preparedText
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
                if let remaining = self.remainingSeconds,
                   remaining > 0,
                   self.elapsed >= max(0.35, remaining - 0.2),
                   self.phase.isRecording {
                    self.finishRecording()
                }
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

    private func refreshUsage() {
        guard let accessCode = KeychainStore.loadAccessCode(), !accessCode.isEmpty else { return }
        Task {
            do {
                let usage = try await client.usage(accessCode: accessCode)
                remainingSeconds = usage.remainingSeconds
                if usage.remainingSeconds <= 0 { statusMessage = "Beta allowance used" }
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}

enum AppError: LocalizedError {
    case missingAccessCode
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .missingAccessCode: "Add your beta access code in Settings."
        case .emptyTranscript: "No speech was detected."
        }
    }
}
