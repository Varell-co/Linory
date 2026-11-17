import SwiftUI
import LyricsCore

/// State and actions the menu needs from the app.
final class MenuActions: ObservableObject {
    @Published var overlayVisible = true
    @Published var clickThrough = false
    @Published var pinToDesktop = false
    var toggleOverlay: () -> Void = {}
    var toggleClickThrough: () -> Void = {}
    var togglePinToDesktop: () -> Void = {}
    var moveTo: (String) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var openStats: () -> Void = {}
    var quit: () -> Void = {}
}

/// The status-item menu content, shown in a glass panel (see MenuWindow) so it can animate: hover highlights, sections that expand
/// smoothly, and a Now Playing header.
struct MenuPanel: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var actions: MenuActions
    @ObservedObject var auth: SpotifyAuth
    @ObservedObject var shuffle: ShuffleController
    /// Renders every optional row, so the window can be sized for the tallest layout (see MenuWindow).
    private let measuring: Bool
    @AppStorage("source") private var source = SourcePreference.auto.rawValue
    @AppStorage("language") private var languageSetting = AppLanguage.system.rawValue
    @State private var expanded: Section?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @AppStorage(ShuffleController.autoContinueKey) private var autoContinue = true
    @ObservedObject private var sleep = SleepTimerController.shared
    /// The mix checklist under the source picker.
    @State private var mixing = false

    enum Section: CaseIterable { case position, source, shuffle, sleep }

    init(model: PlayerModel, actions: MenuActions, auth: SpotifyAuth, shuffle: ShuffleController, expanded: Section? = nil, measuring: Bool = false) {
        _model = ObservedObject(wrappedValue: model)
        _actions = ObservedObject(wrappedValue: actions)
        _auth = ObservedObject(wrappedValue: auth)
        _shuffle = ObservedObject(wrappedValue: shuffle)
        _expanded = State(initialValue: expanded)
        self.measuring = measuring
    }

    private var language: AppLanguage { (AppLanguage(rawValue: languageSetting) ?? .system).resolved(preferredLanguages: Locale.preferredLanguages) }
    private func t(_ key: L10nKey) -> String { L10n.string(key, language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            nowPlaying.padding(.bottom, 6)
            Divider().padding(.horizontal, 8)
            toggleRow("rectangle.on.rectangle", t(.showOverlay), isOn: actions.overlayVisible, action: actions.toggleOverlay)
            toggleRow("cursorarrow.motionlines", t(.clickThrough), isOn: actions.clickThrough, action: actions.toggleClickThrough)
            toggleRow("pin", t(.pinToDesktop), isOn: actions.pinToDesktop, action: actions.togglePinToDesktop)
            disclosureRow("arrow.up.left.and.arrow.down.right", t(.position), .position)
            if expanded == .position { cornerGrid.transition(sectionTransition) }
            disclosureRow("music.note.list", t(.source), .source)
            if expanded == .source { sourcePicker.transition(sectionTransition) }
            disclosureRow("shuffle", t(.trueShuffle), .shuffle)
            if expanded == .shuffle { shuffleSection.transition(sectionTransition) }
            disclosureRow("moon.zzz", t(.sleepTimer), .sleep, detail: sleep.remaining.map { SleepTimer.format($0) })
            if expanded == .sleep { sleepOptions.transition(sectionTransition) }
            Divider().padding(.horizontal, 8).padding(.vertical, 4)
            MenuRow(symbol: "chart.bar.xaxis", title: t(.sectionStats), action: actions.openStats)
            MenuRow(symbol: "gearshape", title: t(.settingsMenu), shortcut: "⌘,", action: actions.openSettings)
                .keyboardShortcut(",", modifiers: .command)
            MenuRow(symbol: "power", title: "\(t(.quit)) \(Brand.name)", shortcut: "⌘Q", action: actions.quit)
                .keyboardShortcut("q", modifiers: .command)
        }
        // 10 pt inset with 22 pt panel corners: row highlights use 22 - 10 = 12 pt, so corners stay concentric.
        .padding(10)
        .frame(width: 290)
        .background(SystemPanelBackground(cornerRadius: 22))
        .background(PanelShadow(cornerRadius: 22))
        // Opens from the menu-bar icon above it: a slight scale from the top, never from nothing.
        .scaleEffect(appeared || reduceMotion ? 1 : 0.96, anchor: .top)
        .onAppear { withAnimation(Motion.easeOut(0.22)) { appeared = true } }
        .onChange(of: expanded) { section in if section == .shuffle { shuffle.refreshSources() } }
        .onChange(of: auth.isConnected) { connected in if connected && expanded == .shuffle { shuffle.refreshSources() } }
    }

    private var sectionTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6))
    }

    /// Same header as the overlay (cover art, title, artist), plus the mini-player controls while a track plays.
    private var nowPlaying: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                SpotifyTrackLink(track: model.track, language: language) {
                    HStack(spacing: 10) {
                        ZStack {
                            shape.fill(.quaternary)
                            if let image = model.artwork {
                                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).transition(.opacity)
                            } else if model.track != nil {
                                Image(systemName: "music.note").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                            } else {
                                LinorySymbol().padding(7)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(shape)
                        .overlay(shape.strokeBorder(.primary.opacity(0.08)))
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(model.track?.title ?? Brand.name).font(.headline)
                            Text(model.track.map { $0.artist } ?? t(.tagline)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                LikeButton(library: model.library, track: model.track, language: language)
            }
            // Measured with the controls, so a track that starts while the menu is open still fits.
            if model.track != nil || measuring {
                Scrubber(model: model, language: language).padding(.top, 4)
                TransportButtons(model: model, language: language, size: 14)
                songTiming.padding(.top, 2)
            }
        }
        // 8 pt, like the row content, so cover, row icons and section controls share one left edge.
        .padding(.horizontal, 8).padding(.top, 6)
    }

    /// Nudges this song's lyrics in quarter-second steps; remembered for the next listen.
    private var songTiming: some View {
        HStack(spacing: 6) {
            Text(t(.songTiming)).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if model.trackOffset != 0 {
                Button { model.setTrackOffset(0) } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help(t(.songTimingReset)).accessibilityLabel(t(.songTimingReset))
            }
            nudge("minus", -1, help: t(.lyricsLater))
            Text(TrackTiming.format(model.trackOffset)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                .frame(minWidth: 48)
            nudge("plus", 1, help: t(.lyricsEarlier))
        }
    }

    private func nudge(_ symbol: String, _ steps: Int, help: String) -> some View {
        Button { model.nudgeTrackOffset(by: steps) } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 18)
                .background(Capsule().fill(.primary.opacity(0.08)))
        }
        .buttonStyle(PressableStyle(scale: 0.9)).help(help).accessibilityLabel(help)
    }

    private func toggleRow(_ symbol: String, _ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        MenuRow(symbol: symbol, title: title, action: action) {
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in action() }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
    }

    /// `detail` is a short status before the chevron, such as the sleep timer's remaining time.
    private func disclosureRow(_ symbol: String, _ title: String, _ section: Section, detail: String? = nil) -> some View {
        MenuRow(symbol: symbol, title: title, action: {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Motion.lineChange) { expanded = expanded == section ? nil : section }
        }) {
            if let detail { Text(detail).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary) }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded == section ? 90 : 0))
        }
    }

    private var cornerGrid: some View {
        let corners: [(L10nKey, String)] = [(.topLeft, "topLeft"), (.topRight, "topRight"), (.bottomLeft, "bottomLeft"), (.bottomRight, "bottomRight")]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible())], spacing: 6) {
            ForEach(corners, id: \.1) { key, corner in
                Button { actions.moveTo(corner) } label: {
                    Text(t(key)).font(.system(size: 11.5, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.96))
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 6)
    }

    // MARK: True Shuffle

    @ViewBuilder private var shuffleSection: some View {
        if auth.isConnected || measuring {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Picker("", selection: Binding(get: { shuffle.selectedSourceID }, set: { shuffle.select($0) })) {
                        ForEach(pickerSources) { source in Text(source.name ?? t(.shuffleSourceLiked)).tag(source.id) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                    Button { withAnimation(Motion.easeOut(0.2)) { mixing.toggle() } } label: {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 13))
                            .foregroundStyle(mixing || shuffle.selectedMembers.count > 1 ? Brand.waveBlue : .secondary)
                            .frame(width: 24, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .help(t(.shuffleMixSources))
                }
                .disabled(shuffle.activity != nil)
                if mixing || measuring { mixList }
                Button(action: shuffle.shuffleAndPlay) {
                    HStack(spacing: 6) {
                        if shuffle.activity != nil { ProgressView().controlSize(.mini) } else { Image(systemName: "shuffle") }
                        Text(t(.shufflePlay))
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(Brand.waveBlue.opacity(shuffle.activity == nil ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.97))
                .disabled(shuffle.activity != nil)
                shuffleStatus
                let upNext = measuring ? Array(repeating: (uri: "", info: ShuffleTrackInfo(name: "—", artist: "—", artistID: nil)), count: 3) : shuffle.upNext
                if !upNext.isEmpty { upNextList(upNext) }
            }
            .padding(.horizontal, 8).padding(.bottom, 4)
            toggleRow("infinity", t(.shuffleAutoContinue), isOn: autoContinue) { autoContinue.toggle() }
            let current = model.track.map { $0.source == .spotify ? $0.rawID : "" }
            if measuring || (shuffle.currentInShuffle && current == shuffle.currentURI) {
                MenuRow(symbol: "minus.circle", title: t(.shuffleRemove), action: shuffle.removeCurrent)
            }
            if measuring || shuffle.hasShuffle {
                MenuRow(symbol: "square.and.arrow.down", title: t(.shuffleKeep), action: shuffle.keepShuffle)
            }
            let removed = shuffle.selectedCycle.removed.count
            if measuring || removed > 0 {
                MenuRow(symbol: "arrow.uturn.backward", title: L10n.string(.shuffleRestore, removed, language: language), action: shuffle.restoreRemoved)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(t(.shuffleConnectHint)).fixedSize(horizontal: false, vertical: true).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("\(t(.shuffleOpenSettings)) ›", action: actions.openSettings)
                    .buttonStyle(.plain).foregroundStyle(Brand.waveBlue)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8).padding(.bottom, 6)
        }
    }

    /// Sources, then mixes shuffled before. Before the playlists load, a remembered playlist still needs a tag, or the
    /// picker shows nothing.
    private var pickerSources: [ShuffleSource] {
        let sources = shuffle.sources + shuffle.mixes
        let id = shuffle.selectedSourceID
        if sources.contains(where: { $0.id == id }) { return sources }
        return sources + [ShuffleSource(id: id, name: shuffle.isAvailable(id) ? shuffle.sourceName(id) : "…")]
    }

    /// Checklist that builds a mix: the selection becomes every checked source.
    private var mixList: some View {
        let rowHeight: CGFloat = 24
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(shuffle.sources) { source in
                    let on = shuffle.selectedMembers.contains(source.id)
                    Button { shuffle.toggleMember(source.id) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Brand.waveBlue : .secondary)
                            Text(source.name ?? t(.shuffleSourceLiked)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 12)).padding(.horizontal, 8).frame(height: rowHeight).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                }
            }
        }
        // Five rows, then it scrolls; measuring reserves the full height.
        .frame(height: measuring ? rowHeight * 5 : min(CGFloat(shuffle.sources.count), 5) * rowHeight)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .transition(sectionTransition)
    }

    /// Display only; each row opens the track in Spotify.
    private func upNextList(_ items: [(uri: String, info: ShuffleTrackInfo)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t(.shuffleUpNext).uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.tertiary)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button { SpotifyLink.open(item.uri) } label: {
                    (Text(item.info.name) + Text(verbatim: "  \(item.info.artist)").foregroundColor(.secondary))
                        .font(.system(size: 11.5)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder private var shuffleStatus: some View {
        let progress = shuffle.selectedCycle.progress
        Group {
            if measuring {
                Text(t(.shuffleErrorPremium)).fixedSize(horizontal: false, vertical: true)
            } else if let activity = shuffle.activity {
                switch activity {
                case .loading: Text(t(.shuffleLoading))
                case .shuffling(let count): Text(L10n.string(.shuffleBusy, count, language: language))
                case .working: Text(verbatim: "…")
                case .continuing: Text(t(.shuffleContinuing))
                }
            } else if let notice = shuffle.notice {
                Text(notice.text(language: language))
                    .foregroundStyle(notice.isError ? Color.orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if progress.total > 0 || progress.played > 0 {
                HStack(spacing: 4) {
                    Text(L10n.string(.shuffleProgress, progress.played, progress.total, language: language))
                    Text(verbatim: "·")
                    Button(t(.shuffleReset), action: shuffle.reset).buttonStyle(.plain).foregroundStyle(Brand.waveBlue)
                }
            }
        }
        .font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
    }

    // MARK: Sleep timer

    private var sleepOptions: some View {
        let options: [(mode: SleepTimer.Mode?, title: String)] = [(nil, t(.sleepOff))]
            + SleepTimer.presets.map { (SleepTimer.Mode.minutes($0), L10n.string(.sleepMinutes, $0, language: language)) }
            + [(.endOfTrack, t(.sleepEndOfTrack))]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(options, id: \.title) { option in
                let selected = sleep.timer?.mode == option.mode
                Button { sleep.start(option.mode, model: model) } label: {
                    Text(option.title).font(.system(size: 11.5, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? Color.white : .primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(selected ? AnyShapeStyle(Brand.waveBlue) : AnyShapeStyle(.quaternary),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                // "End of track" needs a track to wait for.
                .disabled(option.mode == .endOfTrack && model.track == nil)
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 6)
    }

    private var sourcePicker: some View {
        Picker("", selection: $source) {
            Text(t(.sourceAuto)).tag(SourcePreference.auto.rawValue)
            Text(t(.sourceSpotify)).tag(SourcePreference.spotify.rawValue)
            Text(t(.sourceMusic)).tag(SourcePreference.music.rawValue)
        }
        .pickerStyle(.segmented).labelsHidden()
        .padding(.horizontal, 8).padding(.bottom, 6)
    }
}

/// Soft drop shadow that follows the glass while it animates. Only the outside is drawn,
/// so it never darkens the translucent glass itself.
private struct PanelShadow: View {
    var cornerRadius: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(.black)
            .shadow(color: .black.opacity(0.32), radius: 14, y: 8)
            .mask {
                Rectangle().padding(-60)
                    .overlay(shape.fill(.black).blendMode(.destinationOut))
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}

/// A menu row with a hover highlight that fades in, like a native menu item but animated.
private struct MenuRow<Accessory: View>: View {
    let symbol: String
    let title: String
    var shortcut: String? = nil
    let action: () -> Void
    @ViewBuilder var accessory: () -> Accessory
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 13)).frame(width: 18).foregroundStyle(.secondary)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 8)
                if let shortcut { Text(shortcut).font(.system(size: 12)).foregroundStyle(.tertiary) }
                accessory()
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.primary.opacity(hovering ? 0.08 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .onHover { inside in withAnimation(.easeOut(duration: inside ? 0.08 : 0.2)) { hovering = inside } }
    }
}

extension MenuRow where Accessory == EmptyView {
    init(symbol: String, title: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.init(symbol: symbol, title: title, shortcut: shortcut, action: action, accessory: { EmptyView() })
    }
}
