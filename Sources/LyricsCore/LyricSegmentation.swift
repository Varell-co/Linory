import Foundation

public enum LyricSegmentation {
    /// Split oversized display entries once, leaving the original lyrics and cache untouched.
    public static func split(_ lines: [LyricLine], duration: TimeInterval, maxWidth: Double,
                             measure: (String) -> Double) -> [LyricLine] {
        lines.enumerated().flatMap { index, line -> [LyricLine] in
            guard measure(line.text) > maxWidth else { return [line] }
            let end = index + 1 < lines.count ? lines[index + 1].time : duration
            guard end > line.time else { return [line] }

            let exact = line.words.flatMap { $0.count > 1 ? $0 : nil }
            let texts = exact?.map(\.text) ?? line.text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard texts.count > 1 else { return [line] }

            // Match the word highlighter's character-weighted estimate when no word timing exists.
            let weights = texts.map { Double($0.count + 1) }
            let total = weights.reduce(0, +)
            let sung = min((end - line.time) * 0.9, max(0.6, total * 0.07))
            var elapsed = 0.0
            let offsets = exact?.map(\.offset) ?? weights.map { weight in
                defer { elapsed += sung * weight / total }
                return elapsed
            }
            let boundaries = (1..<texts.count).filter {
                line.time + offsets[$0] > line.time && line.time + offsets[$0] < end
            }
            guard let boundary = boundaries.min(by: { left, right in
                func imbalance(_ split: Int) -> Double {
                    abs(measure(texts[..<split].joined(separator: " ")) - measure(texts[split...].joined(separator: " ")))
                }
                return imbalance(left) < imbalance(right)
            }) else { return [line] }

            let offset = offsets[boundary]
            let firstWords = exact.map { Array($0[..<boundary]) }
            let secondWords = exact.map {
                $0[boundary...].map { LyricWord(offset: $0.offset - offset, text: $0.text) }
            }
            return [
                LyricLine(time: line.time, text: texts[..<boundary].joined(separator: " "), words: firstWords),
                LyricLine(time: line.time + offset, text: texts[boundary...].joined(separator: " "), words: secondWords)
            ]
        }
    }
}
