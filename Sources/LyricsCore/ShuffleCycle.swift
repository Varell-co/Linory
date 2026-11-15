import Foundation

/// No-repeat shuffle rules for one source (Liked Songs or a playlist). Pure; the app saves it as JSON.
/// Track identity is the Spotify track URI.
public struct ShuffleCycle: Codable, Equatable {
    /// Spotify playlists hold at most 10,000 items.
    public static let maxTracks = 10_000

    public private(set) var played: Set<String> = []
    public private(set) var removed: Set<String> = []
    /// Eligible tracks (source minus removed) as of the last `nextOrder`.
    public private(set) var total = 0

    public init() {}

    public var progress: (played: Int, total: Int) { (played.count, total) }

    /// The unplayed, non-removed tracks of `source` in a fresh random order. Starts a new cycle when everything was played.
    public mutating func nextOrder<G: RandomNumberGenerator>(from source: [String], using generator: inout G) -> [String] {
        var seen = Set<String>()
        let eligible = source.filter { !removed.contains($0) && seen.insert($0).inserted }
        // Tracks that left the source no longer count, so progress follows the source.
        played.formIntersection(seen)
        total = eligible.count
        var unplayed = eligible.filter { !played.contains($0) }
        if unplayed.isEmpty {
            played.removeAll()
            unplayed = eligible
        }
        unplayed.shuffle(using: &generator)
        return Array(unplayed.prefix(Self.maxTracks))
    }

    public mutating func markPlayed(_ uri: String) {
        guard !removed.contains(uri) else { return }
        played.insert(uri)
    }

    /// Excludes the track from this source in every future cycle, until `restoreRemoved`.
    public mutating func remove(_ uri: String) {
        guard removed.insert(uri).inserted else { return }
        played.remove(uri)
        total = max(0, total - 1)
    }

    /// Restored tracks join the next order as unplayed; `total` is corrected by the next `nextOrder`.
    public mutating func restoreRemoved() {
        total += removed.count
        removed.removeAll()
    }

    public mutating func reset() { played.removeAll() }
}

public struct ShuffleState: Codable, Equatable {
    public static let likedSourceID = "liked"

    /// Keyed by source ID: `liked` or the playlist ID.
    public var cycles: [String: ShuffleCycle] = [:]
    /// The one reused "Linory Shuffle" playlist.
    public var shufflePlaylistID: String?
    /// Source of the order currently in the Linory Shuffle playlist.
    public var activeSourceID: String?
    public var currentOrder: [String] = []
    public var selectedSourceID: String?

    public init() {}
}
