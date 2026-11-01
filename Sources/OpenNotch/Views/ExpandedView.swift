import SwiftUI

struct ExpandedView: View {
    let openSettings: () -> Void
    let collapse: () -> Void

    @EnvironmentObject private var model: NotchModel

    var body: some View {
        VStack(spacing: 10) {
            header
            Group {
                switch model.tab {
                case .home: HomeView()
                case .shelf: ShelfView()
                case .clipboard: ClipboardView()
                case .timer: FocusView()
                case .mirror: MirrorView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundStyle(.white)
    }

    /// Tabs to the left of the camera housing, actions to the right.
    private var header: some View {
        HStack(spacing: 4) {
            ForEach(NotchTab.allCases) { tab in
                Button { model.tab = tab } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 22)
                        .background(
                            Capsule().fill(model.tab == tab ? Color.white.opacity(0.18) : .clear)
                        )
                        .foregroundStyle(model.tab == tab ? .white : .gray)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
            Spacer(minLength: model.notchSize.width)
            Button {
                collapse()
                openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.gray)
                    .frame(width: 30, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .frame(height: max(model.notchSize.height, 26))
    }
}
