import Foundation
import Testing
@testable import TicTic

@Test func multipartBodyContainsCurrentModelModeLanguageAndAudio() {
    let audio = Data([0x01, 0x02, 0x03, 0x04])
    let body = SarvamClient.multipartBody(
        audioData: audio,
        filename: "sample.m4a",
        language: "ta-IN",
        mode: "translit",
        boundary: "TEST-BOUNDARY"
    )
    let rendered = String(decoding: body, as: UTF8.self)

    #expect(rendered.contains("name=\"model\"\r\n\r\nsaaras:v3"))
    #expect(rendered.contains("name=\"mode\"\r\n\r\ntranslit"))
    #expect(rendered.contains("name=\"language_code\"\r\n\r\nta-IN"))
    #expect(rendered.contains("filename=\"sample.m4a\""))
    #expect(rendered.contains("Content-Type: audio/mp4"))
    #expect(rendered.hasSuffix("--TEST-BOUNDARY--\r\n"))
}

@Test func audioMimeTypeMatchesRecorderFallbackFormat() {
    #expect(SarvamClient.mimeType(for: URL(fileURLWithPath: "/tmp/voice.m4a")) == "audio/mp4")
    #expect(SarvamClient.mimeType(for: URL(fileURLWithPath: "/tmp/voice.wav")) == "audio/wav")
}

@Test func sarvamTranscriptDecoding() throws {
    let json = #"{"request_id":"req-1","transcript":"ನಮಸ್ಕಾರ","language_code":"kn-IN","language_probability":0.98}"#.data(using: .utf8)!
    let result = try JSONDecoder().decode(SarvamTranscript.self, from: json)

    #expect(result.requestID == "req-1")
    #expect(result.transcript == "ನಮಸ್ಕಾರ")
    #expect(result.languageCode == "kn-IN")
    #expect(result.languageProbability == 0.98)
}

@Test func allModesMatchSarvamV3Contract() {
    #expect(Set(TranscriptionMode.allCases.map(\.rawValue)) == [
        "transcribe", "translate", "codemix", "translit", "verbatim"
    ])
}

@Test func transliterationModeIsPresentedAsHinglish() {
    #expect(TranscriptionMode.translit.title == "Hinglish / Roman")
    #expect(TranscriptionMode.translit.subtitle.contains("English letters"))
}

@Test @MainActor func existingInstallMigratesToHinglishAndLeftControlShift() {
    let suite = "TicTicTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(TranscriptionMode.transcribe.rawValue, forKey: "mode")
    defaults.set(HotkeyChoice.rightOption.rawValue, forKey: "hotkey")

    let preferences = Preferences(defaults: defaults)

    #expect(preferences.mode == .translit)
    #expect(preferences.hotkey == .leftControlShift)
}

@Test func defaultShortcutUsesLeftControlAndShiftWithoutSpace() {
    let choice = HotkeyChoice.leftControlShift
    #expect(choice.keyCode == 59)
    #expect(choice.isModifierOnly)
    #expect(choice.modifierKeyCodes == [59, 56])
    #expect(choice.eventFlags.contains(.maskControl))
    #expect(choice.eventFlags.contains(.maskShift))
    #expect(!choice.eventFlags.contains(.maskCommand))
}

@Test func modifierChordStartsAndStopsOnCleanTransitions() {
    var tracker = ModifierChordTracker(requiredKeyCodes: [59, 56])

    #expect(tracker.update(keyCode: 59, flags: [.maskControl]) == nil)
    #expect(tracker.update(keyCode: 56, flags: [.maskControl, .maskShift]) == true)
    #expect(tracker.update(keyCode: 56, flags: [.maskControl]) == false)
    #expect(tracker.update(keyCode: 59, flags: []) == nil)
    #expect(tracker.update(keyCode: 56, flags: [.maskShift]) == nil)
    #expect(tracker.update(keyCode: 59, flags: [.maskControl, .maskShift]) == true)
    #expect(tracker.update(keyCode: 59, flags: [.maskShift]) == false)
}
