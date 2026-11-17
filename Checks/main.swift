import Foundation
import CoreGraphics
import LyricsCore

/// Chorus detection, seek targets, sync clock.
func checkMiniPlayer() throws {
    checkClockSync()
    checkClockSeek()
    checkChorus()
}

func checkClockSync() {
    let t0 = Date(timeIntervalSince1970: 1_000)
    func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }
    var clock = PlaybackClock()
    clock.update(position: 10, playing: true, duration: 100, at: t0)

    // Clock 0.2 s ahead: no jump back, but it catches up with the player within the slew time.
    var ahead = clock
    ahead.update(position: 10.6, playing: true, duration: 100, at: at(0.8))
    precondition(abs(ahead.position(at: at(0.8)) - 10.8) < 0.001, "no visible jump back")
    var previous = ahead.position(at: at(0.8))
    for step in 1...20 {
        let now = ahead.position(at: at(0.8 + Double(step) * 0.05))
        precondition(now > previous, "a slewing clock never runs backwards")
        previous = now
    }
    precondition(abs(ahead.position(at: at(0.8 + PlaybackClock.slewDuration)) - (10.6 + PlaybackClock.slewDuration)) < 0.001, "drift is corrected")
    precondition(abs(ahead.position(at: at(3)) - 12.8) < 0.001, "then runs in step with the player")

    // A real seek back jumps.
    var back = clock
    back.update(position: 10.2, playing: true, duration: 100, at: at(0.8))
    precondition(abs(back.position(at: at(0.8)) - 10.2) < 0.001, "0.6 s back is a seek")

    // Clock behind the player jumps forward at once: forward jumps never flicker.
    var behind = clock
    behind.update(position: 10.85, playing: true, duration: 100, at: at(0.8))
    precondition(abs(behind.position(at: at(0.8)) - 10.85) < 0.001, "behind catches up at once")

    // Anchoring with the sample time instead of the arrival time keeps a slow read from lagging the lyrics.
    var sampled = PlaybackClock()
    sampled.update(position: 30, playing: true, duration: 100, at: at(0.0))
    precondition(abs(sampled.position(at: at(0.09)) - 30.09) < 0.001, "the read time counts as played")

    // Resuming after a pause anchors fresh, and a new slew replaces an old one.
    var resumed = ahead
    resumed.update(position: 11, playing: false, duration: 100, at: at(1))
    resumed.update(position: 11, playing: true, duration: 100, at: at(5))
    precondition(abs(resumed.position(at: at(6)) - 12) < 0.001 && resumed.slew == 0, "resume anchors fresh")
}

func checkClockSeek() {
    let t0 = Date(timeIntervalSince1970: 2_000)
    func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }
    var clock = PlaybackClock()
    clock.update(position: 100, playing: true, duration: 200, at: t0)
    clock.seek(to: 40, at: at(1))
    precondition(clock.position(at: at(1)) == 40 && clock.position(at: at(1.2)) == 40, "holds at the target")

    var stale = clock
    stale.update(position: 101.05, playing: true, duration: 200, at: at(1.05))
    precondition(stale.position(at: at(1.1)) == 40 && stale.pendingSeek == 40, "a read from before the seek is ignored")

    var buffering = clock
    buffering.update(position: 40, playing: true, duration: 200, at: at(1.2))
    precondition(buffering.position(at: at(1.3)) == 40 && buffering.pendingSeek == 40, "still buffering: hold")
    buffering.update(position: 40.1, playing: true, duration: 200, at: at(1.4))
    precondition(buffering.pendingSeek == nil && abs(buffering.position(at: at(1.9)) - 40.6) < 0.001, "runs once the player moves")

    var paused = clock
    paused.update(position: 40, playing: false, duration: 200, at: at(1.1))
    precondition(paused.pendingSeek == nil && paused.position(at: at(9)) == 40, "paused seek is confirmed at once")

    var timeout = clock
    timeout.update(position: 120, playing: true, duration: 200, at: at(1 + PlaybackClock.seekTimeout + 0.1))
    precondition(timeout.pendingSeek == nil && timeout.position(at: at(1 + PlaybackClock.seekTimeout + 0.1)) == 120, "gives up waiting")

    var clamped = clock
    clamped.seek(to: 500, at: at(2))
    precondition(clamped.anchorPosition == 200, "seeks clamp to the duration")
    clamped.seek(to: -3, at: at(2))
    precondition(clamped.anchorPosition == 0, "and to the start")
}

