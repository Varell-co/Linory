import Foundation

/// UI language setting. `system` follows the macOS language order, with English as the fallback.
public enum AppLanguage: String, CaseIterable {
    case system, en, de

    public func resolved(preferredLanguages: [String]) -> AppLanguage {
        guard self == .system else { return self }
        return preferredLanguages.first?.lowercased().hasPrefix("de") == true ? .de : .en
    }
}

public enum L10nKey: String, CaseIterable {
    // Status-item menu
    case hideOverlay, showOverlay, clickThrough, position
    case topLeft, topRight, bottomLeft, bottomRight
    case settingsMenu, quit
    case statusItemDescription, statusItemTooltip
    // Windows and overlay
    case settingsWindowTitle, openSettingsHelp, overlayPlaceholder, tagline, endorsement
    // Settings
    case sectionAppearance, sectionTiming, sectionGeneral, sectionAbout
    case generalSubtitle, overlaySubtitle, timingSubtitle, aboutSubtitle, version
    case sourceHint, autoHideHint, launchAtLoginHint, languageHint, hotKeyTitle, hotKeyHint, timingHint, privacyNote
    case source, sourceAuto, sourceSpotify, sourceMusic, playerNameSpotify, playerNameMusic
    case fontSize, overlayOpacity, backgroundOpacity, width, height, timingOffset, opacitySuffix
    case language, languageSystem, languageEnglish, languageGerman
    case autoHide, launchAtLogin, loginNeedsApproval, loginOpenSettings, loginError
    // Hotkey alert
    case hotKeyErrorTitle, hotKeyErrorText
    // Status messages
    case statusWaitingForPlayer, statusOpenPlayer, statusAutomationDenied, statusPlayerError
    case statusNoTrack, statusSearching, statusNetworkError, statusNoLyrics, statusInstrumental, statusNotSynced
}

public enum L10n {
    public static func string(_ key: L10nKey, _ args: CVarArg..., language: AppLanguage) -> String {
        string(key, arguments: args, language: language)
    }

    public static func string(_ key: L10nKey, arguments: [CVarArg], language: AppLanguage) -> String {
        let resolved = language.resolved(preferredLanguages: Locale.preferredLanguages)
        let format = table[resolved]?[key] ?? table[.en]?[key] ?? key.rawValue
        return arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }

    /// Raw table value, used by the completeness check.
    public static func raw(_ key: L10nKey, language: AppLanguage) -> String? { table[language]?[key] }

