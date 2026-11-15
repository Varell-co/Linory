import Foundation
import CoreGraphics
import LyricsCore

/// Agent A: chorus detection, seek targets, sync clock.
func checkMiniPlayer() throws {
}

func checkParsing() {
    let lines = LRC.parse("[00:03.50] Second\n[00:01.00] First\n[00:07.00][00:09.10] Again\n[00:12.0] \n[00:65.00] Invalid")
    precondition(lines.map(\.time) == [1, 3.5, 7, 9.1, 12])
    precondition(lines.map(\.text) == ["First", "Second", "Again", "Again", ""])
    precondition(LRC.currentIndex(lines, at: 0.99) == nil)
    precondition(LRC.currentIndex(lines, at: 1) == 0)
    precondition(LRC.currentIndex(lines, at: 8) == 2)
    precondition(LRC.currentIndex(lines, at: 12) == 4)
    let enhanced = LRC.parse("[00:01.00][00:31.00] <00:01.00> Made <00:01.40> up  <00:02.00>line")
    precondition(enhanced.map(\.text) == ["Made up line", "Made up line"], "word timestamps are stripped from text")
    precondition(zip(enhanced[0].words?.map(\.offset) ?? [], [0, 0.4, 1.0]).allSatisfy { abs($0 - $1) < 0.001 } && enhanced[0].words?.count == 3, "word times are relative to the line")
    precondition(enhanced[1].words == enhanced[0].words, "repeated line keeps word timing")
}

func checkMatching() throws {
    let json = """
    [
      {"trackName":"Song","artistName":"Artist","duration":200,"syncedLyrics":null},
      {"trackName":"Song","artistName":"Someone else","duration":200,"syncedLyrics":"[00:01.00] Wrong"},
      {"trackName":"Song (Live)","artistName":"Artist","duration":200,"syncedLyrics":"[00:01.00] Wrong"},
      {"trackName":"Song","artistName":"Artist","duration":250,"syncedLyrics":"[00:01.00] Wrong"},
      {"trackName":"Song","artistName":"Artist","duration":201,"syncedLyrics":"[00:01.00] Right"}
    ]
    """
    let results = try JSONDecoder().decode([LyricsResult].self, from: Data(json.utf8))
    precondition(LyricsMatching.best(results, title: "SONG", artist: "Artist", duration: 200)?.syncedLyrics == "[00:01.00] Right")
    precondition(LyricsMatching.best(results, title: "Other", artist: "Artist", duration: 200) == nil)
}

func checkLocalization() {
    for language in [AppLanguage.en, .de] {
        for key in L10nKey.allCases {
            let value = L10n.raw(key, language: language) ?? ""
            precondition(!value.isEmpty, "Missing \(language.rawValue) translation for \(key.rawValue)")
        }
    }
    precondition(AppLanguage.system.resolved(preferredLanguages: ["de-DE"]) == .de)
    precondition(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "de-DE"]) == .en)
    precondition(AppLanguage.system.resolved(preferredLanguages: []) == .en)
    precondition(AppLanguage.de.resolved(preferredLanguages: ["en-US"]) == .de)
    for language in [AppLanguage.en, .de] {
        let text = StatusMessage.playerError(.music, "detail-x").text(language: language)
        precondition(text.contains("detail-x") && text.contains(PlayerSource.music.name(language: language)))
    }
    precondition(StatusMessage.noLyrics.text(language: .de) != StatusMessage.noLyrics.text(language: .en))
}

