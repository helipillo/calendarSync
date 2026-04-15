import Foundation

struct OutlookCalendarRef: Identifiable, Hashable, Codable {
    let id: String
    let name: String
}

struct AppleCalendarRef: Identifiable, Hashable {
    let id: String
    let title: String
    let sourceTitle: String
}

struct SyncEventRecord: Hashable, Codable {
    let sourceCalendarID: String
    let sourceCalendarName: String
    let eventID: String
    let subject: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let notes: String?
    let allDay: Bool
    let modificationDate: Date?

    var sourceKey: String {
        let normalizedTitle = subject
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "\n", with: " ")
        let startInterval = Int(startDate.timeIntervalSince1970)
        return "apple:\(sourceCalendarID):\(startInterval):\(normalizedTitle)"
    }
}

struct OutlookEventRecord: Hashable, Codable {
    let sourceCalendarID: String
    let sourceCalendarName: String
    let eventID: String
    let exchangeID: String?
    let subject: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let notes: String?
    let allDay: Bool
    let modificationDate: Date?
    let icalendarData: String?

    var sourceKey: String {
        let primary = exchangeID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (primary?.isEmpty == false ? primary! : eventID)
        return "outlook:\(sourceCalendarID):\(base)"
    }
}

struct SyncResult {
    let sourceEventCount: Int
    let updatedCount: Int
    let deletedCount: Int
    let backendDescription: String
}

struct SyncWindow {
    let startDate: Date
    let endDate: Date

    static func upcomingDays(_ days: Int, referenceDate: Date = Date(), calendar: Calendar = .current) -> SyncWindow {
        let startDate = calendar.startOfDay(for: referenceDate)
        let endDate = calendar.date(byAdding: .day, value: days, to: startDate) ?? startDate.addingTimeInterval(TimeInterval(days * 24 * 60 * 60))
        return SyncWindow(startDate: startDate, endDate: endDate)
    }

    static func upcomingSevenDays(referenceDate: Date = Date(), calendar: Calendar = .current) -> SyncWindow {
        upcomingDays(7, referenceDate: referenceDate, calendar: calendar)
    }

    func contains(_ date: Date) -> Bool {
        date >= startDate && date < endDate
    }
}
