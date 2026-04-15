import EventKit
import Foundation

actor AppleCalendarService {
    private let eventStore = EKEventStore()
    private let markerPrefix = "[CalendarBridge source="
    private let recurrenceParser = ICalendarRecurrenceParser()
    private let cleanupLookbackDays = 30
    private let cleanupFutureDays = 365

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

    func mirroredEventIdentifiers(destinationCalendarID: String, window: SyncWindow) -> [String: String] {
        guard let calendar = eventStore.calendar(withIdentifier: destinationCalendarID) else {
            return [:]
        }

        let predicate = eventStore.predicateForEvents(
            withStart: window.startDate,
            end: window.endDate,
            calendars: [calendar]
        )

        return eventStore.events(matching: predicate).reduce(into: [:]) { partialResult, event in
            guard let notes = event.notes,
                  let sourceKey = extractSourceKey(from: notes),
                  let eventID = event.eventIdentifier else {
                return
            }
            partialResult[sourceKey] = eventID
        }
    }

    func removeMirroredEventsNotIn(destinationCalendarID: String, window: SyncWindow, validSourceKeys: Set<String>) throws -> Int {
        guard let calendar = eventStore.calendar(withIdentifier: destinationCalendarID) else {
            return 0
        }

        let now = Date()
        let predicate = eventStore.predicateForEvents(
            withStart: window.startDate,
            end: window.endDate,
            calendars: [calendar]
        )

        var deletedCount = 0
        for event in eventStore.events(matching: predicate) {
            guard let notes = event.notes,
                  let sourceKey = extractSourceKey(from: notes),
                  !validSourceKeys.contains(sourceKey),
                  event.startDate >= now else {
                continue
            }
            try eventStore.remove(event, span: .thisEvent, commit: true)
            deletedCount += 1
        }
        return deletedCount
    }

    func removeMirroredEventsOutsideWindow(destinationCalendarID: String, window: SyncWindow) throws -> Int {
        guard let calendar = eventStore.calendar(withIdentifier: destinationCalendarID) else {
            return 0
        }

        let now = Date()
        let searchStart = Calendar.current.date(byAdding: .day, value: -cleanupLookbackDays, to: window.startDate) ?? window.startDate
        let searchEnd = Calendar.current.date(byAdding: .day, value: cleanupFutureDays, to: window.endDate) ?? window.endDate
        let predicate = eventStore.predicateForEvents(
            withStart: searchStart,
            end: searchEnd,
            calendars: [calendar]
        )

        var deletedCount = 0
        for event in eventStore.events(matching: predicate) {
            guard let notes = event.notes,
                  extractSourceKey(from: notes) != nil,
                  let startDate = event.startDate,
                  !window.contains(startDate),
                  startDate >= now else {
                continue
            }
            try eventStore.remove(event, span: .thisEvent, commit: true)
            deletedCount += 1
        }
        return deletedCount
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

    func fetchReadableCalendars() -> [AppleCalendarRef] {
        let allCalendars = Array(eventStore.calendars(for: .event))
        let result = allCalendars.map { cal in
            AppleCalendarRef(
                id: cal.calendarIdentifier,
                title: cal.title,
                sourceTitle: cal.source.title
            )
        }
        return result.sorted {
            if $0.sourceTitle == $1.sourceTitle {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.sourceTitle.localizedCaseInsensitiveCompare($1.sourceTitle) == .orderedAscending
        }
    }

    func fetchEvents(calendarID: String, window: SyncWindow, destinationCalendarID: String?) -> [SyncEventRecord] {
        guard let calendar = eventStore.calendar(withIdentifier: calendarID) else {
            return []
        }

        let predicate = eventStore.predicateForEvents(
            withStart: window.startDate,
            end: window.endDate,
            calendars: [calendar]
        )

        let allEvents = eventStore.events(matching: predicate)
        var result: [SyncEventRecord] = []
        for event in allEvents {
            guard let eventID = event.eventIdentifier else { continue }

            if let destinationCalendarID,
               isMirroredFromCalendar(event: event, calendarID: destinationCalendarID) {
                continue
            }

            result.append(SyncEventRecord(
                sourceCalendarID: calendarID,
                sourceCalendarName: calendar.title,
                eventID: eventID,
                subject: event.title ?? "",
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location,
                notes: event.notes,
                allDay: event.isAllDay,
                modificationDate: event.lastModifiedDate
            ))
        }
        return result
    }

    private func isMirroredFromCalendar(event: EKEvent, calendarID: String) -> Bool {
        guard let notes = event.notes,
              let sourceKey = extractSourceKey(from: notes) else {
            return false
        }
        return sourceKey.hasPrefix("apple:\(calendarID):")
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

    func upsertEvent(record: SyncEventRecord, destinationCalendarID: String, existingEventID: String?) throws -> String {
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

        try eventStore.save(event, span: .thisEvent, commit: true)

        guard let eventID = event.eventIdentifier else {
            throw SyncError.failedToPersistEventIdentifier
        }

        return eventID
    }

    private func buildNotes(from record: SyncEventRecord) -> String {
        let sourceLine = "\(markerPrefix)\(record.sourceKey)]"
        let body = (record.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if body.isEmpty {
            return sourceLine
        }

        return body + "\n\n" + sourceLine
    }

    private func buildNotes(from record: OutlookEventRecord) -> String {
        let sourceLine = "\(markerPrefix)\(record.sourceKey)]"
        let body = (record.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if body.isEmpty {
            return sourceLine
        }

        return body + "\n\n" + sourceLine
    }

    private func extractSourceKey(from notes: String) -> String? {
        guard let startRange = notes.range(of: markerPrefix),
              let endRange = notes.range(of: "]", range: startRange.upperBound..<notes.endIndex) else {
            return nil
        }
        return String(notes[startRange.upperBound..<endRange.lowerBound])
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
