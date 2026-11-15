import AppKit
import SwiftUI
import LyricsCore

extension AppLanguage {
    /// The language picked in Settings, resolved against the macOS language order.
    static var current: AppLanguage {
        (AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .system)
            .resolved(preferredLanguages: Locale.preferredLanguages)
    }
}

func tr(_ key: L10nKey, _ args: CVarArg...) -> String { L10n.string(key, arguments: args, language: .current) }

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = PlayerModel()
    let spotify = SpotifyAuth()
    private var shuffle: ShuffleController!
    var overlay: NSPanel!
    var settings: NSWindow!
    var statusItem: NSStatusItem!
    private let menuActions = MenuActions()
    /// Persisted so click-through survives relaunch.
    var clickThrough = false {
        didSet {
            UserDefaults.standard.set(clickThrough, forKey: "clickThrough")
            overlay?.ignoresMouseEvents = clickThrough
            menuActions.clickThrough = clickThrough
        }
    }
    /// Set by the hotkey or menu; always wins over auto-show.
    private var userHidden = false
    /// A manual show while auto-hidden keeps the overlay up for the grace period, so the toggle has a visible effect.
    private var manualShowAt: Date?
    private var visibilityTimer: Timer?
    private let hotKey = HotKey()
    private var isResizingOverlay = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["fontSize": 25.0, "opacity": 0.78, "overlayOpacity": 1.0, "offset": 0.0, "overlayWidth": 400.0, "overlayHeight": 240.0, "language": AppLanguage.system.rawValue, "source": SourcePreference.auto.rawValue, "clickThrough": false, "autoHide": false])
        NSApp.setActivationPolicy(.accessory)
        overlay = NSPanel(contentRect: NSRect(x: 0, y: 0, width: UserDefaults.standard.double(forKey: "overlayWidth"), height: UserDefaults.standard.double(forKey: "overlayHeight")), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.isOpaque = false; overlay.backgroundColor = .clear; overlay.hasShadow = true
        overlay.level = .floating; overlay.isMovableByWindowBackground = true
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlay.contentView = NSHostingView(rootView: OverlayView(model: model, showSettings: { [weak self] in self?.showSettings() }))
        overlay.delegate = self
        if let saved = UserDefaults.standard.string(forKey: "windowFrame"), NSRectFromString(saved).width > 0 {
            let rect = NSRectFromString(saved)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) { overlay.setFrame(rect, display: true) }
            else { position("topRight") }
        } else { position("topRight") }
        resize()
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        clickThrough = UserDefaults.standard.bool(forKey: "clickThrough")
        overlay.orderFrontRegardless()
        installEditMenu()
        shuffle = ShuffleController(auth: spotify)
        model.onTrackChange = { [weak self] track in
            self?.shuffle.trackChanged(uri: track.source == .spotify ? track.rawID : nil)
        }
        buildMenu()
        if !hotKey.register(handler: { [weak self] in self?.toggleVisibility() }) { showHotKeyError() }
        model.start()
        spotify.restore()
        // Mini-player: the heart asks Spotify whether the current track is liked.
        model.library.attach(spotify)
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.applyVisibility(animated: true) }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyLanguage()
        }
    }
    /// A menu-bar-only app has no visible menu bar, but text fields still get ⌘C, ⌘V, ⌘X, ⌘A and ⌘Z only
    /// through Edit menu key equivalents. Without this, pasting the Spotify Client ID does nothing.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let main = NSMenu()
        main.addItem(NSMenuItem()) // the first item is the app menu
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
    /// Strings that stay on screen; the menu popover follows the language by itself.
    private func applyLanguage() {
        statusItem?.button?.toolTip = tr(.statusItemTooltip)
        statusItem?.button?.setAccessibilityLabel(tr(.statusItemDescription))
        settings?.title = tr(.settingsWindowTitle)
    }
    private func showHotKeyError() {
        let alert = NSAlert()
        alert.messageText = tr(.hotKeyErrorTitle)
        alert.informativeText = tr(.hotKeyErrorText)
        alert.runModal()
    }
    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        clickThrough = false
        setUserHidden(false)
        showSettings()
        return true
    }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidChangeScreen(_ notification: Notification) { resize() }
    func windowDidChangeBackingProperties(_ notification: Notification) { resize() }
    @objc private func screenParametersChanged(_ notification: Notification) { resize() }
    private func saveFrame() { if overlay != nil { UserDefaults.standard.set(NSStringFromRect(overlay.frame), forKey: "windowFrame") } }
    func resize() {
        guard overlay != nil, !isResizingOverlay, let screen = overlay.screen ?? NSScreen.main else { return }
        isResizingOverlay = true
        defer { isResizingOverlay = false }
        let preferredSize = NSSize(width: UserDefaults.standard.double(forKey: "overlayWidth"),
                                   height: UserDefaults.standard.double(forKey: "overlayHeight"))
        let frame = OverlayLayout.frame(preferredSize: preferredSize, currentFrame: overlay.frame,
                                        visibleFrame: screen.visibleFrame, backingScale: screen.backingScaleFactor)
        guard frame != overlay.frame else { return }
        overlay.setFrame(frame, display: true); saveFrame()
    }
    func position(_ corner: String) {
        guard let screen = overlay.screen ?? NSScreen.main else { return }
        resize()
        let area = screen.visibleFrame.insetBy(dx: 16, dy: 16)
        let size = overlay.frame.size
        let x = corner.contains("Right") ? area.maxX - size.width : area.minX
        let y = corner.hasPrefix("top") ? area.maxY - size.height : area.minY
        overlay.setFrameOrigin(NSPoint(x: x, y: y)); saveFrame()
    }
    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Brand.menuBarImage
        statusItem.button?.setAccessibilityLabel(tr(.statusItemDescription))
        statusItem.button?.toolTip = tr(.statusItemTooltip)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        menuActions.toggleOverlay = { [weak self] in self?.toggleVisibility() }
        menuActions.toggleClickThrough = { [weak self] in self?.toggleClick() }
        menuActions.moveTo = { [weak self] corner in self?.position(corner) }
        menuActions.openSettings = { [weak self] in self?.menuWindow.close(); self?.showSettings() }
        menuActions.quit = { NSApp.terminate(nil) }
    }
    /// The right-click menu: a glass panel matching the overlay (see MenuWindow).
    private lazy var menuWindow = MenuWindow { [unowned self] in AnyView(MenuPanel(model: self.model, actions: self.menuActions, auth: self.spotify, shuffle: self.shuffle,
                                                                                         expanded: $0, measuring: $0 != nil)) }
    private func toggleMenu(from button: NSStatusBarButton) { menuWindow.toggle(below: button) }
    @objc func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            toggleMenu(from: sender)
        } else {
            showSettings()
        }
    }
    @objc func toggleVisibility() { setUserHidden(isShowing) }
    private func setUserHidden(_ hidden: Bool) {
        userHidden = hidden
        if !hidden { manualShowAt = Date() }
        applyVisibility()
    }
    /// Tracks the intended state, so a fade-out in progress counts as hidden.
    private var isShowing = true { didSet { menuActions.overlayVisible = isShowing } }
    private func applyVisibility(animated: Bool = false) {
        let show = VisibilityPolicy.shouldShow(
            userHidden: userHidden, autoHide: UserDefaults.standard.bool(forKey: "autoHide"),
            playing: model.clock.playing, hasTrack: model.track != nil,
            notPlayingSince: [model.notPlayingSince, manualShowAt].compactMap { $0 }.max(), now: Date())
        guard show != isShowing else { return }
        isShowing = show
        // Auto-hide fades; the hotkey and menu stay instant, because keyboard actions must never feel delayed.
        let duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? (show ? 0.22 : 0.16) : 0
        if show {
            overlay.alphaValue = duration > 0 ? 0 : 1
            overlay.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            overlay.animator().alphaValue = show ? 1 : 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isShowing else { return } // shown again mid-fade
            self.overlay.orderOut(nil)
            self.overlay.alphaValue = 1
        })
    }
    @objc func toggleClick() { clickThrough.toggle() }
    @objc func showSettings() {
        if settings == nil {
            let hosting = NSHostingController(rootView: SettingsView(auth: spotify, resize: { [weak self] in self?.resize() }))
            hosting.sizingOptions = .preferredContentSize
            settings = NSWindow(contentViewController: hosting)
            settings.styleMask = [.titled, .closable, .fullSizeContentView]
            // Glass runs under a transparent title bar, like the Linory concept.
            settings.titlebarAppearsTransparent = true
            settings.titleVisibility = .hidden
            // An (empty) unified toolbar gives the window the large, toolbar-style corner radius
            // instead of the tight one macOS uses for title-bar-only windows.
            settings.toolbar = NSToolbar()
            settings.toolbarStyle = .unified
            settings.isMovableByWindowBackground = true
            settings.backgroundColor = .clear
            settings.isOpaque = false
            settings.appearance = NSAppearance(named: .darkAqua)
            settings.title = tr(.settingsWindowTitle)
            settings.isReleasedWhenClosed = false
            settings.center()
        }
        settings.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func quitApp() { NSApp.terminate(nil) }
}
