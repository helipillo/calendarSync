import EventKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var settings = AppSettings.load()
    @Published private(set) var outlookCalendars: [OutlookCalendarRef] = []
    @Published private(set) var appleCalendars: [AppleCalendarRef] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncMessage = "Not synced yet"
    @Published private(set) var automationStatus = "Waiting for Outlook access"
    @Published private(set) var calendarAccessGranted = false
    @Published private(set) var debugLog: [String] = []

    private let appleCalendarService = AppleCalendarService()
    private let outlookService = OutlookScriptService()
    private let metadataStore = SyncMetadataStore()
    private lazy var syncEngine = SyncEngine(
        appleCalendarService: appleCalendarService,
        outlookService: outlookService,
        metadataStore: metadataStore
    )
    private var scheduler: SyncScheduler?
    private var hasStarted = false

    var statusSymbolName: String {
        if isSyncing { return "arrow.triangle.2.circlepath.circle.fill" }
        if lastSyncMessage.lowercased().contains("failed") { return "calendar.badge.exclamationmark" }
        return "calendar.badge.clock"
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await refreshAll()
        configureScheduler()

        if settings.isConfigured {
            await syncNow(trigger: .launch)
        }
    }

    func refreshAll() async {
        log("Refreshing calendars and permissions")
        await requestCalendarAccessIfNeeded()
        await loadAppleCalendars()
        await loadOutlookCalendars()
        autoSelectDefaultsIfNeeded()
        log("Refresh complete. Outlook calendars=\(outlookCalendars.count), Apple calendars=\(appleCalendars.count)")
    }

    func requestCalendarAccessIfNeeded() async {
        do {
            calendarAccessGranted = try await appleCalendarService.requestAccessIfNeeded()
            log("Apple Calendar access granted=\(calendarAccessGranted)")
        } catch {
            calendarAccessGranted = false
            lastSyncMessage = "Calendar access failed: \(error.localizedDescription)"
            log("Apple Calendar access error: \(error.localizedDescription)")
        }
    }

    func loadAppleCalendars() async {
        appleCalendars = await appleCalendarService.fetchWritableCalendars()
        log("Loaded \(appleCalendars.count) writable Apple calendars")
    }

    func loadOutlookCalendars() async {
        do {
            outlookCalendars = try await outlookService.fetchCalendars()
            automationStatus = outlookCalendars.isEmpty ? "No Outlook calendars found" : "Outlook connected"
            log("Loaded \(outlookCalendars.count) Outlook calendars")
        } catch {
            outlookCalendars = []
            automationStatus = "Outlook access failed"
            lastSyncMessage = "Failed to read Outlook calendars: \(error.localizedDescription)"
            log("Outlook calendar load error: \(error.localizedDescription)")
        }
    }

    func configureScheduler() {
        scheduler?.stop()
        scheduler = SyncScheduler { [weak self] in
            Task { @MainActor in
                await self?.syncNow(trigger: .scheduled)
            }
        }
        scheduler?.start(frequency: settings.syncFrequency)
    }

    func saveSettings() {
        settings.save()
        configureScheduler()
    }

    func syncNow(trigger: SyncTrigger = .manual) async {
        guard !isSyncing else { return }
        guard settings.isConfigured else {
            lastSyncMessage = "Choose both an Outlook source calendar and an Apple destination calendar"
            log("Sync skipped because configuration is incomplete")
            return
        }

        log("Starting \(trigger.description.lowercased()) sync")
        log("Selected Outlook calendar id=\(settings.selectedOutlookCalendarID) name=\(selectedOutlookCalendarName())")
        log("Selected Apple calendar id=\(settings.selectedAppleCalendarID) name=\(selectedAppleCalendarName())")

        isSyncing = true
        defer { isSyncing = false }

        do {
            let result = try await syncEngine.sync(
                sourceCalendarID: settings.selectedOutlookCalendarID,
                destinationCalendarID: settings.selectedAppleCalendarID
            )

            settings.lastSyncAt = Date()
            settings.save()

            let syncedText = result.updatedCount == 1 ? "1 event" : "\(result.updatedCount) events"
            let deletedText = result.deletedCount == 0 ? "" : ", removed \(result.deletedCount)"
            let triggerText = trigger.description
            log("Sync backend: \(result.backendDescription)")
            log("Source events in next 7 days: \(result.sourceEventCount)")
            log("Updated \(result.updatedCount) events, deleted \(result.deletedCount)")
            let previewEvents = try await outlookService.fetchEvents(
                calendarID: settings.selectedOutlookCalendarID,
                window: SyncWindow.upcomingSevenDays()
            )
            for record in previewEvents.records.prefix(10) {
                log("Source preview: \(Self.debugDateFormatter.string(from: record.startDate)) | \(record.subject)")
            }
            if result.sourceEventCount == 0 {
                lastSyncMessage = "\(triggerText) sync found 0 Outlook events in the next 7 days using \(result.backendDescription)."
            } else {
                lastSyncMessage = "\(triggerText) sync finished via \(result.backendDescription): \(syncedText) updated\(deletedText)"
            }
        } catch {
            lastSyncMessage = "Sync failed: \(error.localizedDescription)"
            log("Sync failed: \(error.localizedDescription)")
        }
    }

    func selectedOutlookCalendarName() -> String {
        outlookCalendars.first(where: { $0.id == settings.selectedOutlookCalendarID })?.name ?? "Not selected"
    }

    func selectedAppleCalendarName() -> String {
        appleCalendars.first(where: { $0.id == settings.selectedAppleCalendarID })?.title ?? "Not selected"
    }

    private func autoSelectDefaultsIfNeeded() {
        if !outlookCalendars.contains(where: { $0.id == settings.selectedOutlookCalendarID }) {
            settings.selectedOutlookCalendarID = outlookCalendars.first?.id ?? ""
            log("Adjusted Outlook selection to a valid calendar")
        }

        if !appleCalendars.contains(where: { $0.id == settings.selectedAppleCalendarID }) {
            let matching = appleCalendars.first(where: { $0.title.localizedCaseInsensitiveContains("outlook") }) ?? appleCalendars.first
            settings.selectedAppleCalendarID = matching?.id ?? ""
            log("Adjusted Apple Calendar selection to a valid calendar")
        }

        settings.save()
    }

    func clearDebugLog() {
        debugLog.removeAll()
    }

    private func log(_ message: String) {
        let entry = "[\(Self.logTimeFormatter.string(from: Date()))] \(message)"
        debugLog.append(entry)
        if debugLog.count > 200 {
            debugLog.removeFirst(debugLog.count - 200)
        }
    }

    private static let logTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let debugDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
