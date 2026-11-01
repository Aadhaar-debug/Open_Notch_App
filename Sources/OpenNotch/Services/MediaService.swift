import AppKit
import ApplicationServices

/// Now-playing info and transport controls, from three sources (all event driven):
///  1. Music.app and Spotify distributed notifications, plus their AppleScript dictionaries.
///  2. Whichever other app is producing sound (CoreAudio). For browsers we read the media
///     tab's title/URL over AppleScript — this is what makes YouTube, Spotify Web, Netflix,
///     etc. show up. Other apps show their name and icon.
///  3. Apple's private MediaRemote framework, on macOS versions that still let
///     third-party apps read it (newer versions return nothing, so 1 and 2 carry the load).
final class MediaService: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var sourceBundleID: String?
    /// Media keys need "Accessibility" permission; the Home view shows a hint while missing.
    @Published private(set) var needsControlPermission = false

    var hasTrack: Bool { !title.isEmpty }

    private enum Source: Equatable {
        case remote            // MediaRemote
        case player(String)    // Music / Spotify, scripted directly
        case app(String)       // any other app producing sound
    }

    private static let players = ["com.apple.Music", "com.spotify.client"]

    private var source: Source?
    private let mr = MediaRemote()
    private var remoteWorks = false
    private let audio = AudioActivityMonitor()
    private let scriptQueue = DispatchQueue(label: "opennotch.applescript", qos: .userInitiated)
    private var artworkKey = ""
    private var browserTimer: Timer?

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(musicChanged(_:)),
                        name: NSNotification.Name("com.apple.Music.playerInfo"), object: nil)
        dnc.addObserver(self, selector: #selector(spotifyChanged(_:)),
                        name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        if mr.isAvailable {
            mr.registerForNotifications()
            let nc = NotificationCenter.default
            for name in ["kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                         "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                         "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"] {
                nc.addObserver(self, selector: #selector(remoteChanged), name: NSNotification.Name(name), object: nil)
            }
            remoteChanged()
        }

        audio.onChange = { [weak self] apps in self?.audioChanged(apps) }
        audio.start()
    }

    /// Called when the Home tab opens, so the info is fresh.
    func refresh() {
        audio.refresh()
        if case .app(let id) = source, BrowserMedia.isScriptableBrowser(id), isPlaying {
            queryBrowser(id)
        }
    }

    // MARK: MediaRemote

    @objc private func remoteChanged() {
        mr.nowPlayingInfo { [weak self] info in
            guard let self, let info, let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
                  !title.isEmpty else { return }
            self.remoteWorks = true
            self.source = .remote
            self.sourceBundleID = nil
            self.set(title: title,
                     artist: info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
                     album: info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "")
            if let data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                self.artwork = NSImage(data: data)
            }
            // Only trust the playing flag when MediaRemote actually gave us a track.
            self.mr.isPlaying { [weak self] playing in self?.isPlaying = playing }
        }
    }

    // MARK: Music / Spotify

    @objc private func musicChanged(_ note: Notification) {
        applyPlayer(note.userInfo, bundleID: "com.apple.Music")
    }

    @objc private func spotifyChanged(_ note: Notification) {
        applyPlayer(note.userInfo, bundleID: "com.spotify.client")
    }

    private func applyPlayer(_ info: [AnyHashable: Any]?, bundleID: String) {
        guard let info, !remoteWorks else { return }
        let state = info["Player State"] as? String ?? ""
        let playing = state == "Playing"
        let isCurrent = source == .player(bundleID)
        if state == "Stopped" {
            if isCurrent { clear() }
            return
        }
        // A paused player shouldn't steal the notch from something else that's playing.
        guard playing || isCurrent || !isPlaying else { return }
        source = .player(bundleID)
        sourceBundleID = bundleID
        stopBrowserTimer()
        set(title: info["Name"] as? String ?? title,
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "")
        isPlaying = playing
        loadPlayerArtwork(bundleID)
    }

    /// For players that were already playing before OpenNotch started (no notification yet).
    private func queryPlayer(_ bundleID: String) {
        let script = """
        set sep to ASCII character 9
        tell application id "\(bundleID)"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & sep & (artist of t) & sep & (album of t) & sep & (player state as text)
        end tell
        """
        runScript(script) { [weak self] output in
            guard let self, let output, !output.isEmpty else { return }
            let parts = output.components(separatedBy: "\t")
            guard parts.count == 4 else { return }
            self.applyPlayer(["Name": parts[0], "Artist": parts[1], "Album": parts[2],
                              "Player State": parts[3] == "playing" ? "Playing" : "Paused"],
                             bundleID: bundleID)
        }
    }

    private func loadPlayerArtwork(_ bundleID: String) {
        let key = "\(bundleID)|\(title)|\(album)"
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        if bundleID == "com.apple.Music" {
            runScriptData("tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track") {
                [weak self] data in
                guard let self, self.artworkKey == key, let data else { return }
                self.artwork = NSImage(data: data)
            }
        } else {
            runScript("tell application id \"com.spotify.client\" to get artwork url of current track") {
                [weak self] url in
                guard let url, let u = URL(string: url) else { return }
                self?.loadArtwork(from: u, key: key)
            }
        }
    }

    // MARK: Any app producing sound

    private func audioChanged(_ apps: [NSRunningApplication]) {
        guard !remoteWorks else { return }

        if apps.isEmpty {
            // Paused/stopped: keep showing the last thing, marked as paused.
            if case .app = source { isPlaying = false; stopBrowserTimer() }
            return
        }
        // Music/Spotify first, then browsers, then anything else.
        func rank(_ app: NSRunningApplication) -> Int {
            let id = app.bundleIdentifier ?? ""
            if Self.players.contains(id) { return 0 }
            if BrowserMedia.isScriptableBrowser(id) { return 1 }
            return 2
        }
        guard let app = apps.min(by: { rank($0) < rank($1) }), let id = app.bundleIdentifier else { return }

        if Self.players.contains(id) {
            if source != .player(id) || !isPlaying { queryPlayer(id) }
            return
        }
        // A scripted player that's still playing keeps priority.
        if case .player(let p) = source, isPlaying, apps.contains(where: { $0.bundleIdentifier == p }) { return }

        let changedApp = source != .app(id)
        source = .app(id)
        sourceBundleID = id
        isPlaying = true
        if BrowserMedia.isScriptableBrowser(id) {
            if changedApp { set(title: app.localizedName ?? "Browser", artist: "Playing audio", album: "") }
            if changedApp || artwork == nil { artworkKey = ""; artwork = app.icon }
            queryBrowser(id)
            startBrowserTimer(id)
        } else {
            stopBrowserTimer()
            set(title: app.localizedName ?? "Audio", artist: "Playing audio", album: "")
            artworkKey = "app|\(id)"
            artwork = app.icon
        }
    }

    private func queryBrowser(_ bundleID: String) {
        let browserName = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?.localizedName ?? "Browser"
        runScript(BrowserMedia.script(for: bundleID)) { [weak self] output in
            guard let self, self.source == .app(bundleID), let output,
                  let tab = BrowserMedia.pick(BrowserMedia.parse(output)) else { return }
            let info = BrowserMedia.info(for: tab, browserName: browserName)
            self.set(title: info.title, artist: info.subtitle, album: "")
            let key = "tab|\(tab.url)"
            if key != self.artworkKey {
                self.artworkKey = key
                if let url = info.artworkURL {
                    self.loadArtwork(from: url, key: key)
                } else {
                    self.artwork = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.icon
                }
            }
        }
    }

    /// While a browser plays, re-read its tab now and then so autoplay's next video shows up.
    private func startBrowserTimer(_ bundleID: String) {
        guard browserTimer == nil else { return }
        let timer = Timer(timeInterval: 6, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying, case .app(let id) = self.source else { return }
            self.queryBrowser(id)
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        browserTimer = timer
    }

    private func stopBrowserTimer() {
        browserTimer?.invalidate()
        browserTimer = nil
    }

    @objc private func appTerminated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let id = app?.bundleIdentifier, id == sourceBundleID { clear() }
    }

    // MARK: Helpers

    private func set(title: String, artist: String, album: String) {
        if self.title != title { self.title = title }
        if self.artist != artist { self.artist = artist }
        if self.album != album { self.album = album }
    }

    private func clear() {
        stopBrowserTimer()
        title = ""; artist = ""; album = ""; artwork = nil; isPlaying = false
        source = nil; sourceBundleID = nil; artworkKey = ""
    }

    private func loadArtwork(from url: URL, key: String) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap(NSImage.init(data:))
            DispatchQueue.main.async { [weak self] in
                guard let self, self.artworkKey == key, let image else { return }
                self.artwork = image
            }
        }.resume()
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Runs AppleScript off the main thread (one at a time); never launches a closed app.
    private func runScript(_ source: String, completion: @escaping (String?) -> Void) {
        scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
            DispatchQueue.main.async { completion(error == nil ? result : nil) }
        }
    }

    private func runScriptData(_ source: String, completion: @escaping (Data?) -> Void) {
        scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error).data
            DispatchQueue.main.async { completion(error == nil ? result : nil) }
        }
    }

    // MARK: Controls

    enum Command { case playPause, next, previous }

    func send(_ command: Command) {
        switch source {
        case .player(let id) where isRunning(id):
            let verb: String
            switch command {
            case .playPause: verb = "playpause"
            case .next: verb = "next track"
            case .previous: verb = "previous track"
            }
            runScript("tell application id \"\(id)\" to \(verb)") { _ in }
            if command == .playPause { isPlaying.toggle() }
        case .remote:
            switch command {
            case .playPause: mr.send(2)
            case .next: mr.send(4)
            case .previous: mr.send(5)
            }
        default:
            // Browsers and other apps: send the keyboard's media keys, which macOS routes to
            // whatever app currently owns "Now Playing" (e.g. the YouTube tab).
            guard MediaKeys.ensureAccess() else {
                needsControlPermission = true
                return
            }
            needsControlPermission = false
            switch command {
            case .playPause: MediaKeys.post(.playPause); isPlaying.toggle()
            case .next: MediaKeys.post(.next)
            case .previous: MediaKeys.post(.previous)
            }
        }
    }

    func openSourceApp() {
        guard let id = sourceBundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { return }
        app.activate()
    }
}

