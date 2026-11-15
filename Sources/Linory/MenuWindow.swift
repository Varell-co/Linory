import AppKit
import SwiftUI

/// The status-item menu as a borderless glass panel, so it matches the overlay instead of looking like a
/// system popover. Opens under the menu-bar icon, closes on outside click, Esc, or losing focus.
final class MenuWindow: NSObject, NSWindowDelegate {
    private var panel: MenuPanelWindow?
    private var outsideClickMonitor: Any?
    private var escMonitor: Any?
    private var localClickMonitor: Any?
    /// Clicking the menu-bar icon while open first closes via focus loss; this stops it reopening right away.
    private var closedAt = Date.distantPast
    /// Builds the menu, optionally with a section already expanded (used only for measuring).
    private let content: (MenuPanel.Section?) -> AnyView
    /// Room around the glass for the SwiftUI-drawn shadow.
    private static let shadowInset = EdgeInsets(top: 14, leading: 28, bottom: 40, trailing: 28)

    var isOpen: Bool { panel?.isVisible == true }

    init(content: @escaping (MenuPanel.Section?) -> AnyView) { self.content = content }

    func toggle(below button: NSStatusBarButton) {
        if isOpen { close() } else if Date().timeIntervalSince(closedAt) > 0.25 { open(below: button) }
    }

    func open(below button: NSStatusBarButton) {
        let panel = MenuPanelWindow()
        // The window is sized once for the tallest layout and never resizes while open: the glass grows and
        // shrinks inside it with SwiftUI's animation. Following the content size instead made the window
        // snap to the new height mid-animation, so the menu jumped and clipped when a section opened.
        let layouts = ([nil] + MenuPanel.Section.allCases).map { NSHostingView(rootView: content($0)).fittingSize }
        let glass = NSSize(width: layouts.map(\.width).max() ?? 0, height: layouts.map(\.height).max() ?? 0)
        let inset = Self.shadowInset
        let hosting = NSHostingView(rootView: content(nil)
            .padding(inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.delegate = self
        if let buttonWindow = button.window {
            let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let glassX = min(max(anchor.midX - glass.width / 2, screen.minX + 8), screen.maxX - glass.width - 8)
            let glassTop = anchor.minY - 6
            let height = glass.height + inset.top + inset.bottom
            panel.setFrame(NSRect(x: glassX - inset.leading, y: glassTop + inset.top - height,
                                  width: glass.width + inset.leading + inset.trailing, height: height), display: true)
        }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        animate(panel, to: 1, duration: 0.2)
        self.panel = panel

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil } // Esc
            return event
        }
        // Clicks in Linory's own windows (the overlay) are not seen by the global monitor.
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // The True Shuffle source picker opens a menu in its own window; picking from it must not close the panel.
            guard let window = event.window, window !== self?.panel,
                  !window.className.contains("StatusBar"), !window.className.contains("Menu") else { return event }
            self?.close()
            return event
        }
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        outsideClickMonitor = nil; escMonitor = nil; localClickMonitor = nil
        closedAt = Date()
        // Closing is faster than opening: the system is responding, not the user deciding.
        animate(panel, to: 0, duration: 0.12) { panel.orderOut(nil) }
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    private func animate(_ window: NSWindow, to alpha: CGFloat, duration: Double, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            window.animator().alphaValue = alpha
        }, completionHandler: completion)
    }
}

/// Borderless panel that can take keyboard focus (for ⌘, ⌘Q, Esc). Its transparent margin lets clicks through.
final class MenuPanelWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // The system shadow traces the window's alpha only when invalidated, so it lagged behind the
        // animating glass. MenuPanel draws its own shadow instead.
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }
    override var canBecomeKey: Bool { true }
}