/// Invented lyrics: verse, chorus, verse, chorus, bridge, chorus.
func checkChorus() {
    let verse1 = ["Paper boats on Sunday", "Drifting past the mill"]
    let chorus = ["Hold the lantern higher", "Let the river sing", "Hold the lantern higher!"]
    let verse2 = ["Copper leaves in autumn", "Falling on the hill"]
    let bridge = ["Quiet now", "Quiet now"]
    var time = 0.0
    var lines: [LyricLine] = []
    var starts: [Double] = []
    for (part, isChorus) in [(verse1, false), (chorus, true), (verse2, false), (chorus.map { $0.uppercased() }, true), ([""], false), (bridge, false), (chorus, true)] {
        if isChorus { starts.append(time + 5) }
        for text in part { time += 5; lines.append(LyricLine(time: time, text: text)) }
    }
    precondition(Chorus.starts(in: lines) == starts, "finds every chorus, ignoring case and punctuation")
    precondition(Chorus.next(after: 0, starts: starts) == starts[0], "first chorus from the intro")
    precondition(Chorus.next(after: starts[0], starts: starts) == starts[1], "after jumping, the next one")
    precondition(Chorus.next(after: starts[0] - 3, starts: starts) == starts[0], "the coming chorus")
    precondition(Chorus.next(after: starts[2] + 1, starts: starts) == starts[0], "wraps to the first")

    let noRepeat = (1...8).map { LyricLine(time: Double($0), text: "Line number \($0)") }
    precondition(Chorus.starts(in: noRepeat).isEmpty, "no chorus without repetition")
    let single = [LyricLine(time: 1, text: "Echo"), LyricLine(time: 2, text: "Other"), LyricLine(time: 3, text: "Echo"), LyricLine(time: 4, text: "More")]
    precondition(Chorus.starts(in: single).isEmpty, "one repeated line is not a chorus")

    // A short hook repeated more often wins over a longer group repeated less.
    let hook = ["Na na hey", "Na na ho"]
    var hookLines: [LyricLine] = []
    for (i, text) in (hook + ["Verse one here"] + hook + ["Verse two here"] + hook + ["End"]).enumerated() {
        hookLines.append(LyricLine(time: Double(i), text: text))
    }
    precondition(Chorus.starts(in: hookLines) == [0, 3, 6], "most repeated group wins")
    precondition(Chorus.next(after: 0, starts: []) == nil)
}

