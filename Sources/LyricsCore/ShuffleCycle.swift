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
    /// `pending` tracks are still queued from the previous order (auto-continue): they are left out, and when they are all
    /// that is unplayed, the new cycle starts without them, so a song never plays twice in a row across the seam.
    public mutating func nextOrder<G: RandomNumberGenerator>(from source: [String], excluding pending: Set<String> = [],
                                                             using generator: inout G) -> [String] {
        var seen = Set<String>()
        let eligible = source.filter { !removed.contains($0) && seen.insert($0).inserted }
        // Tracks that left the source no longer count, so progress follows the source.
        played.formIntersection(seen)
        total = eligible.count
        var unplayed = eligible.filter { !played.contains($0) && !pending.contains($0) }
        if unplayed.isEmpty {
            played.removeAll()
            unplayed = eligible.filter { !pending.contains($0) }
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

/// Title and artist of a shuffled track, for "Up next". Short keys keep the state file small for 10,000 tracks.
public struct ShuffleTrackInfo: Codable, Equatable {
    public let name: String
    public let artist: String
    public let artistID: String?

    public init(name: String, artist: String, artistID: String?) {
        self.name = name; self.artist = artist; self.artistID = artistID
    }

    enum CodingKeys: String, CodingKey { case name = "n", artist = "a", artistID = "i" }
}

public struct ShuffleState: Codable, Equatable {
    public static let likedSourceID = "liked"

    /// Keyed by source ID: `liked` or the playlist ID.
    public var cycles: [String: ShuffleCycle] = [:]
    /// The one reused "Linory Shuffle" playlist.
    public var shufflePlaylistID: String?
    /// Source of the order currently in the Linory Shuffle playlist.
    public var activeSourceID: String?
    /// Mirrors the Linory Shuffle playlist; with auto-continue it holds several rounds, so a URI can appear twice.
    public var currentOrder: [String] = []
    public var selectedSourceID: String?
    /// Title and artist per URI in `currentOrder`.
    public var trackInfo: [String: ShuffleTrackInfo] = [:]
    /// Index in `currentOrder` of the track last confirmed playing from the Linory Shuffle playlist.
    public var playingIndex: Int?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case cycles, shufflePlaylistID, activeSourceID, currentOrder, selectedSourceID, trackInfo, playingIndex
    }

    /// Files written before a field existed decode with its default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cycles = try container.decodeIfPresent([String: ShuffleCycle].self, forKey: .cycles) ?? [:]
        shufflePlaylistID = try container.decodeIfPresent(String.self, forKey: .shufflePlaylistID)
        activeSourceID = try container.decodeIfPresent(String.self, forKey: .activeSourceID)
        currentOrder = try container.decodeIfPresent([String].self, forKey: .currentOrder) ?? []
        selectedSourceID = try container.decodeIfPresent(String.self, forKey: .selectedSourceID)
        trackInfo = try container.decodeIfPresent([String: ShuffleTrackInfo].self, forKey: .trackInfo) ?? [:]
        playingIndex = try container.decodeIfPresent(Int.self, forKey: .playingIndex)
    }

    /// Where `uri` plays in `currentOrder`: the first occurrence from the last known position on, since later rounds
    /// repeat URIs; otherwise the first anywhere (the user jumped back in Spotify).
    public func index(of uri: String) -> Int? {
        let start = min(playingIndex ?? 0, currentOrder.count)
        return currentOrder[start...].firstIndex(of: uri) ?? currentOrder.firstIndex(of: uri)
    }

    /// Auto-continue appends the next round once the second-to-last or last track of the order plays.
    public func needsNextRound(at index: Int) -> Bool { index >= currentOrder.count - 2 }
}

/// A source made of several sources (Liked Songs and playlists). The ID lists the sorted members, so the same
/// selection always maps to the same cycle, whatever order it was picked in.
public enum ShuffleMix {
    static let prefix = "mix:"

    /// One member is that source itself; nil for none.
    public static func id(_ members: [String]) -> String? {
        let sorted = Set(members).sorted()
        guard let first = sorted.first else { return nil }
        return sorted.count == 1 ? first : prefix + sorted.joined(separator: ",")
    }

    /// The members of a mix ID, or the source itself for a plain ID.
    public static func members(_ id: String) -> [String] {
        guard id.hasPrefix(prefix) else { return [id] }
        return id.dropFirst(prefix.count).split(separator: ",").map(String.init)
    }

    public static func isMix(_ id: String) -> Bool { id.hasPrefix(prefix) }
}

/// Reorders a shuffled list so no two neighbours share a primary artist, when the counts allow it.
public enum ArtistSpread {
    /// Builds the order one track at a time: each step picks a track at random (weighted by how many tracks each artist
    /// has left) among artists that differ from the previous one and still leave a valid arrangement for the rest.
    /// When one artist has too many tracks to keep apart, the rule relaxes to "differ from the previous one", then to
    /// any track, and the order stays random. Tracks without an artist count as their own artist.
    /// `previousArtist` is the artist right before the list (the end of the previous round).
    public static func arrange<G: RandomNumberGenerator>(_ uris: [String], artists: [String: String], after previousArtist: String? = nil,
                                                         using generator: inout G) -> [String] {
        var slots: [String: Int] = [:]
        var groups: [[String]] = []
        for uri in uris {
            let key = artists[uri] ?? "track:" + uri
            let slot = slots[key] ?? groups.count
            if slot == groups.count { slots[key] = slot; groups.append([]) }
            groups[slot].append(uri)
        }
        // Random order within each artist; the walk below picks which artist comes next.
        for slot in groups.indices { groups[slot].shuffle(using: &generator) }
        var counts = groups.map(\.count)
        // Artists with tracks left; exhausted ones are swap-removed, so each step costs O(artists left).
        var active = Array(counts.indices)
        var previous = previousArtist.flatMap { slots[$0] } ?? -1
        var result: [String] = []
        result.reserveCapacity(uris.count)
        for rest in stride(from: uris.count - 1, through: 0, by: -1) {
            // Largest and second-largest counts, to test feasibility after a pick in O(1).
            var top = -1, second = -1
            for index in active {
                if top < 0 || counts[index] > counts[top] { second = top; top = index }
                else if second < 0 || counts[index] > counts[second] { second = index }
            }
            // After a pick, that artist may not start the rest, so it fits in rest / 2 slots; any other in (rest + 1) / 2.
            func allowed(_ pick: Int, tier: Int) -> Bool {
                if tier == 2 { return true }
                guard pick != previous else { return false }
                if tier == 1 { return true }
                guard counts[pick] - 1 <= rest / 2 else { return false }
                let other = pick == top ? second : top
                return other < 0 || counts[other] <= (rest + 1) / 2
            }
            var pick = -1
            for tier in 0..<3 where pick < 0 {
                var weight = 0
                for index in active where allowed(index, tier: tier) { weight += counts[index] }
                guard weight > 0 else { continue }
                var roll = Int.random(in: 0..<weight, using: &generator)
                for index in active where allowed(index, tier: tier) {
                    roll -= counts[index]
                    if roll < 0 { pick = index; break }
                }
            }
            counts[pick] -= 1
            result.append(groups[pick].removeLast())
            if counts[pick] == 0, let slot = active.firstIndex(of: pick) { active.swapAt(slot, active.count - 1); active.removeLast() }
            previous = pick
        }
        return result
    }
}
