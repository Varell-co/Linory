import Foundation

public struct LyricLine: Equatable, Codable {
    public let time: TimeInterval
    public let text: String
    /// Per-word timing from enhanced LRC, if the source had it. Offsets are relative to `time`,
    /// so a line repeated under several timestamps (chorus) keeps correct word timing.
    public let words: [LyricWord]?
    public init(time: TimeInterval, text: String, words: [LyricWord]? = nil) {
        self.time = time; self.text = text; self.words = words
    }
}

public struct LyricWord: Equatable, Codable {
    public let offset: TimeInterval
    public let text: String
    public init(offset: TimeInterval, text: String) { self.offset = offset; self.text = text }
}

public enum LRC {
    private static let lineTag = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2}(?:\.\d+)?)\]"#)
    private static let wordTag = try! NSRegularExpression(pattern: #"<(\d{1,3}):(\d{2}(?:\.\d+)?)>"#)

    public static func parse(_ input: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in input.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = lineTag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let (text, timedWords) = words(in: ns.substring(from: last.range.location + last.range.length))
            for match in matches {
                guard let time = seconds(ns, match) else { continue }
                // Enhanced LRC word times are absolute; store them relative to the first timestamp of the line.
                let base = matches.first.flatMap { seconds(ns, $0) } ?? time
                let relative = timedWords?.map { LyricWord(offset: max(0, $0.offset - base), text: $0.text) }
                lines.append(LyricLine(time: time, text: text, words: relative))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// Splits text with optional enhanced-LRC word tags like `<00:12.34>` into display text and timed words.
    private static func words(in body: String) -> (String, [LyricWord]?) {
        let ns = body as NSString
        let tags = wordTag.matches(in: body, range: NSRange(location: 0, length: ns.length))
        let clean = { (s: String) in s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ") }
        guard !tags.isEmpty else { return (clean(body), nil) }
        var words: [LyricWord] = []
        for (i, tag) in tags.enumerated() {
            let start = tag.range.location + tag.range.length
            let end = i + 1 < tags.count ? tags[i + 1].range.location : ns.length
            let text = clean(ns.substring(with: NSRange(location: start, length: end - start)))
            if let time = seconds(ns, tag), !text.isEmpty { words.append(LyricWord(offset: time, text: text)) }
        }
        return (clean(words.map(\.text).joined(separator: " ")), words.isEmpty ? nil : words)
    }

    private static func seconds(_ ns: NSString, _ match: NSTextCheckingResult) -> TimeInterval? {
        guard let minutes = Double(ns.substring(with: match.range(at: 1))),
              let seconds = Double(ns.substring(with: match.range(at: 2))), seconds < 60 else { return nil }
        return minutes * 60 + seconds
    }

    public static func currentIndex(_ lines: [LyricLine], at position: TimeInterval) -> Int? {
        lines.lastIndex { $0.time <= position }
    }
}

/// One LRCLIB record, as returned by `/api/get` and `/api/search`. Optional fields tolerate missing keys.
public struct LyricsResult: Decodable {
    public let trackName: String
    public let artistName: String
    public let albumName: String?
    public let duration: Double
    public let instrumental: Bool?
    public let plainLyrics: String?
    public let syncedLyrics: String?

    var hasSynced: Bool { !(syncedLyrics ?? "").isEmpty && !LRC.parse(syncedLyrics ?? "").isEmpty }
    var hasPlain: Bool { !(plainLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public enum LyricsMatching {
    public static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    /// Same title, same artist (or artist followed by featured artists), duration within ±5 s.
    private static func plausible(_ results: [LyricsResult], title: String, artist: String, duration: Double) -> [LyricsResult] {
        let title = normalized(title), artist = normalized(artist)
        guard !title.isEmpty, !artist.isEmpty else { return [] }
        return results.filter { result in
            let candidateArtist = normalized(result.artistName)
            return normalized(result.trackName) == title &&
                (candidateArtist == artist || candidateArtist.hasPrefix(artist + " ")) &&
                abs(result.duration - duration) <= 5
        }
    }

    private static func closest(_ results: [LyricsResult], to duration: Double) -> LyricsResult? {
        results.min { abs($0.duration - duration) < abs($1.duration - duration) }
    }

    /// Closest plausible match with synced lyrics.
    public static func best(_ results: [LyricsResult], title: String, artist: String, duration: Double) -> LyricsResult? {
        closest(plausible(results, title: title, artist: artist, duration: duration).filter(\.hasSynced), to: duration)
    }

    /// Prefers synced lyrics, then plain lyrics, then an instrumental match.
    public static func bestAny(_ results: [LyricsResult], title: String, artist: String, duration: Double) -> LyricsResult? {
        let candidates = plausible(results, title: title, artist: artist, duration: duration)
        return closest(candidates.filter(\.hasSynced), to: duration)
            ?? closest(candidates.filter(\.hasPlain), to: duration)
            ?? closest(candidates.filter { $0.instrumental == true }, to: duration)
    }
}
