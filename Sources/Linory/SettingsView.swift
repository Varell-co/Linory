import SwiftUI
import LyricsCore
import os

/// Dark glass settings with a sidebar, following the Linory UI concept.
struct SettingsView: View {
    enum Pane: CaseIterable { case general, overlay, timing, spotify, stats, about }

    @AppStorage("fontSize") private var fontSize = 25.0
    @AppStorage("opacity") private var opacity = 0.78
    @AppStorage("overlayOpacity") private var overlayOpacity = 1.0
    @AppStorage("offset") private var offset = 0.0
    @AppStorage("overlayWidth") private var width = 400.0
    @AppStorage("overlayHeight") private var height = 240.0
    @AppStorage("language") private var languageSetting = AppLanguage.system.rawValue
    @AppStorage("source") private var source = SourcePreference.auto.rawValue
    @AppStorage("autoHide") private var autoHide = false
    @AppStorage("spotifyClientID") private var clientID = ""
    @State private var pane = Pane.general
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.requiresApproval
    @State private var loginError: String?
    private let log = Logger(subsystem: LyricsService.subsystem, category: "login")
    @ObservedObject var auth: SpotifyAuth
    @StateObject private var stats = TopItemsModel()
    @State private var statsRange = SpotifyTimeRange.short
    var resize: () -> Void

    init(auth: SpotifyAuth, resize: @escaping () -> Void, pane: Pane = .general) {
        _auth = ObservedObject(wrappedValue: auth)
        self.resize = resize
        _pane = State(initialValue: pane)
    }

