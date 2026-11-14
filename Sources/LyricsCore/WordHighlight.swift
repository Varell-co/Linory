import Foundation

/// How far each word of the active line is "sung", 0...1, for karaoke-style highlighting.
public enum WordHighlight {
    public struct Unit: Equatable {
        public let text: String
        public let fill: Double
    }

    /// Uses enhanced-LRC word times when present. Otherwise estimates: the line is sung in roughly
    /// 0.07 s per character (never longer than 90 % of the gap to the next line), split by word length.
    public static func units(for line: LyricLine, nextTime: TimeInterval?, at position: TimeInterval) -> [Unit] {
        let gap = max(0.3, (nextTime ?? line.time + 6) - line.time)
        func fill(_ start: Double, _ length: Double) -> Double { min(1, max(0, (position - start) / max(0.05, length))) }

        if let words = line.words, !words.isEmpty {
            return words.enumerated().map { i, word in
                let start = line.time + word.offset
                let end = i + 1 < words.count ? line.time + words[i + 1].offset : min(line.time + gap, start + 1.5)
                return Unit(text: word.text, fill: fill(start, end - start))
            }
        }

        let words = line.text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let weights = words.map { Double($0.count + 1) }
        let total = weights.reduce(0, +)
        let sung = min(gap * 0.9, max(0.6, total * 0.07))
        var start = line.time
        return zip(words, weights).map { word, weight in
            let length = sung * weight / total
            defer { start += length }
            return Unit(text: word, fill: fill(start, length))
        }
    }
}
