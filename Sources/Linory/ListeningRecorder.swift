import Foundation
import LyricsCore
import os

/// Keeps Linory's own listening history: one JSON line per song heard, in Application Support. Never uploaded.
@MainActor
final class ListeningRecorder: ObservableObject {
    static let enabledKey = "listeningHistory"

    @Published private(set) var sessions: [ListenSession] = []
    /// Bumped every few seconds while something plays, so an open stats window counts the current song live.
    @Published private(set) var revision = 0
    private var tracker = ListeningTracker()
    private var ticks = 0
    private weak var model: PlayerModel?
    private let fileURL: URL
    private let log = Logger(subsystem: LyricsService.subsystem, category: "history")

    nonisolated init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = support.appendingPathComponent(LyricsService.subsystem, isDirectory: true).appendingPathComponent("history.jsonl")
    }

    private var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    func attach(_ model: PlayerModel) {
        self.model = model
        load()
    }

    /// Sessions including the song playing now.
    var allSessions: [ListenSession] {
        guard let current = tracker.current, current.listened >= ListeningTracker.minimum else { return sessions }
        return sessions + [current]
    }

    /// Called after every player poll.
    func tick() {
        guard enabled else {
            tracker = ListeningTracker() // turning history off drops the song in progress too
            return
        }
        guard let model else { return }
        let now = Date()
        let synced = model.lyrics?.synced == true && model.lyrics?.lines.isEmpty == false
        if let finished = tracker.tick(track: model.track, position: model.clock.position(at: now),
                                       playing: model.clock.playing, syncedLyrics: synced, at: now) {
            append(finished)
        }
        ticks += 1
        if ticks % 6 == 0, model.clock.playing { revision += 1 }
    }

    /// At quit, so the last song is kept.
    func flush() {
        if enabled, let finished = tracker.finish() { append(finished) }
    }

    func clear() {
        tracker = ListeningTracker()
        sessions = []
        try? FileManager.default.removeItem(at: fileURL)
        log.info("history cleared")
    }

    private func append(_ session: ListenSession) {
        sessions.append(session)
        do {
            var line = try Self.encoder.encode(session)
            line.append(0x0A)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: fileURL, options: .atomic)
            }
        } catch {
            log.error("history write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One session per line, so a crash mid-write loses at most that line; unreadable lines are skipped.
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        sessions = data.split(separator: 0x0A).compactMap { try? Self.decoder.decode(ListenSession.self, from: Data($0)) }
        log.info("history loaded: \(self.sessions.count) sessions")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    #if DEBUG
    /// Debug snapshots only.
    func previewSessions(_ sessions: [ListenSession]) { self.sessions = sessions }
    #endif
}
