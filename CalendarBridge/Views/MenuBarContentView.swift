import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CalendarBridge")
                        .font(.headline)
                    Text(appState.nextSyncCountdown)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if appState.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if appState.upcomingEventsCount > 0 {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.blue)
                    Text("\(appState.upcomingEventsCount) events to sync")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                    Label("Sync Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isSyncing || !appState.settings.isConfigured)

                Spacer()

                Toggle(isOn: $appState.showNotifications) {
                    Image(systemName: "bell")
                }
                .toggleStyle(.button)
                .controlSize(.small)
            }
        }
        .padding(16)
    }
}