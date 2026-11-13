---
date: 2026-11-13T21:25:19+00:00
git_commit: b28beed69a6bda8f0104e205ad90599a81f17eba
branch: main
topic: "Fork LyricsOverlay and improve sync, localization, lyrics lookup, Apple Music and visibility"
tags: [plan, fork, lyrics-core, player-model, overlay, settings, lrclib, apple-music, localization]
status: draft
---

# PLAN: LyricsOverlay fork improvements (v0.2.0)

Fork `JulianRudrich/LyricsOverlay` to `MikeLeonFox/LyricsOverlay` and ship a v0.2.0 that has smoother line sync, an English/German UI, more reliable lyrics lookup with a local cache and plain-lyrics fallback, Apple Music support, and launch-at-login and auto-hide options. Keep the fork PR-friendly toward upstream.

## Acceptance Criteria

- The fork exists at `MikeLeonFox/LyricsOverlay`, with `origin` pointing to it and `upstream` pointing to `JulianRudrich/LyricsOverlay`. The app builds as version `0.2.0` with bundle ID `io.github.mikeleonfox.lyricsoverlay`.
- While playing, the highlighted line changes within ~100 ms of its timestamp (plus the user offset), not up to 0.8 s late. When paused, the position freezes.
- The UI follows the macOS language (English fallback), with a System / English / Deutsch override in Settings. Every string exists in both languages, checked automatically. Switching language updates the overlay, Settings and menu without restarting.
- Lyrics lookup order is disk cache, then LRCLIB `/api/get` (title, artist, album, duration), then `/api/search` with the existing strict matching. Replaying a song makes no network request.
- When a song has only plain lyrics, the lines are spread evenly over the song and shown with a "~ not synced" tag. Instrumental tracks show an instrumental status.
- Spotify and Apple Music both work. Players that are not running are never queried, so they are never launched. Source picker offers Auto / Spotify / Apple Music. Auto follows the playing app and keeps the current one when both play.
- A "Launch at login" toggle uses `SMAppService` and shows a hint or error when registration fails or needs approval.
- An "Auto-hide when not playing" toggle is off by default. It hides after 3 s without playback. A manual hide (hotkey or menu) always wins over auto-show.
- Click-through survives relaunch.
- `swift run LyricsCoreChecks` covers all new pure logic, and CI stays green.

## Technical Key Decisions and Tradeoffs

1. **Fork identity:** new bundle ID `io.github.mikeleonfox.lyricsoverlay`, version `0.2.0`, app name unchanged, `upstream` remote kept.
   - Why: no collision with an installed upstream copy, and features can still be PR'd back.
   - Impact: fresh preferences domain and a fresh Automation prompt. Old settings are not migrated.
2. **Single version source:** a root `VERSION` file read by `build-app.sh`, `build-release.sh` and CI.
   - Why: today `build-app.sh` stamps `1.0` while CI expects `0.1.0`.
   - Impact: CI derives the artifact name from `VERSION`.
3. **Localization via an in-code string table in `LyricsCore`**, not `.strings`/`.xcstrings` resources.
   - Why: the `.app` is hand-assembled by `build-app.sh`, so SwiftPM resource bundles would need extra copying and signing. An in-code table also makes completeness testable in `LyricsCoreChecks`.
   - Impact: `Info.plist` usage text stays English only, because the system shows it.
4. **Status is a typed value rendered at display time** (`StatusMessage` enum), not a stored string.
   - Why: a language switch must re-render already-shown status text.
   - Impact: `PlayerModel.status` changes type.
5. **Pure logic lives in `LyricsCore`** (playback clock, plain-lyrics timing, cache key and entry, player selection, visibility policy, localization).
   - Why: only `LyricsCoreChecks` can test code, because the app target is an executable and XCTest isn't always available.
   - Impact: the app target holds only AppKit, SwiftUI, AppleScript and network glue.
6. **Interpolated playback clock + `TimelineView` redraw** instead of faster AppleScript polling.
   - Why: polling stays at 0.8 s (AppleScript is expensive), and the UI extrapolates between polls.
   - Impact: small backward corrections (< 0.3 s) are ignored to avoid flicker. Larger ones (seeks) snap.
