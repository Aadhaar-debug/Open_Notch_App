import AppKit
import Combine

enum NotchTab: String, CaseIterable, Identifiable {
    case home, shelf, clipboard, stats, timer, mirror
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .shelf: return "tray.full.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .stats: return "cpu"
        case .timer: return "timer"
        case .mirror: return "camera.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .shelf: return "Shelf"
        case .clipboard: return "Clipboard"
        case .stats: return "System Stats"
        case .timer: return "Focus"
        case .mirror: return "Mirror"
        }
    }
}

/// A short-lived notification shown in the collapsed notch ("live activity").
enum HUD: Equatable {
    case volume(level: Float, muted: Bool)
    case battery(level: Int, charging: Bool)
    case lowBattery(level: Int)
    case bluetooth(name: String, connected: Bool)
    case focusDone(onBreak: Bool)
    case shelfAdded(count: Int)
}

final class NotchModel: ObservableObject {
    @Published var isExpanded = false
    @Published var tab: NotchTab = .home
    @Published var hud: HUD?
    @Published var isDropTargeted = false

    /// Physical notch size of the screen we're on (or a simulated one).
    @Published var notchSize = CGSize(width: 200, height: 32)
    let expandedSize = CGSize(width: 700, height: 200)

    private var hudWork: DispatchWorkItem?

    func show(_ hud: HUD, for seconds: TimeInterval = 2.0) {
        hudWork?.cancel()
        self.hud = hud
        let work = DispatchWorkItem { [weak self] in self?.hud = nil }
        hudWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
