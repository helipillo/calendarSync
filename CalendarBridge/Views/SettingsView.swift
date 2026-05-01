import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("CalendarBridge")
                .font(.largeTitle.bold())

            Text("Mirror events from one calendar into another from a native macOS menu bar app. Apple Calendar is the recommended source — including Exchange accounts added via Internet Accounts.")
                .foregroundStyle(.secondary)

            Form {
                Section("Configuration") {
                    SyncConfigurationView(compact: false)
                }

                Section("Status") {
                    LabeledContent(appState.settings.sourceType.displayName) {
                        Text(appState.sourceStatus)
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
                    Text("Recommended: create a dedicated Apple Calendar such as 'Work Mirror' and select it as the destination.")
                    Text("Only events created by CalendarBridge are updated or removed in the destination calendar — your existing entries are left untouched.")
                    Text("The Outlook source uses macOS automation; if Outlook isn't available, prefer the Apple Calendar source.")
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