7. **Players behind a `MediaPlayer` protocol** (Spotify and Music readers), with selection in `PlayerSelection`.
   - Why: one code path for Auto and manual sources.
   - Impact: in Auto mode, both running players are polled each tick (at most two AppleScript calls per 0.8 s).
8. **Disk cache as one JSON file** in `~/Library/Application Support/io.github.mikeleonfox.lyricsoverlay/lyrics-cache.json`, capped at 500 entries (oldest evicted). "Not found" and instrumental results expire after 7 days. Network errors are never cached.
   - Why: simple, inspectable, no dependency. LRCLIB fills in missing tracks in the background, so negative results need to expire.
   - Impact: README privacy section documents the cache.
9. **Launch at login reads `SMAppService.mainApp.status` as the source of truth** and stores nothing in UserDefaults.
   - Why: the user can change it in System Settings, so a stored copy could drift.

## Current State

```
Spotify (AppleScript, polled every 0.8s)           LRCLIB /api/search
        │ id,title,artist,duration(ms),position            ▲
        ▼                                                  │ on track change, no cache
  PlayerModel        Sources/LyricsOverlay/main.swift:13 ──┘
   @Published track/lines/position/status(German String)
        │  position only changes per poll → highlight lags ≤0.8s
        ▼
  OverlayView        main.swift:110   prev · ACTIVE · next lines, @AppStorage settings
  SettingsView       main.swift:162   six sliders, German labels
  AppDelegate        main.swift:194   NSPanel, status item + menu (German), ⌥⇧L Carbon hotkey,
                                      clickThrough not persisted
  LyricsCore/Lyrics.swift             LRC.parse, LRC.currentIndex, LyricsResult,
                                      LyricsMatching.best (synced only, ±5s, strict title/artist)
  Checks/main.swift                   preconditions for parse + matching
  build-app.sh                        bundle id de.local.lyricsoverlay, version 1.0, German usage text
  build-release.sh / ci.yml           version 0.1.0
```

All UI strings are German (`main.swift:17,50,63,70,87,104,133,173-179,246-247,259,283-300,312,318`). The README is English.

## Desired End State

```
            ┌──────────── PlayerSelection (Core) ───────────┐
Spotify ──► SpotifyPlayer ─┐                                │
Music   ──► MusicPlayer  ──┴─► PlayerModel ── PlaybackClock (Core) ──► OverlayView (TimelineView 50ms)
 (only if running)              │  StatusMessage                         │ L10n (Core)
                                ▼                                        ▼
                         LyricsService ── LyricsCache (disk) ──► LoadedLyrics{lines, synced}
                                │ miss                          PlainLyrics.estimate (Core)
                                ▼
                     LRCLIB /api/get ──404──► /api/search (LyricsMatching)

AppDelegate: menu rebuilt on open (localized, Source submenu), VisibilityPolicy (Core) drives
auto-hide, clickThrough persisted, LoginItem (SMAppService)
```

### Settings window (proposed)

```
┌ Lyrics Overlay – Settings ───────────────────────┐
│ Lyrics Overlay                                   │
│ APPEARANCE                                       │
│ Font size                              25 pt     │
│ ────────●──────────────                          │
│ Overlay opacity                       100 %      │
│ Background opacity                     78 %      │
│ Width 400 px          Height 240 px              │
│ TIMING                                           │
│ Timing offset                          0.0 s     │
│ PLAYBACK                                         │
│ Source            [ Auto ▾ ]  (Auto/Spotify/Music)│
│ [ ] Auto-hide when nothing is playing            │
│ GENERAL                                          │
│ Language          [ System ▾ ] (System/English/Deutsch)
│ [x] Launch at login                              │
│   ⚠ Needs approval in System Settings [Open…]    │  ← only when status requires approval/error
│ Show/hide overlay: ⌥ ⇧ L · Positive offsets show │
│ lyrics earlier. Title, artist and album are sent │
│ to LRCLIB.                                       │
└──────────────────────────────────────────────────┘
```

### Overlay with plain lyrics (proposed)

