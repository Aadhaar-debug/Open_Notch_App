import AppKit

let app = NSApplication.shared

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    app.setActivationPolicy(.prohibited)
    Snapshot.run(into: CommandLine.arguments[i + 1])
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
