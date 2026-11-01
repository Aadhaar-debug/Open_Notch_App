import EventKit
import Foundation

/// Events for the selected day plus which days of the shown month have events.
/// Access is only requested the first time the Home tab opens.
final class CalendarService: ObservableObject {
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var eventDays: Set<Int> = []
    @Published private(set) var authorized = false
    @Published private(set) var denied = false
    @Published private(set) var selectedDate = Date()
    @Published private(set) var displayedMonth = CalendarService.startOfMonth(Date())

    private let store = EKEventStore()
    private var requested = false
    private var observer: NSObjectProtocol?
    private var calendar: Calendar { .current }

    var isSelectedToday: Bool { calendar.isDateInToday(selectedDate) }

    func activate() {
        // Coming back after midnight (or after browsing) should land on today.
        if !calendar.isDateInToday(selectedDate) && !requested { selectedDate = Date() }
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

    func select(_ date: Date) {
        selectedDate = date
        let month = Self.startOfMonth(date)
        if month != displayedMonth { displayedMonth = month }
        refresh()
    }

    func showMonth(offset: Int) {
        guard let month = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        displayedMonth = month
        refresh()
    }

    func goToToday() { select(Date()) }

    private func didAuthorize() {
        authorized = true
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func refresh() {
        guard authorized else { return }
        // Selected day: from now if it's today, otherwise the whole day.
        let dayStart = calendar.startOfDay(for: selectedDate)
        let from = isSelectedToday ? Date() : dayStart
        if let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) {
            let predicate = store.predicateForEvents(withStart: from, end: dayEnd, calendars: nil)
            events = Array(store.events(matching: predicate)
                .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
                .prefix(4))
        }
        // Dots on the month grid.
        if let monthEnd = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
            let predicate = store.predicateForEvents(withStart: displayedMonth, end: monthEnd, calendars: nil)
            var days = Set<Int>()
            for event in store.events(matching: predicate) {
                var day = max(event.startDate, displayedMonth)
                let last = min(event.endDate.addingTimeInterval(-1), monthEnd.addingTimeInterval(-1))
                while day <= last {
                    days.insert(calendar.component(.day, from: day))
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }
            eventDays = days
        }
    }

    static func startOfMonth(_ date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }
}