```
┌──────────────────────────────────────────┐
│ ♪  Song · Artist            ~ not synced │
│                                          │
│   previous line (dim)                    │
│   CURRENT LINE (bold)                    │
│   next line (dim)                        │
└──────────────────────────────────────────┘
```

### Status-item menu (proposed)

```
Lyrics Overlay
──────────────
Hide overlay
Click-through            ✓ (persisted)
Position          ▸  Top left / Top right / Bottom left / Bottom right
Source            ▸  ✓ Auto / Spotify / Apple Music
──────────────
Settings…           ⌘,
Quit                ⌘Q
```

## Abstractions and Code Reuse

- `VERSION` - new, contains `0.2.0`
- `Package.swift` - unchanged targets (Checks target may get extra files)
- `Sources/LyricsCore`
  - `Lyrics.swift` - extend
    - `LyricsResult` - add optional `plainLyrics`, `instrumental`, `albumName`
    - `LyricsMatching.normalized` - make `public` (reused as cache key)
    - `LyricsMatching.best` - keep the synced-only behavior. Add `bestAny` that prefers synced and falls back to plain-only candidates under the same title/artist/±5 s rules
  - `Track.swift` - new: `PlayerSource` (`spotify`, `music`), `Track` (moved from app; adds `album`, `source`), `PlaybackSnapshot`
  - `Localization.swift` - new: `AppLanguage` (`system`, `en`, `de`) with `resolve(preferredLanguages:)`, `L10nKey: CaseIterable`, `L10n.string(_:_ args:, language:)`, `StatusMessage` enum with `text(language:)`
  - `PlaybackClock.swift` - new: `PlaybackClock` (anchor position/date, playing, duration, `position(at:)`, `update(...)` with the 0.3 s backward-jitter rule)
  - `PlainLyrics.swift` - new: `PlainLyrics.estimate(text:duration:) -> [LyricLine]`, `LoadedLyrics { lines, synced, instrumental }`
  - `LyricsCacheModel.swift` - new: `LyricsCacheKey.make(track:)`, `LyricsCacheEntry: Codable`, `LyricsCacheStore` (pure in-memory dictionary logic: lookup with expiry, insert, evict to cap; serialized by the app)
  - `PlayerSelection.swift` - new: `SourcePreference` (`auto`, `spotify`, `music`), `PlayerSelection.choose(preference:states:current:)`
  - `VisibilityPolicy.swift` - new: `VisibilityPolicy.shouldShow(userHidden:autoHide:playing:hasTrack:notPlayingSince:now:)`
- `Sources/LyricsOverlay` (split `main.swift`)
  - `main.swift` - only the app bootstrap (current lines 328-331)
  - `AppDelegate.swift` - window, status item, menu (`NSMenuDelegate.menuNeedsUpdate` rebuilds localized titles), click-through persistence, visibility
  - `HotKey.swift` - Carbon hotkey register/unregister, extracted from `AppDelegate`
  - `PlayerModel.swift` - polling, selection, clock, lyrics loading via `LyricsService`
  - `Players.swift` - `MediaPlayer` protocol, `SpotifyPlayer` (extracted from `readSpotify`), `MusicPlayer`
  - `LyricsService.swift` - cache file IO plus LRCLIB `/api/get` → `/api/search`
  - `OverlayView.swift`, `SettingsView.swift` - extracted, then localized and extended
  - `LoginItem.swift` - thin wrapper around `SMAppService.mainApp`
- `Checks/main.swift` - extended. Each area gets a `func check…()` so failures point to the area
- `build-app.sh`, `build-release.sh`, `.github/workflows/ci.yml` - read `VERSION`, new bundle ID, English usage text
- `README.md`, `CONTRIBUTING.md`, `RELEASE_NOTES.md` - fork, features, privacy and cache, Apple Music

## Logging & Observability

Add `os.Logger(subsystem: "io.github.mikeleonfox.lyricsoverlay", category: …)` in the app target. Only metadata is logged, never lyrics text.

```
[lyrics] cache hit synced "Song" – "Artist"
[lyrics] /api/get 404 → /api/search (20 results, match: plain)
[lyrics] network error: The request timed out. (not cached)
[player] source auto → music (spotify paused, music playing)
[player] AppleScript error -1743 for com.apple.Music (automation denied)
[login] register failed: Operation not permitted
```

