import Foundation

actor SyncEngine {
    private let appleCalendarService: AppleCalendarService
    private let outlookService: OutlookScriptService
    private let metadataStore: SyncMetadataStore

    init(
        appleCalendarService: AppleCalendarService,
        outlookService: OutlookScriptService,
        metadataStore: SyncMetadataStore
    ) {
        self.appleCalendarService = appleCalendarService
        self.outlookService = outlookService
        self.metadataStore = metadataStore
    }

    func sync(sourceCalendarID: String, destinationCalendarID: String) async throws -> SyncResult {
        let window = SyncWindow.upcomingSevenDays()
        let fetchResult = try await outlookService.fetchEvents(calendarID: sourceCalendarID, window: window)
        let records = fetchResult.records
        let existingMappings = await metadataStore.mappings(for: destinationCalendarID)

        var updatedCount = 0
        let validSourceKeys = Set(records.map(\.sourceKey))

        let outsideWindowAppleEventIDs = await metadataStore.removeOutsideWindow(
            destinationCalendarID: destinationCalendarID,
            window: window
        )

        var deletedCount = 0
        for eventID in outsideWindowAppleEventIDs {
            try await appleCalendarService.removeEvent(withIdentifier: eventID)
            deletedCount += 1
        }

        for record in records {
            let existingEventID = existingMappings[record.sourceKey]
            let appleEventID = try await appleCalendarService.upsertEvent(
                record: record,
                destinationCalendarID: destinationCalendarID,
                existingEventID: existingEventID
            )
            await metadataStore.save(
                sourceKey: record.sourceKey,
                appleEventID: appleEventID,
                destinationCalendarID: destinationCalendarID,
                sourceStartDate: record.startDate
            )
            updatedCount += 1
        }

        let removedAppleEventIDs = await metadataStore.removeMissing(
            validSourceKeys: validSourceKeys,
            destinationCalendarID: destinationCalendarID,
            window: window
        )

        for eventID in removedAppleEventIDs {
            try await appleCalendarService.removeEvent(withIdentifier: eventID)
            deletedCount += 1
        }

        return SyncResult(sourceEventCount: records.count, updatedCount: updatedCount, deletedCount: deletedCount, backendDescription: fetchResult.backendDescription)
    }
}
