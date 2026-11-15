---
date: 2026-11-14T23:35:27Z
git_commit: c84e76d
branch: fork-improvements
topic: "Spotify True Shuffle: honest, no-repeat shuffle written to a Spotify playlist"
tags: [plan, spotify, web-api, pkce, shuffle, lyrics-core, menu-panel, settings, localization]
status: ready
---

# PLAN: Spotify True Shuffle

Add a True Shuffle tool to Linory. The user connects their own Spotify developer app, picks Liked Songs or a playlist they own, and Linory writes an honestly shuffled order of the tracks not yet played this cycle to one reused "Linory Shuffle" playlist. Spotify then plays that playlist itself. No track repeats until every non-removed track of the source has played. Removed tracks stay removed. The current order can be kept as a separate playlist.

This is the first step toward making Linory a primary music companion. It deliberately stays within Spotify's Developer Policy: Linory adds a shuffle tool and never replaces Spotify's player or queue. The policy forbids products that "mimic, or replicate or attempt to replace a core user experience of Spotify". Apple Music is out of scope; the user does not use it.

## Acceptance Criteria

- In **Settings ▸ Spotify**, a user can paste their own Spotify Client ID, connect through a browser login (Authorization Code with PKCE, redirect `linory://callback`), and see "Connected as <display name>". The connection survives app restarts because the refresh token is stored in the Keychain. **Disconnect** removes the token.
- The **True Shuffle** section in the menu panel lists **Liked Songs** plus playlists the user owns or collaborates on (the only playlists whose items a development-mode app can read).
- **Shuffle & play** writes only this cycle's unplayed, non-removed tracks of the chosen source, in a fresh uniform random order, to one reused private **"Linory Shuffle"** playlist (at most 10,000 tracks). It then starts that playlist in the Spotify desktop app with Spotify's own shuffle and repeat turned off.
- A track counts as played as soon as it starts playing, skips included, but only while Spotify's playing context is the Linory Shuffle playlist.
- No track repeats until every non-removed track of the source has played. Then the cycle resets automatically on the next Shuffle & play. Tracks added to the source later join the cycle as unplayed.
- The menu shows **"<played> of <total> played"** and a **Reset** action that clears played tracks for the selected source.
- **Remove from shuffle** on the current track excludes it from that source in all future cycles, removes it from the Linory Shuffle playlist, and skips to the next track. **Restore removed (n)** brings all removed tracks of the source back.
- **Keep this shuffle** copies the current Linory Shuffle order, minus removed tracks, to a new private playlist named **"<source> · Shuffled <date>"**. Linory never edits that playlist again.
- Lyrics, the overlay, and Apple Music reading keep working as before. Linory works without a Spotify connection; the True Shuffle section then points to Settings.
- Every new UI string exists in English and German. `swift run LyricsCoreChecks` passes, including new checks for PKCE, response decoding and the shuffle cycle.

## Technical Key Decisions and Tradeoffs

1. **Spotify only, through a playlist tool, not a Linory-owned queue.**
   - Why: Spotify's Developer Policy bans replacing a core Spotify experience. Writing a shuffled playlist adds value that Spotify lacks; replacing its queue would not.
   - Impact: Spotify does all playback, which stays gapless, works on other devices, and continues if Linory quits. Linory never sequences tracks itself.
2. **Each user brings their own Spotify Client ID.**
   - Why: since March 9, 2026, a development-mode app allows only 5 allowlisted users, and its owner must have Premium. When each user owns their app, the cap never applies.
   - Impact: Settings needs a Client ID field and a short setup guide. Each user needs Spotify Premium. No Client ID ships in the repository.
3. **Login with Authorization Code + PKCE through `ASWebAuthenticationSession`, redirect `linory://callback`.**
   - Why: Spotify removed the implicit grant and requires PKCE for apps without a server. Custom-scheme redirects are still allowed, and `ASWebAuthenticationSession` receives the callback without registering a URL type in Info.plist.
   - Impact: uses the AuthenticationServices framework; no new package dependencies; no client secret.
4. **The refresh token lives in the Keychain, and the access token only in memory.**
   - Why: tokens are credentials and must not land in UserDefaults or logs.
   - Impact: a small Keychain wrapper using the Security framework. Spotify may rotate the refresh token on each refresh, so the newest one is always saved.
5. **Playback starts through AppleScript, not `PUT /me/player/play`.**
   - Why: Linory already has Automation permission for Spotify, and AppleScript avoids device-ID handling and "no active device" errors.
   - Impact: `Players.swift` gets its first write commands (Spotify only): set `shuffling` and `repeating` to false, `play track "spotify:playlist:<id>"`, and `next track`. Unlike reading, Shuffle & play may launch Spotify, because the user explicitly asked to play.