You can view them with `log stream --predicate 'subsystem == "io.github.mikeleonfox.lyricsoverlay"'` (documented in CONTRIBUTING).

## Implementation

### Phase 1: Fork, identity and file split

Dependencies: None

Create the fork, set the new identity and version, and split `main.swift` into files with no change in behavior.

**Tasks**:
- [x] Run `gh repo fork JulianRudrich/LyricsOverlay --clone=false` (creates `MikeLeonFox/LyricsOverlay`)
- [x] Run `git remote rename origin upstream` and `git remote add origin git@github.com:MikeLeonFox/LyricsOverlay.git`, then push `main` to `origin`
- [x] Create branch `fork-improvements` for all following work
- [x] Add root `VERSION` file containing `0.2.0`
- [x] `build-app.sh`: read `VERSION` and write it to `CFBundleShortVersionString` and `CFBundleVersion`. Set `CFBundleIdentifier` to `io.github.mikeleonfox.lyricsoverlay`. Make `NSAppleEventsUsageDescription` English: "Lyrics Overlay reads the current track and playback position to show synchronized lyrics." Make the final echo English.
- [x] `build-release.sh`: make the version argument optional and default it to `$(cat VERSION)`
- [x] `.github/workflows/ci.yml`: read `VERSION` into `$GITHUB_ENV`, then use `${{ env.VERSION }}` for the release build, the archive path, the plist assertion, and the artifact name. Also assert `CFBundleIdentifier` equals the new ID.
- [x] Split `Sources/LyricsOverlay/main.swift` into `AppDelegate.swift`, `HotKey.swift` (Carbon handler and register/unregister from `registerHotKey`/`applicationWillTerminate`), `PlayerModel.swift`, `OverlayView.swift`, `SettingsView.swift`, and a bootstrap-only `main.swift`. No logic changes.
- [x] Move `Track` into `Sources/LyricsCore/Track.swift` as `public`, and import it in the app
- [x] `PlayerModel`: set the User-Agent to `LyricsOverlay/<CFBundleShortVersionString or "dev"> (https://github.com/MikeLeonFox/LyricsOverlay)` per the LRCLIB client identification rule
- [x] README: add a fork note under the title linking upstream. Update the build commands to show that `build-release.sh` defaults to `VERSION`.
- [x] CONTRIBUTING: note the `upstream` remote and that PRs for generally useful features may also go upstream

**Automated Verification**:
- [x] `git remote -v` lists `origin` → `MikeLeonFox/LyricsOverlay` and `upstream` → `JulianRudrich/LyricsOverlay`
- [x] `swift build` succeeds
- [x] `swift run LyricsCoreChecks` prints `LyricsCore checks passed`
- [x] `bash build-app.sh && /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "Lyrics Overlay.app/Contents/Info.plist"` prints `0.2.0`
- [x] `/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "Lyrics Overlay.app/Contents/Info.plist"` prints `io.github.mikeleonfox.lyricsoverlay`
- [x] `bash build-release.sh` (no argument) creates `dist/Lyrics-Overlay-0.2.0-universal.zip`
- [x] `wc -l Sources/LyricsOverlay/main.swift` reports ≤ 10 lines
- [x] After pushing the branch, the CI run on GitHub is green (`gh run list --branch fork-improvements --limit 1` shows `success`)

### Phase 2: English/German localization with language picker

Dependencies: Phase 1

Every user-facing string comes from a checked English/German table. The language follows the system and can be overridden live.