func checkListeningStats() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let monday = Date(timeIntervalSince1970: 1_763_337_600) // Mon 17 Nov 2025 00:00 UTC
    let song = Track(source: .spotify, rawID: "spotify:track:a", title: "Song A", artist: "Artist", duration: 200)
    let other = Track(source: .music, rawID: "42", title: "Song B", artist: "artist", duration: 180)

    // Tracker: only playing time counts, gaps are capped, a track change ends the session.
    var tracker = ListeningTracker()
    var t = monday.addingTimeInterval(9 * 3600)
    precondition(tracker.tick(track: song, position: 0, playing: true, syncedLyrics: false, at: t) == nil)
    for _ in 0..<50 { t += 1; _ = tracker.tick(track: song, position: 1, playing: true, syncedLyrics: true, at: t) }
    t += 600; _ = tracker.tick(track: song, position: 51, playing: true, syncedLyrics: false, at: t) // slept: +5 s only
    t += 10; _ = tracker.tick(track: song, position: 56, playing: false, syncedLyrics: false, at: t) // paused: +0
    t += 1
    let first = tracker.tick(track: other, position: 0, playing: true, syncedLyrics: false, at: t)
    precondition(first?.listened == 55 && first?.syncedLyrics == true && first?.uri == "spotify:track:a" && first?.countsAsPlay == true)
    for _ in 0..<10 { t += 1; _ = tracker.tick(track: other, position: 1, playing: true, syncedLyrics: false, at: t) }
    let skipped = tracker.tick(track: nil, position: 0, playing: false, syncedLyrics: false, at: t + 1)
    precondition(skipped?.listened == 10 && skipped?.skipped == true && skipped?.uri == nil, "10 s of a 3 min song is a skip")
    precondition(tracker.finish() == nil)
    _ = tracker.tick(track: song, position: 0, playing: true, syncedLyrics: false, at: t)
    _ = tracker.tick(track: song, position: 198, playing: true, syncedLyrics: false, at: t + 3)
    let repeated = tracker.tick(track: song, position: 1, playing: true, syncedLyrics: false, at: t + 4)
    precondition(repeated?.listened == 3 && tracker.current?.trackID == song.id, "repeat-one starts a new session")
    _ = tracker.tick(track: song, position: 1.5, playing: true, syncedLyrics: false, at: t + 4.5)
    precondition(tracker.finish() == nil, "under a second is noise")

    // Stats
    func session(_ track: Track, day: Int, hour: Int, listened: Double, synced: Bool = false) -> ListenSession {
        ListenSession(track: track, start: monday.addingTimeInterval(Double(day) * 86_400 + Double(hour) * 3600), listened: listened, syncedLyrics: synced)
    }
    let sessions = [
        session(song, day: 0, hour: 9, listened: 200, synced: true), session(song, day: 1, hour: 21, listened: 200),
        session(other, day: 2, hour: 21, listened: 180, synced: true), session(other, day: 2, hour: 22, listened: 5),
        session(song, day: 3, hour: 8, listened: 30), session(other, day: -40, hour: 12, listened: 180),
    ]
    let now = monday.addingTimeInterval(3 * 86_400 + 12 * 3600) // Thursday noon
    let week = ListeningStats.summarize(sessions, range: .week, now: now, calendar: calendar)
    precondition(week.seconds == 615 && week.plays == 4 && week.skips == 1, "the 40-day-old session is outside the week")
    precondition(abs(week.skipRate - 0.2) < 0.0001 && week.syncedShare == 0.5)
    precondition(week.topTracks.map(\.title) == ["Song A", "Song B"] && week.topTracks[0].plays == 3 && week.topTracks[0].uri != nil)
    precondition(week.topArtists.count == 1 && week.topArtists[0].seconds == 615, "artists group case-insensitively across players")
    precondition(week.clock[0][9] == 200 && week.clock[2][21] == 180 && week.clock[2][22] == 5, "Monday first, by start hour")
    precondition(week.unit == .day && week.buckets.count == 7 && week.buckets.last?.seconds == 30 && week.buckets[3].seconds == 200)
    precondition(week.streakDays == 3, "Thursday has only 30 s so far; the run Mon to Wed still counts")
    let today = ListeningStats.summarize(sessions, range: .today, now: now, calendar: calendar)
    precondition(today.unit == .hour && today.buckets.count == 13 && today.seconds == 30 && today.plays == 1)
    let all = ListeningStats.summarize(sessions, range: .all, now: now, calendar: calendar)
    precondition(all.unit == .month && all.buckets.count == 2 && all.seconds == 795)
    precondition(ListeningStats.summarize([], range: .year, now: now, calendar: calendar).buckets.count == 12)
    let gap = ListeningStats.summarize([session(song, day: 0, hour: 9, listened: 200)], range: .week, now: now, calendar: calendar)
    precondition(gap.streakDays == 0, "a streak needs today or yesterday")

    let encoded = try JSONEncoder().encode(sessions[0])
    let decodedSession = try JSONDecoder().decode(ListenSession.self, from: encoded)
    precondition(decodedSession == sessions[0], "session JSON round trip")
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

    let shifted = LRC.parse("[ar:Someone]\n[offset:+500]\n[00:00.20] Early\n[00:02.00] <00:02.00> Word <00:02.50> timed")
    precondition(shifted.map(\.time).enumerated().allSatisfy { abs($1 - [-0.3, 1.5][$0]) < 0.001 }, "[offset:] in ms, positive shows lyrics earlier")
    precondition(shifted[1].words?.map(\.offset) == [0, 0.5], "word timing stays relative to its line")
    precondition(LRC.parse("[OFFSET: -250]\n[00:01.00] x")[0].time == 1.25, "negative offset delays the lyrics")
    let inline = LRC.parse("[00:01.00] Meet me at [00:02.00] sharp")
    precondition(inline.count == 1 && inline[0].text == "Meet me at [00:02.00] sharp", "a timestamp inside the text is lyric text")

    precondition(TrackTiming.nudged(0, by: 1) == 0.25 && TrackTiming.nudged(0.25, by: -2) == -0.25)
    precondition(TrackTiming.nudged(0.1, by: 0) == 0 && TrackTiming.nudged(9.9, by: 4) == TrackTiming.limit, "snaps to the grid and clamps")
    precondition(TrackTiming.format(0) == "0 s" && TrackTiming.format(0.5) == "+0.50 s" && TrackTiming.format(-0.25) == "−0.25 s")
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
    let blank = try JSONDecoder().decode([LyricsResult].self, from: Data("""
    [{"trackName":"Song","artistName":"Artist","duration":200,"syncedLyrics":"[00:01.00]\\n[00:05.00] "}]
    """.utf8))
    precondition(LyricsMatching.best(blank, title: "Song", artist: "Artist", duration: 200) == nil, "timestamps without text are not synced lyrics")
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

