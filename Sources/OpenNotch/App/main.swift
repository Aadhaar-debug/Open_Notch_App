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

// `OpenNotch --stats` prints two seconds of system stats, then exits.
if CommandLine.arguments.contains("--stats") {
    let stats = SystemStats()
    for _ in 0..<3 { stats.sample(); Thread.sleep(forTimeInterval: 1) }
    let s = stats.now
    print(String(format: "cpu %.0f%% (user %.0f%%, sys %.0f%%)", s.cpu * 100, s.cpuUser * 100, s.cpuSystem * 100))
    print("memory \(bytes(s.memoryUsed)) / \(bytes(s.memoryTotal)), swap \(bytes(s.swapUsed))")
    print("gpu \(s.gpu.map { String(format: "%.0f%%", $0 * 100) } ?? "n/a"), gpu mem \(s.gpuMemory.map { bytes($0) } ?? "n/a")")
    print("net down \(rate(s.netDown)), up \(rate(s.netUp))")
    print("disk \(bytes(s.diskFree)) free of \(bytes(s.diskTotal))")
    print("battery \(s.battery.map { "\($0)%" } ?? "n/a"), load \(String(format: "%.2f", s.load)), thermal \(s.thermal.rawValue)")
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