**Tasks**:
- [x] `LyricsCore/Localization.swift`: add `public enum AppLanguage: String, CaseIterable { case system, en, de }` with `func resolved(preferredLanguages: [String]) -> AppLanguage` (`de*` → `.de`, anything else → `.en`)
- [x] Same file: `public enum L10nKey: String, CaseIterable` covering every string currently in `main.swift` (menu items, settings labels and suffixes, footer, hotkey alert, tooltips, overlay placeholder `LYRICS OVERLAY`, settings window title), plus `public enum L10n { static func string(_ key: L10nKey, _ args: CVarArg..., language: AppLanguage) -> String }` backed by `[AppLanguage: [L10nKey: String]]` for `.en` and `.de`. Keep the German wording from the current `main.swift`.
- [x] Same file: `public enum StatusMessage: Equatable` (`waitingForPlayer`, `openPlayer`, `automationDenied`, `playerError(String)`, `noTrack`, `searching`, `networkError`, `noLyrics`) with `func text(language:) -> String`
- [x] `PlayerModel.swift`: change `status` to `StatusMessage` and map the existing messages to cases
- [x] `OverlayView.swift`, `SettingsView.swift`: add `@AppStorage("language") var language = AppLanguage.system.rawValue`, resolve it with `Locale.preferredLanguages`, and replace literals with `L10n.string`
- [x] `SettingsView.swift`: add a `Picker` for Language (System / English / Deutsch, labels from L10n). Group the controls under section headers APPEARANCE / TIMING / GENERAL as in the mockup.
- [x] `AppDelegate.swift`: make `statusMenu` delegate `menuNeedsUpdate(_:)` rebuild all item titles from the current language. Set the settings window title and status-item tooltip from L10n, and update them on `UserDefaults.didChangeNotification`. Localize the hotkey alert at display time.
- [x] Register `"language": "system"` in `UserDefaults.register(defaults:)`
- [x] Checks: assert every `L10nKey` has a non-empty value for `.en` and `.de`, `AppLanguage.system.resolved(preferredLanguages: ["de-DE"]) == .de`, `["fr-FR"]` → `.en`, an explicit `.de` stays `.de`, and the format arguments of `StatusMessage.playerError("x")` appear in the text
- [x] README: mention the language setting under "Using the overlay"

**Automated Verification**:
- [x] `swift build` succeeds
- [x] `swift run LyricsCoreChecks` passes, including the localization checks
- [x] `grep -nE '"[^"]*[äöüÄÖÜß][^"]*"' Sources/LyricsOverlay/*.swift` returns nothing (no German literals left outside the core table)

**Manual Verification**:
- [ ] With the system language set to English, the overlay, Settings, menu and hotkey alert are in English. Switching the picker to Deutsch changes them right away, including the right-click menu the next time it opens.

### Phase 3: Smooth sync via interpolated playback clock

Dependencies: Phase 1

Remove the up-to-0.8 s highlight lag by extrapolating the position between polls.

**Tasks**:
- [x] `LyricsCore/PlaybackClock.swift`: add `public struct PlaybackClock` with `anchorPosition`, `anchorDate`, `playing`, `duration`, `func position(at now: Date) -> Double` (playing: anchor + elapsed, clamped to `duration`. Paused: anchor), and `mutating func update(position:playing:duration:at:)`. While playing on the same track, a new reading that is less than 0.3 s behind the predicted position keeps the prediction, and anything else re-anchors. `reset()` is used on track change.
- [x] `PlayerModel.swift`: replace `@Published position` with `@Published clock: PlaybackClock`, update it on each poll, and reset it on track change and on `clear`
- [x] `OverlayView.swift`: wrap the lyrics stack in `TimelineView(.animation(minimumInterval: 0.05, paused: !model.clock.playing))` and compute `active` from `model.clock.position(at: context.date) + offset`
- [x] Checks: elapsed time advances the position while playing, a paused clock is frozen, the position clamps to the duration, a reading 0.2 s behind is ignored, a reading 2 s behind (seek) re-anchors, a reading ahead re-anchors, and `reset` zeroes the clock
- [x] README: drop any wording implying the lag. No other doc change is needed.

**Automated Verification**:
- [x] `swift build` succeeds
- [x] `swift run LyricsCoreChecks` passes, including the `PlaybackClock` checks

**Manual Verification**:
- [ ] With a well-synced song, the highlight changes on the beat with no visible ~1 s lag. Pausing freezes it, and seeking jumps to the right line within one poll.

### Phase 4: Better lyrics lookup, cache and plain-lyrics fallback

Dependencies: Phase 2 (uses `StatusMessage`), Phase 3 (overlay rendering path via `TimelineView` that plain lyrics reuse)

