import Foundation

actor SyncMetadataStore {
    private struct StoredMapping: Codable {
        var sourceKey: String
        var appleEventID: String
        var destinationCalendarID: String
        var lastSeenAt: Date
        var sourceStartDate: Date?
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

    func save(sourceKey: String, appleEventID: String, destinationCalendarID: String, sourceStartDate: Date) {
        var all = loadMappings()
        if let index = all.firstIndex(where: { $0.sourceKey == sourceKey && $0.destinationCalendarID == destinationCalendarID }) {
            all[index].appleEventID = appleEventID
            all[index].lastSeenAt = Date()
            all[index].sourceStartDate = sourceStartDate
        } else {
            all.append(StoredMapping(
                sourceKey: sourceKey,
                appleEventID: appleEventID,
                destinationCalendarID: destinationCalendarID,
                lastSeenAt: Date(),
                sourceStartDate: sourceStartDate
            ))
        }
        store(all)
    }

    func remove(sourceKey: String, destinationCalendarID: String) {
        var all = loadMappings()
        all.removeAll { $0.sourceKey == sourceKey && $0.destinationCalendarID == destinationCalendarID }
        store(all)
    }

    func removeMissing(validSourceKeys: Set<String>, destinationCalendarID: String, window: SyncWindow) -> [String] {
        var all = loadMappings()
        let removed = all.filter {
            $0.destinationCalendarID == destinationCalendarID
                && isWithinWindow($0.sourceStartDate, window: window)
                && !validSourceKeys.contains($0.sourceKey)
        }
        all.removeAll {
            $0.destinationCalendarID == destinationCalendarID
                && isWithinWindow($0.sourceStartDate, window: window)
                && !validSourceKeys.contains($0.sourceKey)
        }
        store(all)
        return removed.map(\.appleEventID)
    }

    func removeOutsideWindow(destinationCalendarID: String, window: SyncWindow) -> [String] {
        var all = loadMappings()
        let removed = all.filter {
            $0.destinationCalendarID == destinationCalendarID
                && shouldRemoveOutsideWindow($0.sourceStartDate, window: window)
        }
        all.removeAll {
            $0.destinationCalendarID == destinationCalendarID
                && shouldRemoveOutsideWindow($0.sourceStartDate, window: window)
        }
        store(all)
        return removed.map(\.appleEventID)
    }

    private func isWithinWindow(_ date: Date?, window: SyncWindow) -> Bool {
        guard let date else { return false }
        return window.contains(date)
    }

    private func shouldRemoveOutsideWindow(_ date: Date?, window: SyncWindow) -> Bool {
        guard let date else { return true }
        return !window.contains(date)
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