6. **Played tracks are detected from the existing 0.8 s poll, confirmed by one Web API call per track change.**
   - Why: AppleScript does not expose the playing context. `GET /me/player/currently-playing` returns `context.uri`, so a song played from another playlist does not count as played.
   - Impact: at most one extra request per track change, and only while a shuffle session is active.
7. **Shuffle rules are a pure `ShuffleCycle` model in LyricsCore, saved as JSON.**
   - Why: this follows the existing `LyricsCacheStore` pattern of pure logic plus app-side persistence, so `LyricsCoreChecks` can verify it.
   - Impact: state goes to `~/Library/Application Support/io.github.mikeleonfox.lyricsoverlay/shuffle-state.json`, keyed by source ID. Track identity is the Spotify track URI, which matches the AppleScript `id of current track`.
8. **Use the post-February-2026 Web API paths.**
   - Why: development-mode apps lost the old paths.
   - Impact: create with `POST /me/playlists`; read, replace, add and delete items with `GET|PUT|POST|DELETE /playlists/{id}/items`; read Liked Songs with `GET /me/tracks`; list playlists with `GET /me/playlists`. Write in batches of 100 URIs: the first `PUT` replaces, and further `POST`s append.
9. **Scopes:** `user-library-read playlist-read-private playlist-read-collaborative playlist-modify-private user-read-currently-playing`. All playlists Linory creates are private, so `playlist-modify-public` is not needed.

## Current State

```
 Linory (menu-bar app, LSUIElement)
 ┌──────────────────────────────────────────────────────────────────┐
 │ AppDelegate ── owns overlay NSPanel, MenuWindow, Settings NSWindow │
 │                                                                  │
 │ PlayerModel (ObservableObject) ── Timer 0.8 s ──► poll()          │
 │   track / lyrics / artwork / clock / status                      │
 │   update(snapshot) on track change → artwork + LyricsService     │
 │                         │                                        │
 │ Players.swift ◄─────────┘  SpotifyPlayer / MusicPlayer           │
 │   read-only NSAppleScript (id, name, artist, album, duration,    │
 │   position, playing). Never launches a player.                   │
 │                                                                  │
 │ MenuPanel (290 pt glass): now playing, overlay toggles,          │
 │   Position ›, Source ›, Settings…, Quit                          │
 │ SettingsView (700×480): General / Overlay / Timing / About       │
 │                                                                  │
 │ LyricsCore (pure): Track, PlayerSelection, PlaybackClock, LRC,   │
 │   LyricsCacheStore, L10n …  ── verified by Checks/main.swift     │
 └──────────────────────────────────────────────────────────────────┘
```

- `Sources/Linory/Players.swift:40-52`: `SpotifyPlayer.read()` returns the track `id`, which is the Spotify URI (`spotify:track:…`), as `Track.rawID`. `Track.id` is prefixed `spotify:`.
- `Sources/Linory/PlayerModel.swift:93-102`: `update(_:)` detects a track change. This is the hook for played tracking.
- `Sources/Linory/MenuPanel.swift:26,43-46`: `Section` enum and disclosure rows. True Shuffle becomes a third section.
- `Sources/Linory/SettingsView.swift:7`: `Pane` enum; a new `.spotify` pane is added.
- `Sources/Linory/LyricsService.swift:19-22`: the Application Support path pattern for JSON state.
- `Sources/LyricsCore/Localization.swift:13-33`: `L10nKey`. `checkLocalization()` in `Checks/main.swift` fails if any key lacks an English or German string.
- `build-app.sh:28`: `NSAppleEventsUsageDescription` says Linory only reads; it must mention starting playback.

## Desired End State

```
 Linory
 ┌────────────────────────────────────────────────────────────────────────┐
 │ AppDelegate ── creates ShuffleController, passes it to MenuPanel and    │
 │                SettingsView                                            │
 │                                                                        │
 │ SpotifyAuth ── PKCE via ASWebAuthenticationSession; Keychain refresh    │
 │   token; in-memory access token; auto refresh                          │
 │        │                                                               │
 │ SpotifyAPI ── me, playlists, saved tracks, playlist items (get/put/     │
 │   post/delete), create playlist, currently-playing context              │
 │        │                                                               │
 │ ShuffleController (ObservableObject, @MainActor)                        │
 │   sources, selected source, progress, busy/error state                 │
 │   shuffleAndPlay · reset · removeCurrent · restoreRemoved · keep        │
 │   trackChanged(uri) ◄── PlayerModel.update (Spotify tracks only)        │
 │        │                    │                                          │
 │   ShuffleStore (JSON)       SpotifyControl (AppleScript write cmds)    │
 │        │                                                               │
 │ LyricsCore: PKCE, SpotifyResponses (decoders), ShuffleCycle,           │
 │   ShuffleState — all checked in Checks/main.swift                      │
 └────────────────────────────────────────────────────────────────────────┘
          │ HTTPS (api.spotify.com, accounts.spotify.com)     │ AppleScript
          ▼                                                   ▼
   Spotify Web API  ── writes "Linory Shuffle" ──►  Spotify.app plays it
```