**Tasks**:
- [x] `LyricsCore/Lyrics.swift`: extend `LyricsResult` with optional `plainLyrics`, `instrumental`, `albumName` (decoding stays tolerant of missing fields). Make `normalized` public. Add `LyricsMatching.bestAny(_:title:artist:duration:) -> LyricsResult?`, which applies the same title/artist/±5 s rules and returns the closest synced candidate, or else the closest candidate with non-empty `plainLyrics`, or else an instrumental match.
- [x] `LyricsCore/Track.swift`: add `album: String` to `Track`
- [x] `LyricsCore/PlainLyrics.swift`: add `public struct LoadedLyrics: Codable, Equatable { lines; synced: Bool; instrumental: Bool }`, plus `PlainLyrics.estimate(text:duration:)`. It drops empty lines and spreads the rest evenly from `lead = min(10, duration * 0.05)` to `duration * 0.95`. It returns `[]` for empty text or duration ≤ 0.
- [x] `LyricsCore/LyricsCacheModel.swift`: add `LyricsCacheKey.make(title:artist:duration:)` (normalized title|artist|rounded duration), `LyricsCacheEntry: Codable { lyrics: LoadedLyrics?, fetchedAt: Date }` (`nil` means not found), and `LyricsCacheStore` with `lookup(key, now)` (not-found and instrumental entries expire after 7 days, found synced/plain never expire), `insert`, and eviction of the oldest entries above 500
- [x] `LyricsOverlay/LyricsService.swift`: `load(track:) async -> Result<LoadedLyrics?, Error>`. Check the cache first. Then call `GET /api/get?track_name&artist_name&album_name(if non-empty)&duration(Int, 1...3600 else omitted)`. On 200, decode one `LyricsResult` and validate with `bestAny([result], …)`. On 404 or no valid result, call `/api/search` and use `bestAny`. Successful outcomes, including not-found, are stored in the cache. Network or HTTP errors are returned and not cached. The cache file is read once at startup and written atomically after each insert, off the main thread.
- [x] Spotify AppleScript in `PlayerModel` (later `Players.swift`): also return `album of t`
- [x] `PlayerModel.swift`: replace the inline `URLSession` code with `LyricsService`, keep the `generation` guard, and publish `lyrics: LoadedLyrics?`. Add statuses `instrumental` and `notSynced` to `StatusMessage` and the L10n table.
- [x] `OverlayView.swift`: when `lyrics.synced == false`, show the `~ not synced` tag (L10n) at the right of the header. Instrumental shows a `♪` instrumental status line.
- [x] Add `os.Logger` category `lyrics` with the log lines from the Logging section
- [x] Checks: `bestAny` prefers synced over plain at equal duration, falls back to plain, still rejects a wrong artist or a duration off by more than 5 s. `estimate` gives evenly spaced, increasing times inside the bounds and `[]` for blank input. Cache key normalization (case and diacritics are ignored). The cache store expires not-found entries after 7 days but not found ones, and evicts the oldest at 501 entries. `LyricsResult` decodes the `/api/get` sample JSON with `plainLyrics` and `instrumental`, using invented lyrics text and no copyrighted lyrics.
- [x] README: update the LRCLIB paragraph (album and duration are also sent, plain-lyrics fallback) and the privacy section (local cache location, delete the file to clear it)

**Automated Verification**:
- [x] `swift build` succeeds
- [x] `swift run LyricsCoreChecks` passes, including the matching, plain-lyrics and cache checks

**Manual Verification**:
- [ ] A synced song loads. Replaying it shows lyrics instantly with no `/api/` request in `log stream`.
- [ ] A song with only plain lyrics on LRCLIB scrolls with the `~ not synced` tag. With Wi-Fi off, a previously played song still shows lyrics.

### Phase 5: Apple Music support with source selection

Dependencies: Phase 4 (uses `Track.album` and `LyricsService`)