/// Artist spread, multi-source, auto-continue, sleep timer, stats decoding.
func checkShuffleUpgrades() throws {
    try checkArtistSpread()
    checkAutoContinue()
    try checkShuffleMetadata()
    checkSleepTimer()
    try checkTopItems()
}

/// Number of neighbours that share an artist.
func adjacentRepeats(_ order: [String], _ artists: [String: String]) -> Int {
    zip(order, order.dropFirst()).filter { artists[$0] != nil && artists[$0] == artists[$1] }.count
}

func checkArtistSpread() throws {
    // 4 artists with 6, 5, 3 and 2 tracks: always separable.
    var artists: [String: String] = [:]
    var uris: [String] = []
    for (artist, count) in [("a", 6), ("b", 5), ("c", 3), ("d", 2)] {
        for n in 0..<count { uris.append("spotify:track:\(artist)\(n)"); artists["spotify:track:\(artist)\(n)"] = artist }
    }
    for seed in 0..<50 {
        var rng = SplitMix64(state: UInt64(seed))
        let order = ArtistSpread.arrange(uris, artists: artists, using: &rng)
        precondition(order.sorted() == uris.sorted(), "a permutation")
        precondition(adjacentRepeats(order, artists) == 0, "no neighbours by the same artist when avoidable")
    }
    // The tightest case: 5 of one artist among 9 tracks fits only as a _ a _ a _ a _ a; with "a" just before, it cannot start.
    let tight = (0..<5).map { "spotify:track:t\($0)" } + (0..<4).map { "spotify:track:o\($0)" }
    let tightArtists = Dictionary(uniqueKeysWithValues: tight.map { ($0, $0.hasPrefix("spotify:track:t") ? "a" : "o\($0.last!)") })
    var rng = SplitMix64(state: 7)
    let tightOrder = ArtistSpread.arrange(tight, artists: tightArtists, using: &rng)
    precondition(adjacentRepeats(tightOrder, tightArtists) == 0 && tightArtists[tightOrder[0]] == "a", "the forced layout is found")
    let seam = ArtistSpread.arrange(Array(tight.prefix(4)) + Array(tight.suffix(4)), artists: tightArtists, after: "a", using: &rng)
    precondition(tightArtists[seam[0]] != "a" && adjacentRepeats(seam, tightArtists) == 0, "the previous round's last artist is respected")

    // Unavoidable: 6 of one artist and 2 others need at least 3 repeats. Still a random permutation of every track.
    let heavy = (0..<6).map { "spotify:track:h\($0)" } + ["spotify:track:x", "spotify:track:y"]
    let heavyArtists = Dictionary(uniqueKeysWithValues: heavy.map { ($0, $0.hasPrefix("spotify:track:h") ? "h" : $0) })
    var heavyOrders = Set<[String]>()
    for seed in 0..<20 {
        var r = SplitMix64(state: UInt64(seed))
        let order = ArtistSpread.arrange(heavy, artists: heavyArtists, using: &r)
        precondition(order.sorted() == heavy.sorted() && (3...5).contains(adjacentRepeats(order, heavyArtists)), "unavoidable repeats")
        heavyOrders.insert(order)
    }
    precondition(heavyOrders.count > 10, "the unavoidable case stays random")

    // Unknown artists (URI-only data) never block anything; same seed gives the same order.
    var s1 = SplitMix64(state: 9), s2 = SplitMix64(state: 9), s3 = SplitMix64(state: 10)
    let plain = (0..<30).map { "spotify:track:p\($0)" }
    let p1 = ArtistSpread.arrange(plain, artists: [:], using: &s1)
    precondition(p1 == ArtistSpread.arrange(plain, artists: [:], using: &s2) && p1 != ArtistSpread.arrange(plain, artists: [:], using: &s3))
    precondition(Set(p1) == Set(plain))

    // Every position is reachable: over many seeds each track starts the order at least once.
    var firsts = Set<String>()
    for seed in 0..<400 {
        var r = SplitMix64(state: UInt64(seed))
        firsts.insert(ArtistSpread.arrange(uris, artists: artists, using: &r)[0])
    }
    precondition(firsts.count == uris.count, "random, not a fixed pattern")

    // Mix IDs: stable, order-independent, deduped; one member is the source itself.
    let mix = ShuffleMix.id(["p2", "liked", "p1", "p2"])
    precondition(mix == "mix:liked,p1,p2" && mix == ShuffleMix.id(["p1", "p2", "liked"]), "stable mix ID")
    precondition(ShuffleMix.members(mix!) == ["liked", "p1", "p2"] && ShuffleMix.isMix(mix!))
    precondition(ShuffleMix.id(["p1"]) == "p1" && ShuffleMix.members("p1") == ["p1"] && ShuffleMix.id([]) == nil && !ShuffleMix.isMix("liked"))
}