### UI mockups

Menu panel, connected (current panel plus a new section):

```
 ┌──────────────────────────────────┐
 │ [art] Song title                 │
 │       Artist                     │
 │ ──────────────────────────────── │
 │ ▢ Show overlay            (on)   │
 │ ▢ Click-through          (off)   │
 │ ⤢ Position                  ›    │
 │ ♫ Source                    ›    │
 │ ⤮ True Shuffle              ⌄    │
 │   [ Liked Songs           ▾ ]    │
 │   [   ⤮ Shuffle & play      ]    │
 │   124 of 812 played · Reset      │
 │   ⊖ Remove from shuffle          │  ← only while a shuffled Spotify track plays
 │   ⤓ Keep this shuffle            │  ← only when a Linory Shuffle exists
 │   ↺ Restore removed (3)          │  ← only when n > 0
 │ ──────────────────────────────── │
 │ ⚙ Settings…                ⌘,    │
 │ ⏻ Quit Linory               ⌘Q   │
 └──────────────────────────────────┘
```

Menu panel, not connected:

```
 │ ⤮ True Shuffle              ⌄    │
 │   Connect Spotify in Settings    │
 │   to use True Shuffle.  [Open ›] │
```

Busy and error states replace the progress line: `Shuffling 812 tracks…`, or a one-line localized error such as `Spotify login expired. Reconnect in Settings.`

Settings ▸ Spotify pane:

```
 ┌───────────┬──────────────────────────────────────────────────────┐
 │ Linory    │ Spotify                                              │
 │ v0.x      │ Connect your own Spotify app to use True Shuffle.    │
 │           │ ┌──────────────────────────────────────────────────┐ │
 │ General   │ │ Client ID     [ 3f9c…                         ]  │ │
 │ Overlay   │ │ Redirect URI  linory://callback          [Copy]  │ │
 │ Timing    │ ├──────────────────────────────────────────────────┤ │
 │ Spotify ◄ │ │ ● Connected as Mike            [ Disconnect ]    │ │
 │ About     │ └──────────────────────────────────────────────────┘ │
 │           │ ┌ How to get a Client ID ──────────────────────────┐ │
 │           │ │ 1. Open developer.spotify.com/dashboard          │ │
 │           │ │ 2. Create app, select "Web API"                  │ │
 │           │ │ 3. Add the redirect URI above, save              │ │
 │           │ │ 4. Copy the Client ID here, press Connect        │ │
 │           │ │ Requires Spotify Premium on your account.        │ │
 │           │ └──────────────────────────────────────────────────┘ │
 └───────────┴──────────────────────────────────────────────────────┘
```

When disconnected, the status row shows `○ Not connected  [ Connect Spotify ]`. The button is disabled while the Client ID is empty.

## Abstractions and Code Reuse

- `Sources/LyricsCore`
  - `SpotifyPKCE.swift` - new, pure.
    - `SpotifyPKCE.verifier(randomBytes:)` - base64url, no padding, 43–128 chars.
    - `SpotifyPKCE.challenge(for:)` - SHA-256 (CryptoKit), base64url.
    - `SpotifyPKCE.authorizeURL(clientID:redirectURI:scopes:state:challenge:)` - builds `https://accounts.spotify.com/authorize`.
    - `SpotifyPKCE.tokenRequestBody(...)` - form bodies for `authorization_code` and `refresh_token`.
  - `SpotifyResponses.swift` - new, pure `Decodable` types and helpers.
    - `SpotifyToken`, `SpotifyUser` (`id`, `display_name`), `SpotifyPlaylistPage` (`id`, `name`, `owner.id`, `collaborative`, `next`), `SpotifyTrackPage` (`next`, item URIs), `SpotifyCurrentlyPlaying` (`context?.uri`, `item?.uri`).
    - The track page decoder accepts both `item` (new) and `track` (old and `/me/tracks`) per entry, and skips local files (`is_local`), episodes (`type != "track"`) and null entries.
  - `ShuffleCycle.swift` - new, pure; mirrors `LyricsCacheStore`.
    - `ShuffleCycle` (Codable: `played: Set<String>`, `removed: Set<String>`, `total: Int`).
    - `nextOrder(from:using:)` - eligible = source deduped minus removed; prune `played` to eligible; if nothing unplayed, clear `played`; return unplayed shuffled with the given RNG, capped at `ShuffleCycle.maxTracks = 10_000`; set `total`.
    - `markPlayed(_:)`, `remove(_:)`, `restoreRemoved()`, `reset()`, `progress` (`played ∩ eligible` count, `total`).
    - `ShuffleState` (Codable): `cycles: [String: ShuffleCycle]` keyed by source ID (`liked` or the playlist ID), `shufflePlaylistID: String?`, `activeSourceID: String?`, `currentOrder: [String]`, `selectedSourceID: String?`.
  - `Localization.swift` - new `L10nKey` cases with English and German strings (listed in each phase).
