import EventKit
import Foundation

/// Today's remaining events. Access is only requested the first time the Home tab opens.
final class CalendarService: ObservableObject {
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var authorized = false
    @Published private(set) var denied = false

    private let store = EKEventStore()
    private var requested = false
    private var observer: NSObjectProtocol?

    func activate() {
        guard Settings.bool(Settings.showCalendar) else { return }
        if authorized { refresh(); return }
        guard !requested else { return }
        requested = true
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess {
            didAuthorize()
        } else if status == .notDetermined {
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async {
                    if granted { self?.didAuthorize() } else { self?.denied = true }
                }
            }
        } else {
            denied = true
        }
    }

    private func didAuthorize() {
        authorized = true
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func refresh() {
        guard authorized else { return }
        let now = Date()
        guard let end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now) else { return }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        events = Array(store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .prefix(4))
    }
}
