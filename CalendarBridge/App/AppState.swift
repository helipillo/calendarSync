import EventKit
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    @Published var settings = AppSettings.load()
    @Published private(set) var outlookCalendars: [OutlookCalendarRef] = []
    @Published private(set) var sourceAppleCalendars: [AppleCalendarRef] = []
    @Published private(set) var destinationAppleCalendars: [AppleCalendarRef] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncMessage = "Not synced yet"
    @Published private(set) var sourceStatus = "Waiting for calendar access"
    @Published private(set) var calendarAccessGranted = false
    @Published private(set) var debugLog: [String] = []
    @Published private(set) var upcomingEventsCount: Int = 0
    @Published private(set) var nextSyncCountdown: String = ""
    @Published var showNotifications: Bool = true

    private let appleCalendarService = AppleCalendarService()
    private let outlookService = OutlookScriptService()
    private lazy var syncEngine = SyncEngine(
        appleCalendarService: appleCalendarService,
        outlookService: outlookService
    )
    private var scheduler: SyncScheduler?
    private var hasStarted = false
    private var countdownTimer: Timer?

    enum SyncStatus {
        case idle
        case syncing
        case success
        case error
    }

    @Published private(set) var syncStatus: SyncStatus = .idle

    var statusSymbolName: String {
        switch syncStatus {
        case .idle:
            return "calendar"
        case .syncing:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.circle.fill"
        }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await requestNotificationPermission()
        await refreshAll()
        configureScheduler()
        startCountdownTimer()

        if settings.isConfigured {
            await syncNow(trigger: .launch)
        }
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            log("Notification permission error: \(error.localizedDescription)")
        }
    }

    private func startCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCountdown()
            }
        }
        updateCountdown()
    }

    private func updateCountdown() {
        guard let lastSync = settings.lastSyncAt else {
            nextSyncCountdown = "Sync soon"
            return
        }
        let nextSync = lastSync.addingTimeInterval(settings.syncFrequency.interval)
        let interval = nextSync.timeIntervalSinceNow
        if interval <= 0 {
            nextSyncCountdown = "Sync now"
        } else {
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            if hours > 0 {
                nextSyncCountdown = "Next sync in \(hours)h \(minutes)m"
            } else {
                nextSyncCountdown = "Next sync in \(minutes)m"
            }
        }
    }

    func refreshAll() async {
        log("Refreshing calendars and permissions")
        await requestCalendarAccessIfNeeded()
        await loadAppleCalendars()
        if settings.sourceType == .outlook {
            await loadOutlookCalendars()
        } else {
            outlookCalendars = []
            sourceStatus = calendarAccessGranted ? "Apple Calendar connected" : "Calendar access not granted"
        }
        autoSelectDefaultsIfNeeded()
        await updateUpcomingEventsCount()
        log("Refresh complete. Source calendars=\(sourceAppleCalendars.count), Destination calendars=\(destinationAppleCalendars.count)")
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
        sourceAppleCalendars = await appleCalendarService.fetchReadableCalendars()
        destinationAppleCalendars = await appleCalendarService.fetchWritableCalendars()
        log("Loaded \(sourceAppleCalendars.count) source calendars, \(destinationAppleCalendars.count) destination calendars")
    }

    func loadOutlookCalendars() async {
        do {
            outlookCalendars = try await outlookService.fetchCalendars()
            sourceStatus = outlookCalendars.isEmpty ? "No Outlook calendars found" : "Outlook connected"
            log("Loaded \(outlookCalendars.count) Outlook calendars")
        } catch {
            outlookCalendars = []
            sourceStatus = "Outlook access failed"
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
            lastSyncMessage = "Choose a source calendar and an Apple destination calendar"
            log("Sync skipped because configuration is incomplete")
            return
        }

        guard settings.sourceType != .appleCalendar || settings.selectedSourceAppleCalendarID != settings.selectedAppleCalendarID else {
            lastSyncMessage = "Source and destination cannot be the same calendar"
            log("Sync skipped: source and destination are the same")
            return
        }

        log("Starting \(trigger.description.lowercased()) sync")
        log("Source type: \(settings.sourceType.displayName)")
        log("Selected source calendar id=\(settings.sourceCalendarConfigured) name=\(selectedSourceCalendarName())")
        log("Selected destination calendar id=\(settings.selectedAppleCalendarID) name=\(selectedDestinationCalendarName())")

        isSyncing = true
        syncStatus = .syncing
        defer {
            isSyncing = false
        }

        do {
            let result = try await syncEngine.sync(
                sourceType: settings.sourceType,
                sourceCalendarID: settings.sourceCalendarConfigured,
                destinationCalendarID: settings.selectedAppleCalendarID,
                windowDuration: settings.syncWindowDuration,
                bidirectionalAppleSyncEnabled: settings.isBidirectionalAppleSyncActive
            )

            settings.lastSyncAt = Date()
            settings.save()
            updateCountdown()

            let syncedText = result.updatedCount == 1 ? "1 event" : "\(result.updatedCount) events"
            let deletedText = result.deletedCount == 0 ? "" : ", removed \(result.deletedCount)"
            let triggerText = trigger.description
            log("Source events in next \(settings.syncWindowDuration.description): \(result.sourceEventCount)")
            log("Updated \(result.updatedCount) events, deleted \(result.deletedCount)")
            if settings.isBidirectionalAppleSyncActive {
                log("Bidirectional Apple sync is enabled")
            }

            if result.sourceEventCount == 0 {
                lastSyncMessage = "\(triggerText) sync found 0 events in the next \(settings.syncWindowDuration.description)."
            } else {
                lastSyncMessage = "\(triggerText) sync finished: \(syncedText) synced\(deletedText)"
                if settings.isBidirectionalAppleSyncActive {
                    lastSyncMessage = "\(triggerText) bidirectional sync finished: \(syncedText) synced\(deletedText)"
                }
            }

            syncStatus = .success
            await sendNotification(title: "Sync Complete", body: "\(syncedText) synced to \(selectedDestinationCalendarName())")

            Task {
                try? await Task.sleep(for: .seconds(3))
                syncStatus = .idle
            }
        } catch {
            lastSyncMessage = "Sync failed: \(error.localizedDescription)"
            log("Sync failed: \(error.localizedDescription)")
            syncStatus = .error
            await sendNotification(title: "Sync Failed", body: error.localizedDescription)

            Task {
                try? await Task.sleep(for: .seconds(5))
                syncStatus = .idle
            }
        }
    }

    private func sendNotification(title: String, body: String) async {
        guard showNotifications else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    func updateUpcomingEventsCount() async {
        guard settings.isConfigured else {
            upcomingEventsCount = 0
            return
        }
        let window = SyncWindow.upcomingDays(settings.syncWindowDuration.days)
        switch settings.sourceType {
        case .appleCalendar:
            let forwardEvents = await appleCalendarService.fetchEvents(
                calendarID: settings.selectedSourceAppleCalendarID,
                window: window,
                destinationCalendarID: settings.selectedAppleCalendarID
            )
            if settings.isBidirectionalAppleSyncActive {
                let reverseEvents = await appleCalendarService.fetchEvents(
                    calendarID: settings.selectedAppleCalendarID,
                    window: window,
                    destinationCalendarID: settings.selectedSourceAppleCalendarID
                )
                upcomingEventsCount = forwardEvents.count + reverseEvents.count
            } else {
                upcomingEventsCount = forwardEvents.count
            }
        case .outlook:
            do {
                let result = try await outlookService.fetchEvents(
                    calendarID: settings.selectedOutlookCalendarID,
                    window: window
                )
                upcomingEventsCount = result.records.count
            } catch {
                upcomingEventsCount = 0
            }
        }
    }

    func selectedSourceCalendarName() -> String {
        switch settings.sourceType {
        case .appleCalendar:
            return sourceAppleCalendars.first(where: { $0.id == settings.selectedSourceAppleCalendarID })?.title ?? "Not selected"
        case .outlook:
            return outlookCalendars.first(where: { $0.id == settings.selectedOutlookCalendarID })?.name ?? "Not selected"
        }
    }

    func selectedDestinationCalendarName() -> String {
        destinationAppleCalendars.first(where: { $0.id == settings.selectedAppleCalendarID })?.title ?? "Not selected"
    }

    private func autoSelectDefaultsIfNeeded() {
        switch settings.sourceType {
        case .appleCalendar:
            if !sourceAppleCalendars.contains(where: { $0.id == settings.selectedSourceAppleCalendarID }) {
                settings.selectedSourceAppleCalendarID = sourceAppleCalendars.first?.id ?? ""
                log("Adjusted Apple source selection to a valid calendar")
            }
        case .outlook:
            if !outlookCalendars.contains(where: { $0.id == settings.selectedOutlookCalendarID }) {
                settings.selectedOutlookCalendarID = outlookCalendars.first?.id ?? ""
                log("Adjusted Outlook selection to a valid calendar")
            }
        }

        if !destinationAppleCalendars.contains(where: { $0.id == settings.selectedAppleCalendarID }) {
            let matching = destinationAppleCalendars.first(where: { $0.title.localizedCaseInsensitiveContains("outlook") }) ?? destinationAppleCalendars.first
            settings.selectedAppleCalendarID = matching?.id ?? ""
            log("Adjusted destination calendar selection to a valid calendar")
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
}