    private static let table: [AppLanguage: [L10nKey: String]] = [
        .en: [
            .hideOverlay: "Hide overlay",
            .showOverlay: "Show overlay",
            .clickThrough: "Click-through",
            .position: "Position",
            .topLeft: "Top left",
            .topRight: "Top right",
            .bottomLeft: "Bottom left",
            .bottomRight: "Bottom right",
            .settingsMenu: "Settings…",
            .quit: "Quit",
            .statusItemDescription: "Linory – Settings",
            .statusItemTooltip: "Open settings · Right-click for menu",
            .settingsWindowTitle: "Linory – Settings",
            .openSettingsHelp: "Open settings",
            .overlayPlaceholder: "Linory",
            .tagline: "Lyrics in your flow.",
            .endorsement: "A Varell product",
            .source: "Source",
            .sourceAuto: "Auto",
            .sourceSpotify: "Spotify",
            .sourceMusic: "Apple Music",
            .playerNameSpotify: "Spotify",
            .playerNameMusic: "Music",
            .fontSize: "Font size",
            .overlayOpacity: "Opacity: whole overlay",
            .backgroundOpacity: "Opacity: background",
            .width: "Width",
            .height: "Height",
            .timingOffset: "Timing offset",
            .opacitySuffix: " % opacity",
            .language: "Language",
            .languageSystem: "System",
            .languageEnglish: "English",
            .languageGerman: "Deutsch",
            .autoHide: "Auto-hide when nothing is playing",
            .launchAtLogin: "Launch at login",
            .loginNeedsApproval: "Needs approval in System Settings.",
            .loginOpenSettings: "Open System Settings…",
            .loginError: "Could not change the login item: %@",
            .hotKeyErrorTitle: "Shortcut unavailable",
            .hotKeyErrorText: "⌥ ⇧ L could not be registered. Another app may be using this shortcut. You can still show and hide the overlay from the menu.",
            .statusWaitingForPlayer: "Waiting for Spotify or Music…",
            .statusOpenPlayer: "Open Spotify or Music and play a song.",
            .statusAutomationDenied: "Allow access to %@: System Settings → Privacy & Security → Automation.",
            .statusPlayerError: "%@ could not be read: %@",
            .statusNoTrack: "Play a song in %@.",
            .statusSearching: "Searching for lyrics…",
            .statusNetworkError: "Lyrics could not be loaded. Check your internet connection.",
            .statusNoLyrics: "No lyrics found for this song.",
            .statusInstrumental: "♪ Instrumental",
            .statusNotSynced: "~ not synced",
            .sectionAppearance: "Overlay",
            .sectionTiming: "Timing",
            .sectionGeneral: "General",
            .sectionAbout: "About",
            .generalSubtitle: "Core settings and behavior.",
            .overlaySubtitle: "Size, type and transparency.",
            .timingSubtitle: "Line up lyrics with the music.",
            .aboutSubtitle: "Lyrics in your flow.",
            .version: "Version %@",
            .sourceHint: "Which player Linory follows.",
            .autoHideHint: "Hide the overlay a few seconds after playback stops.",
            .launchAtLoginHint: "Start Linory automatically with macOS.",
            .languageHint: "Language of the Linory interface.",
            .hotKeyTitle: "Overlay hotkey",
            .hotKeyHint: "Show or hide the lyrics overlay.",
            .timingHint: "Positive values show lyrics earlier.",
            .privacyNote: "Song title, artist, album and duration are sent to LRCLIB to find lyrics. Results are cached on this Mac.",
        ],
        .de: [
            .hideOverlay: "Overlay ausblenden",
            .showOverlay: "Overlay einblenden",
            .clickThrough: "Klicks durchlassen",
            .position: "Position",
            .topLeft: "Oben links",
            .topRight: "Oben rechts",
            .bottomLeft: "Unten links",
            .bottomRight: "Unten rechts",
            .settingsMenu: "Einstellungen …",
            .quit: "Beenden",
            .statusItemDescription: "Linory – Einstellungen",
            .statusItemTooltip: "Einstellungen öffnen · Rechtsklick für Menü",
            .settingsWindowTitle: "Linory – Einstellungen",
            .openSettingsHelp: "Einstellungen öffnen",
            .overlayPlaceholder: "Linory",
            .tagline: "Lyrics in deinem Flow.",
            .endorsement: "Ein Produkt von Varell",
            .source: "Quelle",
            .sourceAuto: "Automatisch",
            .sourceSpotify: "Spotify",
            .sourceMusic: "Apple Music",
            .playerNameSpotify: "Spotify",
            .playerNameMusic: "Musik",
            .fontSize: "Schriftgröße",
            .overlayOpacity: "Transparenz: gesamtes Overlay",
            .backgroundOpacity: "Transparenz: Hintergrund",
            .width: "Breite",
            .height: "Höhe",
            .timingOffset: "Timing-Korrektur",
            .opacitySuffix: " % Deckkraft",
            .language: "Sprache",
            .languageSystem: "System",
            .languageEnglish: "English",
            .languageGerman: "Deutsch",
            .autoHide: "Ausblenden, wenn nichts läuft",
            .launchAtLogin: "Bei Anmeldung starten",
            .loginNeedsApproval: "Muss in den Systemeinstellungen erlaubt werden.",
            .loginOpenSettings: "Systemeinstellungen öffnen …",
            .loginError: "Anmeldeobjekt konnte nicht geändert werden: %@",
            .hotKeyErrorTitle: "Hotkey nicht verfügbar",
            .hotKeyErrorText: "⌥ ⇧ L konnte nicht registriert werden. Möglicherweise verwendet eine andere App diese Tastenkombination. Das Overlay lässt sich weiterhin über das Menü ein- und ausblenden.",
            .statusWaitingForPlayer: "Warte auf Spotify oder Musik …",
            .statusOpenPlayer: "Öffne Spotify oder Musik und spiele einen Song ab.",
            .statusAutomationDenied: "Zugriff auf %@ erlauben: Systemeinstellungen → Datenschutz & Sicherheit → Automation.",
            .statusPlayerError: "%@ konnte nicht gelesen werden: %@",
            .statusNoTrack: "Spiele einen Song in %@ ab.",
            .statusSearching: "Suche Lyrics …",
            .statusNetworkError: "Lyrics konnten nicht geladen werden. Prüfe deine Internetverbindung.",
            .statusNoLyrics: "Keine Lyrics für diesen Song gefunden.",
            .statusInstrumental: "♪ Instrumental",
            .statusNotSynced: "~ nicht synchron",
            .sectionAppearance: "Overlay",
            .sectionTiming: "Timing",
            .sectionGeneral: "Allgemein",
            .sectionAbout: "Über",
            .generalSubtitle: "Grundeinstellungen und Verhalten.",
            .overlaySubtitle: "Größe, Schrift und Transparenz.",
            .timingSubtitle: "Lyrics an die Musik anpassen.",
            .aboutSubtitle: "Lyrics in deinem Flow.",
            .version: "Version %@",
            .sourceHint: "Welchem Player Linory folgt.",
            .autoHideHint: "Overlay einige Sekunden nach dem Stoppen ausblenden.",
            .launchAtLoginHint: "Linory automatisch mit macOS starten.",
            .languageHint: "Sprache der Linory-Oberfläche.",
            .hotKeyTitle: "Overlay-Hotkey",
            .hotKeyHint: "Lyrics-Overlay ein- oder ausblenden.",
            .timingHint: "Positive Werte zeigen die Lyrics früher.",
            .privacyNote: "Songtitel, Interpret, Album und Dauer werden zur Suche an LRCLIB gesendet. Ergebnisse werden auf diesem Mac zwischengespeichert.",
        ],
    ]
}

