import AppKit
import LyricsCore
import os

/// Sleep timer: pauses Spotify or Music after a set time or at the end of the current track. Pausing only; Linory
/// never stops, fades or otherwise touches the audio.
@MainActor
final class SleepTimerController: ObservableObject {
    static let shared = SleepTimerController()

    @Published private(set) var timer: SleepTimer?
    /// Seconds until the pause, refreshed twice a second while a timer runs.
    @Published private(set) var remaining: TimeInterval?
    private var ticker: Timer?
    private weak var model: PlayerModel?
    private static let queue = DispatchQueue(label: "sleep-timer")
    private let log = Logger(subsystem: LyricsService.subsystem, category: "sleep")

    /// nil turns the timer off.
    func start(_ mode: SleepTimer.Mode?, model: PlayerModel) {
        ticker?.invalidate()
        ticker = nil
        self.model = model
        timer = mode.flatMap { SleepTimer($0, now: Date(), trackID: model.track?.id) }
        remaining = nil
        guard timer != nil else { return }
        tick()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let timer, let model else { return }
        let now = Date()
        let track = model.track
        let trackRemaining = track.map { $0.duration - model.clock.position(at: now) } ?? 0
        let left = timer.remaining(now: now, trackID: track?.id, trackRemaining: trackRemaining)
        remaining = left
        guard left <= 0 else { return }
        start(nil, model: model)
        // The player Linory shows; with none, every running one.
        let sources = track.map { [$0.source] } ?? PlayerSource.allCases
        log.info("pausing \(sources.map(\.rawValue).joined(separator: ","), privacy: .public)")
        let bundleIDs = sources.map(\.bundleID)
        Self.queue.async { bundleIDs.forEach { Self.pause(bundleID: $0) } }
    }

    /// Never launches a player: a player that is not running is already silent.
    private nonisolated static func pause(bundleID: String) {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return }
        var error: NSDictionary?
        NSAppleScript(source: #"tell application id "\#(bundleID)" to pause"#)?.executeAndReturnError(&error)
        if let error {
            Logger(subsystem: LyricsService.subsystem, category: "sleep").error("pause failed: \(error[NSAppleScript.errorNumber] as? Int ?? 0)")
        }
    }
}
