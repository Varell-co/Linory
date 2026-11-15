import Foundation

public enum PlayerSource: String, CaseIterable {
    case spotify, music

    public var bundleID: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        }
    }
}

public struct Track: Equatable {
    /// Prefixed with the source, so the same raw id in two players is two different tracks.
    public let id: String
    /// The player's own id: for Spotify the track URI (`spotify:track:…`).
    public let rawID: String
    public let source: PlayerSource
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double

    public init(source: PlayerSource, rawID: String, title: String, artist: String, album: String = "", duration: Double) {
        self.id = "\(source.rawValue):\(rawID)"
        self.rawID = rawID
        self.source = source; self.title = title; self.artist = artist; self.album = album; self.duration = duration
    }
}

public struct PlaybackSnapshot: Equatable {
    public let track: Track
    public let position: Double
    public let playing: Bool

    public init(track: Track, position: Double, playing: Bool) {
        self.track = track; self.position = position; self.playing = playing
    }
}
