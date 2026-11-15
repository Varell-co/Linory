import Charts
import SwiftUI
import LyricsCore

/// "Your music": Linory's own listening history (Spotify and Music), plus Spotify's top lists.
struct StatsView: View {
    @ObservedObject var recorder: ListeningRecorder
    @ObservedObject var auth: SpotifyAuth
    var openSettings: () -> Void
    @AppStorage("language") private var languageSetting = AppLanguage.system.rawValue
    @AppStorage(ListeningRecorder.enabledKey) private var historyEnabled = true
    @AppStorage("statsRange") private var rangeSetting = ListeningRange.week.rawValue
    @StateObject private var spotify = TopItemsModel()
    @State private var spotifyRange = SpotifyTimeRange.short
    @State private var hoveredBucket: Date?
    @State private var hoveredCell: ClockCell?
    @State private var confirmClear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct ClockCell: Equatable { let day: Int; let hour: Int }

    private var language: AppLanguage { (AppLanguage(rawValue: languageSetting) ?? .system).resolved(preferredLanguages: Locale.preferredLanguages) }
    private func t(_ key: L10nKey) -> String { L10n.string(key, language: language) }
    private var locale: Locale { Locale(identifier: language == .de ? "de_DE" : "en_US") }
    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar
    }
    private var range: ListeningRange { ListeningRange(rawValue: rangeSetting) ?? .week }

    var body: some View {
        // `revision` ticks while music plays, so the song in progress is counted live.
        let _ = recorder.revision
        let sessions = recorder.allSessions
        let summary = ListeningStats.summarize(sessions, range: range, now: Date(), calendar: calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if sessions.isEmpty {
                    card { Text(t(.statsNoHistory)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.7)) }
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    tiles(summary)
                    // Side-by-side cards share the taller one's height.
                    HStack(alignment: .top, spacing: 12) {
                        overTime(summary)
                        listeningClock(summary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 12) {
                        historyList(t(.listTopSongs), summary.topTracks)
                        historyList(t(.listTopArtists), summary.topArtists)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                spotifySection.padding(.top, 14)
                historySettings.padding(.top, 14)
            }
            .padding(.horizontal, 28).padding(.top, 44).padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 860, height: 640)
        .background(GlassBackground(cornerRadius: Brand.panelCornerRadius, strength: 1))
        .clipShape(RoundedRectangle(cornerRadius: Brand.panelCornerRadius, style: .continuous))
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .tint(Brand.waveBlue)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, locale)
        .animation(reduceMotion ? nil : Motion.easeOut(0.25), value: rangeSetting)
    }

    // MARK: Header and tiles

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t(.sectionStats)).font(.system(size: 22, weight: .semibold))
                Text(t(.historySubtitle)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Picker("", selection: $rangeSetting) {
                Text(t(.rangeToday)).tag(ListeningRange.today.rawValue)
                Text(t(.range7Days)).tag(ListeningRange.week.rawValue)
                Text(t(.range30Days)).tag(ListeningRange.month.rawValue)
                Text(t(.rangeYear)).tag(ListeningRange.year.rawValue)
                Text(t(.rangeAll)).tag(ListeningRange.all.rawValue)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
        .padding(.bottom, 6)
    }

    private func tiles(_ summary: ListeningSummary) -> some View {
        HStack(spacing: 12) {
            tile(t(.tileListening), duration(summary.seconds),
                 range == .today || summary.buckets.isEmpty ? nil : L10n.string(.tileListeningDetail, duration(summary.seconds / Double(dayCount(summary))), language: language))
            tile(t(.tilePlays), "\(summary.plays)",
                 summary.plays > 0 ? L10n.string(.tilePlaysDetail, Int((summary.syncedShare * 100).rounded()), language: language) : nil)
            tile(t(.tileStreak), "\(summary.streakDays)", t(.tileStreakDetail))
            tile(t(.tileSkips), "\(Int((summary.skipRate * 100).rounded())) %", t(.tileSkipsDetail))
        }
    }

    private func tile(_ title: String, _ value: String, _ detail: String?) -> some View {
        card(spacing: 4) {
            Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(detail ?? " ").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
        }
    }

    // MARK: Charts

    private func overTime(_ summary: ListeningSummary) -> some View {
        let component: Calendar.Component = summary.unit == .hour ? .hour : summary.unit == .day ? .day : .month
        let hovered = summary.buckets.first { $0.start == hoveredBucket }
        let peak = summary.buckets.max { $0.seconds < $1.seconds }
        return card {
            Text(t(.chartOverTime)).font(.system(size: 13, weight: .medium))
            Chart(summary.buckets) { bucket in
                BarMark(x: .value("Time", bucket.start, unit: component), y: .value("Minutes", bucket.seconds / 60))
                    .cornerRadius(3)
                    .foregroundStyle(Brand.waveBlue.opacity(hoveredBucket == nil || hoveredBucket == bucket.start ? 1 : 0.4))
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel().foregroundStyle(.white.opacity(0.45))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 7)) {
                    AxisValueLabel(format: axisFormat(summary), centered: true).foregroundStyle(.white.opacity(0.45))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            guard case .active(let point) = phase,
                                  let date: Date = proxy.value(atX: point.x - geometry[proxy.plotAreaFrame].origin.x) else {
                                hoveredBucket = nil
                                return
                            }
                            hoveredBucket = summary.buckets.last { $0.start <= date }?.start
                        }
                }
            }
            .frame(height: 150)
            caption(hovered.map { "\(bucketLabel($0.start, summary)) · \(duration($0.seconds))" }
                    ?? peak.flatMap { $0.seconds > 0 ? "\(t(.chartHoverHint))" : nil })
        }
    }

    private func listeningClock(_ summary: ListeningSummary) -> some View {
        let maximum = summary.clock.flatMap { $0 }.max() ?? 0
        // Monday first, matching the summary's rows.
        let weekdays = (0..<7).map { calendar.shortWeekdaySymbols[($0 + 1) % 7] }
        return card {
            Text(t(.chartClock)).font(.system(size: 13, weight: .medium))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(0..<7, id: \.self) { day in
                    HStack(spacing: 2) {
                        Text(weekdays[day]).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                            .frame(width: 28, alignment: .leading)
                        ForEach(0..<24, id: \.self) { hour in
                            let seconds = summary.clock[day][hour]
                            let cell = ClockCell(day: day, hour: hour)
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(heat(seconds, maximum: maximum))
                                .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .strokeBorder(.white.opacity(hoveredCell == cell ? 0.8 : 0), lineWidth: 1))
                                // Width from the card, a fixed height: the cells stay square-ish at the window's fixed size.
                                .frame(maxWidth: .infinity).frame(height: 12)
                                .onHover { inside in
                                    if inside { hoveredCell = cell } else if hoveredCell == cell { hoveredCell = nil }
                                }
                        }
                    }
                }
                HStack(spacing: 0) {
                    Color.clear.frame(width: 30, height: 1)
                    ForEach([0, 6, 12, 18], id: \.self) { hour in
                        Text(hourLabel(hour)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 2)
            }
            HStack(spacing: 8) {
                caption(hoveredCell.map { cell in
                    "\(weekdays[cell.day]) \(hourLabel(cell.hour))–\(hourLabel((cell.hour + 1) % 24)) · \(duration(summary.clock[cell.day][cell.hour]))"
                } ?? t(.chartHoverHint))
                Spacer(minLength: 0)
                // Sequential legend: one hue, light to strong.
                HStack(spacing: 3) {
                    Text(t(.chartLess)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                    ForEach(0..<5, id: \.self) { step in
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(heatStep(step)).frame(width: 9, height: 9)
                    }
                    Text(t(.chartMore)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }

    /// Five steps of one hue; empty hours stay a faint neutral so the grid stays visible.
    private func heat(_ seconds: Double, maximum: Double) -> Color {
        guard seconds > 0, maximum > 0 else { return heatStep(0) }
        return heatStep(min(4, 1 + Int((seconds / maximum) * 3.999)))
    }

    private func heatStep(_ step: Int) -> Color {
        step == 0 ? .white.opacity(0.06) : Brand.waveBlue.opacity([0, 0.3, 0.5, 0.75, 1][step])
    }

    private func caption(_ text: String?) -> some View {
        Text(text ?? " ").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).monospacedDigit().lineLimit(1)
    }

    // MARK: Lists

    private func historyList(_ title: String, _ entries: [ListeningSummary.Entry]) -> some View {
        let longest = entries.first?.seconds ?? 1
        return card {
            Text(title).font(.system(size: 13, weight: .medium))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { rank, entry in
                    let row = VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(rank + 1)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                                .foregroundStyle(.white.opacity(0.45)).frame(width: 16, alignment: .trailing)
                            (Text(entry.title) + Text(verbatim: entry.subtitle.isEmpty ? "" : "  \(entry.subtitle)").foregroundColor(.white.opacity(0.5)))
                                .font(.system(size: 12.5)).lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(duration(entry.seconds)) · \(L10n.string(.playsCount, entry.plays, language: language))")
                                .font(.system(size: 11)).monospacedDigit().foregroundStyle(.white.opacity(0.5)).layoutPriority(1)
                        }
                        // Thin bar, relative to the top entry.
                        GeometryReader { geometry in
                            Capsule().fill(Brand.waveBlue.opacity(0.85))
                                .frame(width: max(3, geometry.size.width * entry.seconds / longest), height: 3)
                        }
                        .frame(height: 3).padding(.leading, 24)
                    }
                    .contentShape(Rectangle())
                    if let uri = entry.uri {
                        Button { SpotifyLink.open(uri) } label: { row }.buttonStyle(PressableStyle(scale: 0.99))
                    } else {
                        row
                    }
                }
            }
        }
    }

    // MARK: Spotify

    @ViewBuilder private var spotifySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom) {
                Text(t(.statsOnSpotify)).font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
                if auth.isConnected {
                    Picker("", selection: $spotifyRange) {
                        Text(t(.statsRangeShort)).tag(SpotifyTimeRange.short)
                        Text(t(.statsRangeMedium)).tag(SpotifyTimeRange.medium)
                        Text(t(.statsRangeLong)).tag(SpotifyTimeRange.long)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            Text(t(.statsSubtitle)).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
        }
        .padding(.bottom, 4)
        Group {
            if !auth.isConnected {
                card {
                    HStack {
                        Text(t(.statsConnectHint)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                        Spacer(minLength: 8)
                        Button(t(.statsOpenSpotify), action: openSettings)
                    }
                }
            } else {
                // Logins from before stats existed lack `user-top-read`; Spotify then answers 403.
                if auth.needsReconnect || spotify.failure == .forbidden {
                    HStack {
                        Label(t(.statsReconnectHint), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Spacer(minLength: 8)
                        Button(t(.spotifyReconnect)) { auth.connect() }
                    }
                    .font(.caption).padding(.horizontal, 4)
                } else if spotify.failure == .other {
                    Label(t(.statsError), systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).padding(.horizontal, 4)
                }
                let items = spotify.items[spotifyRange]
                HStack(alignment: .top, spacing: 12) {
                    spotifyList(t(.statsTopArtists), items?.artists)
                    spotifyList(t(.statsTopTracks), items?.tracks)
                }
            }
        }
        .task(id: "\(spotifyRange.rawValue)|\(auth.isConnected)") {
            if auth.isConnected { await spotify.load(spotifyRange, api: auth.api) } else { spotify.clear() }
        }
    }

    /// Display only. Each row opens the artist or track in Spotify.
    private func spotifyList(_ title: String, _ items: [SpotifyTopItem]?) -> some View {
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
                                (Text(item.name) + Text(verbatim: item.artists.isEmpty ? "" : "  \(item.artists)").foregroundColor(.white.opacity(0.5)))
                                    .font(.system(size: 12.5)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 3).contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.99))
                    }
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: History settings

    private var historySettings: some View {
        card {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 17)).frame(width: 26).foregroundStyle(.white.opacity(0.85))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t(.historyKeep)).font(.system(size: 13, weight: .medium))
                    Text(t(.historyKeepHint)).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 12)
                // Two steps instead of a dialog: the first click arms, a second one within 4 s deletes.
                Button(confirmClear ? t(.historyClearConfirm) : t(.historyClear)) {
                    if confirmClear {
                        recorder.clear()
                        confirmClear = false
                    } else {
                        confirmClear = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { confirmClear = false }
                    }
                }
                .foregroundStyle(confirmClear ? Color.red : .primary)
                .disabled(recorder.allSessions.isEmpty)
                Toggle("", isOn: $historyEnabled).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    // MARK: Building blocks

    private func card<Content: View>(spacing: CGFloat = 12, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.08)))
            }
    }

    private func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes < 60
            ? L10n.string(.durationMinutes, minutes, language: language)
            : L10n.string(.durationHours, minutes / 60, minutes % 60, language: language)
    }

    /// Days the range covers so far, for the daily average.
    private func dayCount(_ summary: ListeningSummary) -> Int {
        guard summary.unit == .month, let first = summary.buckets.first?.start else { return max(1, summary.buckets.count) }
        return max(1, (calendar.dateComponents([.day], from: first, to: Date()).day ?? 0) + 1)
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour().locale(locale))
    }

    private func axisFormat(_ summary: ListeningSummary) -> Date.FormatStyle {
        // Charts formats axis dates in the system locale unless the style carries the app language.
        switch (summary.unit, range) {
        case (.hour, _): return .dateTime.hour().locale(locale)
        case (.day, .week): return .dateTime.weekday(.abbreviated).locale(locale)
        case (.day, _): return .dateTime.day().locale(locale)
        default: return .dateTime.month(.abbreviated).locale(locale)
        }
    }

    private func bucketLabel(_ date: Date, _ summary: ListeningSummary) -> String {
        switch summary.unit {
        case .hour: return "\(hourLabel(calendar.component(.hour, from: date)))"
        case .day: return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
        case .month: return date.formatted(.dateTime.month(.wide).year().locale(locale))
        }
    }
}

/// Spotify's top artists and tracks per time range, loaded once per window and range.
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