- `Sources/Linory`
  - `Keychain.swift` - new: `Keychain.read/write/delete(account:)`, a generic password with service `LyricsService.subsystem`.
  - `SpotifyAuth.swift` - new `@MainActor final class SpotifyAuth: ObservableObject`. Publishes `state` (`.disconnected`, `.connecting`, `.connected(displayName)`, `.failed(message)`). Provides `connect(clientID:)`, `disconnect()`, and `validAccessToken() async throws -> String`, which refreshes when expired or within 60 s of expiry.
  - `SpotifyAPI.swift` - new `actor SpotifyAPI`: an authorized `request(...)`, with one retry after a refresh on 401 and a single wait honoring `Retry-After` on 429. Also typed calls: `me()`, `ownPlaylists()`, `likedTrackURIs()`, `playlistTrackURIs(id:)`, `createPlaylist(name:description:)`, `replaceItems(playlistID:uris:)` (PUT first 100, POST the rest), `removeItems(playlistID:uris:)`, `currentContextURI()`.
  - `Players.swift` - add `enum SpotifyControl` with `playPlaylist(id:)` (launches Spotify if needed, waits up to 10 s for it to run, sets `shuffling`/`repeating` false, plays) and `nextTrack()`. Reuses the AppleScript error mapping style of `MediaPlayer.run`.
  - `ShuffleController.swift` - new `@MainActor final class ShuffleController: ObservableObject`. It owns `ShuffleState` persistence (JSON next to the lyrics cache, written atomically) and the menu actions. `trackChanged(uri:)` is called by `PlayerModel`.
  - `PlayerModel.swift` - add `var onTrackChange: ((Track) -> Void)?`, called in `update(_:)` after `track` changes. No other behavior changes.
  - `MenuPanel.swift` - add `Section.shuffle`, a `shuffleSection` view, and observe `ShuffleController`. Reuse `MenuRow`, `disclosureRow` and `sectionTransition`.
  - `SettingsView.swift` - add `Pane.spotify` (icon `music.note.house`). Reuse `card`/`row`, with a `TextField` for the Client ID stored in `@AppStorage("spotifyClientID")`.
  - `AppDelegate.swift` - create `SpotifyAuth`, `SpotifyAPI` and `ShuffleController`; wire `PlayerModel.onTrackChange`; pass the controller to `MenuPanel` and `SettingsView`; "Open ›" reuses the existing `MenuActions.openSettings`.
- `build-app.sh` - update `NSAppleEventsUsageDescription`.
- `Checks/main.swift` - new `checkSpotifyPKCE()`, `checkSpotifyResponses()`, `checkShuffleCycle()`, all called before the success print.

## Logging & Observability

Use `Logger(subsystem: LyricsService.subsystem, category: "spotify")` and `category: "shuffle"`. Never log tokens, the code verifier, the authorization code or the Client ID.

```
spotify  connected as <public: display name>
spotify  token refreshed (expires in 3600 s)
spotify  request GET /me/tracks → 200 (page 3)
spotify  request PUT /playlists/<id>/items → 429, retry after 2 s
spotify  login failed: <public: localized error>
shuffle  source liked: 812 eligible, 688 unplayed, 3 removed → wrote 688 to <playlist id>
shuffle  cycle complete for liked, reset
shuffle  played spotify:track:… (context matches)
shuffle  ignored spotify:track:… (context spotify:playlist:other)
shuffle  removed spotify:track:… from liked
shuffle  kept 688 tracks as "Liked Songs · Shuffled 15 Nov"
```

## Implementation

### Phase 1: Connect Spotify

Dependencies: None

Users can enter their own Client ID, log in with PKCE, stay connected across restarts, and disconnect. Nothing shuffles yet.

**Tasks**:
- [x] `Sources/LyricsCore/SpotifyPKCE.swift`: implement `verifier`, `challenge`, `authorizeURL` (params `client_id`, `response_type=code`, `redirect_uri`, `code_challenge_method=S256`, `code_challenge`, `scope`, `state`), and `tokenRequestBody` for both grant types.
- [x] `Sources/LyricsCore/SpotifyResponses.swift`: add `SpotifyToken` (`access_token`, `expires_in`, `refresh_token?`) and `SpotifyUser`.
- [x] `Sources/Linory/Keychain.swift`: read/write/delete a generic password (`kSecClassGenericPassword`, service = subsystem, account `spotify-refresh-token`).
- [x] `Sources/Linory/SpotifyAuth.swift`:
  - `connect(clientID:)`: generate the verifier from `SecRandomCopyBytes` and a random `state`, start `ASWebAuthenticationSession(url:callbackURLScheme: "linory")` with a presentation anchor (the settings window, or a key window), verify `state`, exchange the code at `https://accounts.spotify.com/api/token`, store the refresh token, then load `GET /me` for the display name.
  - On launch, if a refresh token and a Client ID exist, refresh silently and set `.connected`. A failed refresh with `invalid_grant` deletes the token and sets `.disconnected`.
  - `disconnect()`: delete the Keychain item, clear the in-memory token, set `.disconnected`.
  - Changing the Client ID while connected disconnects.