    private var language: AppLanguage { (AppLanguage(rawValue: languageSetting) ?? .system).resolved(preferredLanguages: Locale.preferredLanguages) }
    private func t(_ key: L10nKey) -> String { L10n.string(key, language: language) }
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title(pane)).font(.system(size: 22, weight: .semibold))
                        Text(subtitle(pane)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.bottom, 10)
                    content
                }
                .id(pane)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                .padding(.horizontal, 28).padding(.top, 44).padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 700, height: 480)
        .background(GlassBackground(cornerRadius: Brand.panelCornerRadius, strength: 1))
        // Clip the sidebar and blur too; the native window only rounds the title bar.
        .clipShape(RoundedRectangle(cornerRadius: Brand.panelCornerRadius, style: .continuous))
        .ignoresSafeArea() // run under the transparent title bar
        .foregroundStyle(.white)
        .tint(Brand.waveBlue)
        .environment(\.colorScheme, .dark)
        .onChange(of: width) { _ in resize() }
        .onChange(of: height) { _ in resize() }
        // A login belongs to one Client ID.
        .onChange(of: clientID) { _ in if auth.state != .disconnected { auth.disconnect() } }
        .onAppear(perform: refreshLogin)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refreshLogin() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                LinorySymbol().frame(width: 36, height: 27)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Brand.name).font(.system(size: 18, weight: .semibold))
                    Text("v\(version)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 10).padding(.top, 44).padding(.bottom, 22)
            ForEach(Pane.allCases, id: \.self) { item in
                Button { withAnimation(Motion.easeOut(0.24)) { pane = item } } label: {
                    Label(title(item), systemImage: icon(item))
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background {
                            // The selection glides to the clicked item instead of jumping.
                            if pane == item {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.12))
                                    .matchedGeometryEffect(id: "selection", in: selection)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.97))
                .foregroundStyle(.white.opacity(pane == item ? 1 : 0.75))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(width: 200)
        .background(.black.opacity(0.15))
    }

    private func title(_ pane: Pane) -> String {
        switch pane {
        case .general: return t(.sectionGeneral)
        case .overlay: return t(.sectionAppearance)
        case .timing: return t(.sectionTiming)
        case .spotify: return t(.sectionSpotify)
        case .stats: return t(.sectionStats)
        case .about: return t(.sectionAbout)
        }
    }
    private func subtitle(_ pane: Pane) -> String {
        switch pane {
        case .general: return t(.generalSubtitle)
        case .overlay: return t(.overlaySubtitle)
        case .timing: return t(.timingSubtitle)
        case .spotify: return t(.spotifySubtitle)
        case .stats: return t(.statsSubtitle)
        case .about: return t(.aboutSubtitle)
        }
    }
    private func icon(_ pane: Pane) -> String {
        switch pane {
        case .general: return "slider.horizontal.3"
        case .overlay: return "square.3.layers.3d"
        case .timing: return "metronome"
        case .spotify: return "music.note.house"
        case .stats: return "chart.bar"
        case .about: return "info.circle"
        }
    }

    // MARK: Panes

    @ViewBuilder private var content: some View {
        switch pane {
        case .general:
            row("music.note", t(.source), t(.sourceHint)) {
                Picker("", selection: $source) {
                    Text(t(.sourceAuto)).tag(SourcePreference.auto.rawValue)
                    Text(t(.sourceSpotify)).tag(SourcePreference.spotify.rawValue)
                    Text(t(.sourceMusic)).tag(SourcePreference.music.rawValue)
                }
                .labelsHidden().fixedSize()
            }
            row("eye.slash", t(.autoHide), t(.autoHideHint)) { Toggle("", isOn: $autoHide).labelsHidden().toggleStyle(.switch) }
            row("power", t(.launchAtLogin), t(.launchAtLoginHint)) {
                Toggle("", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)).labelsHidden().toggleStyle(.switch)
            }
            if loginNeedsApproval {
                HStack {
                    Label(t(.loginNeedsApproval), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Button(t(.loginOpenSettings)) { LoginItem.openSystemSettings() }
                }
                .font(.caption).padding(.horizontal, 4)
            }
            if let loginError {
                Label(L10n.string(.loginError, loginError, language: language), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
            row("globe", t(.language), t(.languageHint)) {
                Picker("", selection: $languageSetting) {
                    Text(t(.languageSystem)).tag(AppLanguage.system.rawValue)
                    Text(t(.languageEnglish)).tag(AppLanguage.en.rawValue)
                    Text(t(.languageGerman)).tag(AppLanguage.de.rawValue)
                }
                .labelsHidden().fixedSize()
            }
            row("keyboard", t(.hotKeyTitle), t(.hotKeyHint)) {
                Text("⌥ ⇧ L").font(.system(size: 13, weight: .medium, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        case .overlay:
            card { slider(t(.fontSize), $fontSize, 14...44, suffix: " pt") }
            card {
                slider(t(.overlayOpacity), $overlayOpacity, 0.15...1, multiplier: 100, suffix: t(.opacitySuffix))
                slider(t(.backgroundOpacity), $opacity, 0...1, multiplier: 100, suffix: t(.opacitySuffix))
            }
            card {
                slider(t(.width), $width, 260...800, suffix: " pt")
                slider(t(.height), $height, 160...500, suffix: " pt")
            }
        case .timing:
            card { slider(t(.timingOffset), $offset, -5...5, suffix: " s", decimals: 1) }
            Text(t(.timingHint)).font(.caption).foregroundStyle(.white.opacity(0.55)).padding(.horizontal, 4)
        case .spotify:
            spotifyPane
        case .stats:
            statsPane
        case .about:
            card {
                HStack(spacing: 14) {
                    LinorySymbol().frame(width: 56, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Brand.name).font(.system(size: 20, weight: .semibold))
                        Text(L10n.string(.version, version, language: language)).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                        Text(t(.endorsement).uppercased()).font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(.white.opacity(0.45)).padding(.top, 4)
                    }
                }
            }
            Text(t(.privacyNote)).font(.caption).foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
        }
    }

    // MARK: Spotify

    @ViewBuilder private var spotifyPane: some View {
        card {
            HStack(spacing: 12) {
                Text(t(.spotifyClientID)).font(.system(size: 13, weight: .medium)).frame(width: 100, alignment: .leading)
                TextField("", text: $clientID, prompt: Text(verbatim: "3f9c…"))
                    .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
            }
            HStack(spacing: 12) {
                Text(t(.spotifyRedirectURI)).font(.system(size: 13, weight: .medium)).frame(width: 100, alignment: .leading)
                Text(verbatim: SpotifyPKCE.redirectURI).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button(t(.spotifyCopy)) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(SpotifyPKCE.redirectURI, forType: .string)
                }
            }
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 10) {
                Circle().fill(auth.isConnected ? Color.green : .white.opacity(0.35)).frame(width: 8, height: 8)
                Text(spotifyStatus).font(.system(size: 13)).lineLimit(2)
                Spacer(minLength: 12)
                if auth.state == .connecting { ProgressView().controlSize(.small) }
                if auth.isConnected {
                    Button(t(.spotifyDisconnect)) { auth.disconnect() }
                } else {
                    Button(t(.spotifyConnect)) { auth.connect() }
                        .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty || auth.state == .connecting)
                }
            }
        }
        if auth.needsReconnect {
            HStack {
                Label(t(.spotifyReconnectHint), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(t(.spotifyReconnect)) { auth.connect() }
            }
            .font(.caption).padding(.horizontal, 4)
        }
        card {
            Text(t(.spotifyGuideTitle)).font(.system(size: 13, weight: .medium))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array([L10nKey.spotifyGuideStep1, .spotifyGuideStep2, .spotifyGuideStep3, .spotifyGuideStep4].enumerated()), id: \.offset) { index, key in
                    Text("\(index + 1). ") + Text((try? AttributedString(markdown: t(key))) ?? AttributedString(t(key)))
                }
            }
            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
            Text(t(.spotifyPremiumNote)).font(.caption).foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: Your music

    private var statsPane: some View {
        VStack(alignment: .leading, spacing: 10) { statsContent }
            .task(id: StatsRequest(range: statsRange, connected: auth.isConnected)) {
                if auth.isConnected { await stats.load(statsRange, api: auth.api) } else { stats.clear() }
            }
    }

    @ViewBuilder private var statsContent: some View {
        if !auth.isConnected {
            HStack {
                Text(t(.statsConnectHint)).foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 8)
                Button(t(.statsOpenSpotify)) { withAnimation(Motion.easeOut(0.24)) { pane = .spotify } }
            }
            .font(.system(size: 13)).padding(.horizontal, 4)
        } else {
            Picker("", selection: $statsRange) {
                Text(t(.statsRangeShort)).tag(SpotifyTimeRange.short)
                Text(t(.statsRangeMedium)).tag(SpotifyTimeRange.medium)
                Text(t(.statsRangeLong)).tag(SpotifyTimeRange.long)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            // Logins from before stats existed lack `user-top-read`; Spotify then answers 403.
            if auth.needsReconnect || stats.failure == .forbidden {
                HStack {
                    Label(t(.statsReconnectHint), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(t(.spotifyReconnect)) { auth.connect() }
                }
                .font(.caption).padding(.horizontal, 4)
            } else if stats.failure == .other {
                Label(t(.statsError), systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).padding(.horizontal, 4)
            }
            let items = stats.items[statsRange]
            HStack(alignment: .top, spacing: 10) {
                topList(t(.statsTopArtists), items?.artists)
                topList(t(.statsTopTracks), items?.tracks)
            }
        }
    }

    /// Display only. Each row opens the artist or track in Spotify.
    private func topList(_ title: String, _ items: [SpotifyTopItem]?) -> some View {
        card {
            Text(title).font(.system(size: 13, weight: .medium))
            if let items {
                if items.isEmpty { Text(t(.statsEmpty)).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)) }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { rank, item in
                        Button { SpotifyLink.open(item.uri) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(rank + 1)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.45)).frame(width: 16, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.name).font(.system(size: 12.5))
                                    if !item.artists.isEmpty { Text(item.artists).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)) }
                                }
                                .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 3).contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
        }
    }

    private var spotifyStatus: String {
        switch auth.state {
        case .disconnected: return t(.spotifyNotConnected)
        case .connecting: return t(.spotifyConnecting)
        case .connected(let name): return L10n.string(.spotifyConnected, name, language: language)
        case .failed(let message): return L10n.string(.spotifyLoginFailed, message, language: language)
        }
    }

    // MARK: Building blocks

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)))
            }
    }

    private func row<Control: View>(_ symbol: String, _ title: String, _ hint: String, @ViewBuilder control: () -> Control) -> some View {
        card {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 17)).frame(width: 26).foregroundStyle(.white.opacity(0.85))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(hint).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 12)
                control()
            }
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, multiplier: Double = 1, suffix: String, decimals: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(String(format: "%.*f", decimals, value.wrappedValue * multiplier) + suffix)
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(.white.opacity(0.55))
            }
            Slider(value: value, in: range)
        }
    }

    private func refreshLogin() {
        launchAtLogin = LoginItem.isEnabled
        loginNeedsApproval = LoginItem.requiresApproval
    }
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            log.error("\(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshLogin()
    }
}

private struct StatsRequest: Equatable {
    let range: SpotifyTimeRange
    let connected: Bool
}

/// Top artists and tracks per time range, loaded once per Settings window and range.
@MainActor
final class TopItemsModel: ObservableObject {
    enum Failure { case forbidden, other }

    @Published private(set) var items: [SpotifyTimeRange: (artists: [SpotifyTopItem], tracks: [SpotifyTopItem])] = [:]
    @Published private(set) var failure: Failure?
    private var loading: Set<SpotifyTimeRange> = []

    /// Another login may be a different account.
    func clear() {
        items = [:]
        failure = nil
    }

    func load(_ range: SpotifyTimeRange, api: SpotifyAPI) async {
        guard items[range] == nil, loading.insert(range).inserted else { return }
        defer { loading.remove(range) }
        do {
            async let artists = api.topItems("artists", range: range)
            async let tracks = api.topItems("tracks", range: range)
            items[range] = try await (artists, tracks)
            failure = nil
        } catch SpotifyError.http(403) {
            failure = .forbidden
        } catch {
            failure = .other
        }
    }
}
