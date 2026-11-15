import Foundation

/// Spotify Web API response shapes. Only the fields Linory uses are decoded.

public struct SpotifyToken: Decodable, Equatable {
    public let accessToken: String
    public let expiresIn: Int
    /// Spotify may rotate the refresh token on refresh; absent means keep the old one.
    public let refreshToken: String?
    /// Space-separated scopes this login granted.
    public let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", expiresIn = "expires_in", refreshToken = "refresh_token", scope
    }
}

/// `{"error": "invalid_grant", ...}` from the token endpoint.
public struct SpotifyTokenError: Decodable, Equatable {
    public let error: String
}

public struct SpotifyUser: Decodable, Equatable {
    public let id: String
    public let displayName: String?

    enum CodingKeys: String, CodingKey { case id, displayName = "display_name" }
}

public struct SpotifyPlaylist: Decodable, Equatable {
    public struct Owner: Decodable, Equatable { public let id: String }
    public let id: String
    public let name: String
    public let owner: Owner
    public let collaborative: Bool

    public init(id: String, name: String, ownerID: String, collaborative: Bool) {
        self.id = id; self.name = name; self.owner = Owner(id: ownerID); self.collaborative = collaborative
    }

    enum CodingKeys: String, CodingKey { case id, name, owner, collaborative }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        owner = try container.decode(Owner.self, forKey: .owner)
        collaborative = try container.decodeIfPresent(Bool.self, forKey: .collaborative) ?? false
    }

    /// A development-mode app can read items only from playlists the user owns or collaborates on.
    public static func readable(_ playlists: [SpotifyPlaylist], userID: String) -> [SpotifyPlaylist] {
        playlists.filter { $0.owner.id == userID || $0.collaborative }
    }
}

public struct SpotifyPlaylistPage: Decodable {
    public let playlists: [SpotifyPlaylist]
    public let next: String?

    enum CodingKeys: String, CodingKey { case items, next }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playlists = try container.decodeIfPresent([SpotifyPlaylist?].self, forKey: .items)?.compactMap { $0 } ?? []
        next = try container.decodeIfPresent(String.self, forKey: .next)
    }
}

/// One page of `/playlists/{id}/items` (entries use `item`) or `/me/tracks` (entries use `track`).
/// Keeps only playable track URIs: local files, episodes and null entries are skipped.
public struct SpotifyTrackPage: Decodable {
    public let uris: [String]
    public let next: String?
    /// Entries in the whole list, including skipped ones; used to load the remaining pages in parallel.
    public let total: Int?

    private struct Entry: Decodable {
        let item: Object?
        let track: Object?
        let isLocal: Bool?
        enum CodingKeys: String, CodingKey { case item, track, isLocal = "is_local" }
    }
    private struct Object: Decodable {
        let uri: String?
        let type: String?
        let isLocal: Bool?
        enum CodingKeys: String, CodingKey { case uri, type, isLocal = "is_local" }
    }
    enum CodingKeys: String, CodingKey { case items, next, total }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.decodeIfPresent(Int.self, forKey: .total)
        let entries = try container.decodeIfPresent([Entry?].self, forKey: .items) ?? []
        uris = entries.compactMap { entry in
            guard let entry, entry.isLocal != true, let object = entry.item ?? entry.track,
                  object.isLocal != true, object.type ?? "track" == "track",
                  let uri = object.uri, uri.hasPrefix("spotify:track:") else { return nil }
            return uri
        }
        next = try container.decodeIfPresent(String.self, forKey: .next)
    }
}

/// A Spotify Connect device from `GET /me/player/devices`.
public struct SpotifyDevice: Decodable, Equatable {
    public let id: String?
    public let name: String
    public let type: String
    public let isActive: Bool
    public let isRestricted: Bool

    public init(id: String?, name: String, type: String, isActive: Bool, isRestricted: Bool = false) {
        self.id = id; self.name = name; self.type = type; self.isActive = isActive; self.isRestricted = isRestricted
    }

    enum CodingKeys: String, CodingKey { case id, name, type, isActive = "is_active", isRestricted = "is_restricted" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        isRestricted = try container.decodeIfPresent(Bool.self, forKey: .isRestricted) ?? false
    }

    public struct List: Decodable { public let devices: [SpotifyDevice] }

    /// Where Shuffle & play starts: this Mac's Spotify app (a `Computer`) first, the active one among those first.
    /// Other devices only when they are already playing, so a shuffle never starts on a speaker by surprise.
    public static func preferred(_ devices: [SpotifyDevice]) -> SpotifyDevice? {
        let usable = devices.filter { $0.id != nil && !$0.isRestricted }
        let computers = usable.filter { $0.type == "Computer" }
        return computers.first { $0.isActive } ?? usable.first { $0.isActive } ?? computers.first
    }
}

public struct SpotifyCurrentlyPlaying: Decodable, Equatable {
    public let contextURI: String?
    public let itemURI: String?

    private struct URIObject: Decodable { let uri: String? }
    enum CodingKeys: String, CodingKey { case context, item }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contextURI = try container.decodeIfPresent(URIObject.self, forKey: .context)?.uri
        itemURI = try container.decodeIfPresent(URIObject.self, forKey: .item)?.uri
    }

    /// Context URIs come as `spotify:playlist:<id>` or the older `spotify:user:<user>:playlist:<id>`.
    public func isPlaylist(_ id: String) -> Bool { contextURI?.hasSuffix("playlist:\(id)") == true }
}