- [x] `Sources/Linory/SpotifyAPI.swift`: base `request` with bearer token, a refresh-and-retry once on 401, `Retry-After` handling once on 429, and `HTTPError` for other non-2xx responses; plus `me()`.
- [x] `Sources/Linory/SettingsView.swift`: add `Pane.spotify` with the Client ID field, the read-only redirect URI with a Copy button (`NSPasteboard`), a connection status row with Connect/Disconnect, and the four-step guide card with the Premium note. Disable Connect when the Client ID is empty.
- [x] `Sources/Linory/AppDelegate.swift`: create `SpotifyAuth` at launch and inject it into `SettingsView`.
- [x] `Sources/LyricsCore/Localization.swift`: add keys with EN and DE strings: `sectionSpotify`, `spotifySubtitle`, `spotifyClientID`, `spotifyRedirectURI`, `spotifyCopy`, `spotifyConnect`, `spotifyDisconnect`, `spotifyConnected` (with `%@` name), `spotifyNotConnected`, `spotifyConnecting`, `spotifyGuideTitle`, `spotifyGuideStep1`…`spotifyGuideStep4`, `spotifyPremiumNote`, `spotifyLoginFailed` (with `%@`).
- [x] `Checks/main.swift`: add `checkSpotifyPKCE()`:
  - The RFC 7636 test vector: `challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"`.
  - The verifier from 32 fixed bytes is 43 chars of `[A-Za-z0-9-_]`.
  - The authorize URL contains every required parameter, percent-encoded, with `scope` space-separated.
  - The token bodies contain `grant_type`, `client_id`, and `code_verifier` or `refresh_token`.
  - `SpotifyToken` decodes with and without `refresh_token`.
- [x] `docs/USAGE.md`: add a "Connect Spotify (optional)" section covering the four steps, the Premium requirement, the 5-user development-mode note (each user uses their own app), and how to disconnect.
- [x] `docs/PRIVACY.md`: explain that with Spotify connected, Linory talks to `accounts.spotify.com` and `api.spotify.com` with the user's own Client ID; the refresh token is stored in the macOS Keychain; the Client ID is in macOS preferences; and Disconnect removes the token.

**Automated Verification**:
- [x] `swift build` succeeds.
- [x] `swift run LyricsCoreChecks` prints `LyricsCore checks passed`, including `checkSpotifyPKCE()` and the new localization keys.
- [x] `bash build-app.sh` produces and verifies `~/Applications/Linory.app`.

**Manual Verification**:
- [ ] With a fresh Spotify developer app whose redirect URI is `linory://callback`, paste the Client ID, press Connect, log in in the browser sheet, and Settings shows "Connected as <name>".
- [ ] After quitting and reopening Linory, it is still connected with no browser prompt.
- [ ] Disconnect shows "Not connected", and the Keychain item `io.github.mikeleonfox.lyricsoverlay` / `spotify-refresh-token` is gone (Keychain Access).
- [ ] Cancelling the browser sheet returns to "Not connected" without an error dialog.
- [ ] Lyrics and the overlay still work for Spotify and Music, whether connected or not.

### Phase 2: True Shuffle and play

Dependencies: Phase 1

Users pick a source, press Shuffle & play, and Spotify plays an honest no-repeat order. Progress and Reset work.

**Tasks**:
- [x] `Sources/LyricsCore/SpotifyResponses.swift`: add `SpotifyPlaylistPage`, `SpotifyTrackPage` (decoding both the `item` and `track` keys; skipping local files, episodes and nulls), `SpotifyCurrentlyPlaying`, and `SpotifyPlaylistSummary` filtering (`owner.id == user.id || collaborative`).
- [x] `Sources/LyricsCore/ShuffleCycle.swift`: implement `ShuffleCycle` and `ShuffleState` as described in Abstractions. `nextOrder` takes `inout some RandomNumberGenerator` so checks can use a seeded generator.
- [x] `Sources/Linory/SpotifyAPI.swift`:
  - `ownPlaylists()`: paginate `GET /me/playlists?limit=50` and filter.
  - `likedTrackURIs()`: paginate `GET /me/tracks?limit=50`.
  - `playlistTrackURIs(id:)`: paginate `GET /playlists/{id}/items?limit=50`.
  - `createPlaylist(name:description:)`: `POST /me/playlists` with `public: false`.
  - `replaceItems(playlistID:uris:)`: `PUT` the first 100 to `/playlists/{id}/items`, then `POST` the remaining URIs in batches of 100. An empty list sends `PUT` with `uris: []`.
  - `currentContextURI()`: `GET /me/player/currently-playing`; a 204 response returns nil.
