---
date: 2026-11-15
branch: fork-improvements
topic: "Lyrics-first mini-player, True Shuffle upgrades, sleep timer, stats, and exact lyric sync"
tags: [plan, spotify, music, sync, overlay, menu-panel, shuffle, stats]
status: in-progress
---

# PLAN: Lyrics-first mini-player and True Shuffle upgrades

Linory stays a **companion** to Spotify and Music, never a replacement player. Every feature below adds something Spotify lacks or controls the user's own player.

## Hard constraints (Spotify Developer Policy, checked 2026-11-15)

- §III.11: no product that "mimic[s], or replicate[s] or attempt[s] to replace a core user experience of Spotify". So no search, library browser, or queue editor.
- §III.7: no segue, mixing, overlapping or crossfading. Linory never touches audio.
- §III.14: no Spotify content into an AI or ML model.
- Since 2024-11-27, new apps get no audio features, audio analysis, recommendations, related artists, or Spotify-made playlists.
- §II.4.2 / II.5: wherever Spotify metadata or cover art is shown, provide a way to open the item in Spotify (`open spotify:track:…` or the web link).
- No strings that mention Claude or AI assistants in repo files.

## Features

### A. Lyrics-first mini-player and exact sync (agent A)

1. **Exact sync.** Lyrics must match the music to within about 50 ms on Spotify and Music.
   - Today, `PlayerModel.update` anchors the clock with `Date()` on the main thread *after* the AppleScript read finished. Anchor with the sample time instead: the midpoint of the AppleScript call, captured on the reader queue.
   - Detect track changes, play/pause and seeks instantly through distributed notifications (`com.spotify.client.PlaybackStateChanged`, `com.apple.Music.playerInfo`), and then poll immediately, instead of waiting up to 0.8 s.
   - Measure, don't guess: add a debug log of clock-vs-player drift, and report numbers before and after.
   - Keep `PlaybackClock` pure in LyricsCore with checks.
2. **Click a lyric line to seek** (Spotify and Music, AppleScript `set player position`). The clock re-anchors at once, with no flicker back.
3. **Jump to chorus.** Detect the chorus from repeated line groups in synced lyrics (pure LyricsCore function with checks). Show a control only when a chorus is found and lyrics are synced.
4. **Mini-player controls** in the overlay (shown on hover, hidden with click-through) and in the menu's now-playing header: previous, play/pause, next, a scrubber (click or drag to seek), and **♥ Like** for Spotify tracks. Like uses `PUT /me/library?uris=` and `GET /me/library/contains?uris=` (scope `user-library-modify` / `user-library-read`), and is hidden when Spotify isn't connected. Clicking the title or cover opens the track in Spotify (policy §II.4.2).

### B. True Shuffle upgrades, sleep timer, stats (agent B)

1. **Keep artists apart.** No two consecutive tracks by the same primary artist when avoidable, otherwise uniformly random. Decode the artist ID from playlist and liked items. Pure LyricsCore with seeded checks.
2. **Keep playing when a round ends.** When the last track of the Linory Shuffle playlist starts, append the next order automatically (same source, new round), so music never stops. Can be toggled on or off in the shuffle section, on by default.
3. **Up next:** the next 3 tracks of the Linory Shuffle order (title and artist) in the shuffle section. Store minimal metadata from the item pages.
4. **Mix several sources:** the source picker allows a mix of Liked Songs and several playlists as one source (stable ID from the sorted member IDs). The cycle is keyed by that ID.
5. **Sleep timer** (menu row): off, 15, 30, 45 or 60 min, or end of the current track. Pauses Spotify or Music via AppleScript. Shows the remaining time.
6. **Stats:** a new Settings pane, **Your music**: top artists and top tracks (`GET /me/top/{artists|tracks}?time_range=short_term|medium_term|long_term&limit=10`, scope `user-top-read`). Display only. Each row opens the item in Spotify.

## File ownership (parallel work: stay in your lane)

| Agent A owns | Agent B owns |
|---|---|
| `PlayerModel.swift`, `Players.swift`, `OverlayView.swift`, `PlaybackClock.swift`, new LyricsCore files for chorus and sync | `ShuffleController.swift`, `ShuffleCycle.swift`, `SpotifyResponses.swift`, `SettingsView.swift`, new LyricsCore files for shuffle, sleep timer and stats |
| `MenuPanel.swift`: only the `nowPlaying` header | `MenuPanel.swift`: only the True Shuffle section and a new sleep-timer row |
| `SpotifyAPI.swift`: only the "agent A" section | `SpotifyAPI.swift`: only the "agent B" section |
| `Localization.swift` and `Checks/main.swift`: only under the "agent A" markers / `checkMiniPlayer()` | same, under the "agent B" markers / `checkShuffleUpgrades()` |

Both may add small wiring in `AppDelegate.swift`. Keep it in one contiguous block, commented with your feature.

## Verification

- `swift build` and `swift run LyricsCoreChecks` pass. Every new UI string exists in English and German.
- Do **not** run `build-app.sh` and do not install to `~/Applications`. The lead merges and installs.
- Docs: update `docs/USAGE.md` (and `PRIVACY.md` if data use changes) for your features.

## Implementation Notes

(Agents: record decisions, measurements and deviations here, under your letter.)
