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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var language: AppLanguage { (AppLanguage(rawValue: languageSetting) ?? .system).resolved(preferredLanguages: Locale.preferredLanguages) }

    private var lines: [LyricLine] { model.lyrics?.lines ?? [] }
    private func visibleLines(active: Int?) -> [(Int, LyricLine)] {
        guard !lines.isEmpty else { return [] }
        let start = max(0, (active ?? 0) - 1)
        return Array(lines.enumerated().dropFirst(start).prefix(active == nil || active == 0 ? 3 : 4))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button(action: showSettings) {
                    LinorySymbol()
                        .frame(width: 22, height: 17)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.string(.openSettingsHelp, language: language))
                Text(model.track.map { "\($0.title)  ·  \($0.artist)" } ?? L10n.string(.overlayPlaceholder, language: language))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if model.lyrics?.synced == false && !lines.isEmpty {
                    Text(StatusMessage.notSynced.text(language: language)).italic().layoutPriority(1)
                }
            }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.62))
            if lines.isEmpty {
                Text(model.status.text(language: language)).font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.8))
            } else {
                // Redraws between polls from the interpolated clock; paused while playback is paused.
                TimelineView(.animation(minimumInterval: 0.05, paused: !model.clock.playing)) { context in
                    lyrics(active: LRC.currentIndex(lines, at: model.clock.position(at: context.date) + offset))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Brand.ink.opacity(opacity), in: RoundedRectangle(cornerRadius: Brand.panelCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Brand.panelCornerRadius).strokeBorder(.white.opacity(0.1 * opacity)))
        .opacity(overlayOpacity)
    }

    private func lyrics(active: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(visibleLines(active: active), id: \.0) { index, line in
                let isActive = index == active
                Text(line.text.isEmpty ? "♪" : line.text)
                    .font(.system(size: isActive ? fontSize : fontSize * 0.8, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isActive ? 1 : 0.5))
                    .lineLimit(2)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Soft wave-blue band behind the active line, as in the brand concept.
                    .background(Brand.waveBlue.opacity(isActive ? 0.3 : 0), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, -10)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: active)
    }
}
