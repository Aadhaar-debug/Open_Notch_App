import SwiftUI

struct FocusView: View {
    @EnvironmentObject private var focus: FocusTimer
    @AppStorage(Settings.focusMinutes) private var focusMinutes = 25
    @AppStorage(Settings.breakMinutes) private var breakMinutes = 5

    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: focus.progress)
                    .stroke(focus.onBreak ? Color.green : Color.orange,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: focus.progress)
                VStack(spacing: 2) {
                    Text(focus.label).font(.system(size: 24, weight: .semibold).monospacedDigit())
                    Text(focus.onBreak ? "Break" : "Focus").font(.system(size: 11)).foregroundStyle(.gray)
                }
            }
            .frame(width: 118, height: 118)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button(focus.isRunning ? "Pause" : "Start") { focus.toggle() }
                        .buttonStyle(PillStyle(color: focus.onBreak ? .green : .orange))
                    Button("Reset") { focus.reset() }.buttonStyle(PillStyle(color: .gray))
                    Button(focus.onBreak ? "Skip break" : "Skip") { focus.skip() }.buttonStyle(PillStyle(color: .gray))
                }
                Stepper("Focus: \(focusMinutes) min", value: $focusMinutes, in: 1...120, step: 5)
                    .disabled(focus.isRunning)
                Stepper("Break: \(breakMinutes) min", value: $breakMinutes, in: 1...60)
                    .disabled(focus.isRunning)
                Text("\(focus.completedSessions) focus sessions completed")
                    .font(.system(size: 11)).foregroundStyle(.gray)
            }
            .font(.system(size: 12))
            Spacer()
        }
    }
}

struct PillStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(configuration.isPressed ? 0.5 : 0.3)))
            .foregroundStyle(.white)
    }
}
