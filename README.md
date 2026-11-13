# Lyrics Overlay

> Fork of [JulianRudrich/LyricsOverlay](https://github.com/JulianRudrich/LyricsOverlay). Generally useful changes are offered back upstream.

A small native macOS app that shows time-synchronized lyrics for the currently playing song in Spotify. The overlay floats above other windows, highlights the current line, and shows nearby lines so you can follow along while working.

> **Early prototype:** built and tested on one Mac. Contributions and reports from other setups are welcome, but installation, macOS version support, and Spotify integration have not yet been widely tested.

## Features

- Synced lyrics, with the current line highlighted and surrounding lines visible.
- Drag the overlay or place it in a screen corner.
- Adjust font size, overlay dimensions, background and overall opacity, and timing offset.
- Click the music note in the overlay to open settings. Right-click the menu-bar icon for positioning, click-through mode, and quit.
- Press **Option + Shift + L** to show or hide the overlay globally.
- Works across macOS spaces; behavior in full-screen apps can vary.

Lyrics are looked up on [LRCLIB](https://lrclib.net/), not obtained from Spotify. Availability, accuracy, and synchronization vary by track. The app displays only results with synchronized timestamps and a plausible title, artist, and duration match.

## Requirements

- macOS 13 or later is the current deployment target, but has not yet been verified across all supported macOS versions.
- Spotify **desktop app**, installed and running. The Spotify web player is not supported.
- Internet connection for LRCLIB searches.
- Swift and Apple Command Line Tools to build from source.

## Download and run

Download the latest ZIP from [GitHub Releases](../../releases), extract it, and open `Lyrics Overlay.app`. The early release is **not notarized or signed with an Apple Developer ID**; macOS Gatekeeper may block it. Only open it if you trust the source. If blocked, review Apple's [instructions for safely opening an app](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac). Do not disable Gatekeeper globally. This release has not yet been tested on another Mac or on Intel hardware.

Play a song in Spotify and allow Lyrics Overlay to control Spotify when macOS asks. If permission is denied, check **System Settings → Privacy & Security → Automation**. The app reads the current track and playback position through Spotify's AppleScript interface; it does not require a Spotify login or API credentials.

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

## Privacy and third-party services

For each track lookup, the app sends the song title and artist to LRCLIB over HTTPS. LRCLIB receives the request and associated network metadata, such as your IP address. Spotify playback details are read locally through macOS Automation. Settings and the window position are stored locally in macOS preferences. No application analytics are implemented in this prototype.

LRCLIB is a third-party service, and its availability and policies may change. Users and distributors are responsible for considering applicable terms and rights relating to lyrics. This project is not affiliated with Spotify or LRCLIB.

## Development

```sh
swift build
swift run LyricsCoreChecks
# Create an ad-hoc signed universal ZIP in dist/ (version defaults to the VERSION file):
bash build-release.sh
```

The checks cover LRC parsing and conservative track matching. They do not replace an end-to-end test with Spotify: verify the automation prompt, loading lyrics, pausing, seeking, changing tracks, the overlay controls, and the global shortcut. XCTest is not available in every Command Line Tools installation, so the current checks use a standalone executable.

## License

The source code is available under the [MIT License](LICENSE). This license applies to the project code, not to lyrics provided by third parties. Do not submit copyrighted lyrics as test fixtures or project assets.
