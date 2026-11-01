import AppKit

/// Pomodoro-style focus timer. Ticks once a second only while running.
final class FocusTimer: ObservableObject {
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var onBreak = false
    @Published private(set) var completedSessions = 0

    var onPhaseFinished: ((Bool) -> Void)?

    private var timer: Timer?
    private var endDate: Date?

    var phaseLength: TimeInterval {
        let key = onBreak ? Settings.breakMinutes : Settings.focusMinutes
        return TimeInterval(max(UserDefaults.standard.integer(forKey: key), 1) * 60)
    }

    var progress: Double {
        guard phaseLength > 0 else { return 0 }
        return 1 - (displayRemaining / phaseLength)
    }

    /// Remaining time, or the full phase length when the timer hasn't started.
    var displayRemaining: TimeInterval { remaining > 0 ? remaining : phaseLength }

    var label: String {
        let t = Int(displayRemaining.rounded(.up))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        if remaining <= 0 { remaining = phaseLength }
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        timer?.invalidate(); timer = nil
        isRunning = false
    }

    func reset() {
        pause()
        onBreak = false
        remaining = 0
    }

    func skip() {
        pause()
        onBreak.toggle()
        remaining = 0
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(endDate.timeIntervalSinceNow, 0)
        if remaining <= 0 {
            pause()
            if !onBreak { completedSessions += 1 }
            onBreak.toggle()
            remaining = 0
            NSSound(named: "Glass")?.play()
            onPhaseFinished?(onBreak)
        }
    }
}
