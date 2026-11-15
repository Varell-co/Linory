# Using Linory

[Back to Linory](../README.md)

## Requirements

- macOS 13 or later is the current deployment target, but has not yet been verified across all supported macOS versions.
- Spotify **desktop app** or the **Music** app, running. Web players are not supported. Reading the current track never launches a player; only **Shuffle & play** in True Shuffle may open Spotify.
- Internet connection for LRCLIB searches.
- Swift and Apple Command Line Tools to build from source.

## Download and run

Download the latest ZIP from [GitHub Releases](https://github.com/MikeLeonFox/LyricsOverlay/releases), extract it, and open `Linory.app`. The early release is **not notarized or signed with an Apple Developer ID**; macOS Gatekeeper may block it. Only open it if you trust the source. If blocked, review Apple's [instructions for safely opening an app](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac). Do not disable Gatekeeper globally. This release has not yet been tested on another Mac or on Intel hardware.

Play a song in Spotify or Music and allow Linory to control that app when macOS asks. macOS asks separately for each player. If permission is denied, check **System Settings → Privacy & Security → Automation**. The app reads the current track and playback position through the player's AppleScript interface; it does not require a login or API credentials. Radio streams in Music have no readable track and show no lyrics.

## Using the overlay

- Drag a free area of the overlay (the header, the edges, or anywhere when lyrics are not synced) to move it. Its position is saved locally.
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

## Mini-player

Linory controls the player you are listening to; Spotify or Music still does all the playing.

- **Controls:** a faint line under the lyrics shows the song's progress. Hover over the overlay and ♥, previous, play/pause and next appear next to the title, and the line becomes a scrubber with the elapsed and remaining time; click or drag it to seek. The controls stay hidden while click-through is on. The menu's now-playing header (right-click the menu-bar icon) always shows them while a track plays.
- **Seek:** click or drag the progress bar. It shows elapsed and remaining time.
- **Click a lyric line** to jump the song to that line (synced lyrics only). The timing offset is respected, so the clicked line is the one that lights up.
- **Chorus:** when synced lyrics repeat a group of lines, each chorus start shows as a dot on the progress line while you hover. Click a dot to jump there.
- **♥ Like:** with [Spotify connected](#connect-spotify-optional), a heart adds the current Spotify track to your Liked Songs or removes it. It is hidden for Music tracks and without a connection.
- **Open in Spotify:** click the cover or title of a Spotify track to show it in Spotify.
- Commands never start a player that is not running.

### Sync

Linory dates every position reading with the moment the player reported it, rather than when the reading arrived, and reacts to track changes, play and pause as soon as Spotify or Music announces them. Seeks made in Spotify itself are noticed within 0.8 s. After a seek, the lyrics hold on the target until the player has buffered and plays again. If the lyrics still run early or late for your setup (for example Bluetooth headphones), adjust **Settings → Timing → Timing offset**.

## Connect Spotify (optional)

Lyrics need no login. Only **True Shuffle**, the **On Spotify** lists in **Your music** and the mini-player's **♥ Like** need a Spotify connection, which uses a Spotify app that you create yourself:

1. Open the [Spotify developer dashboard](https://developer.spotify.com/dashboard) and sign in.
2. Create an app and select **Web API**.
3. Add the redirect URI `linory://callback` and save. **Settings → Spotify** has a Copy button for it.
4. Copy the app's **Client ID** into **Settings → Spotify**, then press **Connect Spotify** and log in.

Your Spotify account needs **Premium**. Spotify limits apps in development mode to 5 allowlisted users, so each person uses their own app rather than a shared one. Linory stays connected across restarts. **Disconnect** removes the stored login; changing the Client ID also disconnects.

## True Shuffle

True Shuffle plays a source in an honest random order, with no repeats until every track has played. It needs a [Spotify connection](#connect-spotify-optional). Open it from the menu: right-click the menu-bar icon, then **True Shuffle**.

- **Sources:** Liked Songs, plus playlists you own or collaborate on. Spotify only lets development-mode apps read those, so playlists made by Spotify (Daily Mix, Discover Weekly) and other people's playlists are missing.
- **Mix sources:** the stack button next to the source picker opens a checklist. Check several sources (for example Liked Songs and two playlists) to shuffle them as one; a song in more than one of them counts once. A mix keeps its own progress, and choosing the same sources again, in any order, continues it. Mixes you have shuffled before stay in the source picker.
- **Shuffle & play** writes this cycle's unplayed tracks, freshly shuffled, to one private playlist named **Linory Shuffle**, then starts it in Spotify with Spotify's own shuffle and repeat turned off. Linory overwrites that playlist on every shuffle, so don't edit it yourself. It may open Spotify. Spotify playlists hold at most 10,000 tracks; larger sources continue in the next shuffle.
- **Artists kept apart:** two songs by the same main artist never play back to back, unless one artist makes up more than half of the source; then the order is simply random where it has to be.
- **Keep playing** (on by default): when the second-to-last track of the order starts, Linory adds the next round of the same source to the end of the Linory Shuffle playlist, so the music doesn't stop. A new cycle starts there when the current one is complete. Once the playlist holds 10,000 tracks, Linory stops adding and asks you to press Shuffle & play.
- **Up next** shows the next three tracks of the order while a shuffled track plays. Click one to open it in Spotify.
- **What counts as played:** a track counts as soon as it starts, skips included, but only while Spotify plays it from the Linory Shuffle playlist. The same song played from another playlist doesn't count.
- **Cycles:** the menu shows **played of total**. Once everything has played, the next Shuffle & play starts a new cycle by itself. Tracks you add to the source later join the running cycle as unplayed. **Reset** starts the selected source over now.
- **Remove from shuffle** appears while a shuffled track plays. It skips the track, takes it out of the Linory Shuffle playlist, and keeps it out of every future shuffle of that source. **Restore removed (n)** brings all removed tracks of the selected source back in the next shuffle.
- **Keep this shuffle** copies the current order, without removed tracks, to a new private playlist named like **Liked Songs · Shuffled 15 Nov**. Linory never changes that playlist again.

## Sleep timer

Right-click the menu-bar icon, then **Sleep timer**, and pick 15, 30, 45 or 60 minutes, or **End of track**. When the time is up, Linory pauses the player it shows (Spotify or Music) through AppleScript, the same way the pause button does. The menu shows the time left; **Off** cancels it. End of track pauses just before the current song ends. The timer does not survive quitting Linory.

## Your music

Open **Your music** from the menu (right-click the menu-bar icon). It shows what you listened to while Linory was running, in Spotify and Music, for today, the last 7 or 30 days, 12 months, or all time:

- **Tiles:** listening time (with the daily average), plays (with the share that had synced lyrics), your day streak, and how many songs you skipped.
- **Listening over time** and the **listening clock** (weekday × hour). Hover a bar or cell for its exact time.
- **Most played songs and artists**, ranked by the time you actually listened. Click a Spotify song to open it in Spotify.

A song counts as a play after 30 seconds, or half of a shorter song; leaving earlier counts as skipped. Only time while music plays counts, not pauses. Turn **Keep listening history** off at the bottom of the window to stop recording, or press **Clear history** twice to delete it.

**On Spotify** shows Spotify's own ranking of your 10 top artists and tracks for the last 4 weeks, 6 months or year. It needs a [Spotify connection](#connect-spotify-optional); if you connected before this existed, press **Reconnect** once to allow Linory to read your top items.

## Where the lyrics come from

Lyrics are looked up on [LRCLIB](https://lrclib.net/), not obtained from the music player. Availability, accuracy, and synchronization vary by track. Linory first asks LRCLIB for the exact track (title, artist, album, and duration), then falls back to a search. It only shows results with a plausible title, artist, and duration match. Synced lyrics are preferred. When a track only has plain lyrics, the lines are spread evenly over the song and marked **~ not synced**. Results are cached locally, so replaying a song needs no network request.
