# Lyrics Overlay

> Fork of [JulianRudrich/LyricsOverlay](https://github.com/JulianRudrich/LyricsOverlay). Generally useful changes are offered back upstream.

A small native macOS app that shows time-synchronized lyrics for the currently playing song in Spotify or Apple Music. The overlay floats above other windows, highlights the current line, and shows nearby lines so you can follow along while working.

> **Early prototype:** built and tested on one Mac. Contributions and reports from other setups are welcome, but installation, macOS version support, and Spotify integration have not yet been widely tested.

## Features

- Synced lyrics, with the current line highlighted and surrounding lines visible. The highlight follows playback smoothly between player updates.
- Works with Spotify and Apple Music. **Source → Auto** follows whichever app is playing and stays with the current one when both play; you can also pick one player.
- English and German interface.
- Drag the overlay or place it in a screen corner.
- Adjust font size, overlay dimensions, background and overall opacity, and timing offset.
- Click the music note in the overlay to open settings. Right-click the menu-bar icon for positioning, click-through mode, and quit.
- Press **Option + Shift + L** to show or hide the overlay globally.
- Works across macOS spaces; behavior in full-screen apps can vary.

Lyrics are looked up on [LRCLIB](https://lrclib.net/), not obtained from the music player. Availability, accuracy, and synchronization vary by track. The app first asks LRCLIB for the exact track (title, artist, album, and duration), then falls back to a search. It only shows results with a plausible title, artist, and duration match. Synced lyrics are preferred. When a track only has plain lyrics, the lines are spread evenly over the song and marked **~ not synced**. Results are cached locally, so replaying a song needs no network request.

## Requirements

- macOS 13 or later is the current deployment target, but has not yet been verified across all supported macOS versions.
- Spotify **desktop app** or the **Music** app, running. Web players are not supported. A player that is not running is never launched by Lyrics Overlay.
- Internet connection for LRCLIB searches.
- Swift and Apple Command Line Tools to build from source.

## Download and run

Download the latest ZIP from [GitHub Releases](../../releases), extract it, and open `Lyrics Overlay.app`. The early release is **not notarized or signed with an Apple Developer ID**; macOS Gatekeeper may block it. Only open it if you trust the source. If blocked, review Apple's [instructions for safely opening an app](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac). Do not disable Gatekeeper globally. This release has not yet been tested on another Mac or on Intel hardware.

Play a song in Spotify or Music and allow Lyrics Overlay to control that app when macOS asks. macOS asks separately for each player. If permission is denied, check **System Settings → Privacy & Security → Automation**. The app reads the current track and playback position through the player's AppleScript interface; it does not require a login or API credentials. Radio streams in Music have no readable track and show no lyrics.

## Build from source

Clone or download this repository, then run the following from the project directory:

```sh
bash build-app.sh
open "Lyrics Overlay.app"
```

The build script creates a locally ad-hoc-signed app, not a Developer ID-signed or notarized distribution. Gatekeeper behavior can differ on another Mac. A signed and notarized release has not been prepared yet.

## Using the overlay

- Drag a free area of the overlay to move it. Its position is saved locally.
- Click the note in the overlay, or left-click the menu-bar icon, to open settings.
- Right-click the menu-bar icon to position the overlay, toggle click-through, or quit. Turn click-through off before dragging or clicking the overlay again.
- Set background opacity to 0% for floating text. Positive timing offsets show lyrics earlier.
- The interface follows the macOS language (English or German, English otherwise). Override it under **Settings → General → Language**; the change applies immediately.
- If the global shortcut is already registered by another app, a warning is shown; the menu can still toggle visibility.
- Click-through is remembered across relaunches. Reopening the app from Finder or the Dock turns it off again.
- **Auto-hide when nothing is playing** (Settings → Playback, off by default) hides the overlay 3 seconds after playback stops and shows it again when music resumes. Hiding it yourself with the shortcut or menu always wins.
- **Launch at login** (Settings → General) registers the app with macOS Login Items. It only works from the bundled `Lyrics Overlay.app`, not from `swift run`. If you move the app after enabling it, turn the option off and on again. If macOS needs your approval, Settings shows a link to System Settings.

## Privacy and third-party services

For each track lookup that is not cached, the app sends the song title, artist, album, and duration to LRCLIB over HTTPS. LRCLIB receives the request and associated network metadata, such as your IP address. Playback details are read locally from Spotify or Music through macOS Automation. Settings and the window position are stored locally in macOS preferences. Lookup results are cached in `~/Library/Application Support/io.github.mikeleonfox.lyricsoverlay/lyrics-cache.json` (up to 500 tracks; "not found" results are retried after 7 days). Delete that file to clear the cache. No application analytics are implemented in this prototype.

LRCLIB is a third-party service, and its availability and policies may change. Users and distributors are responsible for considering applicable terms and rights relating to lyrics. This project is not affiliated with Spotify, Apple, or LRCLIB.

## Development

```sh
swift build
swift run LyricsCoreChecks
# Create an ad-hoc signed universal ZIP in dist/ (version defaults to the VERSION file):
bash build-release.sh
```

The checks cover LRC parsing, conservative track matching, localization, the playback clock, plain-lyrics timing, the lyrics cache, and player selection. They do not replace an end-to-end test with Spotify and Music: verify the automation prompt, loading lyrics, pausing, seeking, changing tracks, the overlay controls, and the global shortcut. XCTest is not available in every Command Line Tools installation, so the current checks use a standalone executable.

## License

The source code is available under the [MIT License](LICENSE). This license applies to the project code, not to lyrics provided by third parties. Do not submit copyrighted lyrics as test fixtures or project assets.
