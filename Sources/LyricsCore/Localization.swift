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
    // Settings ▸ Spotify
    case sectionSpotify, spotifySubtitle, spotifyClientID, spotifyRedirectURI, spotifyCopy, spotifyConnect, spotifyDisconnect
    case spotifyConnected, spotifyNotConnected, spotifyConnecting, spotifyLoginFailed, spotifyReconnectHint, spotifyReconnect
    case spotifyGuideTitle, spotifyGuideStep1, spotifyGuideStep2, spotifyGuideStep3, spotifyGuideStep4, spotifyPremiumNote
    // True Shuffle
    case trueShuffle, shuffleSourceLiked, shufflePlay, shuffleProgress, shuffleReset, shuffleLoading, shuffleBusy, shuffleEmpty
    case shuffleConnectHint, shuffleOpenSettings, shufflePlaylistName, shufflePlaylistDescription
    case shuffleErrorAuth, shuffleErrorNetwork, shuffleErrorAutomation, shuffleErrorPremium, shuffleErrorHTTP, shuffleErrorPlayback
    case shuffleRemove, shuffleRestore, shuffleKeep, shuffleKeptName, shuffleKept
    // Mini-player
    case miniPrevious, miniPlay, miniPause, miniNext, miniPosition, miniLike, miniUnlike
    case miniChorus, miniChorusHelp, miniOpenInSpotify

    // Shuffle upgrades, sleep timer and stats
    case shuffleMixName, shuffleMixSources, shuffleAutoContinue, shuffleContinuing, shuffleFull, shuffleUpNext
    case sleepTimer, sleepOff, sleepMinutes, sleepEndOfTrack, sleepPausesIn
    case sectionStats, statsSubtitle, statsTopArtists, statsTopTracks, statsRangeShort, statsRangeMedium, statsRangeLong
    case statsConnectHint, statsOpenSpotify, statsReconnectHint, statsEmpty, statsError
    // Listening history and the stats window
    case historySubtitle, rangeToday, range7Days, range30Days, rangeYear, rangeAll
    case tileListening, tileListeningDetail, tilePlays, tilePlaysDetail, tileStreak, tileStreakDetail, tileSkips, tileSkipsDetail
    case durationMinutes, durationHours, chartOverTime, chartClock, chartLess, chartMore, chartHoverHint
    case listTopSongs, listTopArtists, playsCount, statsOnSpotify, statsNoHistory
    case historyKeep, historyKeepHint, historyClear, historyClearConfirm

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
            .sectionSpotify: "Spotify",
            .spotifySubtitle: "Connect your own Spotify app to use True Shuffle.",
            .spotifyClientID: "Client ID",
            .spotifyRedirectURI: "Redirect URI",
            .spotifyCopy: "Copy",
            .spotifyConnect: "Connect Spotify",
            .spotifyDisconnect: "Disconnect",
            .spotifyConnected: "Connected as %@",
            .spotifyNotConnected: "Not connected",
            .spotifyConnecting: "Connecting…",
            .spotifyLoginFailed: "Login failed: %@",
            .spotifyReconnectHint: "Reconnect once so Linory can start True Shuffle reliably.",
            .spotifyReconnect: "Reconnect",
            .spotifyGuideTitle: "How to get a Client ID",
            .spotifyGuideStep1: "Open [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard).",
            .spotifyGuideStep2: "Create an app and select “Web API”.",
            .spotifyGuideStep3: "Add the redirect URI above and save.",
            .spotifyGuideStep4: "Copy the Client ID here and press Connect.",
            .spotifyPremiumNote: "Requires Spotify Premium on your account.",
            .trueShuffle: "True Shuffle",
            .shuffleSourceLiked: "Liked Songs",
            .shufflePlay: "Shuffle & play",
            .shuffleProgress: "%ld of %ld played",
            .shuffleReset: "Reset",
            .shuffleLoading: "Loading tracks…",
            .shuffleBusy: "Shuffling %ld tracks…",
            .shuffleEmpty: "This source has no tracks to shuffle.",
            .shuffleConnectHint: "Connect Spotify in Settings to use True Shuffle.",
            .shuffleOpenSettings: "Open",
            .shufflePlaylistName: "Linory Shuffle",
            .shufflePlaylistDescription: "True Shuffle by Linory. Rewritten on every shuffle.",
            .shuffleErrorAuth: "Spotify login expired. Reconnect in Settings.",
            .shuffleErrorNetwork: "Spotify could not be reached. Check your internet connection.",
            .shuffleErrorAutomation: "Allow Linory to control Spotify: System Settings → Privacy & Security → Automation.",
            .shuffleErrorPremium: "Spotify refused the request. Your app needs Premium and your account on its user list.",
            .shuffleErrorHTTP: "Spotify returned an error (%ld).",
            .shuffleErrorPlayback: "Spotify could not start playback: %@",
            .shuffleRemove: "Remove from shuffle",
            .shuffleRestore: "Restore removed (%ld)",
            .shuffleKeep: "Keep this shuffle",
            .shuffleKeptName: "%@ · Shuffled %@",
            .shuffleKept: "Saved as “%@”",
            // Mini-player
            .miniPrevious: "Previous track",
            .miniPlay: "Play",
            .miniPause: "Pause",
            .miniNext: "Next track",
            .miniPosition: "Playback position",
            .miniLike: "Add to Liked Songs",
            .miniUnlike: "Remove from Liked Songs",
            .miniChorus: "Chorus",
            .miniChorusHelp: "Jump to the chorus",
            .miniOpenInSpotify: "Open in Spotify",

            // Shuffle upgrades, sleep timer and stats
            .shuffleMixName: "Mix: %@",
            .shuffleMixSources: "Mix sources",
            .shuffleAutoContinue: "Keep playing",
            .shuffleContinuing: "Adding the next round…",
            .shuffleFull: "Linory Shuffle is full. Shuffle & play starts it fresh.",
            .shuffleUpNext: "Up next",
            .sleepTimer: "Sleep timer",
            .sleepOff: "Off",
            .sleepMinutes: "%ld min",
            .sleepEndOfTrack: "End of track",
            .sleepPausesIn: "Pauses in %@",
            .sectionStats: "Your music",
            .statsSubtitle: "Spotify's own ranking of your top artists and tracks. Click one to open it in Spotify.",
            .statsTopArtists: "Top artists",
            .statsTopTracks: "Top tracks",
            .statsRangeShort: "4 weeks",
            .statsRangeMedium: "6 months",
            .statsRangeLong: "1 year",
            .statsConnectHint: "Connect Spotify to see your top artists and tracks.",
            .statsOpenSpotify: "Open Spotify settings",
            .statsReconnectHint: "Reconnect once so Linory may read your top artists and tracks.",
            .statsEmpty: "Not enough listening history yet.",
            .statsError: "Your top items could not be loaded.",
            .historySubtitle: "What you listened to while Linory was running, in Spotify and Music.",
            .rangeToday: "Today",
            .range7Days: "7 days",
            .range30Days: "30 days",
            .rangeYear: "12 months",
            .rangeAll: "All time",
            .tileListening: "Listening time",
            .tileListeningDetail: "About %@ a day",
            .tilePlays: "Plays",
            .tilePlaysDetail: "%ld %% with synced lyrics",
            .tileStreak: "Day streak",
            .tileStreakDetail: "Days in a row with music",
            .tileSkips: "Skipped",
            .tileSkipsDetail: "Left within 30 seconds",
            .durationMinutes: "%ld min",
            .durationHours: "%ld h %ld min",
            .chartOverTime: "Listening over time",
            .chartClock: "Listening clock",
            .chartLess: "Less",
            .chartMore: "More",
            .chartHoverHint: "Hover for details.",
            .listTopSongs: "Most played songs",
            .listTopArtists: "Most played artists",
            .playsCount: "%ld×",
            .statsOnSpotify: "On Spotify",
            .statsNoHistory: "No listening history yet. Play some music while Linory is running, and it shows up here.",
            .historyKeep: "Keep listening history",
            .historyKeepHint: "Stored only on this Mac. Nothing is uploaded.",
            .historyClear: "Clear history",
            .historyClearConfirm: "Click again to delete",

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
            .sectionSpotify: "Spotify",
            .spotifySubtitle: "Verbinde deine eigene Spotify-App, um True Shuffle zu nutzen.",
            .spotifyClientID: "Client-ID",
            .spotifyRedirectURI: "Redirect-URI",
            .spotifyCopy: "Kopieren",
            .spotifyConnect: "Spotify verbinden",
            .spotifyDisconnect: "Trennen",
            .spotifyConnected: "Verbunden als %@",
            .spotifyNotConnected: "Nicht verbunden",
            .spotifyConnecting: "Verbinde …",
            .spotifyLoginFailed: "Anmeldung fehlgeschlagen: %@",
            .spotifyReconnectHint: "Verbinde dich einmal neu, damit Linory True Shuffle zuverlässig starten kann.",
            .spotifyReconnect: "Neu verbinden",
            .spotifyGuideTitle: "So bekommst du eine Client-ID",
            .spotifyGuideStep1: "Öffne [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard).",
            .spotifyGuideStep2: "Erstelle eine App und wähle „Web API“.",
            .spotifyGuideStep3: "Füge die Redirect-URI von oben hinzu und speichere.",
            .spotifyGuideStep4: "Kopiere die Client-ID hierher und klicke auf Verbinden.",
            .spotifyPremiumNote: "Erfordert Spotify Premium für dein Konto.",
            .trueShuffle: "True Shuffle",
            .shuffleSourceLiked: "Lieblingssongs",
            .shufflePlay: "Mischen & abspielen",
            .shuffleProgress: "%ld von %ld gespielt",
            .shuffleReset: "Zurücksetzen",
            .shuffleLoading: "Lade Titel …",
            .shuffleBusy: "Mische %ld Titel …",
            .shuffleEmpty: "Diese Quelle hat keine Titel zum Mischen.",
            .shuffleConnectHint: "Verbinde Spotify in den Einstellungen, um True Shuffle zu nutzen.",
            .shuffleOpenSettings: "Öffnen",
            .shufflePlaylistName: "Linory Shuffle",
            .shufflePlaylistDescription: "True Shuffle von Linory. Wird bei jedem Mischen neu geschrieben.",
            .shuffleErrorAuth: "Spotify-Anmeldung abgelaufen. Verbinde dich in den Einstellungen neu.",
            .shuffleErrorNetwork: "Spotify ist nicht erreichbar. Prüfe deine Internetverbindung.",
            .shuffleErrorAutomation: "Erlaube Linory, Spotify zu steuern: Systemeinstellungen → Datenschutz & Sicherheit → Automation.",
            .shuffleErrorPremium: "Spotify hat die Anfrage abgelehnt. Deine App braucht Premium und dein Konto auf ihrer Nutzerliste.",
            .shuffleErrorHTTP: "Spotify hat einen Fehler gemeldet (%ld).",
            .shuffleErrorPlayback: "Spotify konnte die Wiedergabe nicht starten: %@",
            .shuffleRemove: "Aus Shuffle entfernen",
            .shuffleRestore: "Entfernte wiederherstellen (%ld)",
            .shuffleKeep: "Diesen Shuffle behalten",
            .shuffleKeptName: "%@ · Gemischt %@",
            .shuffleKept: "Gespeichert als „%@“",
            // Mini-player
            .miniPrevious: "Vorheriger Titel",
            .miniPlay: "Wiedergabe",
            .miniPause: "Pause",
            .miniNext: "Nächster Titel",
            .miniPosition: "Wiedergabeposition",
            .miniLike: "Zu Lieblingssongs hinzufügen",
            .miniUnlike: "Aus Lieblingssongs entfernen",
            .miniChorus: "Refrain",
            .miniChorusHelp: "Zum Refrain springen",
            .miniOpenInSpotify: "In Spotify öffnen",

            // Shuffle upgrades, sleep timer and stats
            .shuffleMixName: "Mix: %@",
            .shuffleMixSources: "Quellen mischen",
            .shuffleAutoContinue: "Weiterspielen",
            .shuffleContinuing: "Füge die nächste Runde hinzu …",
            .shuffleFull: "Linory Shuffle ist voll. Mischen & abspielen beginnt neu.",
            .shuffleUpNext: "Als Nächstes",
            .sleepTimer: "Sleep-Timer",
            .sleepOff: "Aus",
            .sleepMinutes: "%ld Min.",
            .sleepEndOfTrack: "Titelende",
            .sleepPausesIn: "Pausiert in %@",
            .sectionStats: "Deine Musik",
            .statsSubtitle: "Spotifys eigene Rangliste deiner Top-Künstler und -Titel. Klicke einen an, um ihn in Spotify zu öffnen.",
            .statsTopArtists: "Top-Künstler",
            .statsTopTracks: "Top-Titel",
            .statsRangeShort: "4 Wochen",
            .statsRangeMedium: "6 Monate",
            .statsRangeLong: "1 Jahr",
            .statsConnectHint: "Verbinde Spotify, um deine Top-Künstler und -Titel zu sehen.",
            .statsOpenSpotify: "Spotify-Einstellungen öffnen",
            .statsReconnectHint: "Verbinde dich einmal neu, damit Linory deine Top-Künstler und -Titel lesen darf.",
            .statsEmpty: "Noch nicht genug Hörverlauf.",
            .statsError: "Deine Top-Einträge konnten nicht geladen werden.",
            .historySubtitle: "Was du gehört hast, während Linory lief, in Spotify und Musik.",
            .rangeToday: "Heute",
            .range7Days: "7 Tage",
            .range30Days: "30 Tage",
            .rangeYear: "12 Monate",
            .rangeAll: "Gesamt",
            .tileListening: "Hörzeit",
            .tileListeningDetail: "Etwa %@ pro Tag",
            .tilePlays: "Wiedergaben",
            .tilePlaysDetail: "%ld %% mit synchronen Lyrics",
            .tileStreak: "Tage in Folge",
            .tileStreakDetail: "Tage am Stück mit Musik",
            .tileSkips: "Übersprungen",
            .tileSkipsDetail: "Vor 30 Sek. gewechselt",
            .durationMinutes: "%ld Min.",
            .durationHours: "%ld Std. %ld Min.",
            .chartOverTime: "Hörzeit im Verlauf",
            .chartClock: "Hör-Uhr",
            .chartLess: "Weniger",
            .chartMore: "Mehr",
            .chartHoverHint: "Für Details darüberfahren.",
            .listTopSongs: "Meistgehörte Songs",
            .listTopArtists: "Meistgehörte Künstler",
            .playsCount: "%ld×",
            .statsOnSpotify: "Auf Spotify",
            .statsNoHistory: "Noch kein Hörverlauf. Spiele Musik, während Linory läuft, dann erscheint sie hier.",
            .historyKeep: "Hörverlauf speichern",
            .historyKeepHint: "Nur auf diesem Mac gespeichert. Nichts wird hochgeladen.",
            .historyClear: "Verlauf löschen",
            .historyClearConfirm: "Zum Löschen erneut klicken",

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
