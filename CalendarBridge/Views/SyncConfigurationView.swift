import SwiftUI

struct SyncConfigurationView: View {
    @EnvironmentObject private var appState: AppState
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sourceTypeSection

            sourceCalendarSection

            destinationCalendarSection

            bidirectionalSection

            syncWindowSection

            syncFrequencySection
        }
        .onAppear {
            Task { await appState.refreshAll() }
        }
    }

    private var sourceTypeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Source type")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Source type", selection: sourceTypeSelection) {
                ForEach(SyncSourceType.allCases) { sourceType in
                    Text(sourceType.displayName).tag(sourceType)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var sourceCalendarSection: some View {
        switch appState.settings.sourceType {
        case .appleCalendar:
            VStack(alignment: .leading, spacing: 6) {
                Text("Source calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Source calendar", selection: sourceAppleSelection) {
                    Text("Select a source calendar").tag("")
                    ForEach(appState.sourceAppleCalendars) { calendar in
                        Text("\(calendar.title) · \(calendar.sourceTitle)").tag(calendar.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .outlook:
            VStack(alignment: .leading, spacing: 6) {
                Text("Outlook source")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Outlook source", selection: sourceOutlookSelection) {
                    Text("Select an Outlook calendar").tag("")
                    ForEach(appState.outlookCalendars) { calendar in
                        Text(calendar.name).tag(calendar.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var destinationCalendarSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Destination calendar")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Destination calendar", selection: destinationSelection) {
                Text("Select a destination calendar").tag("")
                ForEach(appState.destinationAppleCalendars) { calendar in
                    Text("\(calendar.title) · \(calendar.sourceTitle)").tag(calendar.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var bidirectionalSection: some View {
        if appState.settings.sourceType == .appleCalendar {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Bidirectional sync", isOn: bidirectionalSelection)
                    .toggleStyle(.switch)

                Text("Edits sync both ways; deletions sync Source to Destination only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var syncWindowSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sync window")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Sync window", selection: windowDurationSelection) {
                ForEach(SyncWindowDuration.allCases) { duration in
                    Text(duration.description).tag(duration)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var syncFrequencySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sync frequency")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Sync frequency", selection: frequencySelection) {
                ForEach(SyncFrequency.allCases) { frequency in
                    Text(frequency.description).tag(frequency)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var sourceTypeSelection: Binding<SyncSourceType> {
        Binding(
            get: { appState.settings.sourceType },
            set: { newValue in
                appState.settings.sourceType = newValue
                appState.saveSettings()
                Task {
                    await appState.refreshAll()
                }
            }
        )
    }

    private var sourceAppleSelection: Binding<String> {
        Binding(
            get: {
                appState.sourceAppleCalendars.contains(where: { $0.id == appState.settings.selectedSourceAppleCalendarID })
                    ? appState.settings.selectedSourceAppleCalendarID
                    : ""
            },
            set: { newValue in
                appState.settings.selectedSourceAppleCalendarID = newValue
                appState.saveSettings()
            }
        )
    }

    private var sourceOutlookSelection: Binding<String> {
        Binding(
            get: {
                appState.outlookCalendars.contains(where: { $0.id == appState.settings.selectedOutlookCalendarID })
                    ? appState.settings.selectedOutlookCalendarID
                    : ""
            },
            set: { newValue in
                appState.settings.selectedOutlookCalendarID = newValue
                appState.saveSettings()
            }
        )
    }

    private var destinationSelection: Binding<String> {
        Binding(
            get: {
                appState.destinationAppleCalendars.contains(where: { $0.id == appState.settings.selectedAppleCalendarID })
                    ? appState.settings.selectedAppleCalendarID
                    : ""
            },
            set: { newValue in
                appState.settings.selectedAppleCalendarID = newValue
                appState.saveSettings()
            }
        )
    }

    private var frequencySelection: Binding<SyncFrequency> {
        Binding(
            get: { appState.settings.syncFrequency },
            set: { newValue in
                appState.settings.syncFrequency = newValue
                appState.saveSettings()
            }
        )
    }

    private var windowDurationSelection: Binding<SyncWindowDuration> {
        Binding(
            get: { appState.settings.syncWindowDuration },
            set: { newValue in
                appState.settings.syncWindowDuration = newValue
                appState.saveSettings()
            }
        )
    }

    private var bidirectionalSelection: Binding<Bool> {
        Binding(
            get: { appState.settings.isBidirectionalSyncEnabled },
            set: { newValue in
                appState.settings.isBidirectionalSyncEnabled = newValue
                appState.saveSettings()
                Task { await appState.updateUpcomingEventsCount() }
            }
        )
    }
}