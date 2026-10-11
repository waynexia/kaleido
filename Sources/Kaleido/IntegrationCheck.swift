#if DEBUG
import AppKit
import KaleidoCore

/// Opt-in local integration driver. Never loaded in Release builds. All destructive actions
/// require a selected window owned by the disposable fixture bundle; no user titles are saved.
@MainActor
final class IntegrationCheck {
    private let coordinator: SwitcherCoordinator
    private let reportURL: URL
    private let fixtureBundle = "dev.waynexia.Kaleido.WindowFixture"
    private var fixture: NSRunningApplication?
    private let fixtureAX = FixtureAccessibility()
    private var checks: [[String: Any]] = []
    private let source = CGEventSource(stateID: .hidSystemState)
    private var held: CGEventFlags = []

    init(coordinator: SwitcherCoordinator, reportURL: URL) {
        self.coordinator = coordinator
        self.reportURL = reportURL
    }

    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    func run() async {
        writeReport(status: "running")
        let previous = NSWorkspace.shared.frontmostApplication
        defer { release(); previous?.activate(options: [.activateIgnoringOtherApps]) }
        do {
            try await wait("accessibility and event tap", timeout: 8) {
                Accessibility.isTrusted && self.coordinator.shortcuts.isRunning
            }
            fixture = NSRunningApplication.runningApplications(withBundleIdentifier: fixtureBundle).first
            guard let fixture else { throw Failure("Start WindowFixture.app before the integration check") }
            try await wait("three fixture windows") { (await self.fixtureWindows).count == 3 }
            try await wait("window inventory") { self.coordinator.inspectionWindows.filter { $0.bundleIdentifier == self.fixtureBundle }.count == 3 }
            record("enumerate-three-real-windows", detail: ["totalWindowCount": coordinator.windowCount])

            try await focus("Three")
            try await begin(currentOnly: true)
            guard coordinator.inspectionSelection.windows.count == 3 else { throw Failure("Current-application scope included unexpected windows") }
            let selected = coordinator.inspectionSelection.selected?.id
            try await key(53)
            release()
            try await wait("cancel") { !self.coordinator.inspectionActive }
            try await wait("cancel preserves focus") { await self.focusedName == "Three" }
            record("cancel-preserves-focus")

            try await begin(currentOnly: true)
            guard coordinator.inspectionSelection.selected?.id == selected else { throw Failure("Cancel changed MRU ordering") }
            let target = coordinator.inspectionSelection.selected?.title
            release()
            try await wait("release focuses selection") { await self.focusedTitle == target }
            record("modifier-release-focuses-selected-window")

            try await pause(0.3)
            try await begin(currentOnly: true)
            let reverseStart = coordinator.inspectionSelection.selectedIndex!
            let total = coordinator.inspectionSelection.windows.count
            setHeld([.maskControl, .maskAlternate, .maskShift])
            try await wait("Shift reverses selection") { self.coordinator.inspectionSelection.selectedIndex == (reverseStart + total - 1) % total }
            try await key(38)
            guard coordinator.inspectionSelection.selectedIndex == (reverseStart + total - 1) % total else {
                throw Failure("Shift plus cycle moved twice")
            }
            let spaceTarget = coordinator.inspectionSelection.selected?.title
            try await key(49)
            release()
            try await wait("Space focuses selection") { await self.focusedTitle == spaceTarget }
            record("reverse-chord-and-space-focus")

            try await pause(0.3)
            setHeld([.maskControl, .maskAlternate])
            try await key(38, interval: 0.01)
            let quickTarget = coordinator.inspectionSelection.selected?.title
            guard coordinator.inspectionActive, !coordinator.panel.panel.isVisible else { throw Failure("Quick switch displayed prematurely") }
            release()
            try await wait("quick release focus") { await self.focusedTitle == quickTarget && !self.coordinator.inspectionActive }
            record("quick-release-without-panel")
            try await pause(0.3)

            try await begin(currentOnly: true)
            let before = coordinator.inspectionSelection.selectedIndex
            try await key(125)
            try await wait("arrow navigation") { self.coordinator.inspectionSelection.selectedIndex != before }
            try await key(126)
            try await wait("reverse arrow navigation") { self.coordinator.inspectionSelection.selectedIndex == before }
            try await key(53); release()
            record("arrow-navigation")

            try await begin(currentOnly: false)
            guard coordinator.inspectionSelection.windows.count > 3 else { throw Failure("All-window scope omitted other applications") }
            let size = coordinator.panel.panel.frame.size
            record("all-window-panel", detail: ["width": size.width, "height": size.height,
                                                "windowCount": coordinator.inspectionSelection.windows.count])
            if CommandLine.arguments.contains("--capture-kaleido") {
                writeReport(status: "kaleido-visible")
                let gate = reportURL.appendingPathExtension("kaleido-continue")
                try await wait("Kaleido capture", timeout: 45) { FileManager.default.fileExists(atPath: gate.path) }
            }
            try await key(53); release()

            // Only fixture windows may be targeted by window-management shortcuts below.
            try await focus("Three")
            try await choose("Two")
            try await key(46)
            try await wait("minimize fixture") { await self.attribute("Two", kAXMinimizedAttribute) }
            release()
            try await wait("restore minimized fixture") {
                let minimized = await self.attribute("Two", kAXMinimizedAttribute)
                let focused = await self.focusedName
                return !minimized && focused == "Two"
            }
            // AX state updates before AppKit's minimize/restore animation and application
            // activation finish. Let the system settle before starting a different scenario.
            try await pause(0.7)
            record("minimize-and-restore-on-focus")

            try await choose("One")
            try await key(4)
            try await wait("hide fixture") { fixture.isHidden }
            guard coordinator.inspectionSelection.selected?.bundleIdentifier == fixtureBundle else { throw Failure("Hide changed selection to non-fixture") }
            try await key(4)
            try await wait("unhide fixture") { !fixture.isHidden }
            release()
            try await wait("focus after unhide") { await self.focusedName == "One" }
            try await pause(0.3)
            record("hide-and-unhide")

            try await choose("One")
            try await key(3)
            try await wait("enter fullscreen", timeout: 10) { await self.attribute("One", "AXFullScreen") }
            try await pause(1.2)
            try await key(3)
            try await wait("exit fullscreen", timeout: 10) { !(await self.attribute("One", "AXFullScreen")) }
            release()
            try await pause(1.2)
            record("fullscreen-toggle")

            // Exercise the installed reference without changing any of its preferences.
            try await focus("Three")
            setHeld(.maskControl)
            try await key(48)
            try await pause(0.4)
            let reference = referencePanels()
            guard !reference.isEmpty else { throw Failure("AltTab did not display a visible panel for Control+Tab") }
            record("alttab-coexists-and-opens", detail: ["panels": reference])
            // Optional capture gate keeps the real reference panel open for CUA inspection.
            if CommandLine.arguments.contains("--capture-reference") {
                writeReport(status: "reference-visible")
                let gate = reportURL.appendingPathExtension("continue")
                try await wait("reference capture", timeout: 45) { FileManager.default.fileExists(atPath: gate.path) }
            }
            try await key(53); release()
            try await pause(0.2)

            try await focus("Three")
            try await choose("One")
            try await key(13)
            try await wait("close fixture") { (await self.fixtureWindows).count == 2 }
            try await wait("list reconciliation") { self.coordinator.inspectionSelection.windows.count == 2 }
            guard coordinator.inspectionSelection.selected != nil else { throw Failure("Closing selection left no adjacent selection") }
            release()
            record("close-and-reconcile-selection")

            try await pause(0.3)
            try await begin(currentOnly: true)
            try assertFixtureSelection()
            try await key(12)
            try await wait("quit fixture") { fixture.isTerminated }
            release()
            try await wait("remove terminated windows") { !self.coordinator.inspectionWindows.contains { $0.bundleIdentifier == self.fixtureBundle } }
            record("quit-removes-windowless-application")
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.lwouis.alt-tab-macos").isEmpty else {
                throw Failure("AltTab unexpectedly stopped")
            }
            writeReport(status: "passed")
        } catch {
            let selected = coordinator.inspectionSelection.selected
            checks.append(["check": "failure-state", "passed": false, "detail": [
                "sessionActive": coordinator.inspectionActive,
                "selectedFixture": selected?.bundleIdentifier == fixtureBundle ? selected?.title ?? "none" : "other",
                "focusedFixture": await focusedName ?? "none",
                "fixtureTwoMinimized": await attribute("Two", kAXMinimizedAttribute),
                "fixtureWindowCount": (await fixtureWindows).count,
                "injectedEvents": coordinator.shortcuts.integrationEvents,
                "sessionFlags": CGEventSource.flagsState(.combinedSessionState).rawValue,
            ]])
            try? await key(53)
            release()
            writeReport(status: "failed", error: String(describing: error))
        }
    }

    private var fixtureWindows: [String] {
        get async {
            guard let fixture, !fixture.isTerminated else { return [] }
            return await fixtureAX.titles(pid: fixture.processIdentifier)
        }
    }

    private var focusedTitle: String? {
        get async {
            guard let fixture, NSWorkspace.shared.frontmostApplication?.processIdentifier == fixture.processIdentifier else { return nil }
            return await fixtureAX.focusedTitle(pid: fixture.processIdentifier)
        }
    }
    private var focusedName: String? {
        get async { await focusedTitle?.replacingOccurrences(of: "Kaleido Test — ", with: "") }
    }

    private func attribute(_ name: String, _ attribute: String) async -> Bool {
        guard let fixture else { return false }
        return await fixtureAX.attribute(pid: fixture.processIdentifier, name: name, attribute: attribute)
    }

    private func focus(_ name: String) async throws {
        guard let fixture else { throw Failure("Missing disposable fixture application") }
        fixture.unhide()
        fixture.activate(options: [.activateIgnoringOtherApps])
        guard await fixtureAX.focus(pid: fixture.processIdentifier, name: name) else {
            throw Failure("Missing disposable fixture window")
        }
        try await wait("activate disposable fixture") { await self.focusedName == name }
        coordinator.repository.requestRefresh()
        try await pause(0.35)
    }

    private func begin(currentOnly: Bool) async throws {
        setHeld([.maskControl, .maskAlternate])
        try await key(currentOnly ? 38 : 40)
        try await wait("global shortcut opens panel") { self.coordinator.inspectionActive && self.coordinator.panel.panel.isVisible }
    }

    private func choose(_ name: String) async throws {
        try await begin(currentOnly: true)
        for _ in 0..<4 {
            if coordinator.inspectionSelection.selected?.title == "Kaleido Test — \(name)" {
                try assertFixtureSelection()
                return
            }
            try await key(38)
        }
        throw Failure("Cannot select disposable fixture")
    }

    private func assertFixtureSelection() throws {
        guard coordinator.inspectionSelection.selected?.bundleIdentifier == fixtureBundle else {
            throw Failure("Refusing to perform a window action on a non-fixture application")
        }
    }

    private func setHeld(_ flags: CGEventFlags) {
        for (key, mask) in [(CGKeyCode(59), CGEventFlags.maskControl), (58, .maskAlternate), (56, .maskShift)] {
            if held.contains(mask) != flags.contains(mask) {
                if flags.contains(mask) { held.insert(mask) } else { held.remove(mask) }
                let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: flags.contains(mask))!
                event.type = .flagsChanged
                event.flags = held
                event.setIntegerValueField(.eventSourceUserData, value: 0x4b414c45)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    private func release() { setHeld([]) }

    private func key(_ code: CGKeyCode, interval: Double = 0.045) async throws {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)!
            event.flags = held
            event.setIntegerValueField(.eventSourceUserData, value: 0x4b414c45)
            event.post(tap: .cghidEventTap)
            try await pause(interval)
        }
    }

    private func wait(_ description: String, timeout: Double = 5, until condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            guard Date() < deadline else { throw Failure("Timed out: \(description)") }
            try await pause(0.05)
        }
    }

    private func pause(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    private func referencePanels() -> [[String: Any]] {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.lwouis.alt-tab-macos").first?.processIdentifier else { return [] }
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? Int32) == pid,
                  let bounds = info[kCGWindowBounds as String] as? [String: Double],
                  let width = bounds["Width"], width > 100, let height = bounds["Height"], height > 50 else { return nil }
            return ["width": width, "height": height, "layer": info[kCGWindowLayer as String] as? Int ?? 0]
        }
    }

    private func record(_ name: String, detail: [String: Any] = [:]) {
        checks.append(["check": name, "passed": true, "detail": detail])
        writeReport(status: "running")
    }

    private func writeReport(status: String, error: String? = nil) {
        var report: [String: Any] = ["status": status, "checks": checks, "accessibilityTrusted": Accessibility.isTrusted]
        if let error { report["error"] = error }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: reportURL, options: .atomic)
        }
    }
}
/// Dedicated actor keeps independent AX verification off the event tap's main run loop.
private actor FixtureAccessibility {
    private func root(_ pid: pid_t) -> AXUIElement {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.2)
        return root
    }

    private func windows(_ pid: pid_t) -> [AXUIElement] {
        Accessibility.elements(root(pid), kAXWindowsAttribute).filter {
            Accessibility.string($0, kAXTitleAttribute)?.hasPrefix("Kaleido Test — ") == true
        }
    }

    private func window(_ pid: pid_t, _ name: String) -> AXUIElement? {
        windows(pid).first { Accessibility.string($0, kAXTitleAttribute) == "Kaleido Test — \(name)" }
    }

    func titles(pid: pid_t) -> [String] { windows(pid).compactMap { Accessibility.string($0, kAXTitleAttribute) } }

    func focusedTitle(pid: pid_t) -> String? {
        guard let window = Accessibility.element(root(pid), kAXFocusedWindowAttribute) else { return nil }
        return Accessibility.string(window, kAXTitleAttribute)
    }

    func attribute(pid: pid_t, name: String, attribute: String) -> Bool {
        window(pid, name).map { Accessibility.bool($0, attribute) } ?? false
    }

    func focus(pid: pid_t, name: String) -> Bool {
        guard let window = window(pid, name) else { return false }
        Accessibility.set(window, kAXMinimizedAttribute, kCFBooleanFalse)
        Accessibility.set(window, kAXMainAttribute, kCFBooleanTrue)
        return AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
    }
}
#endif
