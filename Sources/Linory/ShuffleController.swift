import AppKit
import LyricsCore
import os

/// Opens a Spotify item (`spotify:track:…`, `spotify:artist:…`) in the Spotify app. Wherever Linory shows
/// Spotify metadata, it links back like this (Spotify Developer Policy).
enum SpotifyLink {
    static func open(_ uri: String) {
        guard let url = URL(string: uri) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// A shuffle source: Liked Songs (`name == nil`, localized at display time) or a playlist.
struct ShuffleSource: Identifiable, Hashable {
    let id: String
    let name: String?
}

/// One line under the Shuffle button. Rendered at display time so a language switch re-renders it.
enum ShuffleNotice: Equatable {
    case empty, auth, network, automation, premium, full
    case http(Int)
    case playback(String)
    case kept(String)

    var isError: Bool { if case .kept = self { return false } else { return true } }

    func text(language: AppLanguage) -> String {
        switch self {
        case .empty: return L10n.string(.shuffleEmpty, language: language)
        case .auth: return L10n.string(.shuffleErrorAuth, language: language)
        case .network: return L10n.string(.shuffleErrorNetwork, language: language)
        case .automation: return L10n.string(.shuffleErrorAutomation, language: language)
        case .premium: return L10n.string(.shuffleErrorPremium, language: language)
        case .full: return L10n.string(.shuffleFull, language: language)
        case .http(let status): return L10n.string(.shuffleErrorHTTP, status, language: language)
        case .playback(let detail): return L10n.string(.shuffleErrorPlayback, detail, language: language)
        case .kept(let name): return L10n.string(.shuffleKept, name, language: language)
        }
    }

    init(_ error: Error) {
        switch error {
        case SpotifyError.loginExpired, SpotifyError.notConnected: self = .auth
        case SpotifyError.http(403): self = .premium
        case SpotifyError.http(let status): self = .http(status)
        case StatusMessage.automationDenied: self = .automation
        case StatusMessage.playerError(_, let detail): self = .playback(detail)
        default: self = .network
        }
    }
}

enum ShuffleActivity: Equatable {
    case loading
    case shuffling(Int)
    case working
    /// Auto-continue is appending the next round.
    case continuing
}

/// True Shuffle: writes an honest, no-repeat order to one reused "Linory Shuffle" playlist that Spotify then plays.
@MainActor
final class ShuffleController: ObservableObject {
    @Published private(set) var sources = [ShuffleSource(id: ShuffleState.likedSourceID, name: nil)]
    @Published private(set) var activity: ShuffleActivity?
    @Published private(set) var notice: ShuffleNotice?
    /// The current track was confirmed to play from the Linory Shuffle playlist.
    @Published private(set) var currentInShuffle = false
    @Published private(set) var state: ShuffleState

    private let auth: SpotifyAuth
    private var api: SpotifyAPI { auth.api }
    private(set) var currentURI: String?
    private var loadingSources = false
    private let fileURL: URL
    private let log = Logger(subsystem: LyricsService.subsystem, category: "shuffle")
    /// Menu toggle, on by default: append the next round before the order runs out.
    static let autoContinueKey = "shuffleAutoContinue"
    private var autoContinue: Bool { UserDefaults.standard.object(forKey: Self.autoContinueKey) as? Bool ?? true }

    init(auth: SpotifyAuth) {
        self.auth = auth
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = support.appendingPathComponent(LyricsService.subsystem, isDirectory: true).appendingPathComponent("shuffle-state.json")
        state = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(ShuffleState.self, from: $0) } ?? ShuffleState()
    }

    var selectedSourceID: String { state.selectedSourceID ?? ShuffleState.likedSourceID }
    var selectedCycle: ShuffleCycle { state.cycles[selectedSourceID] ?? ShuffleCycle() }
    var hasShuffle: Bool { state.shufflePlaylistID != nil && state.activeSourceID != nil && !state.currentOrder.isEmpty }

    func select(_ id: String) {
        state.selectedSourceID = id
        notice = nil
        save()
    }

    func sourceName(_ id: String) -> String {
        let members = ShuffleMix.members(id)
        guard members.count > 1 else { return memberName(id) }
        return tr(.shuffleMixName, members.map(memberName).sorted().joined(separator: " + "))
    }

    private func memberName(_ id: String) -> String {
        if id == ShuffleState.likedSourceID { return tr(.shuffleSourceLiked) }
        return sources.first { $0.id == id }?.name ?? tr(.shufflePlaylistName)
    }

    /// A mix is usable while every member is still a readable source.
    func isAvailable(_ id: String) -> Bool {
        ShuffleMix.members(id).allSatisfy { member in sources.contains { $0.id == member } }
    }

    /// Mixes shuffled before, so the picker can return to them.
    var mixes: [ShuffleSource] {
        state.cycles.keys.filter { ShuffleMix.isMix($0) && isAvailable($0) }
            .map { ShuffleSource(id: $0, name: sourceName($0)) }
            .sorted { $0.name!.localizedStandardCompare($1.name!) == .orderedAscending }
    }

    var selectedMembers: Set<String> { Set(ShuffleMix.members(selectedSourceID)) }

    /// Adds or removes one source from the selection; the last member stays.
    func toggleMember(_ id: String) {
        var members = selectedMembers
        if members.contains(id) { guard members.count > 1 else { return }; members.remove(id) } else { members.insert(id) }
        if let mix = ShuffleMix.id(Array(members)) { select(mix) }
    }

    /// The next three tracks of the Linory Shuffle order after the one playing.
    var upNext: [(uri: String, info: ShuffleTrackInfo)] {
        guard currentInShuffle, let index = state.playingIndex else { return [] }
        return state.currentOrder.dropFirst(index + 1).prefix(3).compactMap { uri in state.trackInfo[uri].map { (uri, $0) } }
    }

    /// Runs when the menu section expands and on connect.
    func refreshSources() {
        auth.retryIfNeeded()
        guard auth.isConnected, let user = auth.user, !loadingSources else { return }
        loadingSources = true
        Task {
            defer { loadingSources = false }
            do { apply(try await api.ownPlaylists(userID: user.id)) } catch { notice = ShuffleNotice(error) }
        }
    }

    func shuffleAndPlay() {
        guard activity == nil, auth.isConnected, let user = auth.user else { return }
        let sourceID = selectedSourceID
        let previousActive = state.activeSourceID
        notice = nil
        activity = .loading
        // Stop counting the old order while it is replaced.
        state.activeSourceID = nil
        currentInShuffle = false
        Task {
            defer { activity = nil }
            do {
                async let sourceTracks = tracks(for: sourceID)
                let playlists = try await api.ownPlaylists(userID: user.id)
                apply(playlists)
                let tracks = try await sourceTracks

                var cycle = state.cycles[sourceID] ?? ShuffleCycle()
                let playedBefore = cycle.played.count
                var generator = SystemRandomNumberGenerator()
                let shuffled = cycle.nextOrder(from: tracks.map(\.uri), using: &generator)
                guard !shuffled.isEmpty else {
                    state.activeSourceID = previousActive
                    notice = .empty
                    return
                }
                if playedBefore > 0 && cycle.played.isEmpty { log.info("cycle complete for \(sourceID, privacy: .public), reset") }

                activity = .shuffling(shuffled.count)
                let order = await Self.spread(shuffled, tracks, after: nil)
                let playlistID = try await writeShufflePlaylist(order, existing: Set(playlists.map(\.id)))
                state.cycles[sourceID] = cycle
                state.currentOrder = order
                state.trackInfo = Self.info(tracks, for: order)
                state.playingIndex = nil
                state.activeSourceID = sourceID
                save()
                log.info("source \(sourceID, privacy: .public): \(cycle.total) eligible, \(order.count) unplayed, \(cycle.removed.count) removed → wrote \(order.count) to \(playlistID, privacy: .public)")
                try await startPlayback(playlistID)
            } catch {
                if state.activeSourceID == nil { state.activeSourceID = previousActive }
                notice = ShuffleNotice(error)
                log.error("shuffle failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Reuses the stored playlist while the user still has it; a playlist deleted in Spotify (unfollowed) is recreated.
    private func writeShufflePlaylist(_ uris: [String], existing: Set<String>) async throws -> String {
        if let id = state.shufflePlaylistID, existing.contains(id) {
            do {
                try await api.replaceItems(playlistID: id, uris: uris)
                return id
            } catch SpotifyError.http(404) {
                log.info("shuffle playlist gone, recreating")
            }
        }
        let id = try await api.createPlaylist(name: tr(.shufflePlaylistName), description: tr(.shufflePlaylistDescription))
        // Stored before writing, so a failed write does not create a second playlist next time.
        state.shufflePlaylistID = id
        save()
        sources.removeAll { $0.id == id }
        try await api.replaceItems(playlistID: id, uris: uris)
        return id
    }

    /// Through the Web API when the login allows it; AppleScript only as a fallback for older logins or no device.
    private func startPlayback(_ playlistID: String) async throws {
        try await SpotifyControl.launchIfNeeded()
        guard auth.canControlPlayback else {
            log.info("playback via AppleScript (login lacks playback scopes)")
            return try await SpotifyControl.playPlaylist(id: playlistID)
        }
        // A Spotify app that just started registers as a device a few seconds later.
        for attempt in 0..<6 {
            if let device = SpotifyDevice.preferred(try await api.devices()), let deviceID = device.id {
                log.info("playback via Web API on \(device.type, privacy: .public)")
                return try await api.playPlaylist(id: playlistID, deviceID: deviceID)
            }
            if attempt < 5 { try await Task.sleep(nanoseconds: 1_000_000_000) }
        }
        log.info("playback via AppleScript (no Spotify device found)")
        try await SpotifyControl.playPlaylist(id: playlistID)
    }

    func reset() {
        guard activity == nil else { return }
        state.cycles[selectedSourceID]?.reset()
        notice = nil
        save()
    }

    /// Counts a track as played only while Spotify's playing context is the Linory Shuffle playlist.
    func trackChanged(uri: String?) {
        currentURI = uri
        currentInShuffle = false
        guard let uri, let sourceID = state.activeSourceID, let playlistID = state.shufflePlaylistID,
              auth.isConnected, state.currentOrder.contains(uri) else { return }
        Task {
            // The Web API can trail AppleScript by a moment after a track change.
            for _ in 0..<3 {
                guard currentURI == uri else { return }
                guard let playing = try? await api.currentlyPlaying() else { return }
                guard playing.itemURI == uri else {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    continue
                }
                guard currentURI == uri, state.activeSourceID == sourceID else { return }
                if playing.isPlaylist(playlistID) {
                    state.cycles[sourceID, default: ShuffleCycle()].markPlayed(uri)
                    state.playingIndex = state.index(of: uri)
                    currentInShuffle = true
                    save()
                    log.info("played \(uri, privacy: .public) (context matches)")
                    if autoContinue, let index = state.playingIndex, state.needsNextRound(at: index) { continueRound(after: index) }
                } else {
                    log.info("ignored \(uri, privacy: .public) (context \(playing.contextURI ?? "none", privacy: .public))")
                }
                return
            }
            log.info("ignored \(uri, privacy: .public) (Spotify reported another track)")
        }
    }

    func removeCurrent() {
        guard activity == nil, currentInShuffle, let uri = currentURI,
              let sourceID = state.activeSourceID, let playlistID = state.shufflePlaylistID else { return }
        // The local removal stands even if Spotify cannot be updated.
        state.cycles[sourceID, default: ShuffleCycle()].remove(uri)
        state.currentOrder.removeAll { $0 == uri }
        state.trackInfo[uri] = nil
        save()
        currentInShuffle = false
        notice = nil
        activity = .working
        log.info("removed \(uri, privacy: .public) from \(sourceID, privacy: .public)")
        Task {
            defer { activity = nil }
            do { try await SpotifyControl.nextTrack() } catch { notice = ShuffleNotice(error) }
            do { try await api.removeItems(playlistID: playlistID, uris: [uri]) } catch { notice = ShuffleNotice(error) }
        }
    }

    func restoreRemoved() {
        guard activity == nil else { return }
        state.cycles[selectedSourceID]?.restoreRemoved()
        notice = nil
        save()
    }

    /// Copies the current order to a new private playlist that Linory never edits again.
    func keepShuffle() {
        guard activity == nil, hasShuffle, let sourceID = state.activeSourceID else { return }
        let removed = state.cycles[sourceID]?.removed ?? []
        let uris = state.currentOrder.filter { !removed.contains($0) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppLanguage.current == .de ? "de_DE" : "en_US")
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        let name = tr(.shuffleKeptName, sourceName(sourceID), formatter.string(from: Date()))
        notice = nil
        activity = .working
        Task {
            defer { activity = nil }
            do {
                let id = try await api.createPlaylist(name: name, description: "")
                try await api.replaceItems(playlistID: id, uris: uris)
                notice = .kept(name)
                log.info("kept \(uris.count) tracks as \"\(name, privacy: .public)\"")
            } catch {
                notice = ShuffleNotice(error)
            }
        }
    }

    /// Keeps playing when a round ends: appends the next round (same source, artists kept apart) to the Linory Shuffle
    /// playlist while its last tracks play. Tracks after `index` are still queued and skip this round.
    private func continueRound(after index: Int) {
        guard activity == nil, let sourceID = state.activeSourceID, let playlistID = state.shufflePlaylistID else { return }
        // The playlist mirrors currentOrder, and Spotify playlists hold at most 10,000 items.
        let capacity = ShuffleCycle.maxTracks - state.currentOrder.count
        guard capacity > 0 else {
            notice = .full
            return
        }
        let pending = Set(state.currentOrder.dropFirst(index + 1))
        let lastArtist = state.currentOrder.last.flatMap { state.trackInfo[$0]?.artistID }
        activity = .continuing
        Task {
            defer { activity = nil }
            do {
                let tracks = try await tracks(for: sourceID)
                var cycle = state.cycles[sourceID] ?? ShuffleCycle()
                let playedBefore = cycle.played
                var generator = SystemRandomNumberGenerator()
                let next = cycle.nextOrder(from: tracks.map(\.uri), excluding: pending, using: &generator)
                let order = Array(await Self.spread(next, tracks, after: lastArtist).prefix(capacity))
                guard !order.isEmpty, state.activeSourceID == sourceID, state.shufflePlaylistID == playlistID else { return }
                try await api.appendItems(playlistID: playlistID, uris: order)
                // Tracks counted while the round was built still count.
                for uri in (state.cycles[sourceID]?.played ?? []).subtracting(playedBefore) { cycle.markPlayed(uri) }
                state.cycles[sourceID] = cycle
                state.currentOrder += order
                state.trackInfo.merge(Self.info(tracks, for: order)) { _, new in new }
                save()
                log.info("auto-continue \(sourceID, privacy: .public): appended \(order.count) to \(playlistID, privacy: .public)")
            } catch {
                notice = ShuffleNotice(error)
                log.error("auto-continue failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// One source, or every member of a mix, deduplicated by URI.
    private func tracks(for sourceID: String) async throws -> [SpotifyTrackInfo] {
        var seen = Set<String>()
        var tracks: [SpotifyTrackInfo] = []
        // Members load one after another; each already loads 4 pages at a time.
        for member in ShuffleMix.members(sourceID) {
            for track in try await api.tracks(source: member) where seen.insert(track.uri).inserted { tracks.append(track) }
        }
        return tracks
    }

    /// Keeps one artist's tracks apart. Off the main actor: 10,000 tracks take a moment.
    private nonisolated static func spread(_ order: [String], _ tracks: [SpotifyTrackInfo], after artist: String?) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            var artists: [String: String] = [:]
            for track in tracks { if let id = track.artistID { artists[track.uri] = id } }
            var generator = SystemRandomNumberGenerator()
            return ArtistSpread.arrange(order, artists: artists, after: artist, using: &generator)
        }.value
    }

    private static func info(_ tracks: [SpotifyTrackInfo], for uris: [String]) -> [String: ShuffleTrackInfo] {
        let wanted = Set(uris)
        var info: [String: ShuffleTrackInfo] = [:]
        for track in tracks where wanted.contains(track.uri) {
            info[track.uri] = ShuffleTrackInfo(name: track.name, artist: track.artistName, artistID: track.artistID)
        }
        return info
    }

    private func apply(_ playlists: [SpotifyPlaylist]) {
        let shuffleID = state.shufflePlaylistID
        sources = [ShuffleSource(id: ShuffleState.likedSourceID, name: nil)] + playlists
            .filter { $0.id != shuffleID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { ShuffleSource(id: $0.id, name: $0.name) }
        if !isAvailable(selectedSourceID) { select(ShuffleState.likedSourceID) }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
        } catch {
            log.error("state write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
