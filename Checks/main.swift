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
        precondition(StatusMessage.playerError("detail-x").text(language: language).contains("detail-x"))
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

checkParsing()
try checkMatching()
checkLocalization()
checkPlaybackClock()
print("LyricsCore checks passed")
