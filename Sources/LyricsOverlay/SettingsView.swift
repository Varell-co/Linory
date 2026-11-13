import SwiftUI
import LyricsCore
import os

struct SettingsView: View {
    @AppStorage("fontSize") private var fontSize = 25.0
    @AppStorage("opacity") private var opacity = 0.78
    @AppStorage("overlayOpacity") private var overlayOpacity = 1.0
    @AppStorage("offset") private var offset = 0.0
    @AppStorage("overlayWidth") private var width = 400.0
    @AppStorage("overlayHeight") private var height = 240.0
    @AppStorage("language") private var languageSetting = AppLanguage.system.rawValue
    @AppStorage("source") private var source = SourcePreference.auto.rawValue
    @AppStorage("autoHide") private var autoHide = false
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.requiresApproval
    @State private var loginError: String?
    private let log = Logger(subsystem: LyricsService.subsystem, category: "login")
    var resize: () -> Void

    private var language: AppLanguage { (AppLanguage(rawValue: languageSetting) ?? .system).resolved(preferredLanguages: Locale.preferredLanguages) }
    private func t(_ key: L10nKey) -> String { L10n.string(key, language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                LinorySymbol().frame(width: 40, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Brand.name).font(.title2.weight(.semibold))
                    Text(t(.tagline)).font(.callout).foregroundStyle(.secondary)
                }
            }
            section(.sectionAppearance)
            control(t(.fontSize), value: $fontSize, range: 14...44, suffix: " pt")
            control(t(.overlayOpacity), value: $overlayOpacity, range: 0.15...1, multiplier: 100, suffix: t(.opacitySuffix))
            control(t(.backgroundOpacity), value: $opacity, range: 0...1, multiplier: 100, suffix: t(.opacitySuffix))
            control(t(.width), value: $width, range: 260...800, suffix: " px")
            control(t(.height), value: $height, range: 160...500, suffix: " px")
            section(.sectionTiming)
            control(t(.timingOffset), value: $offset, range: -5...5, suffix: " s", decimals: 1)
            section(.sectionPlayback)
            Picker(t(.source), selection: $source) {
                Text(t(.sourceAuto)).tag(SourcePreference.auto.rawValue)
                Text(t(.sourceSpotify)).tag(SourcePreference.spotify.rawValue)
                Text(t(.sourceMusic)).tag(SourcePreference.music.rawValue)
            }
            Toggle(t(.autoHide), isOn: $autoHide)
            section(.sectionGeneral)
            Picker(t(.language), selection: $languageSetting) {
                Text(t(.languageSystem)).tag(AppLanguage.system.rawValue)
                Text(t(.languageEnglish)).tag(AppLanguage.en.rawValue)
                Text(t(.languageGerman)).tag(AppLanguage.de.rawValue)
            }
            Toggle(t(.launchAtLogin), isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            if loginNeedsApproval {
                HStack {
                    Label(t(.loginNeedsApproval), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Button(t(.loginOpenSettings)) { LoginItem.openSystemSettings() }
                }.font(.caption)
            }
            if let loginError {
                Label(L10n.string(.loginError, loginError, language: language), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Text(t(.settingsFooter))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(t(.endorsement)).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(24).frame(width: 420)
        .onChange(of: width) { _ in resize() }
        .onChange(of: height) { _ in resize() }
        .onAppear(perform: refreshLogin)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refreshLogin() }
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
    private func section(_ key: L10nKey) -> some View {
        Text(t(key)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
    }
    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, multiplier: Double = 1, suffix: String, decimals: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text(String(format: "%.*f", decimals, value.wrappedValue * multiplier) + suffix).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range)
        }
    }
}
