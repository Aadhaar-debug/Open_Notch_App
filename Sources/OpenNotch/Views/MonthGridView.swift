import SwiftUI

/// Compact month calendar: today is filled, the selected day is ringed, and days with
/// events get a dot. Clicking a day shows its events in the agenda beside it.
struct MonthGridView: View {
    @EnvironmentObject private var calendar: CalendarService

    private var cal: Calendar { .current }

    private static let monthFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "LLLL yyyy"; return f
    }()

    /// Day numbers laid out in weeks, `nil` for the blanks before the 1st.
    private var cells: [Int?] {
        let month = calendar.displayedMonth
        guard let days = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        let weekday = cal.component(.weekday, from: month)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + (1...days).map { Optional($0) }
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 2) {
                Text(Self.monthFormat.string(from: calendar.displayedMonth))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .onTapGesture { calendar.goToToday() }
                    .help("Go to today")
                Spacer(minLength: 0)
                chevron("chevron.left") { calendar.showMonth(offset: -1) }
                chevron("chevron.right") { calendar.showMonth(offset: 1) }
            }
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity)
                }
            }
            let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
            VStack(spacing: 1) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in
                            if i < row.count, let day = row[i] {
                                dayCell(day)
                            } else {
                                Color.clear.frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func date(for day: Int) -> Date? {
        cal.date(byAdding: .day, value: day - 1, to: calendar.displayedMonth)
    }

    private func dayCell(_ day: Int) -> some View {
        let date = date(for: day)
        let isToday = date.map(cal.isDateInToday) ?? false
        let isSelected = date.map { cal.isDate($0, inSameDayAs: calendar.selectedDate) } ?? false
        let hasEvents = calendar.eventDays.contains(day)
        return Button {
            if let date { calendar.select(date) }
        } label: {
            ZStack {
                if isToday {
                    Circle().fill(Color.accentColor).frame(width: 16, height: 16)
                } else if isSelected {
                    Circle().stroke(Color.white.opacity(0.6), lineWidth: 1).frame(width: 16, height: 16)
                }
                Text("\(day)")
                    .font(.system(size: 9.5, weight: isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isToday ? .white : .white.opacity(0.85))
                if hasEvents && !isToday {
                    Circle().fill(Color.orange).frame(width: 3, height: 3).offset(y: 7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chevron(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.gray)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