**Tasks**:
- [x] `LyricsCore/Track.swift`: add `public enum PlayerSource: String, CaseIterable { case spotify, music }` with `bundleID` (`com.spotify.client`, `com.apple.Music`). `Track` gets `source`, and its id is prefixed with the source.
- [x] `LyricsCore/PlayerSelection.swift`: add `SourcePreference` (`auto`, `spotify`, `music`) and `choose(preference:states:[PlayerSource: PlayerState(running, playing)], current:)`. A manual preference returns that source if it is running, otherwise nil. Auto keeps `current` if it is playing, else picks the first playing source (Spotify, then Music), else keeps `current` if running, else the first running source, else nil.
- [x] `LyricsOverlay/Players.swift`: add `protocol MediaPlayer { var source: PlayerSource { get }; func read() -> Result<PlaybackSnapshot?, PlayerError> }`, where `nil` means stopped. `SpotifyPlayer` is the existing script (duration ms → s). `MusicPlayer` uses `tell application id "com.apple.Music"` and returns `{persistent ID, name, artist, album, duration (s), player position, playing}`. Error -1728 (no readable current track, e.g. radio) maps to `noTrack`. Error -1743 maps to `automationDenied`. `isRunning` uses `NSRunningApplication.runningApplications(withBundleIdentifier:)`, and `read()` is never called when the player is not running.
- [x] `PlayerModel.swift`: on each poll, read every running player (in Auto mode) or only the preferred one, build the states, call `PlayerSelection.choose`, and use that snapshot. Log source switches (`player` category).
- [x] `StatusMessage`: `openPlayer` text becomes "Open Spotify or Music and play a song." (en/de). `automationDenied` names the source.
- [x] `SettingsView.swift`: add a PLAYBACK section with a `Source` picker (`@AppStorage("source")`, default `auto`)
- [x] `AppDelegate.swift`: add a `Source ▸` submenu with checkmarks for Auto / Spotify / Apple Music, bound to the same default
- [x] `build-app.sh`: change the usage description to "…from Spotify or Music…"
- [x] Checks: the `PlayerSelection` matrix (auto with both playing keeps current, auto switches when current pauses and the other plays, manual returns nil when not running, nothing running returns nil) and that Track ids differ across sources for the same raw id
- [x] README: Requirements, Features and the Automation paragraph mention Apple Music and the separate permission prompt per player. RELEASE_NOTES gets a new v0.2.0 section listing all features.

**Automated Verification**:
- [x] `swift build` succeeds
- [x] `swift run LyricsCoreChecks` passes, including the `PlayerSelection` checks
- [x] `bash build-app.sh && /usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' "Lyrics Overlay.app/Contents/Info.plist" | grep -q Music`

**Manual Verification**:
- [ ] With only Music running and playing, lyrics show after the Automation prompt is allowed. Quitting Music and opening Spotify switches over. With Spotify running and Music closed, Music is never launched.
- [ ] With both playing in Auto, the overlay stays on the current one. Pausing it switches to the other. Picking "Spotify" in the menu forces Spotify.

### Phase 6: Launch at login, auto-hide and persisted click-through

Dependencies: Phase 2 (L10n), Phase 5 (playing state from the selected player)

