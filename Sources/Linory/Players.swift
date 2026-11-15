import AppKit
import LyricsCore

protocol MediaPlayer {
    var source: PlayerSource { get }
    /// `.success(nil)` means the player is stopped. Only call while the player is running.
    func read() -> Result<PlaybackSnapshot?, StatusMessage>
}

extension MediaPlayer {
    /// Checked before every read: talking to a player via AppleScript would launch it.
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty }

    /// Runs a script returning {id, name, artist, album, duration, position, playing} or {"stopped"}.
    func run(_ script: String, durationScale: Double) -> Result<PlaybackSnapshot?, StatusMessage> {
        var error: NSDictionary?
        guard let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&error) else {
            let number = error?[NSAppleScript.errorNumber] as? Int
            let detail = error?[NSAppleScript.errorMessage] as? String ?? "\(number ?? 0)"
            switch number {
            case -1743: return .failure(.automationDenied(source))
            case -1728: return .failure(.noTrack(source)) // no readable current track, e.g. a radio stream
            default: return .failure(.playerError(source, detail))
            }
        }
        if descriptor.numberOfItems == 1, descriptor.atIndex(1)?.stringValue == "stopped" { return .success(nil) }
        guard descriptor.numberOfItems >= 7,
              let id = descriptor.atIndex(1)?.stringValue,
              let title = descriptor.atIndex(2)?.stringValue,
              let artist = descriptor.atIndex(3)?.stringValue,
              let duration = descriptor.atIndex(5), let position = descriptor.atIndex(6) else {
            return .failure(.noTrack(source))
        }
        let album = descriptor.atIndex(4)?.stringValue ?? ""
        let track = Track(source: source, rawID: id, title: title, artist: artist, album: album, duration: duration.doubleValue * durationScale)
        return .success(PlaybackSnapshot(track: track, position: position.doubleValue, playing: descriptor.atIndex(7)?.booleanValue ?? false))
    }
}

struct SpotifyPlayer: MediaPlayer {
    let source = PlayerSource.spotify
    func read() -> Result<PlaybackSnapshot?, StatusMessage> {
        run("""
        if application id "com.spotify.client" is not running then return {"stopped"}
        tell application id "com.spotify.client"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {id of t, name of t, artist of t, album of t, duration of t, player position, (player state is playing)}
        end tell
        """, durationScale: 0.001) // Spotify reports milliseconds
    }
}

struct MusicPlayer: MediaPlayer {
    let source = PlayerSource.music
    func read() -> Result<PlaybackSnapshot?, StatusMessage> {
        run("""
        if application id "com.apple.Music" is not running then return {"stopped"}
        tell application id "com.apple.Music"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {persistent ID of t, name of t, artist of t, album of t, duration of t, player position, (player state is playing)}
        end tell
        """, durationScale: 1)
    }
}

/// A fresh position with the moment it was true.
struct PositionSample {
    let position: Double
    let sampledAt: Date
    let readTime: TimeInterval
}

/// Transport commands from the mini-player and lyric clicks.
enum PlayerCommand {
    case playPause, next, previous
    case seek(Double)

    var script: String {
        switch self {
        case .playPause: return "playpause"
        case .next: return "next track"
        case .previous: return "previous track"
        case .seek(let seconds): return "set player position to \(max(0, seconds))"
        }
    }
}

extension MediaPlayer {
    /// A single Apple event, so the midpoint of the call is when the player sampled its position.
    /// The full `read()` sends seven events and its position lands near the end of the call (measured), so its
    /// midpoint would put the lyrics about 40 ms ahead.
    func readPosition() -> PositionSample? {
        let script = """
        if application id "\(source.bundleID)" is not running then return -1
        tell application id "\(source.bundleID)" to return player position
        """
        var error: NSDictionary?
        let start = Date()
        guard let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&error) else { return nil }
        let end = Date()
        let position = descriptor.doubleValue
        guard position >= 0 else { return nil }
        let readTime = end.timeIntervalSince(start)
        return PositionSample(position: position, sampledAt: start.addingTimeInterval(readTime / 2), readTime: readTime)
    }

    /// Like reading, never launches the player: commands to a player that is not running are dropped.
    @discardableResult
    func perform(_ command: PlayerCommand) -> Bool {
        guard isRunning else { return false }
        var error: NSDictionary?
        return NSAppleScript(source: "tell application id \"\(source.bundleID)\" to \(command.script)")?.executeAndReturnError(&error) != nil
    }
}

/// Spotify write commands, used only by True Shuffle.
enum SpotifyControl {
    private static let queue = DispatchQueue(label: "spotify-control")
    private static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: PlayerSource.spotify.bundleID).isEmpty }

    /// Unlike reading, this may launch Spotify: the user explicitly asked to play.
    /// Shuffle and repeat are set again after `play`, because Spotify can restore a context's own setting when it starts.
    static func playPlaylist(id: String) async throws {
        try await launchIfNeeded()
        try await run("""
        tell application id "com.spotify.client"
            set shuffling to false
            set repeating to false
            play track "spotify:playlist:\(id)"
            delay 0.5
            set shuffling to false
            set repeating to false
        end tell
        """)
    }

    static func launchIfNeeded() async throws {
        if !isRunning {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: PlayerSource.spotify.bundleID) else {
                throw StatusMessage.playerError(.spotify, "Spotify is not installed.")
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            for _ in 0..<20 where !isRunning { try await Task.sleep(nanoseconds: 500_000_000) }
            guard isRunning else { throw StatusMessage.playerError(.spotify, "Spotify did not start.") }
            // A freshly started Spotify ignores AppleScript for a moment.
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    static func nextTrack() async throws {
        guard isRunning else { return }
        try await run(#"tell application id "com.spotify.client" to next track"#)
    }

    private static func run(_ source: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                var error: NSDictionary?
                if NSAppleScript(source: source)?.executeAndReturnError(&error) != nil { return continuation.resume() }
                let number = error?[NSAppleScript.errorNumber] as? Int
                let detail = error?[NSAppleScript.errorMessage] as? String ?? "\(number ?? 0)"
                continuation.resume(throwing: number == -1743 ? StatusMessage.automationDenied(.spotify) : StatusMessage.playerError(.spotify, detail))
            }
        }
    }
}

/// Cover art for the current track: Spotify gives a CDN link, Music gives the image bytes.
enum Artwork {
    case url(URL)
    case data(Data)
}

extension MediaPlayer {
    /// Read once per track change. Returns nil for tracks without artwork (or when the player quit meanwhile).
    func readArtwork() -> Artwork? {
        guard isRunning else { return nil }
        let script: String
        switch source {
        case .spotify:
            script = """
            if application id "com.spotify.client" is not running then return ""
            tell application id "com.spotify.client" to return artwork url of current track
            """
        case .music:
            script = """
            if application id "com.apple.Music" is not running then return ""
            tell application id "com.apple.Music" to return raw data of artwork 1 of current track
            """
        }
        var error: NSDictionary?
        guard let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&error) else { return nil }
        if source == .spotify {
            return descriptor.stringValue.flatMap { URL(string: $0) }.map(Artwork.url)
        }
        let data = descriptor.data
        return data.isEmpty ? nil : .data(data)
    }
}
