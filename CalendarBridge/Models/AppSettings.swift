import Foundation

enum SyncSourceType: String, CaseIterable, Codable, Identifiable {
    case appleCalendar = "apple"
    case outlook = "outlook"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleCalendar: return "Apple Calendar"
        case .outlook: return "Outlook"
        }
    }
}

struct AppSettings: Codable {
    var sourceType: SyncSourceType = .appleCalendar
    var selectedSourceAppleCalendarID: String = ""
    var selectedOutlookCalendarID: String = ""
    var selectedAppleCalendarID: String = ""
    var syncFrequency: SyncFrequency = .fourHours
    var syncWindowDuration: SyncWindowDuration = .sevenDays
    var isBidirectionalSyncEnabled: Bool = false
    var lastSyncAt: Date?

    static let storageKey = "CalendarBridge.AppSettings"

    var isConfigured: Bool {
        let sourceConfigured: Bool
        switch sourceType {
        case .appleCalendar:
            sourceConfigured = !selectedSourceAppleCalendarID.isEmpty
        case .outlook:
            sourceConfigured = !selectedOutlookCalendarID.isEmpty
        }
        return sourceConfigured && !selectedAppleCalendarID.isEmpty
    }

    var sourceCalendarConfigured: String {
        switch sourceType {
        case .appleCalendar: return selectedSourceAppleCalendarID
        case .outlook: return selectedOutlookCalendarID
        }
    }

    var isBidirectionalAppleSyncActive: Bool {
        sourceType == .appleCalendar && isBidirectionalSyncEnabled
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

enum SyncWindowDuration: String, CaseIterable, Codable, Identifiable {
    case sevenDays = "7d"
    case fourteenDays = "14d"
    case oneMonth = "30d"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .sevenDays: return "7 days"
        case .fourteenDays: return "14 days"
        case .oneMonth: return "30 days"
        }
    }

    var days: Int {
        switch self {
        case .sevenDays: return 7
        case .fourteenDays: return 14
        case .oneMonth: return 30
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
