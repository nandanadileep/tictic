import AppKit
import Foundation

enum TranscriptionMode: String, CaseIterable, Codable, Identifiable {
    case transcribe
    case translate
    case codemix
    case translit
    case verbatim

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcribe: "Original script"
        case .translate: "Translate to English"
        case .codemix: "Code-mixed"
        case .translit: "Roman script"
        case .verbatim: "Verbatim"
        }
    }

    var subtitle: String {
        switch self {
        case .transcribe: "Clean text in the language you speak"
        case .translate: "Indian-language speech, polished English text"
        case .codemix: "English words stay English; Indic words keep their script"
        case .translit: "Write Indian languages using Latin characters"
        case .verbatim: "Keep fillers and spoken-number phrasing"
        }
    }
}

enum IndicLanguage: String, CaseIterable, Codable, Identifiable {
    case unknown
    case hiIN = "hi-IN"
    case bnIN = "bn-IN"
    case knIN = "kn-IN"
    case mlIN = "ml-IN"
    case mrIN = "mr-IN"
    case odIN = "od-IN"
    case paIN = "pa-IN"
    case taIN = "ta-IN"
    case teIN = "te-IN"
    case enIN = "en-IN"
    case guIN = "gu-IN"
    case asIN = "as-IN"
    case urIN = "ur-IN"
    case neIN = "ne-IN"
    case kokIN = "kok-IN"
    case ksIN = "ks-IN"
    case sdIN = "sd-IN"
    case saIN = "sa-IN"
    case satIN = "sat-IN"
    case mniIN = "mni-IN"
    case brxIN = "brx-IN"
    case maiIN = "mai-IN"
    case doiIN = "doi-IN"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unknown: "Auto-detect"
        case .hiIN: "Hindi"
        case .bnIN: "Bengali"
        case .knIN: "Kannada"
        case .mlIN: "Malayalam"
        case .mrIN: "Marathi"
        case .odIN: "Odia"
        case .paIN: "Punjabi"
        case .taIN: "Tamil"
        case .teIN: "Telugu"
        case .enIN: "Indian English"
        case .guIN: "Gujarati"
        case .asIN: "Assamese"
        case .urIN: "Urdu"
        case .neIN: "Nepali"
        case .kokIN: "Konkani"
        case .ksIN: "Kashmiri"
        case .sdIN: "Sindhi"
        case .saIN: "Sanskrit"
        case .satIN: "Santali"
        case .mniIN: "Manipuri"
        case .brxIN: "Bodo"
        case .maiIN: "Maithili"
        case .doiIN: "Dogri"
        }
    }
}

enum HotkeyChoice: String, CaseIterable, Codable, Identifiable {
    case controlShiftSpace
    case controlOptionD
    case commandShiftPeriod
    case optionShiftSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controlShiftSpace: "⌃ ⇧ Space"
        case .controlOptionD: "⌃ ⌥ D"
        case .commandShiftPeriod: "⌘ ⇧ ."
        case .optionShiftSpace: "⌥ ⇧ Space"
        }
    }

    var keyCode: CGKeyCode {
        switch self {
        case .controlShiftSpace, .optionShiftSpace: 49
        case .controlOptionD: 2
        case .commandShiftPeriod: 47
        }
    }

    var eventFlags: CGEventFlags {
        switch self {
        case .controlShiftSpace: [.maskControl, .maskShift]
        case .controlOptionD: [.maskControl, .maskAlternate]
        case .commandShiftPeriod: [.maskCommand, .maskShift]
        case .optionShiftSpace: [.maskAlternate, .maskShift]
        }
    }
}

enum WritingStyle: String, CaseIterable, Codable, Identifiable {
    case automatic
    case clean
    case concise
    case professional
    case casual

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Match the app"
        case .clean: "Clean & natural"
        case .concise: "Concise"
        case .professional: "Professional"
        case .casual: "Casual"
        }
    }
}

struct PersonalTerm: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case replacement
        case shortcut
        var id: String { rawValue }
        var title: String { self == .replacement ? "Correction" : "Voice shortcut" }
    }

    let id: UUID
    var spoken: String
    var written: String
    var kind: Kind
}

struct TranscriptRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let languageCode: String?
    let mode: TranscriptionMode
    let createdAt: Date
    let duration: TimeInterval
}

struct SarvamTranscript: Decodable, Equatable {
    let requestID: String?
    let transcript: String
    let languageCode: String?
    let languageProbability: Double?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case transcript
        case languageCode = "language_code"
        case languageProbability = "language_probability"
    }
}

enum RecordingPhase: Equatable {
    case idle
    case recording(locked: Bool)
    case transcribing
    case success(String)
    case failure(String)

    var isRecording: Bool {
        if case .recording = self { true } else { false }
    }
}
