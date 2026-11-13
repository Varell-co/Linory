import Foundation

/// Extrapolates the playback position between player polls, so the highlight is not tied to the poll rate.
public struct PlaybackClock: Equatable {
    /// Backward corrections smaller than this are treated as poll jitter and ignored, so the highlight never flickers back.
    public static let jitterTolerance: Double = 0.3

    public private(set) var anchorPosition: Double = 0
    public private(set) var anchorDate: Date = .distantPast
    public private(set) var playing = false
    public private(set) var duration: Double = 0

    public init() {}

    public func position(at now: Date) -> Double {
        guard playing else { return anchorPosition }
        let position = anchorPosition + max(0, now.timeIntervalSince(anchorDate))
        return duration > 0 ? min(position, duration) : position
    }

    public mutating func update(position: Double, playing: Bool, duration: Double, at now: Date) {
        let predicted = self.position(at: now)
        let behind = predicted - position
        let isJitter = self.playing && playing && behind > 0 && behind < Self.jitterTolerance
        self.duration = duration
        if !isJitter {
            anchorPosition = position
            anchorDate = now
        }
        self.playing = playing
    }

    public mutating func reset() { self = PlaybackClock() }
}
