import AppKit
import Combine
import SwiftUI

@main
struct CalendarBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let appState = AppState()
    private var statusCancellable: AnyCancellable?

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
            setupPopover()
            observeStatusIcon()
            await appState.start()
        }
    }

    private func observeStatusIcon() {
        statusCancellable = appState.$syncStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusIcon()
            }
    }

    func setupPopover() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateStatusIcon()

            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
    }

    private func updateStatusIcon() {
        let imageName = appState.statusSymbolName
        statusItem?.button?.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "CalendarBridge")
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let syncItem = NSMenuItem(title: "Sync Now", action: #selector(syncNow), keyEquivalent: "s")
        syncItem.target = self
        menu.addItem(syncItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit CalendarBridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func syncNow() {
        Task {
            await appState.syncNow(trigger: .manual)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if let popover = popover, popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(sender)
        }
    }

    private func showPopover(_ sender: NSStatusBarButton) {
        if popover == nil {
            popover = NSPopover()
            popover?.contentSize = NSSize(width: 380, height: 400)
            popover?.behavior = .transient
            popover?.animates = true

            let contentView = MenuBarContentView()
                .environmentObject(appState)
            popover?.contentViewController = NSHostingController(rootView: contentView)
        }

        popover?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)

        Task {
            await appState.refreshAll()
        }
    }
}
