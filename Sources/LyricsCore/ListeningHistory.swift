import Foundation

/// One song as it was heard: how long it actually played, not how long it is. Stored on this Mac only.
public struct ListenSession: Codable, Equatable {
    /// `Track.id`, so the same song in two players stays two entries.
    public let trackID: String
    /// `spotify:track:…` for Spotify, nil for Music; links rows back to Spotify.
    public let uri: String?
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double
    public let start: Date
    /// Seconds actually played: pauses and seeks don't count.
    public internal(set) var listened: Double
    public internal(set) var syncedLyrics: Bool

    public init(track: Track, start: Date, listened: Double = 0, syncedLyrics: Bool = false) {
        trackID = track.id
        uri = track.source == .spotify && track.rawID.hasPrefix("spotify:track:") ? track.rawID : nil
        title = track.title; artist = track.artist; album = track.album; duration = track.duration
        self.start = start; self.listened = listened; self.syncedLyrics = syncedLyrics
    }

    /// Spotify's rule of thumb: 30 s, or half of a shorter song.
    public var countsAsPlay: Bool { listened >= min(30, duration * 0.5) }
    /// Left before it counted as a play. Very short songs can't be skipped.
    public var skipped: Bool { !countsAsPlay && duration > 45 }
}

/// Turns the player model's polls into sessions. Pure: the app feeds it and stores what it returns.
public struct ListeningTracker {
    /// A longer gap between polls (sleep, a hung player) is not counted as listening.
    public static let maxGap: TimeInterval = 5
    /// Sessions under a second are noise from skipping through tracks.
    public static let minimum: TimeInterval = 1

    public private(set) var current: ListenSession?
    private var lastTick: Date?
    private var lastPosition: Double = 0

    public init() {}

    /// Returns the session that just ended, if any: on a track change, or when a repeated song starts over.
    public mutating func tick(track: Track?, position: Double, playing: Bool, syncedLyrics: Bool, at now: Date) -> ListenSession? {
        var finished: ListenSession?
        let restarted = current != nil && track?.id == current?.trackID
            && lastPosition > (track?.duration ?? 0) - 5 && position < 5 && (track?.duration ?? 0) > 10
        if track?.id != current?.trackID || restarted {
            finished = finish()
            if let track { current = ListenSession(track: track, start: now) }
        } else if playing, let lastTick {
            current?.listened += min(max(0, now.timeIntervalSince(lastTick)), Self.maxGap)
        }
        if syncedLyrics { current?.syncedLyrics = true }
        lastTick = now
        lastPosition = position
        return finished
    }

    /// Ends the current session, for example when Linory quits.
    public mutating func finish() -> ListenSession? {
        defer { current = nil; lastTick = nil; lastPosition = 0 }
        guard let current, current.listened >= Self.minimum else { return nil }
        return current
    }
}

// MARK: Stats

public enum ListeningRange: String, CaseIterable {
    case today, week, month, year, all
}

public struct ListeningSummary: Equatable {
    public struct Entry: Equatable, Identifiable {
        public let id: String
        public let title: String
        public let subtitle: String
        public let uri: String?
        public let seconds: Double
        public let plays: Int
    }

    public enum Unit: Equatable { case hour, day, month }

    public struct Bucket: Equatable, Identifiable {
        public let start: Date
        public let seconds: Double
        public var id: Date { start }
    }

    public var seconds: Double = 0
    public var plays = 0
    public var skips = 0
    /// Of all sessions in the range: skipped ones, 0...1.
    public var skipRate: Double = 0
    /// Of plays in the range: with synced lyrics, 0...1.
    public var syncedShare: Double = 0
    /// Days in a row with at least a minute of listening, up to today (or yesterday, if today is still empty).
    public var streakDays = 0
    public var topTracks: [Entry] = []
    public var topArtists: [Entry] = []
    /// Listening over time, oldest first: hours for today, days for a week or month, months beyond.
    public var buckets: [Bucket] = []
    public var unit: Unit = .day
    /// Seconds per weekday (Monday first) and hour.
    public var clock: [[Double]] = Array(repeating: Array(repeating: 0, count: 24), count: 7)
}

public enum ListeningStats {
    public static let topCount = 10

    public static func start(of range: ListeningRange, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch range {
        case .today: return today
        case .week: return calendar.date(byAdding: .day, value: -6, to: today)
        case .month: return calendar.date(byAdding: .day, value: -29, to: today)
        case .year: return calendar.date(byAdding: .month, value: -11, to: calendar.dateInterval(of: .month, for: now)?.start ?? today)
        case .all: return nil
        }
    }

