import Foundation

/// Extrapolates the playback position between player polls, so the highlight is not tied to the poll rate.
/// Samples must be dated with the moment the player reported them, not when they arrived.
public struct PlaybackClock: Equatable {
    /// A clock running ahead of the player by less than this is slewed back instead of jumping, so the highlight
    /// never flickers back. Anything larger is a real seek and jumps.
    public static let slewTolerance: Double = 0.3
    /// How long a slew takes. Longer than `slewTolerance`, so the clock slows down but never runs backwards.
    public static let slewDuration: Double = 0.6
    /// How long the clock waits for the player to confirm a seek before trusting samples again.
    public static let seekTimeout: Double = 1.5

    public private(set) var anchorPosition: Double = 0
    public private(set) var anchorDate: Date = .distantPast
    public private(set) var playing = false
    public private(set) var duration: Double = 0
    /// Seconds the clock is ahead at `anchorDate`, removed linearly over `slewDuration`.
    public private(set) var slew: Double = 0
    /// Target of a seek the player has not confirmed yet. Players buffer briefly after a seek and report the
    /// target without moving, so the clock holds there instead of running ahead of the music.
    public private(set) var pendingSeek: Double?

    public init() {}

    public func position(at now: Date) -> Double {
        guard playing, pendingSeek == nil else { return anchorPosition }
        let elapsed = max(0, now.timeIntervalSince(anchorDate))
        let position = anchorPosition + elapsed - slew * min(1, elapsed / Self.slewDuration)
        return duration > 0 ? min(position, duration) : position
    }

    /// `now` is when the player sampled `position`.
    public mutating func update(position: Double, playing: Bool, duration: Double, at now: Date) {
        self.duration = duration
        if let target = pendingSeek {
            let sinceSeek = now.timeIntervalSince(anchorDate)
            if sinceSeek < Self.seekTimeout {
                // Before the player applied the seek, it still reports the old position.
                let moved = position - target
                if moved < -0.05 || moved > max(0, sinceSeek) + 0.1 { return }
                // Still buffering at the target: hold.
                if playing && moved < 0.02 { self.playing = true; return }
            }
            pendingSeek = nil
            anchor(position, at: now)
            self.playing = playing
            return
        }
        let predicted = self.position(at: now)
        let ahead = predicted - position
        if self.playing && playing && ahead > 0 && ahead < Self.slewTolerance {
            // Continue from what is on screen and catch up with the player over the next moment.
            anchor(predicted, at: now)
            slew = ahead
        } else {
            anchor(position, at: now)
        }
        self.playing = playing
    }

    /// A seek the app asked for: shows the target at once and holds it until the player confirms it.
    public mutating func seek(to position: Double, at now: Date) {
        anchor(duration > 0 ? min(max(0, position), duration) : max(0, position), at: now)
        pendingSeek = anchorPosition
    }

    public mutating func reset() { self = PlaybackClock() }

    private mutating func anchor(_ position: Double, at date: Date) {
        anchorPosition = position
        anchorDate = date
        slew = 0
    }
}
