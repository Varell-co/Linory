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
    private var language: AppLanguage { (AppLanguage(rawValue: languageSetting) ?? .system).resolved(preferredLanguages: Locale.preferredLanguages) }

    private func visibleLines(active: Int?) -> [(Int, LyricLine)] {
        guard !model.lines.isEmpty else { return [] }
        let start = max(0, (active ?? 0) - 1)
        return Array(model.lines.enumerated().dropFirst(start).prefix(active == nil || active == 0 ? 3 : 4))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button(action: showSettings) {
                    Image(systemName: "music.note")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.string(.openSettingsHelp, language: language))
                Text(model.track.map { "\($0.title)  ·  \($0.artist)" } ?? L10n.string(.overlayPlaceholder, language: language))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.62))
            if model.lines.isEmpty {
                Text(model.status.text(language: language)).font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.8))
            } else {
                // Redraws between polls from the interpolated clock; paused while playback is paused.
                TimelineView(.animation(minimumInterval: 0.05, paused: !model.clock.playing)) { context in
                    lyrics(active: LRC.currentIndex(model.lines, at: model.clock.position(at: context.date) + offset))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(opacity), in: RoundedRectangle(cornerRadius: 16))
        .opacity(overlayOpacity)
    }

    private func lyrics(active: Int?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleLines(active: active), id: \.0) { index, line in
                Text(line.text.isEmpty ? "♪" : line.text)
                    .font(.system(size: index == active ? fontSize : fontSize * 0.8, weight: index == active ? .bold : .medium))
                    .foregroundStyle(.white.opacity(index == active ? 1 : 0.4))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: active)
    }
}
