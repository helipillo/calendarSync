import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CalendarBridge")
                        .font(.headline)
                    Text("Outlook to Apple Calendar sync")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if appState.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    statusRow(title: "Outlook", value: appState.automationStatus)
                    statusRow(title: "Source", value: appState.selectedOutlookCalendarName())
                    statusRow(title: "Destination", value: appState.selectedAppleCalendarName())
                    statusRow(title: "Last sync", value: lastSyncText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SyncConfigurationView(compact: true)

            Text(appState.lastSyncMessage)
                .font(.caption)
                .foregroundStyle(appState.lastSyncMessage.lowercased().contains("failed") ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    Task { await appState.syncNow() }
                } label: {
                    Label("Force Update", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isSyncing || !appState.settings.isConfigured)

                Button("Refresh") {
                    Task { await appState.refreshAll() }
                }
                .disabled(appState.isSyncing)
            }

            Divider()

            HStack {
                Button {
                    openSettingsWindow()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(14)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .font(.caption)
    }

    private var lastSyncText: String {
        guard let lastSyncAt = appState.settings.lastSyncAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastSyncAt, relativeTo: Date())
    }

    private func openSettingsWindow() {
        if !NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            _ = NSApplication.shared.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
