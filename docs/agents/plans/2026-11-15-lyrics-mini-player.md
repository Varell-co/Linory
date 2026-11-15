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

### A. Mini-player and exact sync

**Measurements (Spotify desktop, this Mac, 2026-11-15, in-process `NSAppleScript`):**

- The full `read()` script (seven Apple events) takes 88 ms median, 96 to 181 ms max. Its `player position` lands at 0.97 of the call (median of 15, measured against single-event position reads before and after). So the call's midpoint would put lyrics about 40 ms *ahead*; the old "anchor at `Date()` on main after the read" was only about 3 ms plus the main-thread hop (0 to 16 ms) behind.
- A single-event `player position` read takes 22 to 28 ms; consecutive readings deviate from wall time by ±6 ms, so its midpoint is a good sample time. `PlayerModel` now does this extra read while playing and anchors with its midpoint (fallback: end of the full read).
- After `set player position`, Spotify applies the seek within about 40 ms, then reports the target *without moving* for about 210 ms while it buffers.
- Spotify posts `PlaybackStateChanged` for play, pause and track changes, but **not** for seeks.

**The real sync bug** was in `PlaybackClock`: any clock lead under 0.3 s was treated as jitter and never corrected. Every buffering stall (track skip, seek in Spotify) left the lyrics up to about 0.2 s ahead for the rest of the song. Now a small lead is slewed out over 0.6 s (the clock slows down, never runs backwards, so no flicker), larger differences jump, and a clock that is behind jumps forward at once. Linory's own seeks hold the clock on the target until the player reports movement, and reads started before a seek are dropped.

**Drift, before and after.** Spotify was paused by the time the live run could start, and Linory must not start playback, so there are no live `drift` log numbers yet. Instead, the measured timings above feed a model of both pipelines (old clock with `Date()`-on-main anchoring; new clock with sample-time anchoring and notifications): a skip, a seek in Spotify and a seek at 80 s, over 300 two-minute runs.

| | before | after |
|---|---|---|
| Lyrics vs. audio, from 3 s after an event: median / p95 / max | 3 / 125 / 200 ms | 1 / 2 / 3 ms |
| Time off by more than 50 ms (same window) | 11.5 % | 0 % |
| `drift` log value at each poll: median / p95 | 4 / 149 ms | 1 / 4 ms |

To measure live: run the dev build while Spotify plays and stream the debug log, for example `log stream --level debug --predicate 'subsystem == "io.github.mikeleonfox.lyricsoverlay" AND category == "player"'` (debug messages are not persisted, so `log show` misses them). Each poll logs `drift <ms> ms, read <ms> ms`: the overlay's position at the sample time minus the player's. Expect single-digit values except right after seeks made in Spotify.

**Decisions:**

- `seek(to:)` takes player time; `seek(toLyricTime:)` subtracts the timing offset (and adds 10 ms against rounding), used by line clicks and Chorus. The scrubber works in player time.
- Chorus detection (`Chorus.starts`) ignores empty lines and compares `LyricsMatching.normalized` text. Ties on repetition count prefer the longer group, then the earlier one. `Chorus.next` skips a chorus that starts within 0.5 s, so pressing twice moves on.
- Overlay controls use an `NSTrackingArea` (`.activeAlways`) for hover, because the overlay never becomes key. Only synced lyric rows take clicks; other rows let clicks through, so the overlay can still be dragged from them.
- Liked state lives in `SpotifyLibrary` (owned by `PlayerModel`, attached to `SpotifyAuth` in one `AppDelegate` line). It asks Spotify once per track, only while a view shows the heart, and flips optimistically.
- Cover and title open `spotify:track:` URIs in Spotify. Music tracks are not linked.
- The Chorus button is only in the overlay; the menu header has previous, play/pause, next, scrubber and the heart.

**Untested:** the menu header and the heart were not seen running (no Spotify login in the dev build, and no synthetic clicks allowed); Music was not running, so its timing and its `playerInfo` notification are untested; the like endpoints were not called live.

### B

