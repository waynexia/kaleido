import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = SwitcherCoordinator()
    private var settings: PreferencesWindowController?
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?
    private var paused = false
    private var isPreview: Bool { CommandLine.arguments.contains("--preview") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createMenu()
        if isPreview {
            coordinator.showPreview()
            if let index = CommandLine.arguments.firstIndex(of: "--export-preview"), CommandLine.arguments.count > index + 1 {
                let path = CommandLine.arguments[index + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    do { try self?.coordinator.panel.exportPreview(to: URL(fileURLWithPath: path)) }
                    catch { fputs("Preview export failed: \(error)\n", stderr) }
                    NSApp.terminate(nil)
                }
            }
            return
        }
        let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.waynexia.Kaleido")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = otherInstances.first {
            existing.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
            return
        }
        updateMenuVisibility(UserDefaults.standard.bool(forKey: "showMenuBarIcon"))
        refreshAvailability()
        if !Accessibility.isTrusted || altTabRunning { showPreferences() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refreshAvailability() }
    }

    private var altTabRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.lwouis.alt-tab-macos").isEmpty
    }

    private func refreshAvailability() {
        let trusted = Accessibility.isTrusted
        let conflict = altTabRunning
        if trusted, !conflict, !paused { coordinator.start() }
        else { coordinator.pause() }
        settings?.updateStatus(trusted: trusted, listening: coordinator.shortcuts.isRunning, conflict: conflict, paused: paused)
    }

    @objc func showPreferences() {
        if settings == nil {
            settings = PreferencesWindowController()
            settings?.onRecheck = { [weak self] in self?.refreshAvailability() }
            settings?.onMenuVisibilityChange = { [weak self] in self?.updateMenuVisibility($0) }
            settings?.onPauseChange = { [weak self] value in self?.paused = value; self?.refreshAvailability() }
        }
        refreshAvailability()
        settings?.present()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !isPreview { showPreferences() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        coordinator.pause()
    }

    private func createMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Kaleido")
        let settings = NSMenuItem(title: "设置…", action: #selector(showPreferences), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出 Kaleido", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }

    private func updateMenuVisibility(_ visible: Bool) {
        if !visible {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Kaleido")
        item.button?.toolTip = "Kaleido"
        let menu = NSMenu()
        let settings = NSMenuItem(title: "设置…", action: #selector(showPreferences), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Kaleido", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}