- [x] `Sources/Linory/Players.swift`: add `SpotifyControl.playPlaylist(id:)`. If Spotify is not running, call `NSWorkspace.shared.openApplication` and poll `isRunning` for up to 10 s. Then run `set shuffling to false`, `set repeating to false`, and `play track "spotify:playlist:<id>"`. Map error -1743 to `StatusMessage.automationDenied(.spotify)`.
- [x] `Sources/Linory/ShuffleController.swift`:
  - Load and save `ShuffleState` at `…/io.github.mikeleonfox.lyricsoverlay/shuffle-state.json` (atomic write).
  - Publish `sources: [ShuffleSource]` (Liked Songs first, then playlists by name), `selectedSourceID`, `progress`, `isBusy`, `errorMessage`.
  - `refreshSources()` runs when the section expands and on connect.
  - `shuffleAndPlay()`:
    - Fetch the source URIs and compute `nextOrder`.
    - Ensure the "Linory Shuffle" playlist exists. Reuse the stored ID; if a write returns 404, create the playlist again.
    - `replaceItems`, then store `currentOrder`, `activeSourceID` and the state, then call `SpotifyControl.playPlaylist`.
    - A source with zero eligible tracks shows `shuffleEmpty` and writes nothing.
  - `reset()`: `cycle.reset()` for the selected source, then save.
  - `trackChanged(uri:)`: if `activeSourceID` is set and the URI is in `currentOrder`, call `currentContextURI()`. If it equals `spotify:playlist:<shufflePlaylistID>`, call `markPlayed`, save, and update progress. Otherwise log `ignored`.
- [x] `Sources/Linory/PlayerModel.swift`: add `onTrackChange` and call it in `update(_:)` after `track = snapshot.track`.
- [x] `Sources/LyricsCore/Track.swift`: add `public let rawID: String`, stored in `init`, so the Spotify URI (the AppleScript id, e.g. `spotify:track:…`) is not re-derived by string slicing.
- [x] `Sources/Linory/AppDelegate.swift`: create `SpotifyAPI` and `ShuffleController`. Set `model.onTrackChange = { track in if track.source == .spotify { controller.trackChanged(uri: track.rawID) } }`. Pass the controller to `MenuPanel`.
- [x] `Sources/Linory/MenuPanel.swift`: add `Section.shuffle` and the `shuffleSection` view per the mockup: a source `Picker` (menu style), a Shuffle & play button with a busy spinner, a progress line with Reset, the not-connected state with "Open ›" calling `actions.openSettings`, and a one-line error.
- [x] `build-app.sh`: change `NSAppleEventsUsageDescription` to "Linory reads the current track from Spotify or Music to show synchronized lyrics, and starts your True Shuffle playlist in Spotify."
- [x] `Sources/LyricsCore/Localization.swift`: add EN and DE strings for `trueShuffle`, `shuffleSourceLiked` ("Liked Songs"), `shufflePlay`, `shuffleProgress` (`%d of %d played`), `shuffleReset`, `shuffleBusy` (`Shuffling %d tracks…`), `shuffleEmpty`, `shuffleConnectHint`, `shuffleOpenSettings`, `shufflePlaylistName` ("Linory Shuffle"), `shufflePlaylistDescription`, `shuffleErrorAuth`, `shuffleErrorNetwork`, `shuffleErrorAutomation`, and `shuffleErrorPremium` (a 403 from the API).
- [x] `Checks/main.swift`: add `checkSpotifyResponses()`:
  - A playlist-items page with an `item` key, a `/me/tracks` page with a `track` key, a local file, an episode and a null entry decode to only the track URIs, in order.
  - The playlist filter keeps owned and collaborative playlists only.
  - `currently-playing` decodes `context.uri`, and also a null context.
- [x] `Checks/main.swift`: add `checkShuffleCycle()` using a seeded `SplitMix64` generator defined in the checks file:
  - The first order is a permutation of the eligible tracks, with no duplicates even if the source has duplicates.
  - After `markPlayed` of k tracks, `nextOrder` contains only the others.
  - When all tracks are played, `nextOrder` returns every eligible track again, and `played` is empty before marking.
  - A track added to the source later appears in the next order while the cycle continues.
  - Tracks removed from the source are pruned from `played`, and the progress total follows the source.
  - `reset()` clears `played` but not `removed`.
  - The cap: 10,050 eligible tracks yield 10,000, and the other 50 stay unplayed.
  - Two different seeds give different orders, and the same seed gives the same order.
  - A `ShuffleState` JSON round trip is lossless.
