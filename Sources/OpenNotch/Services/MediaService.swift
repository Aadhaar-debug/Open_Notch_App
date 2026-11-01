import AppKit

/// Now-playing info and transport controls.
///
/// Two sources, both event driven (no polling):
///  1. Apple's private MediaRemote framework — covers every player (browsers, Podcasts, …)
///     on macOS versions that still allow third-party apps to read it.
///  2. Music.app and Spotify distributed notifications — always available.
final class MediaService: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var sourceBundleID: String?

    var hasTrack: Bool { !title.isEmpty }

    private let mr = MediaRemote()
    private var lastArtworkKey = ""

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(musicChanged(_:)),
                        name: NSNotification.Name("com.apple.Music.playerInfo"), object: nil)
        dnc.addObserver(self, selector: #selector(spotifyChanged(_:)),
                        name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)

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
    }

    // MARK: MediaRemote

    @objc private func remoteChanged() {
        mr.nowPlayingInfo { [weak self] info in
            guard let self, let info, let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
                  !title.isEmpty else { return }
            self.title = title
            self.artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            self.album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            if let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double { self.isPlaying = rate > 0 }
            self.sourceBundleID = nil
            if let data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                self.artwork = NSImage(data: data)
            }
            // Only trust the playing flag when MediaRemote actually gave us a track;
            // on systems where it is blocked it always reports "not playing".
            self.mr.isPlaying { [weak self] playing in self?.isPlaying = playing }
        }
    }

    // MARK: Music / Spotify

    @objc private func musicChanged(_ note: Notification) {
        apply(note.userInfo, bundleID: "com.apple.Music")
    }

    @objc private func spotifyChanged(_ note: Notification) {
        apply(note.userInfo, bundleID: "com.spotify.client")
    }

    private func apply(_ info: [AnyHashable: Any]?, bundleID: String) {
        guard let info else { return }
        let state = info["Player State"] as? String ?? ""
        if state == "Stopped" {
            if sourceBundleID == bundleID { clear() }
            return
        }
        title = info["Name"] as? String ?? title
        artist = info["Artist"] as? String ?? ""
        album = info["Album"] as? String ?? ""
        isPlaying = state == "Playing"
        sourceBundleID = bundleID
        let key = "\(bundleID)|\(title)|\(album)"
        if key != lastArtworkKey {
            lastArtworkKey = key
            artwork = nil
            fetchArtwork(bundleID: bundleID, key: key)
        }
    }

    private func clear() {
        title = ""; artist = ""; album = ""; artwork = nil; isPlaying = false
        sourceBundleID = nil; lastArtworkKey = ""
    }

    private func fetchArtwork(bundleID: String, key: String) {
        guard isRunning(bundleID) else { return }
        if bundleID == "com.apple.Music" {
            DispatchQueue.global(qos: .utility).async {
                let script = "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"
                var error: NSDictionary?
                let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
                let image = result.flatMap { NSImage(data: $0.data) }
                DispatchQueue.main.async { [weak self] in
                    if self?.lastArtworkKey == key { self?.artwork = image }
                }
            }
        } else if bundleID == "com.spotify.client" {
            DispatchQueue.global(qos: .utility).async {
                let script = "tell application id \"com.spotify.client\" to get artwork url of current track"
                var error: NSDictionary?
                guard let urlString = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue,
                      let url = URL(string: urlString) else { return }
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    let image = data.flatMap(NSImage.init(data:))
                    DispatchQueue.main.async { [weak self] in
                        if self?.lastArtworkKey == key { self?.artwork = image }
                    }
                }.resume()
            }
        }
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: Controls

    enum Command { case playPause, next, previous }

    func send(_ command: Command) {
        // Never launch Music/Spotify by talking to them when they're not running.
        if let id = sourceBundleID, isRunning(id) {
            let verb: String
            switch command {
            case .playPause: verb = "playpause"
            case .next: verb = "next track"
            case .previous: verb = "previous track"
            }
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                NSAppleScript(source: "tell application id \"\(id)\" to \(verb)")?.executeAndReturnError(&error)
            }
            if command == .playPause { isPlaying.toggle() }
            return
        }
        switch command {
        case .playPause: mr.send(2)
        case .next: mr.send(4)
        case .previous: mr.send(5)
        }
    }

    func openSourceApp() {
        guard let id = sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
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
