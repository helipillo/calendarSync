import Foundation

actor SyncEngine {
    private let appleCalendarService: AppleCalendarService
    private let outlookService: OutlookScriptService

    init(
        appleCalendarService: AppleCalendarService,
        outlookService: OutlookScriptService,
        metadataStore: SyncMetadataStore
    ) {
        self.appleCalendarService = appleCalendarService
        self.outlookService = outlookService
    }

    func sync(sourceCalendarID: String, destinationCalendarID: String) async throws -> SyncResult {
        let window = SyncWindow.upcomingSevenDays()
        let fetchResult = try await outlookService.fetchEvents(calendarID: sourceCalendarID, window: window)
        let records = fetchResult.records
        let existingMappings = await appleCalendarService.mirroredEventIdentifiers(
            destinationCalendarID: destinationCalendarID,
            window: window
        )

        var updatedCount = 0
        let validSourceKeys = Set(records.map(\.sourceKey))

        var deletedCount = try await appleCalendarService.removeMirroredEventsOutsideWindow(
            destinationCalendarID: destinationCalendarID,
            window: window
        )

        for record in records {
            let existingEventID = existingMappings[record.sourceKey]
            let appleEventID = try await appleCalendarService.upsertEvent(
                record: record,
                destinationCalendarID: destinationCalendarID,
                existingEventID: existingEventID
            )
            updatedCount += 1
        }

        deletedCount += try await appleCalendarService.removeMirroredEventsNotIn(
            destinationCalendarID: destinationCalendarID,
            window: window,
            validSourceKeys: validSourceKeys
        )

        return SyncResult(sourceEventCount: records.count, updatedCount: updatedCount, deletedCount: deletedCount, backendDescription: fetchResult.backendDescription)
    }
}
