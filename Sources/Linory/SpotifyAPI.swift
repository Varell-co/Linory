import Foundation
import LyricsCore
import os

/// Spotify Web API calls (post-February-2026 paths). Tokens come from `SpotifyAuth` and are never logged.
actor SpotifyAPI {
    private let auth: SpotifyAuth
    private let log = Logger(subsystem: LyricsService.subsystem, category: "spotify")
    private static let base = "https://api.spotify.com/v1"
    private static let batchSize = 100

    init(auth: SpotifyAuth) { self.auth = auth }

    func me() async throws -> SpotifyUser {
        try await JSONDecoder().decode(SpotifyUser.self, from: send("GET", "/me").data)
    }

    /// Playlists the user owns or collaborates on: the only ones whose items a development-mode app can read.
    func ownPlaylists(userID: String) async throws -> [SpotifyPlaylist] {
        var playlists: [SpotifyPlaylist] = []
        var next: String? = "/me/playlists?limit=50"
        while let path = next {
            let page = try await JSONDecoder().decode(SpotifyPlaylistPage.self, from: send("GET", path).data)
            playlists += page.playlists
            next = page.next
        }
        return SpotifyPlaylist.readable(playlists, userID: userID)
    }

    func createPlaylist(name: String, description: String) async throws -> String {
        struct Created: Decodable { let id: String }
        let body: [String: Any] = ["name": name, "description": description, "public": false]
        return try await JSONDecoder().decode(Created.self, from: send("POST", "/me/playlists", json: body).data).id
    }

    /// The first `PUT` replaces all items, further `POST`s append in batches of 100.
    func replaceItems(playlistID: String, uris: [String]) async throws {
        let path = "/playlists/\(playlistID)/items"
        let batches = stride(from: 0, to: uris.count, by: Self.batchSize).map { Array(uris[$0..<min($0 + Self.batchSize, uris.count)]) }
        try await send("PUT", path, json: ["uris": batches.first ?? []])
        for batch in batches.dropFirst() { try await send("POST", path, json: ["uris": batch]) }
    }

    func removeItems(playlistID: String, uris: [String]) async throws {
        for start in stride(from: 0, to: uris.count, by: Self.batchSize) {
            let batch = uris[start..<min(start + Self.batchSize, uris.count)]
            try await send("DELETE", "/playlists/\(playlistID)/items", json: ["items": batch.map { ["uri": $0] }])
        }
    }

    // MARK: Library and liked state

    /// `GET /me/library/contains` answers with one bool per URI.
    func isSaved(uri: String) async throws -> Bool {
        try await JSONDecoder().decode([Bool].self, from: send("GET", "/me/library/contains?uris=\(Self.query(uri))").data).first ?? false
    }

    func save(uri: String) async throws { try await send("PUT", "/me/library?uris=\(Self.query(uri))") }

    func unsave(uri: String) async throws { try await send("DELETE", "/me/library?uris=\(Self.query(uri))") }

    private static func query(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ":-_."))) ?? value
    }

    // MARK: Playback

    func devices() async throws -> [SpotifyDevice] {
        try await JSONDecoder().decode(SpotifyDevice.List.self, from: send("GET", "/me/player/devices").data).devices
    }

    /// Starts the playlist from its first track on the device. Spotify's servers resolve the playlist, so a playlist
    /// created or rewritten seconds ago plays correctly, unlike asking the desktop app, whose cache can lag behind.
    func playPlaylist(id: String, deviceID: String) async throws {
        try await send("PUT", "/me/player/play?device_id=\(deviceID)",
                       json: ["context_uri": "spotify:playlist:\(id)", "offset": ["position": 0]])
        try await send("PUT", "/me/player/shuffle?state=false&device_id=\(deviceID)")
        try await send("PUT", "/me/player/repeat?state=off&device_id=\(deviceID)")
    }

    /// nil when nothing is playing (204).
    func currentlyPlaying() async throws -> SpotifyCurrentlyPlaying? {
        let (data, status) = try await send("GET", "/me/player/currently-playing")
        guard status != 204, !data.isEmpty else { return nil }
        return try JSONDecoder().decode(SpotifyCurrentlyPlaying.self, from: data)
    }

    // MARK: Shuffle and stats

    /// Tracks of Liked Songs or one playlist, with name and primary artist. After the first page, pages load 4 at a time.
    func tracks(source id: String) async throws -> [SpotifyTrackInfo] {
        let path = id == ShuffleState.likedSourceID ? "/me/tracks" : "/playlists/\(id)/items"
        let first = try await JSONDecoder().decode(SpotifyTrackPage.self, from: send("GET", "\(path)?limit=50").data)
        guard first.next != nil, let total = first.total else { return first.tracks }
        var tracks = first.tracks
        let offsets = Array(stride(from: 50, to: total, by: 50))
        for chunk in stride(from: 0, to: offsets.count, by: 4).map({ offsets[$0..<min($0 + 4, offsets.count)] }) {
            try await withThrowingTaskGroup(of: [SpotifyTrackInfo].self) { group in
                for offset in chunk {
                    group.addTask {
                        try await JSONDecoder().decode(SpotifyTrackPage.self, from: self.send("GET", "\(path)?limit=50&offset=\(offset)").data).tracks
                    }
                }
                for try await page in group { tracks += page }
            }
        }
        return tracks
    }

    /// Appends after the existing items (auto-continue), in batches of 100.
    func appendItems(playlistID: String, uris: [String]) async throws {
        for start in stride(from: 0, to: uris.count, by: Self.batchSize) {
            try await send("POST", "/playlists/\(playlistID)/items", json: ["uris": Array(uris[start..<min(start + Self.batchSize, uris.count)])])
        }
    }

    /// `GET /me/top/{artists|tracks}`, the 10 most played in the range. Needs `user-top-read`.
    func topItems(_ type: String, range: SpotifyTimeRange) async throws -> [SpotifyTopItem] {
        try await JSONDecoder().decode(SpotifyTopItem.Page.self, from: send("GET", "/me/top/\(type)?time_range=\(range.rawValue)&limit=10").data).items
    }

    /// Refreshes and retries once on 401; waits once for `Retry-After` on 429.
    @discardableResult
    private func send(_ method: String, _ path: String, json: [String: Any]? = nil) async throws -> (data: Data, status: Int) {
        guard let url = URL(string: path.hasPrefix("https://") ? path : Self.base + path) else { throw SpotifyError.http(0) }
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        var token = try await auth.validAccessToken()
        var refreshed = false
        var waited = false
        while true {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 20
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let logPath = url.path
            switch status {
            case 200..<300:
                log.debug("request \(method, privacy: .public) \(logPath, privacy: .public) → \(status)")
                return (data, status)
            case 401 where !refreshed:
                log.info("request \(method, privacy: .public) \(logPath, privacy: .public) → 401, refreshing")
                refreshed = true
                token = try await auth.refreshAccessToken()
            case 429 where !waited:
                let delay = min(max(Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1, 1), 30)
                log.info("request \(method, privacy: .public) \(logPath, privacy: .public) → 429, retry after \(Int(delay)) s")
                waited = true
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            default:
                log.error("request \(method, privacy: .public) \(logPath, privacy: .public) → \(status)")
                throw status == 401 ? SpotifyError.loginExpired : SpotifyError.http(status)
            }
        }
    }
}
