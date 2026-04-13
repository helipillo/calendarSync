import AppKit
import SwiftUI

@main
struct CalendarBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("CalendarBridge", systemImage: appState.statusSymbolName) {
            MenuBarContentView()
                .environmentObject(appState)
                .frame(width: 380)
                .task {
                    await appState.start()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 520, height: 520)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
