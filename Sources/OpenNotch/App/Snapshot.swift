import AppKit
import SwiftUI

/// `OpenNotch --snapshot <dir>` renders the collapsed notch, a live activity and every
/// expanded tab to PNGs offscreen, then exits. Used to check layout without a screen.
enum Snapshot {
    static func run(into dir: String) {
        Settings.registerDefaults()
        let services = Services.shared
        let model = services.model
        model.notchSize = CGSize(width: 185, height: 32)
        services.shelf.add([URL(fileURLWithPath: "/Applications/Safari.app"),
                            URL(fileURLWithPath: NSHomeDirectory() + "/Documents")])

        func render(_ name: String) {
            let size = CGSize(width: model.expandedSize.width + 48, height: model.expandedSize.height + 24)
            let root = NotchRootView(openSettings: {}, collapse: {})
                .environmentObject(services.model)
                .environmentObject(services.media)
                .environmentObject(services.shelf)
                .environmentObject(services.clipboard)
                .environmentObject(services.focus)
                .environmentObject(services.calendar)
                .environmentObject(services.stats)
                .transaction { $0.animation = nil }
                .background(Color(white: 0.75))
            let view = NSHostingView(rootView: root)
            view.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }

        render("collapsed")
        model.show(.volume(level: 0.6, muted: false), for: 60)
        render("hud-volume")
        model.show(.battery(level: 82, charging: true), for: 60)
        render("hud-battery")
        model.hud = nil
        model.isExpanded = true
        for _ in 0..<3 { services.stats.sample(); Thread.sleep(forTimeInterval: 0.5) }
        for tab in NotchTab.allCases where tab != .mirror {
            model.tab = tab
            render("tab-\(tab.rawValue)")
        }
        services.shelf.clear()
    }
}
