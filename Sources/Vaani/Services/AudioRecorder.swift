import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
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
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaani-\(UUID().uuidString)-\(segmentIndex).m4a")
        segmentIndex += 1
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let next = try AVAudioRecorder(url: url, settings: settings)
        next.delegate = self
        next.isMeteringEnabled = true
        guard next.prepareToRecord(), next.record() else { throw RecorderError.couldNotStart }
        recorder = next
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
    case couldNotStart
    var errorDescription: String? { "The microphone recording could not start." }
}
