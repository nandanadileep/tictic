import Combine
import Foundation

@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let language = "language"
        static let mode = "mode"
        static let hotkey = "hotkey"
        static let saveHistory = "saveHistory"
        static let pasteAutomatically = "pasteAutomatically"
        static let smartFormatting = "smartFormatting"
        static let writingStyle = "writingStyle"
        static let outputPresetVersion = "outputPresetVersion"
    }

    private let defaults: UserDefaults

    @Published var language: IndicLanguage { didSet { defaults.set(language.rawValue, forKey: Key.language) } }
    @Published var mode: TranscriptionMode { didSet { defaults.set(mode.rawValue, forKey: Key.mode) } }
    @Published var hotkey: HotkeyChoice { didSet { defaults.set(hotkey.rawValue, forKey: Key.hotkey) } }
    @Published var saveHistory: Bool { didSet { defaults.set(saveHistory, forKey: Key.saveHistory) } }
    @Published var pasteAutomatically: Bool { didSet { defaults.set(pasteAutomatically, forKey: Key.pasteAutomatically) } }
    @Published var smartFormatting: Bool { didSet { defaults.set(smartFormatting, forKey: Key.smartFormatting) } }
    @Published var writingStyle: WritingStyle { didSet { defaults.set(writingStyle.rawValue, forKey: Key.writingStyle) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = IndicLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .unknown
        if defaults.integer(forKey: Key.outputPresetVersion) < 1 {
            mode = .translit
            defaults.set(TranscriptionMode.translit.rawValue, forKey: Key.mode)
            defaults.set(1, forKey: Key.outputPresetVersion)
        } else {
            mode = TranscriptionMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .translit
        }
        let savedHotkey = HotkeyChoice(rawValue: defaults.string(forKey: Key.hotkey) ?? "")
        let resolvedHotkey: HotkeyChoice
        switch savedHotkey {
        case nil, .rightOption, .controlShiftSpace:
            resolvedHotkey = .leftControlShift
        default:
            resolvedHotkey = savedHotkey!
        }
        hotkey = resolvedHotkey
        defaults.set(resolvedHotkey.rawValue, forKey: Key.hotkey)
        saveHistory = defaults.object(forKey: Key.saveHistory) as? Bool ?? true
        pasteAutomatically = defaults.object(forKey: Key.pasteAutomatically) as? Bool ?? true
        smartFormatting = defaults.object(forKey: Key.smartFormatting) as? Bool ?? true
        writingStyle = WritingStyle(rawValue: defaults.string(forKey: Key.writingStyle) ?? "") ?? .automatic
    }
}
