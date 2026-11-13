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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let model = PlayerModel()
    var overlay: NSPanel!
    var settings: NSWindow!
    var statusItem: NSStatusItem!
    var statusMenu: NSMenu!
    /// Persisted so click-through survives relaunch.
    var clickThrough = false {
        didSet {
            UserDefaults.standard.set(clickThrough, forKey: "clickThrough")
            overlay?.ignoresMouseEvents = clickThrough
        }
    }
    /// Set by the hotkey or menu; always wins over auto-show.
    private var userHidden = false
    /// A manual show while auto-hidden keeps the overlay up for the grace period, so the toggle has a visible effect.
    private var manualShowAt: Date?
    private var visibilityTimer: Timer?
    private let hotKey = HotKey()

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
        clickThrough = UserDefaults.standard.bool(forKey: "clickThrough")
        overlay.orderFrontRegardless()
        buildMenu()
        if !hotKey.register(handler: { [weak self] in self?.toggleVisibility() }) { showHotKeyError() }
        model.start()
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.applyVisibility() }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyLanguage()
        }
    }
    /// Menu titles are rebuilt in menuNeedsUpdate; these are the strings that stay on screen.
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
    private func saveFrame() { if overlay != nil { UserDefaults.standard.set(NSStringFromRect(overlay.frame), forKey: "windowFrame") } }
    func resize() {
        guard overlay != nil else { return }
        var frame = overlay.frame
        let newHeight = UserDefaults.standard.double(forKey: "overlayHeight")
        frame.origin.y += frame.height - newHeight
        frame.size = NSSize(width: UserDefaults.standard.double(forKey: "overlayWidth"), height: newHeight)
        overlay.setFrame(frame, display: true); saveFrame()
    }
    func position(_ corner: String) {
        let screen = overlay.screen ?? NSScreen.main ?? NSScreen.screens.first!
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
        statusMenu = NSMenu()
        statusMenu.delegate = self
    }
    /// Rebuilt on every open so titles follow the current language and state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        menu.removeAllItems()
        let title = NSMenuItem(title: Brand.name, action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(item(tr(overlay.isVisible ? .hideOverlay : .showOverlay), #selector(toggleVisibility)))
        let click = item(tr(.clickThrough), #selector(toggleClick)); click.state = clickThrough ? .on : .off; menu.addItem(click)
        let corners = NSMenu()
        for (key, corner) in [(L10nKey.topLeft, "topLeft"), (.topRight, "topRight"), (.bottomLeft, "bottomLeft"), (.bottomRight, "bottomRight")] {
            let entry = item(tr(key), #selector(selectCorner(_:))); entry.representedObject = corner; corners.addItem(entry)
        }
        let positionItem = NSMenuItem(title: tr(.position), action: nil, keyEquivalent: ""); positionItem.submenu = corners; menu.addItem(positionItem)
        let sources = NSMenu()
        let selected = UserDefaults.standard.string(forKey: "source") ?? SourcePreference.auto.rawValue
        for (key, preference) in [(L10nKey.sourceAuto, SourcePreference.auto), (.sourceSpotify, .spotify), (.sourceMusic, .music)] {
            let entry = item(tr(key), #selector(selectSource(_:))); entry.representedObject = preference.rawValue
            entry.state = preference.rawValue == selected ? .on : .off; sources.addItem(entry)
        }
        let sourceItem = NSMenuItem(title: tr(.source), action: nil, keyEquivalent: ""); sourceItem.submenu = sources; menu.addItem(sourceItem)
        menu.addItem(.separator())
        menu.addItem(item(tr(.settingsMenu), #selector(showSettings), key: ","))
        menu.addItem(item(tr(.quit), #selector(quitApp), key: "q"))
    }
    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; return item
    }
    @objc func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = statusMenu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            showSettings()
        }
    }
    @objc func toggleVisibility() { setUserHidden(overlay.isVisible) }
    private func setUserHidden(_ hidden: Bool) {
        userHidden = hidden
        if !hidden { manualShowAt = Date() }
        applyVisibility()
    }
    private func applyVisibility() {
        let show = VisibilityPolicy.shouldShow(
            userHidden: userHidden, autoHide: UserDefaults.standard.bool(forKey: "autoHide"),
            playing: model.clock.playing, hasTrack: model.track != nil,
            notPlayingSince: [model.notPlayingSince, manualShowAt].compactMap { $0 }.max(), now: Date())
        if show && !overlay.isVisible { overlay.orderFrontRegardless() }
        if !show && overlay.isVisible { overlay.orderOut(nil) }
    }
    @objc func toggleClick() { clickThrough.toggle() }
    @objc func selectSource(_ sender: NSMenuItem) { if let value = sender.representedObject as? String { UserDefaults.standard.set(value, forKey: "source") } }
    @objc func selectCorner(_ sender: NSMenuItem) { if let key = sender.representedObject as? String { position(key) } }
    @objc func showSettings() {
        if settings == nil {
            let hosting = NSHostingController(rootView: SettingsView(resize: { [weak self] in self?.resize() }))
            hosting.sizingOptions = .preferredContentSize // window follows the content height
            settings = NSWindow(contentViewController: hosting)
            settings.styleMask = [.titled, .closable]
            settings.title = tr(.settingsWindowTitle)
            settings.isReleasedWhenClosed = false
            settings.center()
        }
        settings.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func quitApp() { NSApp.terminate(nil) }
}
