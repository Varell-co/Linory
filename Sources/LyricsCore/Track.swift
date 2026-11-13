import Foundation

public struct Track: Equatable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double
    public init(id: String, title: String, artist: String, album: String = "", duration: Double) {
        self.id = id; self.title = title; self.artist = artist; self.album = album; self.duration = duration
    }
}
