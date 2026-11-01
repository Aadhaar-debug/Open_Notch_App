import SwiftUI

struct ClipboardView: View {
    @EnvironmentObject private var clipboard: ClipboardService
    @AppStorage(Settings.clipboardHistory) private var enabled = true
    @StateObject private var copiedID = StateBox<UUID?>(nil)

    var body: some View {
        if !enabled {
            placeholder("Clipboard history is off. Turn it on in Settings.")
        } else if clipboard.items.isEmpty {
            placeholder("Copy something and it will show up here")
        } else {
            VStack(spacing: 6) {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(clipboard.items) { item in
                            row(item)
                        }
                    }
                }
                HStack {
                    Text("\(clipboard.items.count) items · kept in memory only")
                        .font(.system(size: 10)).foregroundStyle(.gray)
                    Spacer()
                    Button("Clear") { clipboard.clear() }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(.gray)
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard").font(.system(size: 24))
            Text(text).font(.system(size: 12))
        }
        .foregroundStyle(.gray)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ item: ClipItem) -> some View {
        Button {
            clipboard.copy(item)
            copiedID.value = item.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if copiedID.value == item.id { copiedID.value = nil } }
        } label: {
            HStack(spacing: 8) {
                if let image = item.image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(height: 30)
                    Text("Image").font(.system(size: 12)).foregroundStyle(.gray)
                } else {
                    Image(systemName: "text.alignleft").font(.system(size: 11)).foregroundStyle(.gray)
                    Text(item.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\n", with: " ") ?? "")
                        .font(.system(size: 12)).lineLimit(1)
                }
                Spacer()
                if copiedID.value == item.id {
                    Text("Copied").font(.system(size: 10, weight: .semibold)).foregroundStyle(.green)
                } else {
                    Text(item.date, style: .relative).font(.system(size: 10)).foregroundStyle(.gray)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy") { clipboard.copy(item) }
            Button("Delete") { clipboard.remove(item) }
        }
    }
}