/// Posts the hardware play/pause, next and previous keys.
enum MediaKeys {
    enum Key: Int { case playPause = 16, next = 17, previous = 18 } // NX_KEYTYPE_*

    /// Posting events needs the user's OK under Privacy & Security › Accessibility.
    static func ensureAccess() -> Bool {
        if CGPreflightPostEventAccess() { return true }
        CGRequestPostEventAccess()
        return CGPreflightPostEventAccess()
    }

    static func post(_ key: Key) {
        for down in [true, false] {
            let flags = down ? 0xa00 : 0xb00
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: (key.rawValue << 16) | flags, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

/// Thin dlopen wrapper around /System/Library/PrivateFrameworks/MediaRemote.framework.
private final class MediaRemote {
    private typealias GetInfo = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias GetIsPlaying = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias Register = @convention(c) (DispatchQueue) -> Void
    private typealias SendCommand = @convention(c) (Int, CFDictionary?) -> Bool

    private var getInfo: GetInfo?
    private var getIsPlaying: GetIsPlaying?
    private var register: Register?
    private var sendCommand: SendCommand?

    init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_LAZY) else { return }
        func load<T>(_ name: String, as: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        getInfo = load("MRMediaRemoteGetNowPlayingInfo", as: GetInfo.self)
        getIsPlaying = load("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetIsPlaying.self)
        register = load("MRMediaRemoteRegisterForNowPlayingNotifications", as: Register.self)
        sendCommand = load("MRMediaRemoteSendCommand", as: SendCommand.self)
    }

    var isAvailable: Bool { getInfo != nil }

    func registerForNotifications() { register?(.main) }

    func nowPlayingInfo(_ completion: @escaping ([String: Any]?) -> Void) {
        guard let getInfo else { return completion(nil) }
        getInfo(.main) { dict in completion(dict as? [String: Any]) }
    }

    func isPlaying(_ completion: @escaping (Bool) -> Void) {
        getIsPlaying?(.main) { completion($0) }
    }

    func send(_ command: Int) { _ = sendCommand?(command, nil) }
}
