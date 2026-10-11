import AppKit

// Disposable windows for manual integration testing. No permissions or user files required.
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var statuses: [NSTextField] = []
    var timer: Timer?
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
            let status = NSTextField(labelWithString: "")
            status.frame = NSRect(x: 30, y: 50, width: 380, height: 24)
            window.contentView?.addSubview(status)
            statuses.append(status)
            let activate = NSButton(title: "Activate \(name)", target: self, action: #selector(activateWindow(_:)))
            activate.tag = index
            activate.frame = NSRect(x: 30, y: 14, width: 150, height: 28)
            window.contentView?.addSubview(activate)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            let active = NSApp.isActive ? "yes" : "no"
            let key = NSApp.keyWindow?.title.replacingOccurrences(of: "Kaleido Test — ", with: "") ?? "none"
            self?.statuses.forEach { $0.stringValue = "Active: \(active) · Key window: \(key)" }
        }
    }
    @objc func activateWindow(_ sender: NSButton) {
        NSApp.activate(ignoringOtherApps: true)
        windows[sender.tag].makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = FixtureDelegate()
app.delegate = delegate
app.run()
