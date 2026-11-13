import Foundation
import LyricsCore

func checkParsing() {
    let lines = LRC.parse("[00:03.50] Second\n[00:01.00] First\n[00:07.00][00:09.10] Again\n[00:12.0] \n[00:65.00] Invalid")
    precondition(lines.map(\.time) == [1, 3.5, 7, 9.1, 12])
    precondition(lines.map(\.text) == ["First", "Second", "Again", "Again", ""])
    precondition(LRC.currentIndex(lines, at: 0.99) == nil)
    precondition(LRC.currentIndex(lines, at: 1) == 0)
    precondition(LRC.currentIndex(lines, at: 8) == 2)
    precondition(LRC.currentIndex(lines, at: 12) == 4)
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
print("LyricsCore checks passed")
