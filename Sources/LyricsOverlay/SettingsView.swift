import SwiftUI
import LyricsCore

struct SettingsView: View {
    @AppStorage("fontSize") private var fontSize = 25.0
    @AppStorage("opacity") private var opacity = 0.78
    @AppStorage("overlayOpacity") private var overlayOpacity = 1.0
    @AppStorage("offset") private var offset = 0.0
    @AppStorage("overlayWidth") private var width = 400.0
    @AppStorage("overlayHeight") private var height = 240.0
    @AppStorage("language") private var languageSetting = AppLanguage.system.rawValue
    var resize: () -> Void

    private var language: AppLanguage { (AppLanguage(rawValue: languageSetting) ?? .system).resolved(preferredLanguages: Locale.preferredLanguages) }
    private func t(_ key: L10nKey) -> String { L10n.string(key, language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lyrics Overlay").font(.title2.bold())
            section(.sectionAppearance)
            control(t(.fontSize), value: $fontSize, range: 14...44, suffix: " pt")
            control(t(.overlayOpacity), value: $overlayOpacity, range: 0.15...1, multiplier: 100, suffix: t(.opacitySuffix))
            control(t(.backgroundOpacity), value: $opacity, range: 0...1, multiplier: 100, suffix: t(.opacitySuffix))
            control(t(.width), value: $width, range: 260...800, suffix: " px")
            control(t(.height), value: $height, range: 160...500, suffix: " px")
            section(.sectionTiming)
            control(t(.timingOffset), value: $offset, range: -5...5, suffix: " s", decimals: 1)
            section(.sectionGeneral)
            Picker(t(.language), selection: $languageSetting) {
                Text(t(.languageSystem)).tag(AppLanguage.system.rawValue)
                Text(t(.languageEnglish)).tag(AppLanguage.en.rawValue)
                Text(t(.languageGerman)).tag(AppLanguage.de.rawValue)
            }
            Text(t(.settingsFooter))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24).frame(width: 420)
        .onChange(of: width) { _ in resize() }
        .onChange(of: height) { _ in resize() }
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
