import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the transparent panel that sits over the notch.
///
/// The panel keeps a fixed frame (the expanded size plus a margin) so expanding never
/// resizes a window — only the SwiftUI shape animates. While collapsed the panel ignores
/// mouse events, so the menu bar under it stays clickable; hover and drags are detected
/// with global mouse monitors, which need no Accessibility permission.
final class NotchWindowController: NSObject {
    private let services: Services
    private var model: NotchModel { services.model }
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var dragBaseline = NSPasteboard(name: .drag).changeCount
    private var notchRect = NSRect.zero
    private var screenObserver: NSObjectProtocol?

    private let margin: CGFloat = 24
    /// Extra width each side of the notch used by live activities.
    static let activityWing: CGFloat = 46

    init(services: Services, openSettings: @escaping () -> Void) {
        self.services = services
        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true

        let root = NotchRootView(openSettings: openSettings, collapse: { [weak self] in self?.collapse() })
            .environmentObject(services.model)
            .environmentObject(services.media)
            .environmentObject(services.shelf)
            .environmentObject(services.clipboard)
            .environmentObject(services.focus)
            .environmentObject(services.calendar)
            .environmentObject(services.stats)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting

        reposition()
        panel.orderFrontRegardless()
        installMonitors()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reposition() }

        // A drop on the shelf while collapsed (from the global drag path) should open the shelf.
        services.shelf.onAdded = { [weak self] count in
            guard let self, !self.model.isExpanded else { return }
            self.model.show(.shelfAdded(count: count))
        }
    }

    // MARK: Geometry

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func reposition() {
        guard let screen = targetScreen() else { return }
        let frame = screen.frame
        var notch: CGSize
        if screen.safeAreaInsets.top > 0 {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            notch = CGSize(width: max(frame.width - left - right, 120), height: screen.safeAreaInsets.top)
        } else {
            // No hardware notch: draw a simulated one the height of the menu bar.
            let menuBar = max(frame.maxY - screen.visibleFrame.maxY, 24)
            notch = CGSize(width: 190, height: menuBar)
        }
        model.notchSize = notch

        let size = CGSize(width: model.expandedSize.width + margin * 2, height: model.expandedSize.height + margin)
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
        notchRect = NSRect(x: frame.midX - notch.width / 2, y: frame.maxY - notch.height,
                           width: notch.width, height: notch.height)
    }

    private var hoverRect: NSRect {
        notchRect.insetBy(dx: -Self.activityWing, dy: -4)
    }

    private var expandedRect: NSRect {
        let s = model.expandedSize
        return NSRect(x: notchRect.midX - s.width / 2, y: notchRect.maxY - s.height,
                      width: s.width, height: s.height).insetBy(dx: -14, dy: -14)
    }

    // MARK: Mouse

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in
            self?.handle(e, inside: false)
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in
            self?.handle(e, inside: true)
            return e
        }) { monitors.append(local) }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            if e.keyCode == 53 { self?.collapse(); return nil } // Esc
            return e
        }) { monitors.append(keys) }
    }

    private func handle(_ event: NSEvent, inside: Bool) {
        let p = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            dragBaseline = NSPasteboard(name: .drag).changeCount
            if model.isExpanded && !inside && !expandedRect.contains(p) { collapse() }
        case .leftMouseUp:
            if !model.isExpanded { expandWork?.cancel() }
        case .leftMouseDragged:
            let dragging = NSPasteboard(name: .drag).changeCount != dragBaseline
            if !model.isExpanded, dragging, hoverRect.contains(p), Settings.bool(Settings.expandOnDrag) {
                expand(tab: .shelf, delay: 0)
            } else if model.isExpanded {
                trackExpanded(p)
            }
        default:
            if model.isExpanded {
                trackExpanded(p)
            } else if hoverRect.contains(p) {
                expand(tab: nil, delay: UserDefaults.standard.double(forKey: Settings.hoverDelay))
            } else {
                expandWork?.cancel()
            }
        }
    }

    private func trackExpanded(_ p: NSPoint) {
        if expandedRect.contains(p) {
            collapseWork?.cancel()
            collapseWork = nil
        } else if collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in self?.collapse() }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }

    private func expand(tab: NotchTab?, delay: TimeInterval) {
        expandWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Hover must still be on the notch when the delay ends.
            if delay > 0 && !self.hoverRect.contains(NSEvent.mouseLocation) { return }
            if let tab { self.model.tab = tab }
            guard !self.model.isExpanded else { return }
            self.collapseWork?.cancel()
            self.collapseWork = nil
            self.panel.ignoresMouseEvents = false
            self.model.hud = nil
            self.model.isExpanded = true
            if Settings.bool(Settings.haptics) {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        expandWork = work
        if delay <= 0 { work.perform() } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func collapse() {
        expandWork?.cancel()
        collapseWork?.cancel()
        collapseWork = nil
        guard model.isExpanded else { return }
        model.isExpanded = false
        model.isDropTargeted = false
        panel.ignoresMouseEvents = true
        if panel.isKeyWindow { panel.resignKey() }
    }
}