**Tasks**:
- [x] `LyricsCore/VisibilityPolicy.swift`: `shouldShow(userHidden:autoHide:playing:hasTrack:notPlayingSince: Date?, now:)` returns `!userHidden && (!autoHide || (hasTrack && playing) || notPlayingSince.map { now.timeIntervalSince($0) < 3 } ?? false)`. At launch, `notPlayingSince` starts as the launch time, so auto-hide also waits 3 s before hiding an idle overlay.
- [x] `AppDelegate.swift`: track `userHidden` (set by the hotkey or menu toggle, cleared when the user shows it again or reopens the app), observe `model` changes (Combine `objectWillChange` or a 0.8 s tick), and order the overlay in or out per the policy. `toggleVisibility` flips `userHidden`, and the menu title reflects the actual visibility.
- [x] `PlayerModel.swift`: publish `notPlayingSince: Date?`, set when playback stops or there's no track and cleared when playing
- [x] `AppDelegate.swift`: persist `clickThrough` under the `"clickThrough"` key (default false). Apply it at launch to `overlay.ignoresMouseEvents` and `clickItem.state`. `applicationShouldHandleReopen` also stores `false`.
- [x] `LyricsOverlay/LoginItem.swift`: `LoginItem.isEnabled` (`SMAppService.mainApp.status == .enabled`), `requiresApproval`, and `setEnabled(_:) throws` (register/unregister). Add `openSystemSettings()` → `SMAppService.openSystemSettingsLoginItems()`.
- [x] `SettingsView.swift`: add an "Auto-hide when nothing is playing" toggle (`@AppStorage("autoHide")`, default false) in PLAYBACK. Add a "Launch at login" toggle in GENERAL, backed by `LoginItem` with state refreshed `onAppear`. Show an inline warning plus an "Open System Settings…" button when approval is required, and the localized error text when `setEnabled` throws.
- [x] Size the settings window to its content (`NSHostingController` with `sizingOptions = .preferredContentSize`) instead of the fixed 420×510 size
- [x] L10n: add all new keys in en and de
- [x] Add `os.Logger` category `login` for failures
- [x] Checks: the `VisibilityPolicy` matrix (userHidden always hides, autoHide off always shows, autoHide shows while playing, still shows 2 s after stopping, hides 4 s after stopping, hides with no track after the grace period)
- [x] README: document launch at login (only from the bundled `.app`, moving the app after enabling may require re-enabling), auto-hide, and that click-through is remembered. RELEASE_NOTES v0.2.0 is completed.

**Automated Verification**:
- [x] `swift build` succeeds
- [x] `swift run LyricsCoreChecks` passes, including the `VisibilityPolicy` checks
- [x] `bash build-release.sh` succeeds and the CI run on `fork-improvements` is green

**Manual Verification**:
- [ ] With auto-hide on, pausing hides the overlay after about 3 s and resuming shows it. After hiding with ⌥⇧L, resuming playback does not show it.
- [ ] Click-through is still on after quitting and relaunching.
- [ ] Turning on "Launch at login" from the bundled app in `/Applications` adds it to Login Items, and it starts after logging out and back in.

## Implementation Notes

During implementation, document user feedback, problems, and decisions here.

- Phase 1: `build-release.sh` failed with the local Swift 6.4 toolchain: both `--triple` builds wrote to the same `.build/out` folder, and `lipo -verify_arch arm64 x86_64` now rejects two archs at once. Fixed with a per-arch `--scratch-path` and one `-verify_arch` call per arch (script and CI).
- Phase 2: the status menu is now rebuilt from scratch in `menuNeedsUpdate`, so `clickItem`/`visibilityItem` references are gone; state is read from `clickThrough` and `overlay.isVisible` on open.
- Phase 2: the settings-window "size to content" task (Phase 6) was done early, because the new sections clipped in the fixed 420×510 window.
- Phase 4: `/api/search` is called with title and artist only (as before); album and duration go only to `/api/get`. Searching wording changed to "Searching for lyrics…" / "No lyrics found" since plain lyrics now count.
- Phase 5: `StatusMessage` cases carry the `PlayerSource` (`automationDenied(source)`, `playerError(source, detail)`, `noTrack(source)`). German uses the app name "Musik". Both scripts also check `application id … is running` inside AppleScript, as a guard against the race where the app quits between the `NSRunningApplication` check and the script.
- Phase 6: a manual show (hotkey/menu/reopen) while auto-hidden counts as a fresh start of the 3 s grace period; otherwise the toggle would have no visible effect when nothing plays.

## References

- Upstream: https://github.com/JulianRudrich/LyricsOverlay
- LRCLIB API docs: https://lrclib.net/docs.md (`/api/get` requires `track_name`, `artist_name`; recommends `album_name`; `duration` 1–3600 s, ±2 s tolerance; 404 `TrackNotFound`; `/api/search` returns ≤ 20 results; clients must identify via User-Agent)
- Apple `SMAppService` (macOS 13+): https://developer.apple.com/documentation/servicemanagement/smappservice
- Current code: `Sources/LyricsOverlay/main.swift`, `Sources/LyricsCore/Lyrics.swift`, `Checks/main.swift`, `build-app.sh`, `build-release.sh`, `.github/workflows/ci.yml`
