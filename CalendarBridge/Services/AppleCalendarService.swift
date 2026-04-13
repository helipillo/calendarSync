import EventKit
import Foundation

actor AppleCalendarService {
    private let eventStore = EKEventStore()
    private let markerPrefix = "[CalendarBridge source="
    private let recurrenceParser = ICalendarRecurrenceParser()

    func requestAccessIfNeeded() async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await eventStore.requestFullAccessToEvents()
        }

        return try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func fetchWritableCalendars() -> [AppleCalendarRef] {
        eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map {
                AppleCalendarRef(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    sourceTitle: $0.source.title
                )
            }
            .sorted {
                if $0.sourceTitle == $1.sourceTitle {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle) == .orderedAscending
            }
    }

    func upsertEvent(record: OutlookEventRecord, destinationCalendarID: String, existingEventID: String?) throws -> String {
        guard let calendar = eventStore.calendar(withIdentifier: destinationCalendarID) else {
            throw SyncError.destinationCalendarMissing
        }

        let event: EKEvent
        if let existingEventID, let existing = eventStore.event(withIdentifier: existingEventID) {
            event = existing
        } else {
            event = EKEvent(eventStore: eventStore)
        }

        event.calendar = calendar
        event.title = record.subject.isEmpty ? "(No title)" : record.subject
        event.startDate = record.startDate
        event.endDate = record.endDate
        event.isAllDay = record.allDay
        event.location = record.location
        event.notes = buildNotes(from: record)
        event.timeZone = record.allDay ? nil : TimeZone.current
        event.recurrenceRules = recurrenceParser.recurrenceRules(from: record.icalendarData)

        try eventStore.save(event, span: .thisEvent, commit: true)

        guard let eventID = event.eventIdentifier else {
            throw SyncError.failedToPersistEventIdentifier
        }

        return eventID
    }

    func removeEvent(withIdentifier identifier: String) throws {
        guard let event = eventStore.event(withIdentifier: identifier) else { return }
        try eventStore.remove(event, span: .thisEvent, commit: true)
    }

    private func buildNotes(from record: OutlookEventRecord) -> String {
        let sourceLine = "\(markerPrefix)\(record.sourceKey)]"
        let body = (record.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if body.isEmpty {
            return sourceLine
        }

        return body + "\n\n" + sourceLine
    }
}

enum SyncError: LocalizedError {
    case destinationCalendarMissing
    case failedToPersistEventIdentifier

    var errorDescription: String? {
        switch self {
        case .destinationCalendarMissing:
            return "The selected Apple Calendar no longer exists"
        case .failedToPersistEventIdentifier:
            return "Apple Calendar did not return an event identifier"
        }
    }
}
