import Combine
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var records: [TranscriptRecord] = []
    private let defaults: UserDefaults
    private let key = "transcriptHistory.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([TranscriptRecord].self, from: data) {
            records = saved
        }
    }

    func add(_ record: TranscriptRecord) {
        records.insert(record, at: 0)
        records = Array(records.prefix(100))
        persist()
    }

    func clear() {
        records = []
        defaults.removeObject(forKey: key)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
    }
}
