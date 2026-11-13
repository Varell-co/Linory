import Foundation

/// Lyrics ready for display. `synced == false` means the times are estimated from plain text.
public struct LoadedLyrics: Codable, Equatable {
    public let lines: [LyricLine]
    public let synced: Bool
    public let instrumental: Bool

    public init(lines: [LyricLine], synced: Bool, instrumental: Bool) {
        self.lines = lines; self.synced = synced; self.instrumental = instrumental
    }

    /// Converts an LRCLIB match: synced lyrics win, then plain lyrics spread over the track, then instrumental.
    public static func make(from result: LyricsResult, duration: Double) -> LoadedLyrics? {
        if let synced = result.syncedLyrics, case let lines = LRC.parse(synced), !lines.isEmpty {
            return LoadedLyrics(lines: lines, synced: true, instrumental: false)
        }
        if let plain = result.plainLyrics, case let lines = PlainLyrics.estimate(text: plain, duration: duration), !lines.isEmpty {
            return LoadedLyrics(lines: lines, synced: false, instrumental: false)
        }
        if result.instrumental == true { return LoadedLyrics(lines: [], synced: false, instrumental: true) }
        return nil
    }
}

public enum PlainLyrics {
    /// Spreads non-empty lines evenly from a short intro lead to 95 % of the track.
    public static func estimate(text: String, duration: Double) -> [LyricLine] {
        let texts = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !texts.isEmpty, duration > 0 else { return [] }
        let lead = min(10, duration * 0.05)
        let step = (duration * 0.95 - lead) / Double(texts.count)
        return texts.enumerated().map { LyricLine(time: lead + Double($0.offset) * step, text: $0.element) }
    }
}