func checkPlaybackClock() {
    let t0 = Date(timeIntervalSince1970: 1_000)
    var clock = PlaybackClock()
    clock.update(position: 10, playing: true, duration: 100, at: t0)
    precondition(abs(clock.position(at: t0.addingTimeInterval(0.5)) - 10.5) < 0.001, "advances while playing")
    precondition(clock.position(at: t0.addingTimeInterval(200)) == 100, "clamps to duration")

    var jitter = clock
    jitter.update(position: 10.6, playing: true, duration: 100, at: t0.addingTimeInterval(0.8)) // predicted 10.8
    precondition(abs(jitter.position(at: t0.addingTimeInterval(0.8)) - 10.8) < 0.001, "0.2 s behind is ignored")

    var seekBack = clock
    seekBack.update(position: 8.8, playing: true, duration: 100, at: t0.addingTimeInterval(0.8))
    precondition(abs(seekBack.position(at: t0.addingTimeInterval(0.8)) - 8.8) < 0.001, "2 s behind re-anchors")

    var ahead = clock
    ahead.update(position: 11.0, playing: true, duration: 100, at: t0.addingTimeInterval(0.8))
    precondition(abs(ahead.position(at: t0.addingTimeInterval(0.8)) - 11.0) < 0.001, "ahead re-anchors")

    var paused = clock
    paused.update(position: 12, playing: false, duration: 100, at: t0.addingTimeInterval(2))
    precondition(paused.position(at: t0.addingTimeInterval(60)) == 12, "paused clock is frozen")

    clock.reset()
    precondition(clock.position(at: t0) == 0 && !clock.playing, "reset zeroes the clock")
}

func decode(_ json: String) throws -> [LyricsResult] { try JSONDecoder().decode([LyricsResult].self, from: Data(json.utf8)) }

