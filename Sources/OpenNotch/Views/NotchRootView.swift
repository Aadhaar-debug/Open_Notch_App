import SwiftUI

struct NotchRootView: View {
    let openSettings: () -> Void
    let collapse: () -> Void

    @EnvironmentObject private var model: NotchModel
    @EnvironmentObject private var media: MediaService
    @EnvironmentObject private var focus: FocusTimer
    @EnvironmentObject private var shelf: ShelfStore
    @AppStorage(Settings.showMediaActivity) private var showMediaActivity = true

    private let topRadius: CGFloat = 8
    private var wing: CGFloat { NotchWindowController.activityWing }

    private enum Activity: Equatable {
        case hud(HUD), focus, media, none
    }

    private var activity: Activity {
        if let hud = model.hud { return .hud(hud) }
        if focus.isRunning { return .focus }
        if showMediaActivity && media.hasTrack && media.isPlaying { return .media }
        return .none
    }

    private var shapeSize: CGSize {
        if model.isExpanded { return model.expandedSize }
        let wings: CGFloat = activity == .none ? 0 : wing * 2
        return CGSize(width: model.notchSize.width + wings + topRadius * 2, height: model.notchSize.height)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(topRadius: topRadius, bottomRadius: model.isExpanded ? 24 : 10)
                    .fill(Color.black)
                    .overlay(
                        NotchShape(topRadius: topRadius, bottomRadius: model.isExpanded ? 24 : 10)
                            .stroke(model.isDropTargeted ? Color.accentColor : .clear, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(model.isExpanded ? 0.45 : 0), radius: 12, y: 4)

                if model.isExpanded {
                    ExpandedView(openSettings: openSettings, collapse: collapse)
                        .padding(.horizontal, topRadius + 16)
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else {
                    collapsedContent
                        .padding(.horizontal, topRadius)
                        .transition(.opacity)
                }
            }
            .frame(width: shapeSize.width, height: shapeSize.height)
            .clipped()
            .contentShape(NotchShape(topRadius: topRadius, bottomRadius: 24))
            .onDrop(of: [.fileURL], isTargeted: $model.isDropTargeted) { providers in
                model.tab = .shelf
                return shelf.accept(providers)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.36, dampingFraction: 0.8), value: model.isExpanded)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: activity)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var collapsedContent: some View {
        HStack(spacing: 0) {
            Group {
                switch activity {
                case .hud(let hud): HUDLeading(hud: hud)
                case .focus: Image(systemName: focus.onBreak ? "cup.and.saucer.fill" : "timer")
                        .foregroundStyle(focus.onBreak ? .green : .orange)
                case .media: ArtworkView(image: media.artwork, size: model.notchSize.height - 10, corner: 5)
                case .none: EmptyView()
                }
            }
            .frame(width: activity == .none ? 0 : wing)

            Spacer(minLength: model.notchSize.width)

            Group {
                switch activity {
                case .hud(let hud): HUDTrailing(hud: hud)
                case .focus: Text(focus.label).font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                case .media: EqualizerView(isPlaying: media.isPlaying).frame(width: 18, height: 12)
                case .none: EmptyView()
                }
            }
            .frame(width: activity == .none ? 0 : wing)
        }
        .frame(height: model.notchSize.height)
        .font(.system(size: 13, weight: .semibold))
    }
}

// MARK: - Live activity pieces

private struct HUDLeading: View {
    let hud: HUD
    var body: some View {
        switch hud {
        case .volume(let level, let muted):
            Image(systemName: muted || level == 0 ? "speaker.slash.fill"
                  : level < 0.33 ? "speaker.wave.1.fill" : level < 0.66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                .foregroundStyle(.white)
        case .battery(let level, let charging):
            Image(systemName: charging ? "battery.100.bolt" : batterySymbol(level))
                .foregroundStyle(charging ? .green : .white)
        case .lowBattery(let level):
            Image(systemName: batterySymbol(level)).foregroundStyle(.red)
        case .bluetooth(_, let connected):
            Image(systemName: connected ? "airpodspro" : "airpodspro")
                .foregroundStyle(connected ? .blue : .gray)
        case .focusDone(let onBreak):
            Image(systemName: onBreak ? "cup.and.saucer.fill" : "brain.head.profile")
                .foregroundStyle(onBreak ? .green : .orange)
        case .shelfAdded:
            Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(.blue)
        }
    }
}

private struct HUDTrailing: View {
    let hud: HUD
    var body: some View {
        switch hud {
        case .volume(let level, let muted):
            Capsule().fill(Color.white.opacity(0.2))
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule().fill(Color.white).frame(width: g.size.width * CGFloat(muted ? 0 : level))
                    }
                }
                .frame(width: 32, height: 5)
        case .battery(let level, _), .lowBattery(let level):
            Text("\(level)%").foregroundStyle(.white).font(.system(size: 12, weight: .semibold).monospacedDigit())
        case .bluetooth(_, let connected):
            Image(systemName: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(connected ? .green : .gray)
        case .focusDone(let onBreak):
            Text(onBreak ? "Break" : "Focus").foregroundStyle(.white).font(.system(size: 11, weight: .semibold))
        case .shelfAdded(let count):
            Text("+\(count)").foregroundStyle(.white).font(.system(size: 12, weight: .semibold))
        }
    }
}

func batterySymbol(_ level: Int) -> String {
    switch level {
    case ..<13: return "battery.0percent"
    case ..<38: return "battery.25percent"
    case ..<63: return "battery.50percent"
    case ..<88: return "battery.75percent"
    default: return "battery.100percent"
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note").font(.system(size: size * 0.45)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}
