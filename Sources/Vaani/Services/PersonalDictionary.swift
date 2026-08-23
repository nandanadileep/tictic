import Combine
import Foundation

struct ProcessedTranscript {
    let text: String
    let expandedShortcut: Bool
}

@MainActor
final class PersonalDictionary: ObservableObject {
    @Published private(set) var terms: [PersonalTerm] = []
    private let defaults: UserDefaults
    private let key = "personalDictionary.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([PersonalTerm].self, from: data) {
            terms = saved
        }
    }

    func add(spoken: String, written: String, kind: PersonalTerm.Kind) {
        let spoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let written = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty, !written.isEmpty else { return }
        terms.append(PersonalTerm(id: UUID(), spoken: spoken, written: written, kind: kind))
        persist()
    }

    func remove(id: UUID) {
        terms.removeAll { $0.id == id }
        persist()
    }

    func process(_ transcript: String) -> ProcessedTranscript {
        let command = transcript.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        for term in terms where term.kind == .shortcut {
            let trigger = term.spoken.lowercased()
            if command == "\(trigger) shortcut" || command == "insert \(trigger)" || command == trigger {
                return ProcessedTranscript(text: term.written, expandedShortcut: true)
            }
        }

        var result = transcript
        for term in terms where term.kind == .replacement {
            let pattern = "(?i)(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: term.spoken))(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: term.written))
        }
        return ProcessedTranscript(text: result, expandedShortcut: false)
    }

    var promptSummary: String {
        terms.filter { $0.kind == .replacement }.map { "\($0.spoken) → \($0.written)" }.joined(separator: ", ")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(terms) { defaults.set(data, forKey: key) }
    }
}
