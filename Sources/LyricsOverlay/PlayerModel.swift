import AppKit
import LyricsCore

final class PlayerModel: ObservableObject {
    @Published var track: Track?
    @Published var lyrics: LoadedLyrics?
    @Published var clock = PlaybackClock()
    @Published var status: StatusMessage = .waitingForPlayer
    private var generation = 0
    private var pending = false
    private let queue = DispatchQueue(label: "spotify-reader")
    private var timer: Timer?
    private let service: LyricsService = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return LyricsService(userAgent: "LyricsOverlay/\(version) (https://github.com/MikeLeonFox/LyricsOverlay)")
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
            return {id of t, name of t, artist of t, album of t, duration of t, player position, (player state is playing)}
        end tell
        """
        var error: NSDictionary?
        guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
            let number = error?[NSAppleScript.errorNumber] as? Int
            let detail = error?[NSAppleScript.errorMessage] as? String ?? "\(number ?? 0)"
            return .failure(number == -1743 ? .automationDenied : .playerError(detail))
        }
        guard descriptor.numberOfItems >= 7,
              let id = descriptor.atIndex(1)?.stringValue,
              let title = descriptor.atIndex(2)?.stringValue,
              let artist = descriptor.atIndex(3)?.stringValue,
              let duration = descriptor.atIndex(5), let position = descriptor.atIndex(6) else {
            return .failure(.noTrack)
        }
        let album = descriptor.atIndex(4)?.stringValue ?? ""
        let track = Track(id: id, title: title, artist: artist, album: album, duration: duration.doubleValue / 1000)
        return .success(Snapshot(track: track, position: position.doubleValue, playing: descriptor.atIndex(7)?.booleanValue ?? false))
    }

    private func clear(_ message: StatusMessage) {
        if track != nil { generation += 1 }
        track = nil; lyrics = nil; clock.reset(); status = message
    }

    private func update(_ snapshot: Snapshot) {
        if track != snapshot.track { clock.reset() }
        clock.update(position: snapshot.position, playing: snapshot.playing, duration: snapshot.track.duration, at: Date())
        guard track != snapshot.track else { return }
        track = snapshot.track
        lyrics = nil
        status = .searching
        generation += 1
        let requestedGeneration = generation
        let track = snapshot.track
        Task { [service] in
            let result = await service.load(track: track)
            await MainActor.run { [weak self] in
                guard let self, self.generation == requestedGeneration else { return }
                switch result {
                case .failure: self.status = .networkError
                case .success(nil): self.status = .noLyrics
                case .success(let lyrics?):
                    self.lyrics = lyrics
                    self.status = lyrics.instrumental ? .instrumental : .noLyrics
                }
            }
        }
    }
}