    public static func summarize(_ sessions: [ListenSession], range: ListeningRange, now: Date, calendar: Calendar) -> ListeningSummary {
        var summary = ListeningSummary()
        summary.streakDays = streak(sessions, now: now, calendar: calendar)
        let from = start(of: range, now: now, calendar: calendar)
        let inRange = sessions.filter { session in session.start <= now && (from.map { session.start >= $0 } ?? true) }

        let plays = inRange.filter(\.countsAsPlay)
        summary.seconds = inRange.reduce(0) { $0 + $1.listened }
        summary.plays = plays.count
        summary.skips = inRange.filter(\.skipped).count
        summary.skipRate = inRange.isEmpty ? 0 : Double(summary.skips) / Double(inRange.count)
        summary.syncedShare = plays.isEmpty ? 0 : Double(plays.filter(\.syncedLyrics).count) / Double(plays.count)

        summary.topTracks = top(inRange, key: \.trackID) { session in (session.title, session.artist, session.uri) }
        summary.topArtists = top(inRange, key: { $0.artist.lowercased() }) { session in (session.artist, "", nil) }

        for session in inRange {
            let weekday = (calendar.component(.weekday, from: session.start) + 5) % 7 // Monday = 0
            summary.clock[weekday][calendar.component(.hour, from: session.start)] += session.listened
        }

        let (unit, starts) = bucketStarts(range: range, from: from ?? inRange.map(\.start).min() ?? now, now: now, calendar: calendar)
        summary.unit = unit
        let component: Calendar.Component = unit == .hour ? .hour : unit == .day ? .day : .month
        var seconds = Array(repeating: 0.0, count: starts.count)
        for session in inRange {
            guard let bucketStart = calendar.dateInterval(of: component, for: session.start)?.start,
                  let index = starts.firstIndex(of: bucketStart) else { continue }
            seconds[index] += session.listened
        }
        summary.buckets = zip(starts, seconds).map { ListeningSummary.Bucket(start: $0, seconds: $1) }
        return summary
    }

    /// Ranked by listening time; ties go to more plays, then the name.
    private static func top(_ sessions: [ListenSession], key: (ListenSession) -> String,
                            describe: (ListenSession) -> (String, String, String?)) -> [ListeningSummary.Entry] {
        var groups: [String: (first: ListenSession, seconds: Double, plays: Int)] = [:]
        for session in sessions {
            let id = key(session)
            let existing = groups[id] ?? (session, 0, 0)
            groups[id] = (existing.first, existing.seconds + session.listened, existing.plays + (session.countsAsPlay ? 1 : 0))
        }
        return groups
            .filter { $0.value.plays > 0 }
            .sorted { a, b in
                if a.value.seconds != b.value.seconds { return a.value.seconds > b.value.seconds }
                if a.value.plays != b.value.plays { return a.value.plays > b.value.plays }
                return a.key < b.key
            }
            .prefix(topCount)
            .map { id, group in
                let (title, subtitle, uri) = describe(group.first)
                return ListeningSummary.Entry(id: id, title: title, subtitle: subtitle, uri: uri, seconds: group.seconds, plays: group.plays)
            }
    }

    private static func bucketStarts(range: ListeningRange, from: Date, now: Date, calendar: Calendar) -> (ListeningSummary.Unit, [Date]) {
        func series(_ component: Calendar.Component, from start: Date) -> [Date] {
            guard let first = calendar.dateInterval(of: component, for: start)?.start else { return [] }
            var dates: [Date] = []
            var date = first
            while date <= now, dates.count < 400 {
                dates.append(date)
                guard let next = calendar.date(byAdding: component, value: 1, to: date) else { break }
                date = next
            }
            return dates
        }
        switch range {
        case .today: return (.hour, series(.hour, from: from).filter { calendar.isDate($0, inSameDayAs: now) })
        case .week, .month: return (.day, series(.day, from: from))
        case .year, .all: return (.month, series(.month, from: from))
        }
    }

    static func streak(_ sessions: [ListenSession], now: Date, calendar: Calendar) -> Int {
        var perDay: [Date: Double] = [:]
        for session in sessions { perDay[calendar.startOfDay(for: session.start), default: 0] += session.listened }
        let active = Set(perDay.filter { $0.value >= 60 }.keys)
        var day = calendar.startOfDay(for: now)
        if !active.contains(day), let yesterday = calendar.date(byAdding: .day, value: -1, to: day) { day = yesterday }
        var count = 0
        while active.contains(day), let previous = calendar.date(byAdding: .day, value: -1, to: day) {
            count += 1
            day = previous
        }
        return count
    }
}
