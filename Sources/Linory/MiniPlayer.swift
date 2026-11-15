import AppKit
import Combine
import SwiftUI
import LyricsCore
import os

/// Liked state of the current Spotify track, for the mini-player's heart. Only known while Spotify is connected.
@MainActor
final class SpotifyLibrary: ObservableObject {
    @Published private(set) var connected = false
    /// nil while unknown: the heart stays hidden rather than guessing.
    @Published private(set) var liked: Bool?
    private var uri: String?
    private weak var auth: SpotifyAuth?
    private var subscription: AnyCancellable?
    private let log = Logger(subsystem: LyricsService.subsystem, category: "spotify")

    /// Created with the player model, before the main actor is known to the compiler; see `SpotifyAuth.init`.
    nonisolated init() {}

    #if DEBUG
    /// Debug snapshots only.
    func previewLiked(_ liked: Bool) { connected = true; self.liked = liked }
    #endif

    func attach(_ auth: SpotifyAuth) {
        self.auth = auth
        subscription = auth.$state
            .map { if case .connected = $0 { return true } else { return false } }
            .removeDuplicates()
            .sink { [weak self] connected in
                self?.connected = connected
                self?.uri = nil // ask again with the new login
                self?.liked = nil
            }
    }

    /// Called by every view showing the heart; asks Spotify once per track.
    func load(uri: String?) async {
        guard uri != self.uri else { return }
        self.uri = uri
        liked = nil
        guard let uri, connected, let api = auth?.api else { return }
        do {
            let saved = try await api.isSaved(uri: uri)
            if self.uri == uri { liked = saved }
        } catch {
            log.error("liked state unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Flips at once and flips back if Spotify refuses.
    func toggle() {
        guard let uri, let wasLiked = liked, let api = auth?.api else { return }
        liked = !wasLiked
        Task {
            do {
                if wasLiked { try await api.unsave(uri: uri) } else { try await api.save(uri: uri) }
            } catch {
                log.error("like failed: \(error.localizedDescription, privacy: .public)")
                if self.uri == uri { liked = wasLiked }
            }
        }
    }
}

extension Track {
    /// Spotify's policy asks for a way back to Spotify wherever its metadata or cover art is shown.
    var spotifyURL: URL? { source == .spotify && rawID.hasPrefix("spotify:track:") ? URL(string: rawID) : nil }
}

/// Makes cover and title open the track in Spotify. Other players' tracks stay plain.
struct SpotifyTrackLink<Content: View>: View {
    let track: Track?
    let language: AppLanguage
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let url = track?.spotifyURL {
            Button { SpotifyLink.open(url.absoluteString) } label: { content().contentShape(Rectangle()) }
                .buttonStyle(PressableStyle(scale: 0.98))
                .help(L10n.string(.miniOpenInSpotify, language: language))
        } else {
            content()
        }
    }
}

/// Previous, play/pause, next for the player Linory follows.
struct TransportButtons: View {
    @ObservedObject var model: PlayerModel
    let language: AppLanguage
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: size * 1.3) {
            button("backward.fill", .miniPrevious, size) { model.send(.previous) }
            button(model.clock.playing ? "pause.fill" : "play.fill", model.clock.playing ? .miniPause : .miniPlay, size * 1.35) {
                model.send(.playPause)
            }
            button("forward.fill", .miniNext, size) { model.send(.next) }
        }
    }

    private func button(_ symbol: String, _ label: L10nKey, _ size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size * 1.6, height: size * 1.6)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.86))
        .help(L10n.string(label, language: language))
        .accessibilityLabel(L10n.string(label, language: language))
    }
}

/// Heart for the current Spotify track. Hidden for Music, without a Spotify login, and until the state is known.
struct LikeButton: View {
    @ObservedObject var library: SpotifyLibrary
    let track: Track?
    let language: AppLanguage

    var body: some View {
        let uri = track?.spotifyURL?.absoluteString
        ZStack {
            if library.connected, uri != nil, let liked = library.liked {
                let label = L10n.string(liked ? .miniUnlike : .miniLike, language: language)
                Button(action: library.toggle) {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(liked ? AnyShapeStyle(Brand.waveBlue) : AnyShapeStyle(.secondary))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.8))
                .help(label)
                .accessibilityLabel(label)
                .transition(.opacity)
            }
        }
        .animation(Motion.easeOut(0.2), value: library.liked)
        .task(id: "\(uri ?? "")|\(library.connected)") { await library.load(uri: uri) }
    }
}

/// Click or drag to seek. Shows elapsed and remaining time; the thumb follows the pointer while dragging and
/// the player seeks once on release.
struct Scrubber: View {
    @ObservedObject var model: PlayerModel
    let language: AppLanguage
    @State private var dragFraction: Double?
    @State private var hovering = false

    private var duration: Double { model.track?.duration ?? 0 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !model.clock.playing || dragFraction != nil)) { context in
            let position = dragFraction.map { $0 * duration } ?? model.clock.position(at: context.date)
            VStack(spacing: 2) {
                bar(fraction: duration > 0 ? min(1, max(0, position / duration)) : 0)
                HStack {
                    Text(Self.time(position))
                    Spacer()
                    Text("-" + Self.time(max(0, duration - position)))
                }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).monospacedDigit()
            }
            .accessibilityElement()
            .accessibilityLabel(L10n.string(.miniPosition, language: language))
            .accessibilityValue("\(Self.time(position)) / \(Self.time(duration))")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 10.0 : -10.0
                model.seek(to: min(max(0, position + step), duration))
            }
        }
    }

    private func bar(fraction: Double) -> some View {
        let active = hovering || dragFraction != nil
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.14))
                Capsule().fill(.primary.opacity(active ? 0.9 : 0.6))
                    .frame(width: max(active ? 6 : 4, geo.size.width * fraction))
            }
            .frame(height: active ? 6 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { dragFraction = min(1, max(0, $0.location.x / max(1, geo.size.width))) }
                .onEnded { value in
                    defer { dragFraction = nil }
                    guard duration > 0 else { return }
                    let fraction = min(1, max(0, value.location.x / max(1, geo.size.width)))
                    model.seek(to: fraction * duration)
                })
        }
        .frame(height: 12)
        .animation(Motion.easeOut(0.15), value: active)
        .onHover { hovering = $0 }
    }

    static func time(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Reports the pointer entering and leaving, also while Linory is in the background. The overlay never becomes
/// key, and SwiftUI's own hover tracking is not guaranteed to fire for an inactive app.
struct HoverArea: NSViewRepresentable {
    let onChange: (Bool) -> Void

    final class TrackingView: NSView {
        var onChange: (Bool) -> Void = { _ in }
        override init(frame: NSRect) {
            super.init(frame: frame)
            // `.inVisibleRect` follows the view's size, so the area never needs updating.
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        required init?(coder: NSCoder) { fatalError("not used") }
        override func mouseEntered(with event: NSEvent) { onChange(true) }
        override func mouseExited(with event: NSEvent) { onChange(false) }
        // Purely an observer: clicks fall through to the views behind it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) { view.onChange = onChange }
}
