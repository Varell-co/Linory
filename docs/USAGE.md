# Using Linory

[Back to Linory](../README.md)

## Requirements

- macOS 13 or later is the current deployment target, but has not yet been verified across all supported macOS versions.
- Spotify **desktop app** or the **Music** app, running. Web players are not supported. A player that is not running is never launched by Linory.
- Internet connection for LRCLIB searches.
- Swift and Apple Command Line Tools to build from source.

## Download and run

Download the latest ZIP from [GitHub Releases](https://github.com/MikeLeonFox/LyricsOverlay/releases), extract it, and open `Linory.app`. The early release is **not notarized or signed with an Apple Developer ID**; macOS Gatekeeper may block it. Only open it if you trust the source. If blocked, review Apple's [instructions for safely opening an app](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac). Do not disable Gatekeeper globally. This release has not yet been tested on another Mac or on Intel hardware.

Play a song in Spotify or Music and allow Linory to control that app when macOS asks. macOS asks separately for each player. If permission is denied, check **System Settings → Privacy & Security → Automation**. The app reads the current track and playback position through the player's AppleScript interface; it does not require a login or API credentials. Radio streams in Music have no readable track and show no lyrics.

## Using the overlay

- Drag a free area of the overlay to move it. Its position is saved locally.
- Moving between screens keeps the same readable text size at each screen's pixel density. The overlay fits the usable area and restores your preferred dimensions when space allows.
- Lyrics stay on one line and shrink to fit their width. Five nearby lines scroll as playback advances.
- A lyric that would shrink below 60% of your chosen font size is split into two consecutive entries at a word boundary. Split timing uses word timestamps when available and estimates otherwise.
- Click **⋯** in the overlay, or left-click the menu-bar icon, to open settings.
- Right-click the menu-bar icon to position the overlay, toggle click-through, or quit. Turn click-through off before dragging or clicking the overlay again.
- Set background opacity to 0% for floating text. Positive timing offsets show lyrics earlier.
- The interface follows the macOS language (English or German, English otherwise). Override it under **Settings → General → Language**; the change applies immediately.
- If the global shortcut is already registered by another app, a warning is shown; the menu can still toggle visibility.
- Click-through is remembered across relaunches. Reopening the app from Finder or the Dock turns it off again.
- **Auto-hide when nothing is playing** (Settings → General, off by default) hides the overlay 3 seconds after playback stops and shows it again when music resumes. Hiding it yourself with the shortcut or menu always wins.
- **Launch at login** (Settings → General) registers the app with macOS Login Items. It only works from the bundled `Linory.app`, not from `swift run`. If you move the app after enabling it, turn the option off and on again. If macOS needs your approval, Settings shows a link to System Settings.

## Where the lyrics come from

Lyrics are looked up on [LRCLIB](https://lrclib.net/), not obtained from the music player. Availability, accuracy, and synchronization vary by track. Linory first asks LRCLIB for the exact track (title, artist, album, and duration), then falls back to a search. It only shows results with a plausible title, artist, and duration match. Synced lyrics are preferred. When a track only has plain lyrics, the lines are spread evenly over the song and marked **~ not synced**. Results are cached locally, so replaying a song needs no network request.
