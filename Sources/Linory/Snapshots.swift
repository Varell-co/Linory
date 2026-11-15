#if DEBUG
import AppKit
import LyricsCore
import SwiftUI

/// Renders every screen and state to PNG (2x) for layout review. Debug builds only; see `main.swift`.
/// Track names and lyrics are invented.
@MainActor
enum Snapshots {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["fontSize": 25.0, "opacity": 0.78, "overlayOpacity": 1.0, "overlayWidth": 400.0, "overlayHeight": 240.0])

        let connected = SpotifyAuth()
        connected.previewConnect(as: "Mike")
        let disconnected = SpotifyAuth()
        let actions = MenuActions()

        let playing = PlayerModel()
        playing.track = Track(source: .spotify, rawID: "spotify:track:preview", title: "Midnight Signals",
                              artist: "The Paper Lanterns", album: "Night Drive", duration: 214)
        playing.lyrics = LoadedLyrics(lines: [
            LyricLine(time: 10, text: "Streetlights hum a quiet tune"), LyricLine(time: 14, text: "We trace the river to the moon"),
            LyricLine(time: 18, text: "Hold the signal, hold it near"), LyricLine(time: 22, text: "Midnight calling, I am here"),
            LyricLine(time: 26, text: "Paper boats on silver streams"), LyricLine(time: 30, text: "Carry all our borrowed dreams"),
            LyricLine(time: 34, text: "Hold the signal, hold it near"), LyricLine(time: 38, text: "Midnight calling, I am here"),
        ], synced: true, instrumental: false)
        playing.clock.update(position: 23, playing: false, duration: 214, at: Date())
        playing.library.previewLiked(true)

        let idle = PlayerModel()
        idle.status = .openPlayer
        let noLyrics = PlayerModel()
        noLyrics.track = playing.track
        noLyrics.status = .noLyrics

        let overlaySize = CGSize(width: defaults.double(forKey: "overlayWidth"), height: defaults.double(forKey: "overlayHeight"))
        for language in [AppLanguage.en, .de] {
            defaults.set(language.rawValue, forKey: "language")
            let suffix = language.rawValue
            func save<V: View>(_ name: String, size: CGSize? = nil, _ view: V) {
                write(view, size: size, to: directory.appendingPathComponent("\(name)-\(suffix).png"))
            }

            save("overlay-lyrics", size: overlaySize, OverlayView(model: playing, showSettings: {}))
            save("overlay-controls", size: overlaySize, OverlayView(model: playing, showSettings: {}, forceControls: true))
            save("overlay-idle", size: overlaySize, OverlayView(model: idle, showSettings: {}))
            save("overlay-nolyrics", size: overlaySize, OverlayView(model: noLyrics, showSettings: {}))

            let shuffle = ShuffleController(auth: connected)
            let offline = ShuffleController(auth: disconnected)
            save("menu-idle", MenuPanel(model: idle, actions: actions, auth: disconnected, shuffle: offline))
            save("menu-playing", MenuPanel(model: playing, actions: actions, auth: connected, shuffle: shuffle))
            for section in MenuPanel.Section.allCases {
                save("menu-\(section)", MenuPanel(model: playing, actions: actions, auth: connected, shuffle: shuffle, expanded: section))
            }
            save("menu-shuffle-disconnected", MenuPanel(model: playing, actions: actions, auth: disconnected, shuffle: offline, expanded: .shuffle))
            save("menu-shuffle-measuring", MenuPanel(model: playing, actions: actions, auth: connected, shuffle: shuffle, expanded: .shuffle, measuring: true))

            for pane in SettingsView.Pane.allCases {
                save("settings-\(pane)", SettingsView(auth: connected, resize: {}, pane: pane))
            }
            save("settings-spotify-disconnected", SettingsView(auth: disconnected, resize: {}, pane: .spotify))
            save("settings-stats-disconnected", SettingsView(auth: disconnected, resize: {}, pane: .stats))
        }
    }

    /// Renders on a neutral backdrop, so translucent glass stays readable in the image.
    private static func write<V: View>(_ view: V, size: CGSize?, to url: URL) {
        let framed = view
            .frame(width: size?.width, height: size?.height)
            .padding(40)
            .background(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: framed)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        // Let appear animations and delayed reveals finish.
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        let bounds = host.bounds
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = bounds.size
        host.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
