import Foundation

actor SyncMetadataStore {
    private struct StoredMapping: Codable {
        var sourceKey: String
        var appleEventID: String
        var destinationCalendarID: String
        var lastSeenAt: Date
    }

    private let defaults: UserDefaults
    private let storageKey = "CalendarBridge.SyncMappings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func mappings(for destinationCalendarID: String) -> [String: String] {
        loadMappings()
            .filter { $0.destinationCalendarID == destinationCalendarID }
            .reduce(into: [:]) { partialResult, entry in
                partialResult[entry.sourceKey] = entry.appleEventID
            }
    }

    func save(sourceKey: String, appleEventID: String, destinationCalendarID: String) {
        var all = loadMappings()
        if let index = all.firstIndex(where: { $0.sourceKey == sourceKey && $0.destinationCalendarID == destinationCalendarID }) {
            all[index].appleEventID = appleEventID
            all[index].lastSeenAt = Date()
        } else {
            all.append(StoredMapping(
                sourceKey: sourceKey,
                appleEventID: appleEventID,
                destinationCalendarID: destinationCalendarID,
                lastSeenAt: Date()
            ))
        }
        store(all)
    }

    func remove(sourceKey: String, destinationCalendarID: String) {
        var all = loadMappings()
        all.removeAll { $0.sourceKey == sourceKey && $0.destinationCalendarID == destinationCalendarID }
        store(all)
    }

    func removeMissing(validSourceKeys: Set<String>, destinationCalendarID: String) -> [String] {
        var all = loadMappings()
        let removed = all.filter { $0.destinationCalendarID == destinationCalendarID && !validSourceKeys.contains($0.sourceKey) }
        all.removeAll { $0.destinationCalendarID == destinationCalendarID && !validSourceKeys.contains($0.sourceKey) }
        store(all)
        return removed.map(\.appleEventID)
    }

    private func loadMappings() -> [StoredMapping] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([StoredMapping].self, from: data)) ?? []
    }

    private func store(_ mappings: [StoredMapping]) {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
