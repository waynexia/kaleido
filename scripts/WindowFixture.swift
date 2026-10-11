import AppKit

// Disposable windows for manual integration testing. No permissions or user files required.
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Window Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        for (index, name) in ["One", "Two", "Three"].enumerated() {
            let window = NSWindow(contentRect: NSRect(x: 120 + index * 90, y: 200 + index * 70, width: 420, height: 240),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Kaleido Test — \(name)"
            window.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: name)
            label.font = .systemFont(ofSize: 32, weight: .medium)
            label.frame = NSRect(x: 30, y: 90, width: 360, height: 50)
            window.contentView?.addSubview(label)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = FixtureDelegate()
app.delegate = delegate
app.run()