func checkAutoContinue() {
    let source = (0..<6).map { "spotify:track:\($0)" }
    var rng = SplitMix64(state: 3)
    var cycle = ShuffleCycle()
    let first = cycle.nextOrder(from: source, using: &rng)
    for uri in first.dropLast() { cycle.markPlayed(uri) }
    // The second-to-last started: the last one is still pending, so the next round starts a new cycle without it.
    let pending: Set<String> = [first.last!]
    let next = cycle.nextOrder(from: source, excluding: pending, using: &rng)
    precondition(Set(next) == Set(source).subtracting(pending) && cycle.played.isEmpty, "the next round skips the pending track")
    cycle.markPlayed(first.last!)
    precondition(cycle.progress == (1, 6), "the pending track counts in the new cycle when it plays")
    // Unplayed tracks outside the order (beyond the 10,000 cap) come first, before a new cycle.
    var partial = ShuffleCycle()
    _ = partial.nextOrder(from: source, using: &rng)
    for uri in source.prefix(4) { partial.markPlayed(uri) }
    let rest = partial.nextOrder(from: source, excluding: [source[4]], using: &rng)
    precondition(rest == [source[5]] && partial.played.count == 4, "the running cycle finishes first")

    var state = ShuffleState()
    state.currentOrder = ["a", "b", "c", "a", "d"]
    precondition(state.index(of: "a") == 0)
    state.playingIndex = 2
    precondition(state.index(of: "a") == 3 && state.index(of: "b") == 1, "later rounds repeat URIs")
    precondition(!state.needsNextRound(at: 2) && state.needsNextRound(at: 3) && state.needsNextRound(at: 4))
}