- **Artist spread:** `ArtistSpread.arrange` (in `ShuffleCycle.swift`) runs right after `ShuffleCycle.nextOrder`, so the existing cycle rules and checks are untouched. Each step picks a random remaining track, weighted per artist, among artists that differ from the previous one and keep the rest arrangeable (an artist fits in `(rest + 1) / 2` slots, the previous one in `rest / 2`). When that is impossible it relaxes to "differ from the previous one", then to any track, so the unavoidable case stays random rather than minimizing repeats. Within an artist the order is uniform; across artists it is a weighted greedy walk, not an exact uniform draw over all valid permutations. Cost is O(tracks × artists): about 0.3 s for 10,000 tracks and 3,000 artists in a release build (9 s in debug), so it runs in a detached task. Tracks without an artist ID (old data) count as their own artist.
- **Metadata:** `SpotifyTrackPage.tracks` adds name and primary artist (ID and name) for both `item` and `track` entries; `uris` is now derived from it. New `SpotifyAPI.tracks(source:)` pages like `trackURIs`; `likedTrackURIs`, `playlistTrackURIs` and `trackURIs` are now unused but left in place because they sit outside the agent B section. Remove them on merge if nothing else uses them.
- **State file:** `ShuffleState` gained `trackInfo` (title, artist, artist ID per URI in `currentOrder`, short JSON keys) and `playingIndex`. A custom `init(from:)` decodes missing fields with defaults, so old `shuffle-state.json` files load (checked).
- **Auto-continue:** triggers when the confirmed playing track is the second-to-last or last of `currentOrder` (`ShuffleState.needsNextRound`). The tracks still queued after it are passed to `nextOrder(from:excluding:)`, which leaves them out and starts the new cycle without them, so no song repeats across the seam; they are counted when they actually play. The new round is spread with the last queued artist as `after`, appended with `POST /playlists/{id}/items`, and added to `currentOrder` and `trackInfo`. Plays counted while the round was being built are merged back. `currentOrder` mirrors the playlist, so it may now hold a URI once per round; `ShuffleState.index(of:)` searches from `playingIndex` on to find the right copy. At 10,000 items Linory stops appending and shows `shuffleFull`. While appending, `activity == .continuing` blocks Shuffle & play, Reset and Restore so the state cannot race. Setting: `UserDefaults` key `shuffleAutoContinue`, default on (read with a fallback, so no `register(defaults:)` change in `AppDelegate`).
- **Mix:** ID `mix:<sorted, deduped member IDs joined by ",">`; one member is just that source's ID. The cycle is keyed by it, and members are fetched one after another and deduplicated by URI. UI: a stack button next to the picker opens a checklist (5 rows, then scrolls); checking sources changes the selection directly, the last member cannot be unchecked. Mixes with a stored cycle are listed in the picker. A mix whose member playlist is gone falls back to Liked Songs, like a missing playlist did.
- **Up next:** shown only while the current track is confirmed in the Linory Shuffle context; each row opens the track in Spotify (`SpotifyLink.open`, policy §II.4.2). Empty after an update until the next Shuffle & play, since old state has no metadata.
- **Sleep timer:** pure `SleepTimer` in LyricsCore; `SleepTimerController.shared` (in `Sources/Linory/SleepTimer.swift`) ticks every 0.5 s and sends `pause` via AppleScript to the player `PlayerModel` shows, or to every running player when none. It never launches a player. "End of track" pauses 0.6 s before the end (poll slack) or as soon as another track is current; it is disabled when nothing plays. A shared instance avoids changing the `MenuPanel` initializer and `AppDelegate`. `disclosureRow` gained an optional `detail` (the remaining time).
- **Your music:** `Pane.stats` with `TopItemsModel` (in `SettingsView.swift`), loaded with `.task(id:)` per range, cached per range while the Settings window lives, cleared on disconnect. A 403 (login without `user-top-read`) shows the Reconnect hint, as does `needsReconnect`.
- **AppDelegate:** no changes needed.
- **Untested against Spotify:** auto-continue append timing, top-items responses, mix fetching and the sleep-timer `pause` were verified only by build and pure checks.
