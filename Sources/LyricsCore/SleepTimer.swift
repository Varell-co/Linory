import Foundation

/// Pauses the player after a set time or at the end of the current track. Pure: the app polls `remaining` and pauses
/// when it reaches zero.
public struct SleepTimer: Equatable {
    public enum Mode: Hashable {
        case minutes(Int)
        case endOfTrack
    }

    public static let presets = [15, 30, 45, 60]
    /// Polling is not exact, so the end of a track is caught slightly early rather than after the next one started.
    public static let endOfTrackLead: TimeInterval = 0.6

    public let mode: Mode
    let deadline: Date
    /// The track playing when "end of track" was chosen.
    let trackID: String?

    /// nil for "end of track" without a playing track.
    public init?(_ mode: Mode, now: Date, trackID: String?) {
        switch mode {
        case .minutes(let minutes):
            deadline = now.addingTimeInterval(TimeInterval(minutes) * 60)
        case .endOfTrack:
            guard trackID != nil else { return nil }
            deadline = .distantFuture
        }
        self.mode = mode
        self.trackID = trackID
    }

    /// Seconds until the pause; 0 means pause now. For "end of track", `trackRemaining` is the time left in the
    /// current track; a different track (or none) means the original one ended.
    public func remaining(now: Date, trackID current: String?, trackRemaining: TimeInterval) -> TimeInterval {
        switch mode {
        case .minutes:
            return max(0, deadline.timeIntervalSince(now))
        case .endOfTrack:
            guard current == trackID else { return 0 }
            return trackRemaining <= Self.endOfTrackLead ? 0 : trackRemaining
        }
    }

    /// `12:05` or `1:02:05`.
    public static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}
