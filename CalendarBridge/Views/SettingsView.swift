import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("CalendarBridge")
                .font(.largeTitle.bold())

            Text("Sync one Outlook calendar into a dedicated Apple Calendar from a native macOS menu bar app.")
                .foregroundStyle(.secondary)

            Form {
                Section("Configuration") {
                    SyncConfigurationView(compact: false)
                }

                Section("Status") {
                    LabeledContent("Outlook") {
                        Text(appState.automationStatus)
                    }
                    LabeledContent("Last sync") {
                        Text(lastSyncText)
                    }
                    LabeledContent("Message") {
                        Text(appState.lastSyncMessage)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Actions") {
                    HStack {
                        Button("Force Update") {
                            Task { await appState.syncNow() }
                        }
                        .disabled(appState.isSyncing || !appState.settings.isConfigured)

                        Button("Refresh Calendars") {
                            Task { await appState.refreshAll() }
                        }
                        .disabled(appState.isSyncing)
                    }
                }

                Section("Debug Log") {
                    HStack {
                        Button("Clear Debug Log") {
                            appState.clearDebugLog()
                        }
                        Spacer()
                        Text("\(appState.debugLog.count) entries")
                            .foregroundStyle(.secondary)
                    }

                    ScrollView {
                        Text(appState.debugLog.isEmpty ? "No debug messages yet." : appState.debugLog.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 180)
                }

                Section("Notes") {
                    Text("Recommended: create a dedicated Apple Calendar such as 'Work Outlook Mirror' and select it as the destination.")
                    Text("The app reads Outlook using macOS automation and writes into Apple Calendar using EventKit permissions.")
                    Text("Recurring events are mirrored using recurrence rules when Outlook exposes valid iCalendar data. Some complex recurring exceptions may still need future refinement.")
                }
            }
        }
        .padding(20)
    }

    private var lastSyncText: String {
        guard let lastSyncAt = appState.settings.lastSyncAt else { return "Never" }
        return DateFormatter.localizedString(from: lastSyncAt, dateStyle: .medium, timeStyle: .short)
    }
}
