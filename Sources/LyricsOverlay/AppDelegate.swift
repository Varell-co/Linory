import AppKit
import SwiftUI
import LyricsCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = PlayerModel()
    var overlay: NSPanel!
    var settings: NSWindow!
    var statusItem: NSStatusItem!
    var statusMenu: NSMenu!
    var clickThrough = false
    var clickItem: NSMenuItem!
    var visibilityItem: NSMenuItem!
    private let hotKey = HotKey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["fontSize": 25.0, "opacity": 0.78, "overlayOpacity": 1.0, "offset": 0.0, "overlayWidth": 400.0, "overlayHeight": 240.0])
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
        overlay.orderFrontRegardless()
        buildMenu()
        if !hotKey.register(handler: { [weak self] in self?.toggleVisibility() }) { showHotKeyError() }
        model.start()
    }
    private func showHotKeyError() {
        let alert = NSAlert()
        alert.messageText = "Hotkey nicht verfügbar"
        alert.informativeText = "⌥ ⇧ L konnte nicht registriert werden. Möglicherweise verwendet eine andere App diese Tastenkombination. Das Overlay lässt sich weiterhin über das Menü ein- und ausblenden."
        alert.runModal()
    }
    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        clickThrough = false
        overlay.ignoresMouseEvents = false
        clickItem.state = .off
        overlay.orderFrontRegardless()
        visibilityItem.title = "Overlay ausblenden"
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
        statusItem.button?.image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "Lyrics Overlay – Einstellungen")
        statusItem.button?.toolTip = "Einstellungen öffnen · Rechtsklick für Menü"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let menu = NSMenu()
        let title = NSMenuItem(title: "Lyrics Overlay", action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
        menu.addItem(.separator())
        visibilityItem = NSMenuItem(title: "Overlay ausblenden", action: #selector(toggleVisibility), keyEquivalent: ""); visibilityItem.target = self; menu.addItem(visibilityItem)
        clickItem = NSMenuItem(title: "Klicks durchlassen", action: #selector(toggleClick), keyEquivalent: ""); clickItem.target = self; menu.addItem(clickItem)
        let corners = NSMenu(title: "Position")
        for (title, key) in [("Oben links", "topLeft"), ("Oben rechts", "topRight"), ("Unten links", "bottomLeft"), ("Unten rechts", "bottomRight")] {
            let item = NSMenuItem(title: title, action: #selector(selectCorner(_:)), keyEquivalent: ""); item.representedObject = key; item.target = self; corners.addItem(item)
        }
        let positionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: ""); positionItem.submenu = corners; menu.addItem(positionItem)
        menu.addItem(.separator())
        let preferences = NSMenuItem(title: "Einstellungen …", action: #selector(showSettings), keyEquivalent: ","); preferences.target = self; menu.addItem(preferences)
        let quit = NSMenuItem(title: "Beenden", action: #selector(quitApp), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        statusMenu = menu
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
    @objc func toggleVisibility() { if overlay.isVisible { overlay.orderOut(nil) } else { overlay.orderFrontRegardless() }; visibilityItem.title = overlay.isVisible ? "Overlay ausblenden" : "Overlay einblenden" }
    @objc func toggleClick() { clickThrough.toggle(); overlay.ignoresMouseEvents = clickThrough; clickItem.state = clickThrough ? .on : .off }
    @objc func selectCorner(_ sender: NSMenuItem) { if let key = sender.representedObject as? String { position(key) } }
    @objc func showSettings() {
        if settings == nil {
            settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 510), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            settings.title = "Lyrics Overlay – Einstellungen"
            settings.isReleasedWhenClosed = false
            settings.contentView = NSHostingView(rootView: SettingsView(resize: { [weak self] in self?.resize() }))
            settings.center()
        }
        settings.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func quitApp() { NSApp.terminate(nil) }
}
