import AVFoundation
import Foundation
import OSLog

@MainActor
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private struct RecordingProfile: Equatable {
        let name: String
        let fileExtension: String
        let settings: [String: Any]

        static func == (lhs: RecordingProfile, rhs: RecordingProfile) -> Bool {
            lhs.name == rhs.name
        }
    }

    private static let recordingProfiles: [RecordingProfile] = [
        aacProfile(name: "AAC 48 kHz", sampleRate: 48_000),
        aacProfile(name: "AAC 44.1 kHz", sampleRate: 44_100),
        aacProfile(name: "AAC 16 kHz", sampleRate: 16_000),
        RecordingProfile(
            name: "PCM WAV 48 kHz",
            fileExtension: "wav",
            settings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        )
    ]

    private static let logger = Logger(subsystem: "com.nandanadileep.tictic", category: "audio")
    private var recorder: AVAudioRecorder?
    private var selectedProfile: RecordingProfile?
    private var meterTimer: Timer?
    private var segmentTimer: Timer?
    private(set) var segmentURLs: [URL] = []
    private var levelHandler: ((Double) -> Void)?
    private var segmentIndex = 0

    var isRecording: Bool { recorder?.isRecording == true }

    func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start(levelHandler: @escaping (Double) -> Void) throws {
        cleanupFiles()
        segmentURLs = []
        segmentIndex = 0
        selectedProfile = nil
        self.levelHandler = levelHandler
        try beginSegment()
        startMeters()
        scheduleSegmentRollover()
    }

    func stop() -> [URL] {
        invalidateTimers()
        if let recorder, recorder.isRecording {
            recorder.stop()
            if let url = validRecording(at: recorder.url) { segmentURLs.append(url) }
        }
        recorder = nil
        levelHandler?(0)
        levelHandler = nil
        return segmentURLs
    }

    func cancel() {
        invalidateTimers()
        recorder?.stop()
        recorder = nil
        cleanupFiles()
        levelHandler?(0)
        levelHandler = nil
    }

    func cleanupFiles() {
        for url in segmentURLs { try? FileManager.default.removeItem(at: url) }
        if let url = recorder?.url { try? FileManager.default.removeItem(at: url) }
        segmentURLs = []
    }

    private func beginSegment() throws {
        let profiles = selectedProfile.map { [$0] } ?? Self.recordingProfiles
        var failures: [String] = []

        for profile in profiles {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("tictic-\(UUID().uuidString)-\(segmentIndex).\(profile.fileExtension)")
            do {
                let next = try AVAudioRecorder(url: url, settings: profile.settings)
                next.delegate = self
                next.isMeteringEnabled = true
                guard next.prepareToRecord() else {
                    throw RecorderError.profileFailed("\(profile.name) could not prepare")
                }
                guard next.record() else {
                    throw RecorderError.profileFailed("\(profile.name) could not begin")
                }
                selectedProfile = profile
                recorder = next
                segmentIndex += 1
                Self.logger.info("Microphone recording started with \(profile.name, privacy: .public)")
                return
            } catch {
                failures.append("\(profile.name): \(error.localizedDescription)")
                Self.logger.error("Recording profile failed: \(profile.name, privacy: .public) — \(error.localizedDescription, privacy: .public)")
                try? FileManager.default.removeItem(at: url)
            }
        }

        throw RecorderError.couldNotStart(failures)
    }

    private func rollSegment() {
        guard let recorder, recorder.isRecording else { return }
        recorder.stop()
        if let url = validRecording(at: recorder.url) { segmentURLs.append(url) }
        do {
            try beginSegment()
            scheduleSegmentRollover()
        } catch {
            invalidateTimers()
        }
    }

    private func validRecording(at url: URL) -> URL? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 1_000 ? url : nil
    }

    private func startMeters() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.055, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                let normalized = max(0, min(1, pow(10, Double(power) / 34)))
                self.levelHandler?(normalized)
            }
        }
    }

    private func scheduleSegmentRollover() {
        segmentTimer?.invalidate()
        segmentTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.rollSegment() }
        }
    }

    private func invalidateTimers() {
        meterTimer?.invalidate()
        segmentTimer?.invalidate()
        meterTimer = nil
        segmentTimer = nil
    }
}

enum RecorderError: LocalizedError {
    case profileFailed(String)
    case couldNotStart([String])

    var errorDescription: String? {
        switch self {
        case let .profileFailed(message): message
        case .couldNotStart:
            "tictic could not start the microphone. Check that an input device is selected in System Settings → Sound."
        }
    }
}

private extension AudioRecorder {
    private static func aacProfile(name: String, sampleRate: Double) -> RecordingProfile {
        RecordingProfile(
            name: name,
            fileExtension: "m4a",
            settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
        )
    }
}
