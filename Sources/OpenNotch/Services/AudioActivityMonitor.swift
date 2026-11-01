import AppKit
import CoreAudio

/// Tells which apps are currently sending audio to an output device, using CoreAudio's
/// public per-process objects (macOS 14.2+). Purely event driven: we listen for the
/// process list changing and for each process's "is running output" flag.
final class AudioActivityMonitor {
    /// Called on the main queue with the regular (Dock) apps that are producing sound.
    var onChange: (([NSRunningApplication]) -> Void)?

    private var processes: [AudioObjectID] = []
    private var reportWork: DispatchWorkItem?

    private lazy var listListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.reloadProcesses()
    }
    private lazy var runningListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.scheduleReport()
    }

    private static var listAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static var runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyIsRunningOutput,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func start() {
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                            &Self.listAddress, .main, listListener)
        reloadProcesses()
    }

    /// Re-reads the current state now (e.g. when the notch opens).
    func refresh() { report() }

    private func reloadProcesses() {
        for id in processes {
            AudioObjectRemovePropertyListenerBlock(id, &Self.runningAddress, .main, runningListener)
        }
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectGetPropertyDataSize(system, &Self.listAddress, 0, nil, &size)
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(system, &Self.listAddress, 0, nil, &size, &ids)
        processes = ids
        for id in ids {
            AudioObjectAddPropertyListenerBlock(id, &Self.runningAddress, .main, runningListener)
        }
        scheduleReport()
    }

    /// Short debounce so a notification "ding" or a track change doesn't flicker the UI.
    private func scheduleReport() {
        reportWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.report() }
        reportWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func report() {
        var apps: [NSRunningApplication] = []
        let me = ProcessInfo.processInfo.processIdentifier
        for id in processes {
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &Self.runningAddress, 0, nil, &size, &running) == noErr,
                  running != 0 else { continue }
            let pid = Self.pid(of: id)
            guard pid > 0, pid != me, let app = Self.owningApp(pid: pid, bundleID: Self.bundleID(of: id)),
                  app.processIdentifier != me, !apps.contains(app) else { continue }
            apps.append(app)
        }
        onChange?(apps)
    }

    // MARK: Process → app

    private static func pid(of id: AudioObjectID) -> pid_t {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &pid)
        return pid
    }

    private static func bundleID(of id: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return "" }
        return value?.takeRetainedValue() as String? ?? ""
    }

    /// Browsers play audio from helper processes (e.g. `com.microsoft.edgemac.helper`,
    /// `com.apple.WebKit.GPU`); map those back to the app the user sees.
    private static func owningApp(pid: pid_t, bundleID: String) -> NSRunningApplication? {
        if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
            return app
        }
        let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let lower = bundleID.lowercased()
        if lower.hasPrefix("com.apple.webkit") {
            return regular.first { $0.bundleIdentifier == "com.apple.Safari" }
                ?? regular.first { $0.bundleIdentifier == "com.apple.SafariTechnologyPreview" }
        }
        if let match = regular
            .filter({ app in
                guard let id = app.bundleIdentifier?.lowercased() else { return false }
                return lower == id || lower.hasPrefix(id + ".")
            })
            .max(by: { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) }) {
            return match
        }
        // Fall back to the helper's parent process.
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        if sysctl(&mib, 4, &info, &size, nil, 0) == 0, info.kp_eproc.e_ppid > 1,
           let parent = NSRunningApplication(processIdentifier: info.kp_eproc.e_ppid),
           parent.activationPolicy == .regular {
            return parent
        }
        return nil
    }
}
