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
