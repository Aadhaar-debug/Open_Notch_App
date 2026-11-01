import EventKit
import SwiftUI

struct HomeView: View {
    @AppStorage(Settings.showCalendar) private var showCalendar = true

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            NowPlayingView()
                .frame(maxWidth: .infinity, alignment: .leading)
            if showCalendar {
                Divider().overlay(Color.white.opacity(0.15))
                CalendarPanel()
                    .frame(width: 150, alignment: .topLeading)
                MonthGridView()
                    .frame(width: 150)
            }
        }
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var media: MediaService

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(image: media.artwork, size: 92, corner: 14)
                .onTapGesture { media.openSourceApp() }
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(media.hasTrack ? media.title : "Nothing playing")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                Text(media.hasTrack ? media.artist : "Play something in Music, Spotify or your browser")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
                    .lineLimit(media.hasTrack ? 1 : 2)
                if !media.album.isEmpty {
                    Text(media.album).font(.system(size: 11)).foregroundStyle(.gray.opacity(0.8)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if media.needsControlPermission {
                    Text("To control browsers and other apps, allow OpenNotch in System Settings › Privacy & Security › Accessibility.")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                HStack(spacing: 22) {
                    control("backward.fill", size: 16) { media.send(.previous) }
                    control(media.isPlaying ? "pause.fill" : "play.fill", size: 22) { media.send(.playPause) }
                    control("forward.fill", size: 16) { media.send(.next) }
                    Spacer()
                    EqualizerView(isPlaying: media.isPlaying, color: .systemGray)
                        .frame(width: 16, height: 12)
                        .opacity(media.hasTrack ? 1 : 0)
                }
            }
            .frame(height: 92)
        }
        .onAppear { media.refresh() }
    }

    private func control(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CalendarPanel: View {
    @EnvironmentObject private var calendar: CalendarService

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, d MMM"; return f
    }()
    private static let timeFormat: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.dayFormat.string(from: calendar.selectedDate))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if calendar.denied {
                Text("Calendar access is off. Enable it in System Settings › Privacy & Security › Calendars.")
                    .font(.system(size: 11)).foregroundStyle(.gray)
            } else if calendar.events.isEmpty {
                Text(!calendar.authorized ? "Loading…" : calendar.isSelectedToday ? "No more events today" : "No events")
                    .font(.system(size: 11)).foregroundStyle(.gray)
            } else {
                ForEach(calendar.events.prefix(3), id: \.eventIdentifier) { event in
                    HStack(alignment: .top, spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(cgColor: event.calendar.cgColor))
                            .frame(width: 3, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title ?? "Event").font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(event.isAllDay ? "All day"
                                 : "\(Self.timeFormat.string(from: event.startDate)) – \(Self.timeFormat.string(from: event.endDate))")
                                .font(.system(size: 10)).foregroundStyle(.gray)
                        }
                    }
                }
            }
        }
        .onAppear { calendar.activate() }
    }
}
