import Foundation

/// Per-song timing correction, added to the global offset. Positive values show the lyrics earlier.
public enum TrackTiming {
    public static let step = 0.25
    public static let limit = 10.0

    public static func key(for trackID: String) -> String { "trackOffset.\(trackID)" }

    /// Moves `value` by whole steps, snapped to the step grid and kept within ±`limit`.
    public static func nudged(_ value: Double, by steps: Int) -> Double {
        let snapped = ((value / step).rounded() + Double(steps)) * step
        return min(limit, max(-limit, snapped))
    }

    public static func format(_ value: Double) -> String {
        value == 0 ? "0 s" : String(format: "%+.2f s", value).replacingOccurrences(of: "-", with: "−")
    }
}
