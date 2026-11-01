import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()

        // Only one copy should ever own the notch.
        let mine = Bundle.main.bundleIdentifier ?? ""
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: mine)
            .filter { $0 != NSRunningApplication.current }
        if !mine.isEmpty && !others.isEmpty {
            NSApp.terminate(nil)
            return
        }

        if !UserDefaults.standard.bool(forKey: Settings.didSetUpLoginItem) {
            LoginItem.setEnabled(true)
            UserDefaults.standard.set(true, forKey: Settings.didSetUpLoginItem)
        }

        let services = Services.shared
        services.start()
        notchController = NotchWindowController(services: services, openSettings: { [weak self] in
            self?.showSettings()
        })

        updateStatusItem()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateStatusItem()
        }
    }

    private func updateStatusItem() {
        let wanted = UserDefaults.standard.bool(forKey: Settings.showMenuBarIcon)
        if wanted, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "OpenNotch")
            let menu = NSMenu()
            menu.addItem(withTitle: "Settings…", action: #selector(showSettingsAction), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit OpenNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu
            statusItem = item
        } else if !wanted, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func showSettingsAction() { showSettings() }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            window.title = "OpenNotch Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // Opening the app again from Finder/Spotlight shows settings, since there is no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
}
