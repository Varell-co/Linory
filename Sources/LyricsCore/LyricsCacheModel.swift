import Foundation

public enum LyricsCacheKey {
    /// Normalized title|artist|rounded duration, so case and diacritics do not create duplicate entries.
    public static func make(title: String, artist: String, duration: Double) -> String {
        "\(LyricsMatching.normalized(title))|\(LyricsMatching.normalized(artist))|\(Int(duration.rounded()))"
    }
}

public struct LyricsCacheEntry: Codable, Equatable {
    /// `nil` means LRCLIB had nothing for this track.
    public let lyrics: LoadedLyrics?
    public let fetchedAt: Date

    public init(lyrics: LoadedLyrics?, fetchedAt: Date) { self.lyrics = lyrics; self.fetchedAt = fetchedAt }

    /// LRCLIB keeps adding tracks, so "not found" and instrumental results are retried after a while.
    var expires: Bool { lyrics == nil || lyrics?.instrumental == true }
}

/// Pure cache logic; the app reads and writes it as JSON.
public struct LyricsCacheStore: Codable, Equatable {
    public static let capacity = 500
    public static let negativeLifetime: TimeInterval = 7 * 24 * 60 * 60

    public private(set) var entries: [String: LyricsCacheEntry] = [:]

    public init() {}

    public func lookup(_ key: String, now: Date) -> LyricsCacheEntry? {
        guard let entry = entries[key] else { return nil }
        if entry.expires && now.timeIntervalSince(entry.fetchedAt) >= Self.negativeLifetime { return nil }
        return entry
    }

    public mutating func insert(_ entry: LyricsCacheEntry, for key: String) {
        entries[key] = entry
        let overflow = entries.count - Self.capacity
        guard overflow > 0 else { return }
        for key in entries.sorted(by: { $0.value.fetchedAt < $1.value.fetchedAt }).prefix(overflow).map(\.key) {
            entries[key] = nil
        }
    }
}
