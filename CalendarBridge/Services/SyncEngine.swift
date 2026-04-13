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
        let records = try await outlookService.fetchEvents(calendarID: sourceCalendarID)
        let existingMappings = await metadataStore.mappings(for: destinationCalendarID)

        var updatedCount = 0
        let validSourceKeys = Set(records.map(\.sourceKey))

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
                destinationCalendarID: destinationCalendarID
            )
            updatedCount += 1
        }

        let removedAppleEventIDs = await metadataStore.removeMissing(
            validSourceKeys: validSourceKeys,
            destinationCalendarID: destinationCalendarID
        )

        var deletedCount = 0
        for eventID in removedAppleEventIDs {
            try await appleCalendarService.removeEvent(withIdentifier: eventID)
            deletedCount += 1
        }

        return SyncResult(sourceEventCount: records.count, updatedCount: updatedCount, deletedCount: deletedCount)
    }
}
