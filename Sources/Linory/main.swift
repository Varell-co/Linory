import AppKit

let app = NSApplication.shared
#if DEBUG
// `LINORY_SNAPSHOTS=<dir> swift run Linory` renders every screen to PNG for layout review, then quits.
if let directory = ProcessInfo.processInfo.environment["LINORY_SNAPSHOTS"] {
    app.setActivationPolicy(.accessory)
    Task { @MainActor in
        Snapshots.render(to: URL(fileURLWithPath: directory))
        exit(0)
    }
    app.run()
}
#endif
let delegate = AppDelegate()
app.delegate = delegate
app.run()
