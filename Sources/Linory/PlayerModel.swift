import AppKit
import LyricsCore
import os

final class PlayerModel: ObservableObject {
    @Published var track: Track?
    @Published var lyrics: LoadedLyrics? {
        didSet { chorusStarts = lyrics?.synced == true ? Chorus.starts(in: lyrics?.lines ?? []) : [] }
    }
    /// Empty unless the lyrics are synced and a repeated group of lines was found.
    @Published private(set) var chorusStarts: [TimeInterval] = []
    @Published var artwork: NSImage?
    @Published var clock = PlaybackClock()
    @Published var status: StatusMessage = .waitingForPlayer
    /// Starts at launch, so auto-hide also waits the grace period before hiding an idle overlay.
    @Published var notPlayingSince: Date? = Date()
    /// Liked state for the mini-player's heart; the app delegate hands it the Spotify login.
    let library = SpotifyLibrary()
    /// Called on the main thread after the current track changes.
    var onTrackChange: ((Track) -> Void)?
    private var generation = 0
    private var pending = false
    /// Something changed while a read was in flight, so its result may already be stale: read again after it.
    private var repoll = false
    /// Bumped by every seek, so reads that started before it cannot drag the clock back.
    private var seekEpoch = 0
    private let queue = DispatchQueue(label: "player-reader")
    private static let players: [MediaPlayer] = [SpotifyPlayer(), MusicPlayer()]
    private var currentSource: PlayerSource?
    private let log = Logger(subsystem: LyricsService.subsystem, category: "player")
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let service: LyricsService = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return LyricsService(userAgent: "Linory/\(version) (https://github.com/MikeLeonFox/LyricsOverlay)")
    }()

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.poll() }
        // Both players announce track changes, play and pause; polling alone noticed them up to 0.8 s late.
        // Spotify posts nothing for seeks made in Spotify itself, so those still wait for the next poll.
        let center = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.poll() })
        }
    }

    // MARK: Control

    func send(_ command: PlayerCommand) {
        guard let player = currentPlayer else { return }
        queue.async { player.perform(command) }
        // Queued behind the command, so it reads the result.
        poll()
    }

    /// `position` is player time. The clock jumps there at once and holds until the player has caught up.
    func seek(to position: Double) {
        guard let player = currentPlayer, track != nil else { return }
        seekEpoch += 1
        clock.seek(to: position, at: Date())
        let target = clock.anchorPosition
        queue.async { player.perform(.seek(target)) }
        poll()
    }

    /// Seeks so that the lyrics show `time`. The timing offset shifts lyrics earlier, so the player goes there earlier too.
    /// The extra 10 ms keeps rounding from landing just before the line.
    func seek(toLyricTime time: TimeInterval) {
        seek(to: time - UserDefaults.standard.double(forKey: "offset") + 0.01)
    }

    func jumpToChorus() {
        let now = clock.position(at: Date()) + UserDefaults.standard.double(forKey: "offset")
        if let start = Chorus.next(after: now, starts: chorusStarts) { seek(toLyricTime: start) }
    }

    private var currentPlayer: MediaPlayer? {
        guard let source = track?.source ?? currentSource else { return nil }
        return Self.players.first { $0.source == source }
    }

    // MARK: Reading

    private struct Sample {
        let snapshot: PlaybackSnapshot
        /// When the player reported the position, not when the read returned.
        let sampledAt: Date
        let readTime: TimeInterval
    }

    private func poll() {
        guard !pending else { repoll = true; return }
        pending = true
        let preference = SourcePreference(rawValue: UserDefaults.standard.string(forKey: "source") ?? "") ?? .auto
        let current = currentSource
        let epoch = seekEpoch
        queue.async { [weak self] in
            let (chosen, result) = Self.read(preference: preference, current: current)
            DispatchQueue.main.async {
                guard let self else { return }
                self.pending = false
                defer { self.pollAgainIfNeeded() }
                // Read before a seek reached the player: drop it, the next read sees the new position.
                guard epoch == self.seekEpoch else { self.repoll = true; return }
                if chosen != self.currentSource {
                    self.log.info("source \(preference.rawValue, privacy: .public) → \(chosen?.rawValue ?? "none", privacy: .public)")
                    self.currentSource = chosen
                }
                switch result {
                case .failure(let status): self.clear(status)
                case .success(nil): self.clear(chosen.map { .noTrack($0) } ?? .openPlayer)
                case .success(let sample?): self.update(sample)
                }
            }
        }
    }

    /// After a seek, reads back to back until the player is playing from the target again.
    private func pollAgainIfNeeded() {
        if repoll {
            repoll = false
            poll()
        } else if clock.pendingSeek != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.poll() }
        }
    }

    /// Reads every candidate player that is running (never launching one) and picks per the preference.
    private static func read(preference: SourcePreference, current: PlayerSource?) -> (PlayerSource?, Result<Sample?, StatusMessage>) {
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
        return (chosen, result.map { snapshot in
            guard let snapshot else { return nil }
            // A paused position does not move, so only a playing one needs a precise time.
            guard snapshot.playing, let fresh = players.first(where: { $0.source == chosen })?.readPosition() else {
                return Sample(snapshot: snapshot, sampledAt: Date(), readTime: 0)
            }
            return Sample(snapshot: PlaybackSnapshot(track: snapshot.track, position: fresh.position, playing: true),
                          sampledAt: fresh.sampledAt, readTime: fresh.readTime)
        })
    }

    private func loadArtwork(for track: Track, generation requested: Int) {
        guard let player = Self.players.first(where: { $0.source == track.source }) else { return }
        let publish: (NSImage?) -> Void = { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { return }
                self.artwork = image
            }
        }
        queue.async {
            switch player.readArtwork() {
            case .data(let data)?: publish(NSImage(data: data))
            case .url(let url)?:
                URLSession.shared.dataTask(with: url) { data, _, _ in publish(data.flatMap(NSImage.init(data:))) }.resume()
            case nil: publish(nil)
            }
        }
    }

    private func clear(_ message: StatusMessage) {
        if track != nil { generation += 1 }
        track = nil; lyrics = nil; artwork = nil; clock.reset(); status = message
        if notPlayingSince == nil { notPlayingSince = Date() }
    }

    private func update(_ sample: Sample) {
        let snapshot = sample.snapshot
        if track != snapshot.track {
            clock.reset()
        } else if clock.playing, snapshot.playing, clock.pendingSeek == nil {
            // What the overlay showed at the moment the player reported its position. Positive: lyrics ahead.
            let drift = (clock.position(at: sample.sampledAt) - snapshot.position) * 1000
            log.debug("drift \(Int(drift.rounded())) ms, read \(Int(sample.readTime * 1000)) ms")
        }
        clock.update(position: snapshot.position, playing: snapshot.playing, duration: snapshot.track.duration, at: sample.sampledAt)
        if snapshot.playing { notPlayingSince = nil } else if notPlayingSince == nil { notPlayingSince = Date() }
        guard track != snapshot.track else { return }
        track = snapshot.track
        onTrackChange?(snapshot.track)
        lyrics = nil
        artwork = nil
        status = .searching
        generation += 1
        let requestedGeneration = generation
        let track = snapshot.track
        loadArtwork(for: track, generation: requestedGeneration)
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