func checkShuffleMetadata() throws {
    let items = #"""
    {"items":[{"item":{"type":"track","uri":"spotify:track:a","name":"Song A","artists":[{"id":"ar1","name":"Artist One"},{"id":"ar2","name":"Two"}]}},
              {"item":{"type":"track","uri":"spotify:track:b"}}],"next":null,"total":2}
    """#
    let page = try JSONDecoder().decode(SpotifyTrackPage.self, from: Data(items.utf8))
    precondition(page.tracks == [SpotifyTrackInfo(uri: "spotify:track:a", name: "Song A", artistName: "Artist One", artistID: "ar1"),
                                 SpotifyTrackInfo(uri: "spotify:track:b")], "playlist items: primary artist and name; URI-only still works")
    let liked = #"{"items":[{"track":{"type":"track","uri":"spotify:track:c","name":"Song C","artists":[{"id":"ar3","name":"Three"}]}}],"next":null}"#
    let likedPage = try JSONDecoder().decode(SpotifyTrackPage.self, from: Data(liked.utf8))
    precondition(likedPage.tracks.first?.artistID == "ar3" && likedPage.tracks.first?.name == "Song C" && likedPage.uris == ["spotify:track:c"], "liked songs")

    // A state file from before these fields existed.
    let old = #"{"cycles":{"liked":{"played":["spotify:track:a"],"removed":[],"total":3}},"shufflePlaylistID":"s","activeSourceID":"liked","currentOrder":["spotify:track:a","spotify:track:b"],"selectedSourceID":"liked"}"#
    let decoded = try JSONDecoder().decode(ShuffleState.self, from: Data(old.utf8))
    precondition(decoded.currentOrder.count == 2 && decoded.cycles["liked"]?.progress.played == 1 && decoded.cycles["liked"]?.total == 3 && decoded.trackInfo.isEmpty && decoded.playingIndex == nil, "old state files load")
    precondition((try? JSONDecoder().decode(ShuffleState.self, from: Data("{}".utf8))) == ShuffleState(), "an empty file loads")
    var state = decoded
    state.trackInfo["spotify:track:a"] = ShuffleTrackInfo(name: "Song A", artist: "Artist One", artistID: "ar1")
    state.playingIndex = 1
    let roundTrip = try JSONDecoder().decode(ShuffleState.self, from: JSONEncoder().encode(state))
    precondition(roundTrip == state, "new fields round trip")
}

func checkSleepTimer() {
    let start = Date(timeIntervalSince1970: 1_000)
    let timer = SleepTimer(.minutes(15), now: start, trackID: nil)!
    precondition(timer.remaining(now: start, trackID: nil, trackRemaining: 0) == 900)
    precondition(timer.remaining(now: start.addingTimeInterval(899.5), trackID: "x", trackRemaining: 10) == 0.5, "minutes ignore the track")
    precondition(timer.remaining(now: start.addingTimeInterval(1_000), trackID: nil, trackRemaining: 0) == 0)

    precondition(SleepTimer(.endOfTrack, now: start, trackID: nil) == nil, "end of track needs a track")
    let end = SleepTimer(.endOfTrack, now: start, trackID: "t1")!
    precondition(end.remaining(now: start, trackID: "t1", trackRemaining: 42) == 42)
    precondition(end.remaining(now: start, trackID: "t1", trackRemaining: 0.5) == 0, "pauses just before the end")
    precondition(end.remaining(now: start, trackID: "t2", trackRemaining: 200) == 0, "a new track means the old one ended")
    precondition(end.remaining(now: start, trackID: nil, trackRemaining: 0) == 0)

    precondition(SleepTimer.format(59.2) == "1:00" && SleepTimer.format(605) == "10:05" && SleepTimer.format(3_725) == "1:02:05")
}

func checkTopItems() throws {
    let artists = #"{"items":[{"id":"a1","name":"Artist","uri":"spotify:artist:a1","genres":["x"]},null,{"name":"no id"}],"total":2}"#
    let artistPage = try JSONDecoder().decode(SpotifyTopItem.Page.self, from: Data(artists.utf8))
    precondition(artistPage.items.map(\.uri) == ["spotify:artist:a1"] && artistPage.items[0].artists.isEmpty, "top artists; bad entries skipped")
    let tracks = #"{"items":[{"id":"t1","name":"Song","uri":"spotify:track:t1","artists":[{"name":"A"},{"name":"B"}]}]}"#
    let trackPage = try JSONDecoder().decode(SpotifyTopItem.Page.self, from: Data(tracks.utf8))
    precondition(trackPage.items.first?.name == "Song" && trackPage.items.first?.artists == "A, B", "top tracks with artist names")
    precondition(SpotifyTimeRange.allCases.map(\.rawValue) == ["short_term", "medium_term", "long_term"])
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
try checkListeningStats()
print("LyricsCore checks passed")
