import Foundation
import LyricsCore
import os

/// Lookup order: disk cache, LRCLIB `/api/get`, then `/api/search`. Network errors are never cached.
actor LyricsService {
    static let subsystem = "co.varell.linory"
    private let log = Logger(subsystem: LyricsService.subsystem, category: "lyrics")
    private let cacheURL: URL
    private var store: LyricsCacheStore?
    private let userAgent: String

    struct HTTPError: LocalizedError {
        let status: Int
        var errorDescription: String? { "HTTP \(status)" }
    }

    init(userAgent: String) {
        self.userAgent = userAgent
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheURL = support.appendingPathComponent(Self.subsystem, isDirectory: true).appendingPathComponent("lyrics-cache.json")
    }

    func load(track: Track) async -> Result<LoadedLyrics?, Error> {
        let key = LyricsCacheKey.make(title: track.title, artist: track.artist, duration: track.duration)
        if let entry = cache().lookup(key, now: Date()) {
            log.info("cache hit \(Self.kind(entry.lyrics), privacy: .public) \"\(track.title, privacy: .public)\" – \"\(track.artist, privacy: .public)\"")
            return .success(entry.lyrics)
        }
        do {
            let lyrics = try await fetch(track)
            store?.insert(LyricsCacheEntry(lyrics: lyrics, fetchedAt: Date()), for: key)
            save()
            return .success(lyrics)
        } catch {
            log.error("network error: \(error.localizedDescription, privacy: .public) (not cached)")
            return .failure(error)
        }
    }

    private func fetch(_ track: Track) async throws -> LoadedLyrics? {
        var query = [URLQueryItem(name: "track_name", value: track.title), URLQueryItem(name: "artist_name", value: track.artist)]
        if !track.album.isEmpty { query.append(URLQueryItem(name: "album_name", value: track.album)) }
        // LRCLIB accepts 1...3600 s and matches within ±2 s.
        if (1...3600).contains(track.duration) { query.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))) }
        let (getData, getStatus) = try await request("get", query)
        if getStatus == 200, let result = try? JSONDecoder().decode(LyricsResult.self, from: getData),
           let match = LyricsMatching.bestAny([result], title: track.title, artist: track.artist, duration: track.duration) {
            let lyrics = LoadedLyrics.make(from: match, duration: track.duration)
            log.info("/api/get hit (match: \(Self.kind(lyrics), privacy: .public))")
            return lyrics
        }
        guard getStatus == 200 || getStatus == 404 else { throw HTTPError(status: getStatus) }

        let (searchData, searchStatus) = try await request("search", Array(query.prefix(2)))
        guard (200..<300).contains(searchStatus) else { throw HTTPError(status: searchStatus) }
        let results = try JSONDecoder().decode([LyricsResult].self, from: searchData)
        let lyrics = LyricsMatching.bestAny(results, title: track.title, artist: track.artist, duration: track.duration)
            .flatMap { LoadedLyrics.make(from: $0, duration: track.duration) }
        log.info("/api/get \(getStatus) → /api/search (\(results.count) results, match: \(Self.kind(lyrics), privacy: .public))")
        return lyrics
    }

    private func request(_ endpoint: String, _ query: [URLQueryItem]) async throws -> (Data, Int) {
        var components = URLComponents(string: "https://lrclib.net/api/\(endpoint)")!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Read once, on first use.
    private func cache() -> LyricsCacheStore {
        if let store { return store }
        let loaded = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(LyricsCacheStore.self, from: $0) } ?? LyricsCacheStore()
        store = loaded
        return loaded
    }

    private func save() {
        guard let store else { return }
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(store).write(to: cacheURL, options: .atomic)
        } catch {
            log.error("cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func kind(_ lyrics: LoadedLyrics?) -> String {
        guard let lyrics else { return "none" }
        return lyrics.instrumental ? "instrumental" : lyrics.synced ? "synced" : "plain"
    }
}
