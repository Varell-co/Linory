import AppKit
import LyricsCore

final class PlayerModel: ObservableObject {
    @Published var track: Track?
    @Published var lines: [LyricLine] = []
    @Published var clock = PlaybackClock()
    @Published var status: StatusMessage = .waitingForPlayer
    private var generation = 0
    private var pending = false
    private let queue = DispatchQueue(label: "spotify-reader")
    private var timer: Timer?
    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "LyricsOverlay/\(version) (https://github.com/MikeLeonFox/LyricsOverlay)"
    }()

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        guard !pending else { return }
        pending = true
        queue.async { [weak self] in
            let result = Self.readSpotify()
            DispatchQueue.main.async {
                guard let self else { return }
                self.pending = false
                switch result {
                case .failure(let status): self.clear(status)
                case .success(let snapshot): self.update(snapshot)
                }
            }
        }
    }

    private struct Snapshot { let track: Track; let position: Double; let playing: Bool }

    private static func readSpotify() -> Result<Snapshot, StatusMessage> {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first != nil else {
            return .failure(.openPlayer)
        }
        let source = """
        tell application id "com.spotify.client"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {id of t, name of t, artist of t, duration of t, player position, (player state is playing)}
        end tell
        """
        var error: NSDictionary?
        guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
            let number = error?[NSAppleScript.errorNumber] as? Int
            let detail = error?[NSAppleScript.errorMessage] as? String ?? "\(number ?? 0)"
            return .failure(number == -1743 ? .automationDenied : .playerError(detail))
        }
        guard descriptor.numberOfItems >= 6,
              let id = descriptor.atIndex(1)?.stringValue,
              let title = descriptor.atIndex(2)?.stringValue,
              let artist = descriptor.atIndex(3)?.stringValue,
              let duration = descriptor.atIndex(4), let position = descriptor.atIndex(5) else {
            return .failure(.noTrack)
        }
        let track = Track(id: id, title: title, artist: artist, duration: duration.doubleValue / 1000)
        return .success(Snapshot(track: track, position: position.doubleValue, playing: descriptor.atIndex(6)?.booleanValue ?? false))
    }

    private func clear(_ message: StatusMessage) {
        if track != nil { generation += 1 }
        track = nil; lines = []; clock.reset(); status = message
    }

    private func update(_ snapshot: Snapshot) {
        if track != snapshot.track { clock.reset() }
        clock.update(position: snapshot.position, playing: snapshot.playing, duration: snapshot.track.duration, at: Date())
        guard track != snapshot.track else { return }
        track = snapshot.track
        lines = []
        status = .searching
        generation += 1
        let requestedGeneration = generation
        let track = snapshot.track
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [URLQueryItem(name: "track_name", value: track.title), URLQueryItem(name: "artist_name", value: track.artist)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let httpOK = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let results = data.flatMap { try? JSONDecoder().decode([LyricsResult].self, from: $0) }
            let match = results.flatMap { LyricsMatching.best($0, title: track.title, artist: track.artist, duration: track.duration) }
            let parsed = match?.syncedLyrics.map(LRC.parse) ?? []
            DispatchQueue.main.async {
                guard let self, self.generation == requestedGeneration else { return }
                self.lines = parsed
                self.status = error != nil || !httpOK || results == nil ? .networkError : .noLyrics
            }
        }.resume()
    }
}
