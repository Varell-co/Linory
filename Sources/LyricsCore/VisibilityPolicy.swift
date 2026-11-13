import Foundation

public enum VisibilityPolicy {
    /// How long the overlay stays up after playback stops before auto-hide kicks in.
    public static let grace: TimeInterval = 3

    /// A manual hide always wins. With auto-hide on, the overlay shows while playing and for a short grace period after.
    public static func shouldShow(userHidden: Bool, autoHide: Bool, playing: Bool, hasTrack: Bool, notPlayingSince: Date?, now: Date) -> Bool {
        guard !userHidden else { return false }
        guard autoHide else { return true }
        if hasTrack && playing { return true }
        return notPlayingSince.map { now.timeIntervalSince($0) < grace } ?? false
    }
}
