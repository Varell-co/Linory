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
    case settingsWindowTitle, openSettingsHelp, overlayPlaceholder
    // Settings
    case sectionAppearance, sectionTiming, sectionGeneral
    case fontSize, overlayOpacity, backgroundOpacity, width, height, timingOffset, opacitySuffix
    case language, languageSystem, languageEnglish, languageGerman
    case settingsFooter
    // Hotkey alert
    case hotKeyErrorTitle, hotKeyErrorText
    // Status messages
    case statusWaitingForPlayer, statusOpenPlayer, statusAutomationDenied, statusPlayerError
    case statusNoTrack, statusSearching, statusNetworkError, statusNoLyrics
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
            .statusItemDescription: "Lyrics Overlay – Settings",
            .statusItemTooltip: "Open settings · Right-click for menu",
            .settingsWindowTitle: "Lyrics Overlay – Settings",
            .openSettingsHelp: "Open settings",
            .overlayPlaceholder: "LYRICS OVERLAY",
            .sectionAppearance: "APPEARANCE",
            .sectionTiming: "TIMING",
            .sectionGeneral: "GENERAL",
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
            .settingsFooter: "Show/hide overlay: ⌥ ⇧ L\nPositive offsets show lyrics earlier. Song title and artist are sent to LRCLIB for the search.",
            .hotKeyErrorTitle: "Shortcut unavailable",
            .hotKeyErrorText: "⌥ ⇧ L could not be registered. Another app may be using this shortcut. You can still show and hide the overlay from the menu.",
            .statusWaitingForPlayer: "Waiting for Spotify…",
            .statusOpenPlayer: "Open Spotify and play a song.",
            .statusAutomationDenied: "Allow access to Spotify: System Settings → Privacy & Security → Automation.",
            .statusPlayerError: "Spotify could not be read: %@",
            .statusNoTrack: "Play a song in Spotify.",
            .statusSearching: "Searching for synced lyrics…",
            .statusNetworkError: "Lyrics could not be loaded. Check your internet connection.",
            .statusNoLyrics: "No synced lyrics found for this song.",
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
            .statusItemDescription: "Lyrics Overlay – Einstellungen",
            .statusItemTooltip: "Einstellungen öffnen · Rechtsklick für Menü",
            .settingsWindowTitle: "Lyrics Overlay – Einstellungen",
            .openSettingsHelp: "Einstellungen öffnen",
            .overlayPlaceholder: "LYRICS OVERLAY",
            .sectionAppearance: "DARSTELLUNG",
            .sectionTiming: "TIMING",
            .sectionGeneral: "ALLGEMEIN",
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
            .settingsFooter: "Overlay ein-/ausblenden: ⌥ ⇧ L\nPositive Werte zeigen die Lyrics früher. Songtitel und Interpret werden zur Suche an LRCLIB gesendet.",
            .hotKeyErrorTitle: "Hotkey nicht verfügbar",
            .hotKeyErrorText: "⌥ ⇧ L konnte nicht registriert werden. Möglicherweise verwendet eine andere App diese Tastenkombination. Das Overlay lässt sich weiterhin über das Menü ein- und ausblenden.",
            .statusWaitingForPlayer: "Warte auf Spotify …",
            .statusOpenPlayer: "Öffne Spotify und spiele einen Song ab.",
            .statusAutomationDenied: "Spotify-Zugriff erlauben: Systemeinstellungen → Datenschutz & Sicherheit → Automation.",
            .statusPlayerError: "Spotify konnte nicht gelesen werden: %@",
            .statusNoTrack: "Spiele einen Song in Spotify ab.",
            .statusSearching: "Suche synchronisierte Lyrics …",
            .statusNetworkError: "Lyrics konnten nicht geladen werden. Prüfe deine Internetverbindung.",
            .statusNoLyrics: "Keine synchronisierten Lyrics für diesen Song gefunden.",
        ],
    ]
}

/// Status shown in the overlay. Stored typed and rendered at display time so a language switch re-renders it.
public enum StatusMessage: Equatable, Error {
    case waitingForPlayer, openPlayer, automationDenied
    case playerError(String)
    case noTrack, searching, networkError, noLyrics

    public func text(language: AppLanguage) -> String {
        switch self {
        case .waitingForPlayer: return L10n.string(.statusWaitingForPlayer, language: language)
        case .openPlayer: return L10n.string(.statusOpenPlayer, language: language)
        case .automationDenied: return L10n.string(.statusAutomationDenied, language: language)
        case .playerError(let detail): return L10n.string(.statusPlayerError, detail, language: language)
        case .noTrack: return L10n.string(.statusNoTrack, language: language)
        case .searching: return L10n.string(.statusSearching, language: language)
        case .networkError: return L10n.string(.statusNetworkError, language: language)
        case .noLyrics: return L10n.string(.statusNoLyrics, language: language)
        }
    }
}
