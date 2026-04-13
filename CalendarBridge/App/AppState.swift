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
        await requestCalendarAccessIfNeeded()
        await loadAppleCalendars()
        await loadOutlookCalendars()
        autoSelectDefaultsIfNeeded()
    }

    func requestCalendarAccessIfNeeded() async {
        do {
            calendarAccessGranted = try await appleCalendarService.requestAccessIfNeeded()
        } catch {
            calendarAccessGranted = false
            lastSyncMessage = "Calendar access failed: \(error.localizedDescription)"
        }
    }

    func loadAppleCalendars() async {
        appleCalendars = await appleCalendarService.fetchWritableCalendars()
    }

    func loadOutlookCalendars() async {
        do {
            outlookCalendars = try await outlookService.fetchCalendars()
            automationStatus = outlookCalendars.isEmpty ? "No Outlook calendars found" : "Outlook connected"
        } catch {
            outlookCalendars = []
            automationStatus = "Outlook access failed"
            lastSyncMessage = "Failed to read Outlook calendars: \(error.localizedDescription)"
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
            return
        }

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
            lastSyncMessage = "\(triggerText) sync finished: \(syncedText) updated\(deletedText)"
        } catch {
            lastSyncMessage = "Sync failed: \(error.localizedDescription)"
        }
    }

    func selectedOutlookCalendarName() -> String {
        outlookCalendars.first(where: { $0.id == settings.selectedOutlookCalendarID })?.name ?? "Not selected"
    }

    func selectedAppleCalendarName() -> String {
        appleCalendars.first(where: { $0.id == settings.selectedAppleCalendarID })?.title ?? "Not selected"
    }

    private func autoSelectDefaultsIfNeeded() {
        if settings.selectedOutlookCalendarID.isEmpty, let onlyOutlook = outlookCalendars.first {
            settings.selectedOutlookCalendarID = onlyOutlook.id
        }

        if settings.selectedAppleCalendarID.isEmpty, let matching = appleCalendars.first(where: { $0.title.localizedCaseInsensitiveContains("outlook") }) ?? appleCalendars.first {
            settings.selectedAppleCalendarID = matching.id
        }

        settings.save()
    }
}
