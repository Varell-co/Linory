import AppKit
import LyricsCore
import os

final class PlayerModel: ObservableObject {
    @Published var track: Track?
    @Published var lyrics: LoadedLyrics?
    @Published var clock = PlaybackClock()
    @Published var status: StatusMessage = .waitingForPlayer
    /// Starts at launch, so auto-hide also waits the grace period before hiding an idle overlay.
    @Published var notPlayingSince: Date? = Date()
    private var generation = 0
    private var pending = false
    private let queue = DispatchQueue(label: "player-reader")
    private static let players: [MediaPlayer] = [SpotifyPlayer(), MusicPlayer()]
    private var currentSource: PlayerSource?
    private let log = Logger(subsystem: LyricsService.subsystem, category: "player")
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
        let preference = SourcePreference(rawValue: UserDefaults.standard.string(forKey: "source") ?? "") ?? .auto
        let current = currentSource
        queue.async { [weak self] in
            let (chosen, result) = Self.read(preference: preference, current: current)
            DispatchQueue.main.async {
                guard let self else { return }
                self.pending = false
                if chosen != self.currentSource {
                    self.log.info("source \(preference.rawValue, privacy: .public) → \(chosen?.rawValue ?? "none", privacy: .public)")
                    self.currentSource = chosen
                }
                switch result {
                case .failure(let status): self.clear(status)
                case .success(nil): self.clear(chosen.map { .noTrack($0) } ?? .openPlayer)
                case .success(let snapshot?): self.update(snapshot)
                }
            }
        }
    }

    /// Reads every candidate player that is running (never launching one) and picks per the preference.
    private static func read(preference: SourcePreference, current: PlayerSource?) -> (PlayerSource?, Result<PlaybackSnapshot?, StatusMessage>) {
        let candidates = players.filter { preference.source == nil || $0.source == preference.source }
        var states: [PlayerSource: PlayerState] = [:]
        var results: [PlayerSource: Result<PlaybackSnapshot?, StatusMessage>] = [:]
        for player in candidates where player.isRunning {
            let result = player.read()
            results[player.source] = result
            let playing = (try? result.get())??.playing ?? false
            states[player.source] = PlayerState(running: true, playing: playing)
        }
        guard let chosen = PlayerSelection.choose(preference: preference, states: states, current: current),
              let result = results[chosen] else { return (nil, .failure(.openPlayer)) }
        return (chosen, result)
    }

    private func clear(_ message: StatusMessage) {
        if track != nil { generation += 1 }
        track = nil; lyrics = nil; clock.reset(); status = message
        if notPlayingSince == nil { notPlayingSince = Date() }
    }

    private func update(_ snapshot: PlaybackSnapshot) {
        if track != snapshot.track { clock.reset() }
        clock.update(position: snapshot.position, playing: snapshot.playing, duration: snapshot.track.duration, at: Date())
        if snapshot.playing { notPlayingSince = nil } else if notPlayingSince == nil { notPlayingSince = Date() }
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
