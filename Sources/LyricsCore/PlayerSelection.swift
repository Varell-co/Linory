import Foundation

public enum SourcePreference: String, CaseIterable {
    case auto, spotify, music

    public var source: PlayerSource? {
        switch self {
        case .auto: return nil
        case .spotify: return .spotify
        case .music: return .music
        }
    }
}

public struct PlayerState: Equatable {
    public let running: Bool
    public let playing: Bool
    public init(running: Bool, playing: Bool) { self.running = running; self.playing = playing }
}

public enum PlayerSelection {
    /// Auto keeps the current player while it plays, so two playing apps do not flip the overlay back and forth.
    public static func choose(preference: SourcePreference, states: [PlayerSource: PlayerState], current: PlayerSource?) -> PlayerSource? {
        func state(_ source: PlayerSource) -> PlayerState { states[source] ?? PlayerState(running: false, playing: false) }
        if let manual = preference.source { return state(manual).running ? manual : nil }
        let order = PlayerSource.allCases
        if let current, state(current).playing { return current }
        if let playing = order.first(where: { state($0).playing }) { return playing }
        if let current, state(current).running { return current }
        return order.first { state($0).running }
    }
}
