import AppKit

let app = NSApplication.shared

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    app.setActivationPolicy(.prohibited)
    Snapshot.run(into: CommandLine.arguments[i + 1])
    exit(0)
}

// `OpenNotch --now-playing` prints what the media detector sees, then exits.
if CommandLine.arguments.contains("--now-playing") {
    app.setActivationPolicy(.prohibited)
    let media = MediaService()
    media.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        print("title:   \(media.title)")
        print("artist:  \(media.artist)")
        print("playing: \(media.isPlaying)")
        print("source:  \(media.sourceBundleID ?? "-")")
        print("artwork: \(media.artwork.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "none")")
        exit(0)
    }
    app.run()
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