/// Status shown in the overlay. Stored typed and rendered at display time so a language switch re-renders it.
public enum StatusMessage: Hashable, Error {
    case waitingForPlayer, openPlayer
    case automationDenied(PlayerSource)
    case playerError(PlayerSource, String)
    case noTrack(PlayerSource)
    case searching, networkError, noLyrics, instrumental, notSynced

    public func text(language: AppLanguage) -> String {
        switch self {
        case .waitingForPlayer: return L10n.string(.statusWaitingForPlayer, language: language)
        case .openPlayer: return L10n.string(.statusOpenPlayer, language: language)
        case .automationDenied(let source): return L10n.string(.statusAutomationDenied, source.name(language: language), language: language)
        case .playerError(let source, let detail): return L10n.string(.statusPlayerError, source.name(language: language), detail, language: language)
        case .noTrack(let source): return L10n.string(.statusNoTrack, source.name(language: language), language: language)
        case .searching: return L10n.string(.statusSearching, language: language)
        case .networkError: return L10n.string(.statusNetworkError, language: language)
        case .noLyrics: return L10n.string(.statusNoLyrics, language: language)
        case .instrumental: return L10n.string(.statusInstrumental, language: language)
        case .notSynced: return L10n.string(.statusNotSynced, language: language)
        }
    }
}

extension PlayerSource {
    /// The app name as macOS shows it ("Musik" on German systems).
    public func name(language: AppLanguage) -> String {
        L10n.string(self == .spotify ? .playerNameSpotify : .playerNameMusic, language: language)
    }
}
