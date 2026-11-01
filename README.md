# OpenNotch

A free, open-source notch app for macOS. Hover over the MacBook notch to get media controls, a file
shelf, clipboard history, a focus timer, a camera mirror, your calendar and live activities for
volume, charging, low battery and Bluetooth devices.

It's an original implementation built from the publicly described features of notch apps like
NotchNook, Droppy and Seam. It contains no code or assets from those apps.

## Features

| | |
|---|---|
| **Hover to open** | Hover over the notch and it opens; move away (or press Esc / click outside) and it closes. The menu bar under the notch stays clickable. |
| **Now playing** | Artwork, title, artist and play/pause/next/previous for **anything making sound**. YouTube, Spotify Web, Netflix, SoundCloud and other media tabs in Chrome, Edge, Brave, Arc, Vivaldi, Opera and Safari show the video/track title, with YouTube thumbnails as artwork. Music and Spotify show full track info and artwork. Any other app (VLC, IINA, games, calls…) shows its name and icon. While something plays, the closed notch shows the artwork and an animated equalizer. |
| **File shelf** | Drag files onto the notch to keep them on hand, then drag them out wherever you need them. AirDrop, compress/uncompress, reveal in Finder, copy path. Files are kept by reference, never copied. |
| **AirDrop drop zone** | Drop files straight onto the AirDrop tile to share them. |
| **Clipboard history** | The last 40 text/image copies; click one to copy it again. Kept in memory only, and items that password managers mark as concealed are skipped. |
| **Focus timer** | Pomodoro with adjustable focus and break lengths, with a countdown in the closed notch. |
| **Mirror** | A quick camera check. The camera is only on while the tab is open. |
| **Calendar** | Today's remaining events on the Home tab. |
| **Live activities** | Volume HUD, charger connected/disconnected, low battery (20/10/5%), Bluetooth/AirPods connect and disconnect, focus session finished. |
| **Any Mac** | On Macs or external displays without a notch, it draws a simulated one. |
| **Open at login** | Registers itself under System Settings › General › Login Items on first launch (toggle in Settings). |

## Performance

The app is built to cost nothing while idle:

- Everything is event driven: CoreAudio property listeners for volume and for which app is playing
  audio, IOKit power notifications for
  battery, IOBluetooth connect notifications, distributed notifications for Music/Spotify, and
  EventKit change notifications.
- The panel never resizes. Only a SwiftUI shape animates, and hover is detected with a cheap global
  mouse monitor (no Accessibility permission needed).
- The equalizer is a Core Animation layer animation, so it runs in the window server instead of
  re-rendering SwiftUI every frame.
- The only polling is a clipboard `changeCount` check twice a second (one integer read with timer
  coalescing) and the focus timer's 1 Hz tick while it's running.

Measured on an M-series MacBook: ~0% CPU at idle and ~17 MB of memory.

## Install

Requires macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not needed.

```bash
git clone https://github.com/Aadhaar-debug/Open_Notch_App.git
cd Open_Notch_App
./scripts/install.sh
```

This builds a universal (Apple silicon + Intel) release, installs it to `/Applications`, launches it
and adds it to your login items. Run the same command to update.

To render screenshots of each state offscreen (useful when developing):

```bash
swift build -c release && .build/release/OpenNotch --snapshot /tmp/opennotch-shots
```

## Permissions

Requested only when a feature first needs them:

- **Automation (Music / Spotify / your browser):** read what's playing (for browsers, the media tab's
  title and URL) and send play/pause/skip to Music and Spotify.
- **Accessibility:** only used to send the play/pause/next/previous media keys to browsers and other
  apps. Asked for the first time you press one of those buttons.
- **Calendars:** the Home tab's event list.
- **Camera:** the Mirror tab.
- **Bluetooth:** connect/disconnect notifications.

Because the app is ad-hoc signed, macOS may ask again after you rebuild it.

## Notes

- Recent macOS versions don't let third-party apps read the system "Now Playing" info
  (MediaRemote). Instead of working around that protection, OpenNotch uses public APIs: CoreAudio
  says which app is producing sound, and the browser's own AppleScript dictionary says which tab.
  While a browser plays, the tab is re-read every 6 s so autoplay's next video shows up.
- Run `.build/release/OpenNotch --now-playing` to print what the detector currently sees.
- `@State` isn't used: in recent SDKs it's a macro that needs Xcode's plugin. A tiny `StateBox`
  observable keeps the project buildable with only the Command Line Tools.

## Uninstall

Turn off "Open at login" in Settings, quit from the menu bar icon, then delete `/Applications/OpenNotch.app`.

## License

MIT. See [LICENSE](LICENSE).
