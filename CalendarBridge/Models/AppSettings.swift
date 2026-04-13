import Foundation

struct AppSettings: Codable {
    var selectedOutlookCalendarID: String = ""
    var selectedAppleCalendarID: String = ""
    var syncFrequency: SyncFrequency = .fourHours
    var lastSyncAt: Date?

    static let storageKey = "CalendarBridge.AppSettings"

    var isConfigured: Bool {
        !selectedOutlookCalendarID.isEmpty && !selectedAppleCalendarID.isEmpty
    }

    static func load(defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: storageKey) else { return AppSettings() }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

enum SyncFrequency: String, CaseIterable, Codable, Identifiable {
    case hourly
    case fourHours
    case twelveHours
    case daily

    var id: String { rawValue }

    var description: String {
        switch self {
        case .hourly: return "Every 1 hour"
        case .fourHours: return "Every 4 hours"
        case .twelveHours: return "Every 12 hours"
        case .daily: return "Every 24 hours"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .hourly: return 60 * 60
        case .fourHours: return 4 * 60 * 60
        case .twelveHours: return 12 * 60 * 60
        case .daily: return 24 * 60 * 60
        }
    }
}

enum SyncTrigger {
    case launch
    case manual
    case scheduled

    var description: String {
        switch self {
        case .launch: return "Startup"
        case .manual: return "Manual"
        case .scheduled: return "Scheduled"
        }
    }
}
