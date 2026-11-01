import AppKit
import UniformTypeIdentifiers

/// Temporary file shelf. Files are kept by reference (never copied or moved) and the
/// list survives restarts.
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [URL] = []
    var onAdded: ((Int) -> Void)?

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Settings.shelfPaths) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        let new = urls.filter { !items.contains($0) }
        guard !new.isEmpty else { return }
        items.append(contentsOf: new)
        save()
        onAdded?(new.count)
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: Settings.shelfPaths)
    }

    // MARK: Drop handling

    /// Loads file URLs from SwiftUI drop providers and adds them.
    func accept(_ providers: [NSItemProvider], then: (([URL]) -> Void)? = nil) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in fileProviders {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            if let then { then(urls) } else { self?.add(urls) }
        }
        return true
    }

    // MARK: Actions

    static func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Zips the given files next to the first one and adds the archive to the shelf.
    func zip(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let dir = first.deletingLastPathComponent()
        let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        var dest = dir.appendingPathComponent("\(base).zip")
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(base) \(n).zip"); n += 1
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            p.currentDirectoryURL = dir
            // -r recurse, -q quiet, -X no extra attributes; relative names keep the archive tidy.
            p.arguments = ["-r", "-q", "-X", dest.path] + urls.map { $0.lastPathComponent }
            try? p.run()
            p.waitUntilExit()
            DispatchQueue.main.async { [weak self] in
                if p.terminationStatus == 0 { self?.add([dest]) }
            }
        }
    }

    /// Unzips an archive into a folder beside it and adds that folder to the shelf.
    func unzip(_ url: URL) {
        let dest = url.deletingPathExtension()
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", url.path, dest.path]
            try? p.run()
            p.waitUntilExit()
            DispatchQueue.main.async { [weak self] in
                if p.terminationStatus == 0 { self?.add([dest]) }
            }
        }
    }
}
