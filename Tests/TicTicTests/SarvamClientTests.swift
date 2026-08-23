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
    #expect(rendered.hasSuffix("--TEST-BOUNDARY--\r\n"))
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

@Test func defaultShortcutIsNotACommonCommandShortcut() {
    let choice = HotkeyChoice.controlShiftSpace
    #expect(choice.keyCode == 49)
    #expect(choice.eventFlags.contains(.maskControl))
    #expect(choice.eventFlags.contains(.maskShift))
    #expect(!choice.eventFlags.contains(.maskCommand))
}
