import SwiftUI

struct SyncConfigurationView: View {
    @EnvironmentObject private var appState: AppState
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Outlook source")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Outlook source", selection: outlookSelection) {
                    Text("Select an Outlook calendar").tag("")
                    ForEach(appState.outlookCalendars) { calendar in
                        Text(calendar.name).tag(calendar.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Apple Calendar destination")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Apple destination", selection: appleSelection) {
                    Text("Select an Apple Calendar").tag("")
                    ForEach(appState.appleCalendars) { calendar in
                        Text("\(calendar.title) · \(calendar.sourceTitle)").tag(calendar.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

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
    }

    private var outlookSelection: Binding<String> {
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

    private var appleSelection: Binding<String> {
        Binding(
            get: {
                appState.appleCalendars.contains(where: { $0.id == appState.settings.selectedAppleCalendarID })
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
}
