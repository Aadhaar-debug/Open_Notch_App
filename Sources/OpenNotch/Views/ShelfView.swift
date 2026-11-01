import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @EnvironmentObject private var shelf: ShelfStore
    @StateObject private var airDropTargeted = StateBox(false)

    var body: some View {
        HStack(spacing: 12) {
            if shelf.items.isEmpty {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(.gray.opacity(0.6))
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "tray.and.arrow.down").font(.system(size: 26))
                            Text("Drop files on the notch to keep them here").font(.system(size: 12))
                        }
                        .foregroundStyle(.gray)
                    )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfTile(url: url)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            VStack(spacing: 8) {
                // Dropping straight onto AirDrop shares without shelving.
                ActionTile(symbol: "airplayaudio", title: "AirDrop", highlighted: airDropTargeted.value) {
                    ShelfStore.airDrop(shelf.items)
                }
                .onDrop(of: [.fileURL], isTargeted: $airDropTargeted.value) { providers in
                    shelf.accept(providers) { urls in ShelfStore.airDrop(urls) }
                }
                ActionTile(symbol: "archivebox.fill", title: "Zip all") { shelf.zip(shelf.items) }
                    .disabled(shelf.items.isEmpty)
                ActionTile(symbol: "trash.fill", title: "Clear") { shelf.clear() }
                    .disabled(shelf.items.isEmpty)
            }
            .frame(width: 92)
        }
    }
}

private struct ShelfTile: View {
    let url: URL
    @EnvironmentObject private var shelf: ShelfStore
    @StateObject private var hovering = StateBox(false)

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 56, height: 56)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 80)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering.value ? 0.12 : 0.05)))
        .overlay(alignment: .topTrailing) {
            if hovering.value {
                Button { shelf.remove(url) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { hovering.value = $0 }
        .onTapGesture(count: 2) { ShelfStore.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { ShelfStore.open(url) }
            Button("Show in Finder") { ShelfStore.reveal([url]) }
            Button("AirDrop") { ShelfStore.airDrop([url]) }
            Button("Compress") { shelf.zip([url]) }
            if url.pathExtension.lowercased() == "zip" {
                Button("Uncompress") { shelf.unzip(url) }
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
            Divider()
            Button("Remove from Shelf") { shelf.remove(url) }
        }
        .help(url.path)
    }
}

struct ActionTile: View {
    let symbol: String
    let title: String
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12))
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 9)
                .fill(highlighted ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}
