import Foundation

/// Finds the chorus in synced lyrics: the group of consecutive lines that repeats most often.
public enum Chorus {
    /// Start times of every occurrence of the chorus, or empty when nothing repeats.
    /// Prefers the most repeated group of at least two lines; among equally frequent groups the longest
    /// (the whole chorus rather than a part of it), then the one that starts first.
    public static func starts(in lines: [LyricLine]) -> [TimeInterval] {
        // Instrumental breaks are empty lines; they never belong to a chorus and must not split one.
        let sung = lines.compactMap { line -> (time: TimeInterval, text: String)? in
            let text = LyricsMatching.normalized(line.text)
            return text.isEmpty ? nil : (line.time, text)
        }
        var best: (count: Int, length: Int, starts: [Int])?
        for length in stride(from: 2, through: sung.count / 2, by: 1) {
            var occurrences: [[String]: [Int]] = [:]
            for start in 0...(sung.count - length) {
                occurrences[sung[start..<start + length].map(\.text), default: []].append(start)
            }
            for starts in occurrences.values {
                // Overlapping matches ("oh oh oh") count once per full group.
                let separate = starts.reduce(into: [Int]()) { kept, start in
                    if kept.last.map({ start >= $0 + length }) ?? true { kept.append(start) }
                }
                guard separate.count >= 2 else { continue }
                if let current = best {
                    let better = separate.count > current.count
                        || (separate.count == current.count && length > current.length)
                        || (separate.count == current.count && length == current.length && separate[0] < current.starts[0])
                    if !better { continue }
                }
                best = (separate.count, length, separate)
            }
        }
        return best?.starts.map { sung[$0].time } ?? []
    }

    /// The next chorus after `position`, or the first one once the last has passed.
    /// Right after jumping to a chorus the position sits on its start, so a second press moves on to the next one.
    public static func next(after position: TimeInterval, starts: [TimeInterval]) -> TimeInterval? {
        starts.first { $0 > position + 0.5 } ?? starts.first
    }
}