- [x] `docs/USAGE.md`: add a "True Shuffle" section covering sources (Liked Songs and owned or collaborative playlists only, plus why Spotify-made playlists are missing), what counts as played, automatic cycle reset, Reset, that the "Linory Shuffle" playlist is overwritten each time, and that Shuffle & play may open Spotify. Update the Requirements line saying a player is never launched: reading never launches one; Shuffle & play does.
- [x] `docs/PRIVACY.md`: add `shuffle-state.json` (track URIs of played and removed tracks per source, the ID of the Linory Shuffle playlist) and how to clear it, and say that Linory asks Spotify for the playing context once per track change during a shuffle.
- [x] `docs/DEVELOPMENT.md`: extend the checks list with PKCE, Spotify response decoding and shuffle cycles, and add True Shuffle to the end-to-end checklist.
- [x] `README.md`: add one short feature paragraph, **True Shuffle**, under the existing feature paragraphs, noting it is optional and needs Spotify Premium and your own Spotify app.

**Automated Verification**:
- [x] `swift build` succeeds.
- [x] `swift run LyricsCoreChecks` passes, including `checkSpotifyResponses()` and `checkShuffleCycle()`.
- [x] `bash build-app.sh` succeeds, and `plutil -extract NSAppleEventsUsageDescription raw ~/Applications/Linory.app/Contents/Info.plist` contains "True Shuffle".

**Manual Verification**:
- [ ] When connected, the True Shuffle section lists Liked Songs and your own playlists. Spotify-made playlists are absent.
- [ ] Shuffle & play creates exactly one private "Linory Shuffle" playlist in Spotify, fills it, and starts it with Spotify's shuffle and repeat off. Pressing it again reuses the same playlist.
- [ ] Skipping through 5 tracks raises the progress by 5. Playing a song from another playlist does not change the progress.
- [ ] After a new Shuffle & play, none of the already played tracks appear in the playlist.
- [ ] Reset sets the progress to 0 of total.
- [ ] Deleting the "Linory Shuffle" playlist in Spotify, then pressing Shuffle & play, recreates it without an error.
- [ ] When disconnected, the section shows the connect hint, and "Open ›" opens Settings.

### Phase 3: Remove, restore and keep

Dependencies: Phase 2

Users can drop the current track for good, bring removed tracks back, and keep a shuffled order as its own playlist.

**Tasks**:
- [x] `Sources/Linory/SpotifyAPI.swift`: add `removeItems(playlistID:uris:)` using `DELETE /playlists/{id}/items` with the body `{"items":[{"uri":…}]}`.
- [x] `Sources/Linory/Players.swift`: add `SpotifyControl.nextTrack()` (`next track`).
- [x] `Sources/Linory/ShuffleController.swift`:
  - `canRemoveCurrent`: true when the current track is Spotify, is in `currentOrder`, and the last context check for it matched the Linory Shuffle playlist. `trackChanged(uri:)` stores that result as `currentInShuffle`.
  - `removeCurrent()`: `cycle.remove(uri)`, remove the URI from `currentOrder`, save, `removeItems`, then `SpotifyControl.nextTrack()`. If the API call fails, the local removal is still kept and the error line explains the failure.
  - `restoreRemoved()`: `cycle.restoreRemoved()` for the selected source, then save. Restored tracks join the next Shuffle & play as unplayed.
  - `keepShuffle()`: create a private playlist named `"<source name> · Shuffled <date>"` (date via `DateFormatter` with the `dMMM` template in the app language), then `replaceItems` with `currentOrder` minus removed. Show the result in the status line (`shuffleKept`).
- [x] `Sources/Linory/MenuPanel.swift`: add the Remove from shuffle, Keep this shuffle and Restore removed (n) rows with the visibility rules from the mockup. Keep, Remove and Restore show the busy state while running.
- [x] `Sources/LyricsCore/Localization.swift`: add EN and DE strings for `shuffleRemove`, `shuffleRestore` (`Restore removed (%d)`), `shuffleKeep`, `shuffleKeptName` (`%@ · Shuffled %@`), and `shuffleKept` (`Saved as "%@"`).
- [x] `Checks/main.swift`: extend `checkShuffleCycle()`:
  - A removed track never appears in any later `nextOrder`, including after the cycle completes.
  - Removing a played track lowers both played and total.
  - `restoreRemoved()` makes those tracks eligible and unplayed.
  - Removal survives `reset()` and the JSON round trip.
- [x] `docs/USAGE.md`: document Remove from shuffle (permanent per source until restored), Restore removed, and Keep this shuffle (a separate playlist Linory never edits).

**Automated Verification**:
- [x] `swift build` succeeds.
- [x] `swift run LyricsCoreChecks` passes, including the extended `checkShuffleCycle()`.
- [x] `bash build-app.sh` succeeds.

