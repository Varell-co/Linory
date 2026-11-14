import SwiftUI
import LyricsCore

/// State and actions the menu needs from the app.
final class MenuActions: ObservableObject {
    @Published var overlayVisible = true
    @Published var clickThrough = false
    var toggleOverlay: () -> Void = {}
    var toggleClickThrough: () -> Void = {}
    var moveTo: (String) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var quit: () -> Void = {}
}

/// The status-item menu content, shown in a glass panel (see MenuWindow) so it can animate: hover highlights, sections that expand
/// smoothly, and a Now Playing header.
struct MenuPanel: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var actions: MenuActions
    @AppStorage("source") private var source = SourcePreference.auto.rawValue
    @AppStorage("language") private var languageSetting = AppLanguage.system.rawValue
    @State private var expanded: Section?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    enum Section: CaseIterable { case position, source }

    init(model: PlayerModel, actions: MenuActions, expanded: Section? = nil) {
        _model = ObservedObject(wrappedValue: model)
        _actions = ObservedObject(wrappedValue: actions)
        _expanded = State(initialValue: expanded)
    }

    private var language: AppLanguage { (AppLanguage(rawValue: languageSetting) ?? .system).resolved(preferredLanguages: Locale.preferredLanguages) }
    private func t(_ key: L10nKey) -> String { L10n.string(key, language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            nowPlaying.padding(.bottom, 6)
            Divider().padding(.horizontal, 6)
            toggleRow("rectangle.on.rectangle", t(.showOverlay), isOn: actions.overlayVisible, action: actions.toggleOverlay)
            toggleRow("cursorarrow.motionlines", t(.clickThrough), isOn: actions.clickThrough, action: actions.toggleClickThrough)
            disclosureRow("arrow.up.left.and.arrow.down.right", t(.position), .position)
            if expanded == .position { cornerGrid.transition(sectionTransition) }
            disclosureRow("music.note.list", t(.source), .source)
            if expanded == .source { sourcePicker.transition(sectionTransition) }
            Divider().padding(.horizontal, 6).padding(.vertical, 4)
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
    }

    private var sectionTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6))
    }

    /// Same header as the overlay: cover art, title, artist.
    private var nowPlaying: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return HStack(spacing: 10) {
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.top, 6)
    }

    private func toggleRow(_ symbol: String, _ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        MenuRow(symbol: symbol, title: title, action: action) {
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in action() }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
    }

    private func disclosureRow(_ symbol: String, _ title: String, _ section: Section) -> some View {
        MenuRow(symbol: symbol, title: title, action: {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Motion.lineChange) { expanded = expanded == section ? nil : section }
        }) {
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
        .padding(.horizontal, 10).padding(.bottom, 6)
    }

    private var sourcePicker: some View {
        Picker("", selection: $source) {
            Text(t(.sourceAuto)).tag(SourcePreference.auto.rawValue)
            Text(t(.sourceSpotify)).tag(SourcePreference.spotify.rawValue)
            Text(t(.sourceMusic)).tag(SourcePreference.music.rawValue)
        }
        .pickerStyle(.segmented).labelsHidden()
        .padding(.horizontal, 10).padding(.bottom, 6)
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
