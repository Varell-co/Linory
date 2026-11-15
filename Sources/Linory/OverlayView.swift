import SwiftUI
import LyricsCore

struct OverlayView: View {
    @ObservedObject var model: PlayerModel
    var showSettings: () -> Void
    @AppStorage("fontSize") private var fontSize = 25.0
    @AppStorage("opacity") private var opacity = 0.78
    @AppStorage("overlayOpacity") private var overlayOpacity = 1.0
    @AppStorage("offset") private var offset = 0.0
    @AppStorage("language") private var languageSetting = AppLanguage.system.rawValue
    @AppStorage("clickThrough") private var clickThrough = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lines: [LyricLine] = []
    @State private var hovering = false
    /// Debug snapshots only: shows the hover controls without a pointer.
    var forceControls = false

    /// Previous/next lines are the active line scaled down, so the size change can animate as a transform.
    private static let neighborScale: CGFloat = 0.78

    private var language: AppLanguage { (AppLanguage(rawValue: languageSetting) ?? .system).resolved(preferredLanguages: Locale.preferredLanguages) }
    private var sourceLines: [LyricLine] { model.lyrics?.lines ?? [] }
    private var trackKey: String { model.track?.id ?? "none" }
    /// Changes when the lyrics area shows something new: another song, lyrics arriving, or another status.
    private var contentKey: String { sourceLines.isEmpty ? "\(trackKey)|status|\(model.status)" : "\(trackKey)|lyrics|\(sourceLines.count)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            // Old and new content overlap here, so a song switch is a crossfade instead of a cut.
            ZStack(alignment: .topLeading) {
                Group {
                    if sourceLines.isEmpty { status } else { lyricsArea }
                }
                .id(contentKey)
                .transition(reduceMotion ? .opacity : .songSwap)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(Motion.easeOut(0.25), value: contentKey)
            if model.track != nil {
                ProgressLine(model: model, language: language, expanded: showsControls)
                    .padding(.top, -4) // sits close to the lyrics' faded bottom edge
            }
        }
        // 16 pt inset with 22 pt panel corners: inner corners (cover art) use 22 - 16 = 6 pt, so they stay concentric.
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Motion.easeOut(hovering ? 0.2 : 0.3), value: showsControls)
        .background(HoverArea { hovering = $0 })
        // Turning click-through on mid-hover means no exit event ever arrives.
        .onChange(of: clickThrough) { _ in hovering = false }
        .background(WindowDragArea())
        .background(SystemPanelBackground(cornerRadius: 22).opacity(opacity))
        .opacity(overlayOpacity)
    }

    private var status: some View {
        Group {
            if model.status == .noLyrics || model.status == .instrumental {
                VStack(spacing: 12) {
                    NoLyricsSymbol(clock: model.clock)
                    statusText.multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                statusText
            }
        }
        // "Searching…" usually lasts a few milliseconds (cache); only show it if it actually takes a while.
        .modifier(Reveal(delay: model.status == .searching ? 0.35 : 0.1))
    }

    private var statusText: some View {
        Text(model.status.text(language: language)).font(.body).foregroundStyle(.secondary)
    }

    private var lyricsArea: some View {
        GeometryReader { geo in
            // Segmentation changes with the lyrics or layout, never on every playback frame.
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !model.clock.playing)) { context in
                lyrics(at: model.clock.position(at: context.date) + offset,
                       time: context.date.timeIntervalSinceReferenceDate, width: geo.size.width)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .onAppear { updateDisplayLines(width: geo.size.width) }
            .onChange(of: geo.size.width) { updateDisplayLines(width: $0) }
            .onChange(of: fontSize) { _ in updateDisplayLines(width: geo.size.width) }
            .onChange(of: model.lyrics) { _ in updateDisplayLines(width: geo.size.width) }
            .onChange(of: model.track?.duration) { _ in updateDisplayLines(width: geo.size.width) }
        }
        .clipped()
        // If the text does not fit (big font, small overlay), it fades out instead of being cut off.
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                     .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }

    // MARK: Mini-player

    /// Only on hover, so the overlay stays lyrics first. Click-through means the user wants to click past it.
    private var showsControls: Bool { (hovering || forceControls) && !clickThrough && model.track != nil }

    // MARK: Header

    /// Like the Now Playing widget: cover art, title and artist, entering one after another per song.
    private var header: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                SpotifyTrackLink(track: model.track, language: language) {
                    HStack(spacing: 10) {
                        artwork.modifier(Reveal())
                        VStack(alignment: .leading, spacing: 0) {
                            Text(model.track?.title ?? L10n.string(.overlayPlaceholder, language: language))
                                .font(.headline)
                                .modifier(Reveal(delay: 0.05))
                            if let artist = model.track?.artist, !artist.isEmpty {
                                Text(artist).font(.subheadline).foregroundStyle(.secondary)
                                    .modifier(Reveal(delay: 0.1))
                            }
                        }
                        .lineLimit(1)
                    }
                }
                .id(trackKey)
                .transition(.songSwap)
            }
            .animation(Motion.easeOut(0.25), value: trackKey)
            Spacer(minLength: 0)
            if showsControls {
                // Same muted ink as the header, so the controls read as part of it rather than a toolbar.
                HStack(spacing: 6) {
                    LikeButton(library: model.library, track: model.track, language: language)
                    TransportButtons(model: model, language: language, size: 11)
                }
                .foregroundStyle(.secondary)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: 6)))
            } else if model.lyrics?.synced == false && !sourceLines.isEmpty {
                Text(StatusMessage.notSynced.text(language: language))
                    .font(.caption).foregroundStyle(.tertiary).layoutPriority(1)
                    .transition(.opacity)
            }
            Button(action: showSettings) {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .help(L10n.string(.openSettingsHelp, language: language))
        }
    }

    /// Cover art with a neutral placeholder; the cover fades in when it has loaded.
    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return ZStack {
            shape.fill(.quaternary)
            Image(systemName: "music.note").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            if let image = model.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).transition(.opacity)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .animation(Motion.easeOut(0.35), value: model.artwork)
    }

    // MARK: Lyrics

    /// Five slots around the active line, keyed by line index: when the line changes, the rows physically
    /// scroll up (the next line grows into the active slot) instead of swapping text in place.
    private func lyrics(at position: Double, time: TimeInterval, width: CGFloat) -> some View {
        // -1 is the intro, before the first line.
        let current = LRC.currentIndex(lines, at: position) ?? -1
        return VStack(alignment: .leading, spacing: 4) {
            ForEach((current - 2)...(current + 2), id: \.self) { index in
                row(index, current: current, position: position, time: time, width: width)
                    // Staggered entrance when the lyrics first appear; rows added later by scrolling just fade.
                    .modifier(Reveal(delay: 0.12 + Double(index - current + 2) * 0.05))
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Motion.lineChange, value: current)
    }

    private func row(_ index: Int, current: Int, position: Double, time: TimeInterval, width: CGFloat) -> some View {
        let distance = abs(index - current)
        let isActive = distance == 0
        let exists = lines.indices.contains(index)
        let textWidth = max(1, width)
        let base = isActive ? 1 : Self.neighborScale
        let fit = exists ? fitScale(lines[index].text, width: textWidth) : 1
        let scale = min(base, fit)
        // Scaled rows keep their full-size layout height; pull them together so spacing stays even.
        let collapse = fontSize * 1.19 * (1 - scale) / 2
        let wait = isActive ? waitProgress(index, at: position) : nil
        // Every row is the same Text view, so a line that becomes active keeps its identity and slides
        // into place. Branching between view types here would make SwiftUI crossfade copies instead.
        let text: Text = wait != nil ? Text(" ")
            : isActive ? activeLine(index, at: position)
            : Text(exists ? (lines[index].text.isEmpty ? "♪" : lines[index].text) : " ")
        return text
        .overlay(alignment: .leading) {
            if let wait { BreakDots(progress: wait, time: time, size: fontSize).transition(.opacity) }
        }
        .font(.system(size: fontSize, weight: .semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.9) // absorbs small measuring differences before truncating
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: textWidth / scale, alignment: .leading)
        .scaleEffect(scale, anchor: .leading)
        .frame(width: textWidth, alignment: .leading)
        .padding(.vertical, (isActive ? 4 : 0) - collapse)
        .opacity(!exists && !isActive ? 0 : distance == 0 ? 1 : distance == 1 ? 0.42 : 0.14)
        .blur(radius: distance >= 2 ? 1.2 : 0)
        // Synced lines jump the song there. Other rows let clicks through, so the overlay can still be dragged.
        .contentShape(Rectangle())
        .onTapGesture { if exists { model.seek(toLyricTime: lines[index].time) } }
        .allowsHitTesting(exists && model.lyrics?.synced == true)
    }

    private static var widthCache: [String: CGFloat] = [:]

    private func updateDisplayLines(width: CGFloat) {
        lines = LyricSegmentation.split(sourceLines, duration: model.track?.duration ?? 0,
                                       maxWidth: max(1, width) * 0.97 / 0.6,
                                       measure: { Double(measuredWidth($0)) })
    }

    /// Scale at which a line fits on one row, measured with the overlay font (1 if it already fits).
    private func fitScale(_ text: String, width: CGFloat) -> CGFloat {
        min(1, width * 0.97 / max(1, measuredWidth(text)))
    }

    private func measuredWidth(_ text: String) -> CGFloat {
        let key = "\(fontSize)|\(text)"
        return Self.widthCache[key] ?? {
            if Self.widthCache.count > 500 { Self.widthCache.removeAll() }
            let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
            let measured = NSAttributedString(string: text, attributes: [.font: font]).size().width
            Self.widthCache[key] = measured
            return measured
        }()
    }

    /// Progress through a wait (intro or instrumental break), or nil when a sung line is active.
    private func waitProgress(_ index: Int, at position: Double) -> Double? {
        if index == -1 {
            guard let first = lines.first else { return nil }
            return first.time > 0 ? min(1, max(0, position / first.time)) : 1
        }
        guard lines.indices.contains(index), lines[index].text.isEmpty else { return nil }
        let end = lines.indices.contains(index + 1) ? lines[index + 1].time : lines[index].time + 4
        return min(1, max(0, (position - lines[index].time) / max(0.1, end - lines[index].time)))
    }

    /// Karaoke-style: each word brightens as it is sung. Unsynced (estimated) lyrics stay fully lit,
    /// because their timing is too rough for word tracking.
    private func activeLine(_ index: Int, at position: Double) -> Text {
        guard lines.indices.contains(index) else { return Text("♪") }
        guard model.lyrics?.synced == true else { return Text(lines[index].text) }
        let next = lines.indices.contains(index + 1) ? lines[index + 1].time : nil
        let units = WordHighlight.units(for: lines[index], nextTime: next, at: position)
        guard !units.isEmpty else { return Text("♪") }
        return units.enumerated().reduce(Text("")) { text, item in
            let word = Text((item.offset == 0 ? "" : " ") + item.element.text)
                .foregroundColor(.primary.opacity(0.3 + 0.7 * item.element.fill))
            return text + word
        }
    }
}

/// The app icon comes alive while music plays (see `LinorySymbol`) and settles back to the logo on pause.
/// Resuming eases in over 0.8 s rather than jumping to full motion.
private struct NoLyricsSymbol: View {
    let clock: PlaybackClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the drift (re)started; .distantFuture while resting, so the first resumed frame starts at rest.
    @State private var startedAt = Date()

    private var moving: Bool { clock.playing && !reduceMotion }

    var body: some View {
        // Wall time, not playback position: the clock re-anchors on every poll and seek, which made the ribbons jump.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !moving)) { context in
            LinorySymbol(time: context.date.timeIntervalSinceReferenceDate,
                         drift: moving ? Motion.easeInOut(min(1, max(0, context.date.timeIntervalSince(startedAt) / 0.8))) : 0)
                .frame(width: 56, height: 42)
        }
        // Only the pause frame animates: the ribbons glide home instead of freezing mid-drift.
        .animation(Motion.easeOut(0.6), value: moving)
        .onChange(of: moving) { startedAt = $0 ? Date() : .distantFuture }
        .frame(height: 42)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

}