**Manual Verification**:
- [ ] During a shuffle, Remove from shuffle skips to the next track, and the removed song disappears from "Linory Shuffle" in Spotify.
- [ ] After Reset and a new Shuffle & play, the removed song is still absent. "Restore removed (1)" brings it back in the next shuffle.
- [ ] Keep this shuffle creates "Liked Songs · Shuffled <date>" with the same order. A later Shuffle & play does not change it.
- [ ] The Remove row is hidden when playing a song outside the shuffle.

## Implementation Notes

During implementation, document user feedback, problems, and decisions here.

- **Context check:** `SpotifyAPI.currentlyPlaying()` replaces `currentContextURI()` and returns both `context.uri` and `item.uri`. The Web API can trail AppleScript after a track change, so `trackChanged` retries up to 3 times (1.5 s apart) until the item matches; otherwise the track is not counted.
- **Deleted Linory Shuffle:** deleting a playlist in Spotify only unfollows it, and the owner can still write to it, so a 404 never arrives. Shuffle & play therefore reuses the stored ID only while it appears in `GET /me/playlists`, and recreates the playlist otherwise. The 404 fallback stays.
- **Linory Shuffle is hidden** from the source list.
- **Paging:** after the first page, track pages load 4 at a time (offset paging), so 10,000 liked songs take about 50 rounds instead of 200.
- **Remove from shuffle** skips to the next track first, then deletes the item from the playlist, so the skip feels instant.
- **Names:** the playlist filter is `SpotifyPlaylist.readable(_:userID:)`. Extra keys: `shuffleLoading`, `shuffleErrorHTTP` (`%ld`), `shuffleErrorPlayback` (`%@`). Counts use `%ld`.
- **Isolation:** `AppDelegate` is not `@MainActor`, so `SpotifyAuth` has a `nonisolated init()`. `ShuffleController` is created in `applicationDidFinishLaunching`.
- **Login at launch without network:** the stored login is kept (state `.failed`) and retried when the True Shuffle section expands.
- **Menu sizing:** `MenuPanel` takes `measuring: Bool`; measuring renders every optional shuffle row, so the fixed-size menu window fits the tallest state. `MenuWindow` no longer closes when a click lands in a menu window (the source picker's pop-up).
- **User feedback, playback (overrides Decision 5):** the first test failed. Spotify showed "Couldn't find that playlist" because the desktop app had not yet synced the just-created playlist when AppleScript asked it to play. Shuffle & play now starts playback through the Web API (`PUT /me/player/play` with `context_uri`, then shuffle off and repeat off) on the device chosen by `SpotifyDevice.preferred`: this Mac's Spotify first, otherwise an already playing device, never an idle speaker. Spotify's servers resolve the playlist at once, which also avoids playing a stale cached order after a rewrite. New scopes: `user-read-playback-state` and `user-modify-playback-state`. Logins without them get a Reconnect hint in Settings and fall back to AppleScript. AppleScript still launches Spotify and is the fallback when no device is found.
- **Paste:** the app had no main menu, so ⌘V did nothing in the Client ID field. A hidden Edit menu now provides the standard shortcuts.
- **Keychain with ad-hoc signing:** every `build-app.sh` run changes the code signature, so macOS may ask once per rebuild to allow Linory to read its Keychain item. Choose "Always Allow".

## References

- Brainstorm decisions in this session: Spotify only; approach B (playlist tool); own Client ID per user; UI in the menu panel plus a Settings pane; played as soon as a track starts; keep "Keep this shuffle".
- [Spotify Developer Policy](https://developer.spotify.com/policy/): bans replicating or replacing a core Spotify experience; "Streaming" includes controlling a background Spotify app.
- [TechCrunch, Feb 6 2026: development-mode changes](https://techcrunch.com/2026/02/06/spotify-changes-developer-mode-api-to-require-premium-accounts-limits-test-users/): 5 allowlisted users per app, Premium required for the owner.
- [Spotify February 2026 Web API migration guide](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide): `/me/playlists`, `/playlists/{id}/items`, `item` field rename, item reads limited to owned or collaborative playlists.
- [Spotify OAuth migration reminder (Nov 27 2025)](https://developer.spotify.com/blog/2025-10-14-reminder-oauth-migration-27-nov-2025): implicit grant removed, PKCE required, custom-scheme redirect allowed.
- RFC 7636 Appendix B: PKCE S256 test vector.
- User complaints that motivated this ([Android Authority: 72-song repeat](https://www.androidauthority.com/spotify-shuffle-repeating-song-queue-3708815/), [Spotify Community queue/shuffle thread](https://community.spotify.com/t5/iOS-iPhone-iPad/Several-issues-with-queue-and-shuffling/td-p/6138664)).
- Code: `Sources/Linory/Players.swift`, `Sources/Linory/PlayerModel.swift`, `Sources/Linory/MenuPanel.swift`, `Sources/Linory/SettingsView.swift`, `Sources/LyricsCore/LyricsCacheModel.swift`, `Checks/main.swift`, `build-app.sh`.