func checkBestAny() throws {
    let both = try decode("""
    [
      {"trackName":"Song","artistName":"Artist","duration":200,"plainLyrics":"Plain line","syncedLyrics":null},
      {"trackName":"Song","artistName":"Artist","duration":200,"plainLyrics":"Plain line","syncedLyrics":"[00:01.00] Synced line"}
    ]
    """)
    precondition(LyricsMatching.bestAny(both, title: "Song", artist: "Artist", duration: 200)?.syncedLyrics != nil, "prefers synced")
    let plainOnly = try decode("""
    [
      {"trackName":"Song","artistName":"Artist","duration":203,"plainLyrics":"Plain line","syncedLyrics":null},
      {"trackName":"Song","artistName":"Someone else","duration":200,"plainLyrics":"Wrong","syncedLyrics":"[00:01.00] Wrong"},
      {"trackName":"Song","artistName":"Artist","duration":206,"plainLyrics":"Too far","syncedLyrics":"[00:01.00] Too far"}
    ]
    """)
    precondition(LyricsMatching.bestAny(plainOnly, title: "Song", artist: "Artist", duration: 200)?.plainLyrics == "Plain line", "falls back to plain")
    precondition(LyricsMatching.bestAny(plainOnly, title: "Song", artist: "Other", duration: 200) == nil, "rejects wrong artist")
    precondition(LyricsMatching.bestAny(plainOnly, title: "Song", artist: "Artist", duration: 230) == nil, "rejects duration off by > 5 s")
    let instrumental = try decode(#"[{"trackName":"Song","artistName":"Artist","duration":200,"instrumental":true}]"#)
    let match = LyricsMatching.bestAny(instrumental, title: "Song", artist: "Artist", duration: 200)
    precondition(match.flatMap { LoadedLyrics.make(from: $0, duration: 200) }?.instrumental == true, "instrumental match")
}

func checkGetResponse() throws {
    // Shape of an LRCLIB /api/get response; lyrics text is invented.
    let json = #"""
    {"id":1,"name":"Song","trackName":"Song","artistName":"Artist","albumName":"Album","duration":180.0,"instrumental":false,
     "plainLyrics":"Made up line one\nMade up line two","syncedLyrics":"[00:01.00] Made up line one\n[00:04.00] Made up line two"}
    """#
    let result = try JSONDecoder().decode(LyricsResult.self, from: Data(json.utf8))
    precondition(result.albumName == "Album" && result.instrumental == false && result.plainLyrics?.isEmpty == false)
    let loaded = LoadedLyrics.make(from: result, duration: 180)
    precondition(loaded?.synced == true && loaded?.lines.count == 2)
}

func checkPlainEstimate() {
    let lines = PlainLyrics.estimate(text: "One\n\n  Two  \nThree\nFour\n", duration: 200)
    precondition(lines.map(\.text) == ["One", "Two", "Three", "Four"], "drops blank lines and trims")
    let lead = min(10, 200 * 0.05)
    precondition(lines.first!.time == lead && lines.last!.time < 200 * 0.95, "inside bounds")
    let gaps = zip(lines.dropFirst(), lines).map { $0.time - $1.time }
    precondition(gaps.allSatisfy { $0 > 0 && abs($0 - gaps[0]) < 0.0001 }, "evenly spaced and increasing")
    precondition(PlainLyrics.estimate(text: " \n ", duration: 200).isEmpty)
    precondition(PlainLyrics.estimate(text: "One", duration: 0).isEmpty)
}

func checkCache() {
    precondition(LyricsCacheKey.make(title: "Café Song", artist: "ARTIST", duration: 200.4) == LyricsCacheKey.make(title: "cafe song", artist: "artist", duration: 199.6))
    let t0 = Date(timeIntervalSince1970: 0)
    let day: TimeInterval = 24 * 60 * 60
    let found = LoadedLyrics(lines: [LyricLine(time: 1, text: "x")], synced: true, instrumental: false)
    var store = LyricsCacheStore()
    store.insert(LyricsCacheEntry(lyrics: nil, fetchedAt: t0), for: "missing")
    store.insert(LyricsCacheEntry(lyrics: found, fetchedAt: t0), for: "found")
    precondition(store.lookup("missing", now: t0.addingTimeInterval(6 * day)) != nil, "not-found valid for 7 days")
    precondition(store.lookup("missing", now: t0.addingTimeInterval(7 * day)) == nil, "not-found expires")
    precondition(store.lookup("found", now: t0.addingTimeInterval(365 * day))?.lyrics == found, "found never expires")

    var full = LyricsCacheStore()
    for i in 0...LyricsCacheStore.capacity { // 501 entries
        full.insert(LyricsCacheEntry(lyrics: found, fetchedAt: t0.addingTimeInterval(Double(i))), for: "k\(i)")
    }
    precondition(full.entries.count == LyricsCacheStore.capacity && full.entries["k0"] == nil && full.entries["k1"] != nil, "evicts the oldest")
}

func checkPlayerSelection() {
    let playing = PlayerState(running: true, playing: true)
    let paused = PlayerState(running: true, playing: false)
    let both: [PlayerSource: PlayerState] = [.spotify: playing, .music: playing]
    precondition(PlayerSelection.choose(preference: .auto, states: both, current: .music) == .music, "auto keeps current while both play")
    precondition(PlayerSelection.choose(preference: .auto, states: both, current: nil) == .spotify, "auto prefers Spotify first")
    precondition(PlayerSelection.choose(preference: .auto, states: [.spotify: playing, .music: paused], current: .music) == .spotify, "auto switches when current pauses")
    precondition(PlayerSelection.choose(preference: .auto, states: [.spotify: paused, .music: paused], current: .music) == .music, "auto keeps paused current")
    precondition(PlayerSelection.choose(preference: .auto, states: [.music: paused], current: nil) == .music, "auto picks the running one")
    precondition(PlayerSelection.choose(preference: .spotify, states: [.music: playing], current: .music) == nil, "manual: nil when not running")
    precondition(PlayerSelection.choose(preference: .music, states: [.spotify: playing, .music: paused], current: .spotify) == .music, "manual forces source")
    precondition(PlayerSelection.choose(preference: .auto, states: [:], current: .spotify) == nil, "nothing running")
    let a = Track(source: .spotify, rawID: "42", title: "T", artist: "A", duration: 1)
    let b = Track(source: .music, rawID: "42", title: "T", artist: "A", duration: 1)
    precondition(a.id != b.id, "track ids differ across sources")
}

func checkVisibilityPolicy() {
    let now = Date(timeIntervalSince1970: 100)
    func show(userHidden: Bool = false, autoHide: Bool = true, playing: Bool = false, hasTrack: Bool = true, stoppedAgo: Double?) -> Bool {
        VisibilityPolicy.shouldShow(userHidden: userHidden, autoHide: autoHide, playing: playing, hasTrack: hasTrack,
                                    notPlayingSince: stoppedAgo.map { now.addingTimeInterval(-$0) }, now: now)
    }
    precondition(!show(userHidden: true, autoHide: false, playing: true, stoppedAgo: nil), "userHidden always hides")
    precondition(!show(userHidden: true, playing: true, stoppedAgo: nil), "userHidden wins over auto-show")
    precondition(show(autoHide: false, stoppedAgo: 100), "auto-hide off always shows")
    precondition(show(playing: true, stoppedAgo: nil), "shows while playing")
    precondition(show(stoppedAgo: 2), "still shows 2 s after stopping")
    precondition(!show(stoppedAgo: 4), "hides 4 s after stopping")
    precondition(!show(hasTrack: false, stoppedAgo: 4), "hides with no track after grace")
    precondition(!show(playing: true, hasTrack: false, stoppedAgo: 4), "playing without a track is not playing")
}

func checkWordHighlight() {
    let line = LyricLine(time: 10, text: "made up words here")
    let before = WordHighlight.units(for: line, nextTime: 14, at: 9)
    precondition(before.count == 4 && before.allSatisfy { $0.fill == 0 }, "nothing filled before the line")
    let middle = WordHighlight.units(for: line, nextTime: 14, at: 10.6).map(\.fill)
    precondition(middle.first == 1 && middle.last == 0 && zip(middle, middle.dropFirst()).allSatisfy { $0 >= $1 }, "fills left to right")
    precondition(WordHighlight.units(for: line, nextTime: 14, at: 13.9).allSatisfy { $0.fill == 1 }, "done before next line")
    precondition(WordHighlight.units(for: line, nextTime: 10.5, at: 10.46).allSatisfy { $0.fill == 1 }, "short gap: done within 90 %")

    let timed = LRC.parse("[00:10.00] <00:10.00> one <00:11.00> two")[0]
    let exact = WordHighlight.units(for: timed, nextTime: 20, at: 10.5)
    precondition(exact.map(\.text) == ["one", "two"] && exact[0].fill > 0 && exact[0].fill < 1 && exact[1].fill == 0, "uses exact word times")
    precondition(WordHighlight.units(for: LyricLine(time: 1, text: ""), nextTime: 2, at: 1.5).isEmpty)
}

func checkOverlayLayout() {
    let preferred = CGSize(width: 400, height: 240)
    let external = CGRect(x: 0, y: 52, width: 5120, height: 1358)
    let retina = CGRect(x: 5120, y: 0, width: 1728, height: 1085)
    let start = CGRect(x: 100.3, y: 200.3, width: 400, height: 240)
    let standard = OverlayLayout.frame(preferredSize: preferred, currentFrame: start, visibleFrame: external, backingScale: 1)
    let moved = CGRect(x: 5200.3, y: 200.3, width: 400, height: 240)
    let highDensity = OverlayLayout.frame(preferredSize: preferred, currentFrame: moved, visibleFrame: retina, backingScale: 2)
    precondition(standard.size == preferred && highDensity.size == preferred, "Retina preserves readable point dimensions")
    precondition(highDensity.width * 2 == 800, "Retina renders twice as many physical pixels")
    precondition(standard.minX == 100 && highDensity.minX == 5200.5, "frames align to physical pixels")

    let small = CGRect(x: -320, y: -220, width: 320, height: 220)
    let fitted = OverlayLayout.frame(preferredSize: preferred, currentFrame: start, visibleFrame: small, backingScale: 1)
    precondition(fitted == small.insetBy(dx: 16, dy: 16), "small screens shrink and relocate the overlay, including negative coordinates")
    let restored = OverlayLayout.frame(preferredSize: preferred, currentFrame: fitted, visibleFrame: external, backingScale: 1)
    precondition(restored.size == preferred && external.contains(restored), "returning to a larger screen restores the preferred size")

    let snapped = CGRect(x: external.maxX - 416, y: external.maxY - 256, width: 400, height: 240)
    let enlarged = OverlayLayout.frame(preferredSize: CGSize(width: 600, height: 300), currentFrame: snapped, visibleFrame: external, backingScale: 1)
    precondition(enlarged.maxX == snapped.maxX && enlarged.maxY == snapped.maxY, "resizing preserves a snapped top-right corner")
    let unchanged = OverlayLayout.frame(preferredSize: preferred, currentFrame: highDensity, visibleFrame: retina, backingScale: 2)
    precondition(unchanged == highDensity, "repeated screen notifications do not move the overlay")
}

func checkLyricSegmentation() {
    func split(_ lines: [LyricLine], duration: Double = 30, width: Double = 15) -> [LyricLine] {
        LyricSegmentation.split(lines, duration: duration, maxWidth: width, measure: { Double($0.count) })
    }
    let text = "alpha beta gamma delta"
    let original = [LyricLine(time: 10, text: text), LyricLine(time: 20, text: "next")]
    let parts = split(original)
    precondition(parts.map(\.text) == ["alpha beta", "gamma delta", "next"], "long entries become two balanced, single-line entries")
    precondition(parts[0].time == 10 && parts[1].time > 10 && parts[1].time < 20 && parts[2] == original[1], "split stays inside the source line's interval")
    precondition(parts.prefix(2).map(\.text).joined(separator: " ") == text, "all words remain in order")
    precondition(LRC.currentIndex(parts, at: parts[1].time - 0.001) == 0 && LRC.currentIndex(parts, at: parts[1].time) == 1, "the halves advance independently, including after a seek")
    precondition(original.count == 2 && original[0].text == text, "source lyrics are unchanged")
    precondition(split(original, width: Double(text.count)) == original, "fitting lines keep their original timing")
    precondition(split([]).isEmpty)
    let singleWord = [LyricLine(time: 1, text: "oneunbrokenlongword")]
    precondition(split(singleWord) == singleWord, "never split inside a word")
    let simultaneous = [LyricLine(time: 10, text: text), LyricLine(time: 10, text: "next")]
    precondition(split(simultaneous) == simultaneous, "duplicate timestamps cannot produce an overlapping entry")
    let last = split([original[0]], duration: 12)
    precondition(last.count == 2 && last[1].time < 12, "the last entry stays inside the track")
    let noTime = split([original[0]], duration: 10)
    precondition(noTime == [original[0]], "do not invent time beyond the track")
    let tinyGap = split([original[0], LyricLine(time: 10.01, text: "next")])
    precondition(tinyGap.count == 3 && tinyGap[1].time < 10.01, "short intervals remain ordered")

    let timed = LRC.parse("[00:10.00]<00:10.00>alpha <00:10.50>beta <00:12.00>gamma <00:13.00>delta\n[00:20.00]next")
    let exact = split(timed)
    precondition(exact[1].time == 12, "use the existing word timestamp for the second half")
    precondition(exact[0].words == Array(timed[0].words!.prefix(2)), "first-half word timestamps stay unchanged")
    precondition(exact[1].words?.map(\.offset) == [0, 1], "second-half word offsets are rebased")
    let fills = WordHighlight.units(for: exact[1], nextTime: 20, at: 12.5)
    precondition(fills[0].fill == 0.5 && fills[1].fill == 0, "karaoke stays aligned to the source word times")

    let unicode = "Café 👩🏽‍💻 walks along a quiet river"
    let unicodeParts = split([LyricLine(time: 1, text: unicode)])
    precondition(unicodeParts.count == 2 && unicodeParts.map(\.text).joined(separator: " ") == unicode, "Unicode words and emoji remain intact")
}

func checkSpotifyPKCE() throws {
    // RFC 7636 Appendix B.
    precondition(SpotifyPKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    let verifier = SpotifyPKCE.verifier(randomBytes: (0..<32).map { UInt8($0 * 7 % 256) })
    let urlSafe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    precondition(verifier.count == 43 && verifier.unicodeScalars.allSatisfy(urlSafe.contains), "verifier is 43 base64url chars")
    precondition(SpotifyPKCE.verifier(randomBytes: [UInt8](repeating: 255, count: 96)).count == 128, "96 bytes give the 128-char maximum")

    let url = SpotifyPKCE.authorizeURL(clientID: "abc123", redirectURI: "linory://callback", scopes: ["a-b", "c-d"], state: "s+t", challenge: "ch")
    let query = url.query ?? ""
    precondition(url.absoluteString.hasPrefix("https://accounts.spotify.com/authorize?"))
    for part in ["client_id=abc123", "response_type=code", "redirect_uri=linory%3A%2F%2Fcallback", "code_challenge_method=S256",
                 "code_challenge=ch", "scope=a-b%20c-d", "state=s%2Bt"] {
        precondition(query.contains(part), "authorize URL has \(part)")
    }
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    precondition(items.first { $0.name == "scope" }?.value == "a-b c-d" && items.first { $0.name == "redirect_uri" }?.value == "linory://callback")

    let code = SpotifyPKCE.tokenRequestBody(clientID: "abc", redirectURI: "linory://callback", grant: .authorizationCode(code: "c/1", verifier: "v"))
    for part in ["grant_type=authorization_code", "code=c%2F1", "client_id=abc", "code_verifier=v", "redirect_uri=linory%3A%2F%2Fcallback"] {
        precondition(code.split(separator: "&").contains(Substring(part)), "code body has \(part)")
    }
    let refresh = SpotifyPKCE.tokenRequestBody(clientID: "abc", redirectURI: "linory://callback", grant: .refreshToken("r"))
    precondition(Set(refresh.split(separator: "&")) == ["grant_type=refresh_token", "refresh_token=r", "client_id=abc"])

    let full = try JSONDecoder().decode(SpotifyToken.self, from: Data(#"{"access_token":"a","token_type":"Bearer","expires_in":3600,"refresh_token":"r","scope":"x"}"#.utf8))
    precondition(full.accessToken == "a" && full.expiresIn == 3600 && full.refreshToken == "r")
    let rotated = try JSONDecoder().decode(SpotifyToken.self, from: Data(#"{"access_token":"b","expires_in":3600}"#.utf8))
    precondition(rotated.refreshToken == nil, "refresh token is optional on refresh")
    precondition(full.scope == "x" && !SpotifyPKCE.grantsAllScopes("x"), "old logins lack scopes")
    precondition(SpotifyPKCE.grantsAllScopes(SpotifyPKCE.scopes.reversed().joined(separator: " ")), "scope order does not matter")
    let user = try JSONDecoder().decode(SpotifyUser.self, from: Data(#"{"id":"u1","display_name":null}"#.utf8))
    precondition(user.id == "u1" && user.displayName == nil)
}

/// Agent B: artist spread, multi-source, auto-continue, sleep timer, stats decoding.
func checkShuffleUpgrades() throws {
}

/// Seeded generator, so shuffle checks are repeatable.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

func checkSpotifyResponses() throws {
    let items = #"""
    {"items":[
      {"added_at":"x","is_local":false,"item":{"type":"track","uri":"spotify:track:a","is_local":false}},
      {"is_local":true,"item":{"type":"track","uri":"spotify:local:x:y:z:1","is_local":true}},
      {"is_local":false,"item":{"type":"episode","uri":"spotify:episode:e"}},
      null,
      {"is_local":false,"item":null},
      {"is_local":false,"item":{"type":"track","uri":"spotify:track:b"}}
    ],"next":"https://api.spotify.com/v1/playlists/p/items?offset=50&limit=50","total":6}
    """#
    let page = try JSONDecoder().decode(SpotifyTrackPage.self, from: Data(items.utf8))
    precondition(page.uris == ["spotify:track:a", "spotify:track:b"], "playlist items: only track URIs, in order")
    precondition(page.next != nil && page.total == 6)
    let liked = #"{"items":[{"added_at":"x","track":{"type":"track","uri":"spotify:track:c"}},{"track":{"type":"track","uri":"spotify:track:d","is_local":false}}],"next":null,"total":2}"#
    let likedPage = try JSONDecoder().decode(SpotifyTrackPage.self, from: Data(liked.utf8))
    precondition(likedPage.uris == ["spotify:track:c", "spotify:track:d"] && likedPage.next == nil, "/me/tracks uses the track key")

    let playlists = #"""
    {"items":[
      {"id":"mine","name":"Mine","owner":{"id":"me"},"collaborative":false},
      {"id":"collab","name":"Collab","owner":{"id":"friend"},"collaborative":true},
      {"id":"spotify-made","name":"Daily Mix","owner":{"id":"spotify"},"collaborative":false},
      null
    ],"next":null}
    """#
    let playlistPage = try JSONDecoder().decode(SpotifyPlaylistPage.self, from: Data(playlists.utf8))
    precondition(playlistPage.playlists.count == 3)
    precondition(SpotifyPlaylist.readable(playlistPage.playlists, userID: "me").map(\.id) == ["mine", "collab"], "owned and collaborative only")

    let playing = try JSONDecoder().decode(SpotifyCurrentlyPlaying.self, from: Data(#"{"context":{"type":"playlist","uri":"spotify:playlist:p1"},"item":{"uri":"spotify:track:a"},"is_playing":true}"#.utf8))
    precondition(playing.contextURI == "spotify:playlist:p1" && playing.itemURI == "spotify:track:a" && playing.isPlaylist("p1") && !playing.isPlaylist("p2"))
    let legacy = try JSONDecoder().decode(SpotifyCurrentlyPlaying.self, from: Data(#"{"context":{"uri":"spotify:user:u:playlist:p1"},"item":null}"#.utf8))
    precondition(legacy.isPlaylist("p1") && legacy.itemURI == nil, "older user-scoped playlist context")
    let devices = try JSONDecoder().decode(SpotifyDevice.List.self, from: Data(#"""
    {"devices":[{"id":"spk","name":"Kitchen","type":"Speaker","is_active":false,"is_restricted":false},
                {"id":"mac","name":"MacBook","type":"Computer","is_active":false,"is_restricted":false},
                {"id":null,"name":"Hidden","type":"Computer","is_active":true}]}
    """#.utf8)).devices
    precondition(SpotifyDevice.preferred(devices)?.id == "mac", "this Mac before an idle speaker; devices without id are skipped")
    let speakerPlaying = devices.map { $0.id == "spk" ? SpotifyDevice(id: "spk", name: "Kitchen", type: "Speaker", isActive: true) : $0 }
    precondition(SpotifyDevice.preferred(speakerPlaying)?.id == "spk", "an already playing device keeps playing")
    precondition(SpotifyDevice.preferred([SpotifyDevice(id: "spk", name: "Kitchen", type: "Speaker", isActive: false)]) == nil, "never start on an idle speaker")
    let noContext = try JSONDecoder().decode(SpotifyCurrentlyPlaying.self, from: Data(#"{"context":null,"item":{"uri":"spotify:track:a"}}"#.utf8))
    precondition(noContext.contextURI == nil && !noContext.isPlaylist("p1"), "null context")
}

func checkShuffleCycle() throws {
    let source = (0..<20).map { "spotify:track:\($0)" }
    var rng = SplitMix64(state: 1)
    var cycle = ShuffleCycle()
    let first = cycle.nextOrder(from: source + source.prefix(3), using: &rng)
    precondition(first.count == 20 && Set(first) == Set(source), "a permutation without duplicates")
    precondition(cycle.progress == (0, 20))

    for uri in first.prefix(5) { cycle.markPlayed(uri) }
    let second = cycle.nextOrder(from: source, using: &rng)
    precondition(Set(second) == Set(first.dropFirst(5)) && cycle.progress == (5, 20), "played tracks are left out")

    for uri in second { cycle.markPlayed(uri) }
    precondition(cycle.progress == (20, 20))
    let third = cycle.nextOrder(from: source, using: &rng)
    precondition(Set(third) == Set(source) && cycle.played.isEmpty, "a complete cycle starts over")

    cycle.markPlayed(source[0])
    let grown = cycle.nextOrder(from: source + ["spotify:track:new"], using: &rng)
    precondition(grown.contains("spotify:track:new") && !grown.contains(source[0]) && cycle.progress == (1, 21), "new tracks join the running cycle")

    cycle.markPlayed(source[1])
    _ = cycle.nextOrder(from: Array(source.dropFirst()), using: &rng)
    precondition(cycle.played == [source[1]] && cycle.total == 19, "tracks gone from the source are pruned")

    cycle.reset()
    precondition(cycle.played.isEmpty)

    // Removal
    var removing = ShuffleCycle()
    _ = removing.nextOrder(from: source, using: &rng)
    removing.markPlayed(source[2])
    removing.remove(source[2])
    removing.remove(source[3])
    precondition(removing.progress == (0, 18), "removing a played track lowers played and total")
    removing.markPlayed(source[3])
    precondition(removing.played.isEmpty, "removed tracks are never marked played")
    for _ in 0..<3 {
        let order = removing.nextOrder(from: source, using: &rng)
        precondition(!order.contains(source[2]) && !order.contains(source[3]), "removed tracks never return")
        for uri in order { removing.markPlayed(uri) }
    }
    removing.reset()
    precondition(removing.removed == [source[2], source[3]], "reset keeps removals")
    let roundTrip = try JSONDecoder().decode(ShuffleCycle.self, from: JSONEncoder().encode(removing))
    precondition(roundTrip == removing, "removals survive JSON")
    removing.restoreRemoved()
    let restored = removing.nextOrder(from: source, using: &rng)
    precondition(removing.removed.isEmpty && restored.contains(source[2]) && restored.contains(source[3]), "restored tracks are eligible and unplayed")

    // Cap
    var big = ShuffleCycle()
    let many = (0..<10_050).map { "spotify:track:m\($0)" }
    let capped = big.nextOrder(from: many, using: &rng)
    precondition(capped.count == ShuffleCycle.maxTracks && big.total == 10_050, "at most 10,000 tracks")
    for uri in capped { big.markPlayed(uri) }
    let rest = big.nextOrder(from: many, using: &rng)
    precondition(rest.count == 50 && Set(rest).isDisjoint(with: capped), "the other 50 stay unplayed")

    // Randomness
    var a = ShuffleCycle(), b = ShuffleCycle(), c = ShuffleCycle()
    var seed1 = SplitMix64(state: 42), seed1Again = SplitMix64(state: 42), seed2 = SplitMix64(state: 43)
    let orderA = a.nextOrder(from: source, using: &seed1)
    precondition(orderA == b.nextOrder(from: source, using: &seed1Again), "same seed, same order")
    precondition(orderA != c.nextOrder(from: source, using: &seed2), "different seeds, different orders")

    var state = ShuffleState()
    state.cycles["liked"] = removing
    state.cycles["p1"] = cycle
    state.shufflePlaylistID = "shuffle"
    state.activeSourceID = "liked"
    state.currentOrder = restored
    state.selectedSourceID = "p1"
    let decoded = try JSONDecoder().decode(ShuffleState.self, from: JSONEncoder().encode(state))
    precondition(decoded == state, "state JSON round trip")
}

checkParsing()
try checkMatching()
checkLocalization()
checkPlaybackClock()
try checkBestAny()
try checkGetResponse()
checkPlainEstimate()
checkCache()
checkPlayerSelection()
checkVisibilityPolicy()
checkWordHighlight()
checkOverlayLayout()
checkLyricSegmentation()
try checkSpotifyPKCE()
try checkSpotifyResponses()
try checkShuffleCycle()
try checkMiniPlayer()
try checkShuffleUpgrades()
print("LyricsCore checks passed")
