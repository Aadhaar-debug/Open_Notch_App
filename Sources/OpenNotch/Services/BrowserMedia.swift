import Foundation

/// Finds the media tab (YouTube, Spotify Web, Netflix, …) in a browser through the
/// browser's public AppleScript dictionary, and turns its title/URL into track info.
enum BrowserMedia {
    struct Tab {
        let url: String
        let title: String
    }

    struct Info {
        let title: String
        let subtitle: String
        let artworkURL: URL?
    }

    static let chromium: Set<String> = [
        "com.google.chrome", "com.google.chrome.beta", "com.google.chrome.canary",
        "com.microsoft.edgemac", "com.microsoft.edgemac.beta", "com.microsoft.edgemac.dev",
        "com.brave.browser", "company.thebrowser.browser", "com.vivaldi.vivaldi",
        "com.operasoftware.opera", "org.chromium.chromium",
    ]
    static let safari: Set<String> = ["com.apple.safari", "com.apple.safaritechnologypreview"]

    static func isScriptableBrowser(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return chromium.contains(id) || safari.contains(id)
    }

    /// AppleScript that lists the active tab first, then every tab, one "URL<TAB>title" per line.
    static func script(for bundleID: String) -> String {
        let isSafari = safari.contains(bundleID.lowercased())
        let active = isSafari ? "current tab of front window" : "active tab of front window"
        let name = isSafari ? "name" : "title"
        // `tab` is a class inside browser dictionaries, so grab the tab character before `tell`.
        return """
        set sep to ASCII character 9
        tell application id "\(bundleID)"
            set out to ""
            try
                set t to \(active)
                set out to (URL of t) & sep & (\(name) of t) & linefeed
            end try
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set out to out & (URL of t) & sep & (\(name) of t) & linefeed
                    end try
                end repeat
            end repeat
            return out
        end tell
        """
    }

    static func parse(_ output: String) -> [Tab] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return Tab(url: parts[0], title: parts[1])
        }
    }

    private static let mediaHosts = [
        "youtube.com/watch", "youtube.com/shorts", "youtube.com/live", "music.youtube.com", "youtu.be",
        "open.spotify.com", "soundcloud.com", "music.apple.com", "netflix.com/watch", "twitch.tv",
        "primevideo.com", "amazon.com/gp/video", "hotstar.com", "jiosaavn.com", "gaana.com", "wynk.in",
        "vimeo.com", "disneyplus.com", "max.com", "hulu.com", "tidal.com", "deezer.com", "pandora.com",
        "podcasts.apple.com", "bandcamp.com", "dailymotion.com", "jiocinema.com", "zee5.com", "sonyliv.com",
    ]

    /// The tab most likely to be the one making sound: the active tab if it's a media
    /// site, else the first media-site tab, else the active tab.
    static func pick(_ tabs: [Tab]) -> Tab? {
        func isMedia(_ t: Tab) -> Bool { mediaHosts.contains { t.url.contains($0) } }
        if let active = tabs.first, isMedia(active) { return active }
        return tabs.first(where: isMedia) ?? tabs.first
    }

    static func info(for tab: Tab, browserName: String) -> Info {
        var title = tab.title
        // "(271) Video title - YouTube" → "Video title"
        if let range = title.range(of: #"^\(\d+\+?\)\s*"#, options: .regularExpression) {
            title.removeSubrange(range)
        }
        var site = host(of: tab.url)
        let suffixes: [(String, String)] = [
            (" - YouTube Music", "YouTube Music"), (" - YouTube", "YouTube"), (" | Spotify", "Spotify"),
            (" - Spotify", "Spotify"), (" | Netflix", "Netflix"), (" - Netflix", "Netflix"),
            (" - Twitch", "Twitch"), (" on SoundCloud", "SoundCloud"), (" | SoundCloud", "SoundCloud"),
            (" - Apple Music", "Apple Music"), (" on Vimeo", "Vimeo"),
        ]
        for (suffix, name) in suffixes where title.hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count))
            site = name
            break
        }
        var subtitle = "\(site) · \(browserName)"
        // Spotify Web titles look like "Song • Artist".
        if site == "Spotify", let dot = title.range(of: " • ") {
            subtitle = String(title[dot.upperBound...])
            title = String(title[..<dot.lowerBound])
        }
        return Info(title: title.isEmpty ? site : title, subtitle: subtitle, artworkURL: youTubeThumbnail(tab.url))
    }

    private static func host(of url: String) -> String {
        guard let host = URL(string: url)?.host else { return "Web" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    static func youTubeThumbnail(_ url: String) -> URL? {
        guard url.contains("youtube.com") || url.contains("youtu.be"),
              let components = URLComponents(string: url) else { return nil }
        var id = components.queryItems?.first(where: { $0.name == "v" })?.value
        if id == nil {
            let parts = components.path.split(separator: "/")
            if url.contains("youtu.be") { id = parts.first.map(String.init) }
            else if let i = parts.firstIndex(where: { $0 == "shorts" || $0 == "live" }), i + 1 < parts.count {
                id = String(parts[i + 1])
            }
        }
        guard let id, !id.isEmpty else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
    }
}
