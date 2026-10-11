import AppKit
import KaleidoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = SwitcherCoordinator()
    private var settings: PreferencesWindowController?
    private var statusItem: NSStatusItem?
    private lazy var permissionMonitor = PermissionMonitor(check: { Accessibility.isTrusted }, schedule: { tick in
        let timer = Timer(timeInterval: 1.5, repeats: true) { _ in tick() }
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    })
    private var workspaceObservers: [NSObjectProtocol] = []
    private var hasLaunched = false
    private var paused = false
    #if DEBUG
    private var integrationCheck: IntegrationCheck?
    #endif
    private var profile = ShortcutProfile(rawValue: UserDefaults.standard.string(forKey: "shortcutProfile") ?? "") ?? .standard
    private var isPreview: Bool { CommandLine.arguments.contains("--preview") }
    private var isSettingsPreview: Bool { isPreview && CommandLine.arguments.contains("--settings-preview") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Reject duplicate instances before applying any command-line preference changes.
        if !isPreview {
            let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.waynexia.Kaleido")
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let existing = otherInstances.first {
                existing.activate(options: [.activateIgnoringOtherApps])
                NSApp.terminate(nil)
                return
            }
        }
        UserDefaults.standard.register(defaults: ["showMenuBarIcon": true])
        if !isPreview, CommandLine.arguments.contains("--coexist") {
            profile = .coexistence
            UserDefaults.standard.set(profile.rawValue, forKey: "shortcutProfile")
        }
        coordinator.shortcuts.configure(profile: profile)
        createMenu()
        if isPreview {
            if isSettingsPreview {
                let trusted = !CommandLine.arguments.contains("--missing-permission")
                settings = PreferencesWindowController(profile: .standard, preview: true)
                settings?.updateStatus(trusted: trusted, listening: trusted, conflict: false, paused: false, profile: .standard)
                if CommandLine.arguments.contains("--light") { settings?.window?.appearance = NSAppearance(named: .aqua) }
                if CommandLine.arguments.contains("--dark") { settings?.window?.appearance = NSAppearance(named: .darkAqua) }
                settings?.showWindow(nil)
            } else {
                coordinator.showPreview()
            }
            if let index = CommandLine.arguments.firstIndex(of: "--export-preview"), CommandLine.arguments.count > index + 1 {
                let path = CommandLine.arguments[index + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    do {
                        if self?.isSettingsPreview == true { try self?.settings?.exportPreview(to: URL(fileURLWithPath: path)) }
                        else { try self?.coordinator.panel.exportPreview(to: URL(fileURLWithPath: path)) }
                    }
                    catch { fputs("Preview export failed: \(error)\n", stderr) }
                    NSApp.terminate(nil)
                }
            }
            return
        }
        updateMenuVisibility(UserDefaults.standard.bool(forKey: "showMenuBarIcon"))
        observeApplicationChanges()
        permissionMonitor.onChange = { [weak self] trusted in
            guard let self else { return }
            self.refreshAvailability()
            if !trusted { self.showPreferences() }
        }
        permissionMonitor.start()
        hasLaunched = true
        if permissionMonitor.isTrusted, altTabRunning && profile == .standard { showPreferences() }
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--integration-check"), CommandLine.arguments.count > index + 1 {
            let check = IntegrationCheck(coordinator: coordinator, reportURL: URL(fileURLWithPath: CommandLine.arguments[index + 1]),
                                         profile: profile, accessibilityTrusted: permissionMonitor.isTrusted)
            integrationCheck = check
            Task { await check.run() }
        }
        #endif
    }

    private var altTabRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.lwouis.alt-tab-macos").isEmpty
    }

    private func refreshAvailability() {
        let trusted = permissionMonitor.isTrusted
        let conflict = altTabRunning && profile == .standard
        if trusted, !conflict, !paused { coordinator.start() }
        else { coordinator.pause() }
        settings?.updateStatus(trusted: trusted, listening: coordinator.shortcuts.isRunning, conflict: conflict, paused: paused, profile: profile)
    }

    private func observeApplicationChanges() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.lwouis.alt-tab-macos" else { return }
                self?.refreshAvailability()
            })
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard hasLaunched else { return }
        permissionMonitor.checkIfNeeded()
        refreshAvailability()
    }

    @objc func showPreferences() {
        if isPreview { settings?.present(); return }
        if settings == nil {
            settings = PreferencesWindowController(profile: profile)
            settings?.onProfileChange = { [weak self] profile in
                guard let self else { return }
                self.coordinator.pause()
                self.profile = profile
                UserDefaults.standard.set(profile.rawValue, forKey: "shortcutProfile")
                self.coordinator.shortcuts.configure(profile: profile)
                self.refreshAvailability()
            }
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
        hasLaunched = false
        permissionMonitor.stop()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
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
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Kaleido — 设置"
        item.button?.setAccessibilityLabel("打开 Kaleido 设置")
        item.button?.target = self
        item.button?.action = #selector(showPreferences)
        statusItem = item
    }
}
