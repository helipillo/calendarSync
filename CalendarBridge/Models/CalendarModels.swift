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
    let updatedCount: Int
    let deletedCount: Int
}
