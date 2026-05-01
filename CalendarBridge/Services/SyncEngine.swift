import Foundation

actor SyncEngine {
    private let appleCalendarService: AppleCalendarService
    private let outlookService: OutlookScriptService

    init(
        appleCalendarService: AppleCalendarService,
        outlookService: OutlookScriptService
    ) {
        self.appleCalendarService = appleCalendarService
        self.outlookService = outlookService
    }

    func sync(
        sourceType: SyncSourceType,
        sourceCalendarID: String,
        destinationCalendarID: String,
        windowDuration: SyncWindowDuration = .sevenDays,
        bidirectionalAppleSyncEnabled: Bool = false
    ) async throws -> SyncResult {
        let window = SyncWindow.upcomingDays(windowDuration.days)

        let forward = try await syncOneWay(
            sourceType: sourceType,
            sourceCalendarID: sourceCalendarID,
            destinationCalendarID: destinationCalendarID,
            window: window,
            allowDeletions: true
        )

        guard sourceType == .appleCalendar, bidirectionalAppleSyncEnabled else {
            return forward
        }

        let reverse = try await syncOneWay(
            sourceType: .appleCalendar,
            sourceCalendarID: destinationCalendarID,
            destinationCalendarID: sourceCalendarID,
            window: window,
            allowDeletions: false
        )

        return SyncResult(
            sourceEventCount: forward.sourceEventCount + reverse.sourceEventCount,
            updatedCount: forward.updatedCount + reverse.updatedCount,
            deletedCount: forward.deletedCount + reverse.deletedCount,
            backendDescription: "Apple Calendar ↔ Apple Calendar"
        )
    }

    private func syncOneWay(
        sourceType: SyncSourceType,
        sourceCalendarID: String,
        destinationCalendarID: String,
        window: SyncWindow,
        allowDeletions: Bool
    ) async throws -> SyncResult {
        let records: [SyncEventRecord]

        switch sourceType {
        case .appleCalendar:
            records = await appleCalendarService.fetchEvents(
                calendarID: sourceCalendarID,
                window: window,
                destinationCalendarID: destinationCalendarID
            )
        case .outlook:
            let fetchResult = try await outlookService.fetchEvents(calendarID: sourceCalendarID, window: window)
            records = fetchResult.records.map { outlookRecord in
                SyncEventRecord(
                    sourceCalendarID: outlookRecord.sourceCalendarID,
                    sourceCalendarName: outlookRecord.sourceCalendarName,
                    eventID: outlookRecord.eventID,
                    subject: outlookRecord.subject,
                    startDate: outlookRecord.startDate,
                    endDate: outlookRecord.endDate,
                    location: outlookRecord.location,
                    notes: outlookRecord.notes,
                    allDay: outlookRecord.allDay,
                    modificationDate: outlookRecord.modificationDate
                )
            }
        }

        let existingMappings = await appleCalendarService.mirroredEventIdentifiers(
            destinationCalendarID: destinationCalendarID,
            window: window
        )

        var updatedCount = 0
        let validSourceKeys = Set(records.map(\.sourceKey))

        var deletedCount = 0
        if allowDeletions {
            deletedCount = try await appleCalendarService.removeMirroredEventsOutsideWindow(
                destinationCalendarID: destinationCalendarID,
                window: window
            )
        }

        for record in records {
            let existingEventID = existingMappings[record.sourceKey]
            _ = try await appleCalendarService.upsertEvent(
                record: record,
                destinationCalendarID: destinationCalendarID,
                existingEventID: existingEventID
            )
            updatedCount += 1
        }

        if allowDeletions {
            deletedCount += try await appleCalendarService.removeMirroredEventsNotIn(
                destinationCalendarID: destinationCalendarID,
                window: window,
                validSourceKeys: validSourceKeys
            )
        }

        return SyncResult(
            sourceEventCount: records.count,
            updatedCount: updatedCount,
            deletedCount: deletedCount,
            backendDescription: sourceType.displayName
        )
    }
}
