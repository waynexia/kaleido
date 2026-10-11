import AppKit
import ApplicationServices
import KaleidoCore

private func windowObserverCallback(_ observer: AXObserver, _ element: AXUIElement,
                                    _ notification: CFString, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let repository = Unmanaged<WindowRepository>.fromOpaque(context).takeUnretainedValue()
    repository.requestRefresh()
}

/// AX queries run on a serial worker, never in the global event tap or AppKit drawing path.
final class WindowRepository {
    private struct Record {
        let descriptor: WindowDescriptor
        let element: AXUIElement
        let app: NSRunningApplication
        let windowID: CGWindowID?
    }
    private struct Observation {
        let observer: AXObserver
        var windows: [String: AXUIElement]
    }

    private let queue = DispatchQueue(label: "dev.waynexia.Kaleido.windows", qos: .userInitiated)
    private var records: [String: Record] = [:]
    private var observations: [pid_t: Observation] = [:]
    private var history = WindowHistory()
    private var lastFocusedID: String?
    private var refreshPending = false
    private var timer: DispatchSourceTimer?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var started = false
    var onChange: (([WindowDescriptor], [Int32: NSImage]) -> Void)?
    var onActionFailure: (() -> Void)?

    func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.requestRefresh()
            })
        }
        queue.async { [weak self] in
            guard let self else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 3)
            timer.setEventHandler { [weak self] in self?.refresh() }
            self.timer = timer
            timer.resume()
        }
    }

    func requestRefresh() {
        queue.async { [weak self] in
            guard let self, !self.refreshPending else { return }
            self.refreshPending = true
            self.queue.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                self?.refreshPending = false
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard Accessibility.isTrusted else { return }
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && $0.bundleIdentifier != "com.McAfee.McAfeeSafariHost"
        }
        let serverWindows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let order = Dictionary(serverWindows.enumerated().compactMap { index, value -> (CGWindowID, Int)? in
            guard let id = value[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return (id, index)
        }, uniquingKeysWith: { first, _ in first })
        let badges = dockBadges()
        var discovered: [Record] = []
        var icons: [Int32: NSImage] = [:]
        for app in apps {
            let pid = app.processIdentifier
            let root = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(root, 0.2)
            ensureObserver(pid: pid, root: root)
            icons[pid] = app.icon
            for element in Accessibility.elements(root, kAXWindowsAttribute) {
                let role = Accessibility.string(element, kAXRoleAttribute)
                let subrole = Accessibility.string(element, kAXSubroleAttribute)
                guard role == kAXWindowRole,
                      subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
                let minimized = Accessibility.bool(element, kAXMinimizedAttribute)
                let fullscreen = Accessibility.bool(element, "AXFullScreen")
                let number = Accessibility.windowID(element)
                // Standard inactive tabs are not WindowServer windows. Off-Space windows are
                // included by optionAll; hidden/minimized windows remain eligible regardless.
                if let number, order[number] == nil, !app.isHidden, !minimized, !fullscreen { continue }
                let id = number.map { "\(pid):\($0)" }
                    ?? records.first { $0.value.app.processIdentifier == pid && CFEqual($0.value.element, element) }?.key
                    ?? "\(pid):\(UUID().uuidString)"
                let descriptor = WindowDescriptor(
                    id: id, processID: pid, application: app.localizedName ?? "Application",
                    bundleIdentifier: app.bundleIdentifier ?? "",
                    title: Accessibility.string(element, kAXTitleAttribute) ?? "",
                    isMinimized: minimized, isHidden: app.isHidden, isFullscreen: fullscreen,
                    badge: badges[app.localizedName ?? ""]
                )
                discovered.append(Record(descriptor: descriptor, element: element, app: app, windowID: number))
                observeWindow(element, id: id, pid: pid)
            }
        }
        discovered.sort {
            let lhs = $0.windowID.flatMap { order[$0] } ?? Int.max
            let rhs = $1.windowID.flatMap { order[$0] } ?? Int.max
            return lhs == rhs ? $0.descriptor.id < $1.descriptor.id : lhs < rhs
        }
        records = Dictionary(discovered.map { ($0.descriptor.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let front = NSWorkspace.shared.frontmostApplication,
           let focused = Accessibility.element(AXUIElementCreateApplication(front.processIdentifier), kAXFocusedWindowAttribute),
           let match = discovered.first(where: { $0.app.processIdentifier == front.processIdentifier && CFEqual($0.element, focused) }),
           match.descriptor.id != lastFocusedID {
            lastFocusedID = match.descriptor.id
            history.recordFocus(match.descriptor.id)
        }
        removeStaleObservers(pids: Set(apps.map(\.processIdentifier)))
        let windows = history.order(discovered.map(\.descriptor))
        DispatchQueue.main.async { [weak self] in self?.onChange?(windows, icons) }
    }

    private func ensureObserver(pid: pid_t, root: AXUIElement) {
        guard observations[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, windowObserverCallback, &observer) == .success, let observer else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        for event in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                      kAXApplicationHiddenNotification, kAXApplicationShownNotification] {
            AXObserverAddNotification(observer, root, event as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observations[pid] = Observation(observer: observer, windows: [:])
    }

    private func observeWindow(_ element: AXUIElement, id: String, pid: pid_t) {
        guard var observation = observations[pid], observation.windows[id] == nil else { return }
        for event in [kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
                      kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
            AXObserverAddNotification(observation.observer, element, event as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        observation.windows[id] = element
        observations[pid] = observation
    }

    private func removeStaleObservers(pids: Set<pid_t>) {
        for pid in Array(observations.keys) {
            guard var observation = observations[pid] else { continue }
            if !pids.contains(pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observation.observer), .commonModes)
                observations.removeValue(forKey: pid)
            } else {
                for id in Array(observation.windows.keys) where records[id] == nil {
                    if let element = observation.windows.removeValue(forKey: id) {
                        for event in [kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
                                      kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
                            AXObserverRemoveNotification(observation.observer, element, event as CFString)
                        }
                    }
                }
                observations[pid] = observation
            }
        }
    }

    private func dockBadges() -> [String: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.1)
        var result: [String: String] = [:]
        for list in Accessibility.elements(root, kAXChildrenAttribute) {
            for item in Accessibility.elements(list, kAXChildrenAttribute) {
                guard let title = Accessibility.string(item, kAXTitleAttribute),
                      let badge = Accessibility.string(item, "AXStatusLabel"), !badge.isEmpty else { continue }
                result[title] = badge
            }
        }
        return result
    }

    func focus(_ id: String) {
        queue.async { [weak self] in
            guard let self, let record = self.records[id], !record.app.isTerminated else { return }
            if record.app.isHidden { record.app.unhide() }
            if Accessibility.bool(record.element, kAXMinimizedAttribute) {
                Accessibility.set(record.element, kAXMinimizedAttribute, kCFBooleanFalse)
            }
            Accessibility.set(record.element, kAXMainAttribute, kCFBooleanTrue)
            let raised = AXUIElementPerformAction(record.element, kAXRaiseAction as CFString) == .success
            let activated = record.app.activate(options: [.activateIgnoringOtherApps])
            // A second raise after activation prevents another window of the same app winning.
            self.queue.asyncAfter(deadline: .now() + 0.08) {
                AXUIElementPerformAction(record.element, kAXRaiseAction as CFString)
                self.requestRefresh()
            }
            if raised || activated {
                self.history.recordFocus(id)
                self.lastFocusedID = id
            } else { self.reportFailure() }
        }
    }

    func perform(_ action: WindowAction, on id: String) {
        queue.async { [weak self] in
            guard let self, let record = self.records[id], !record.app.isTerminated else { return }
            var success = false
            switch action {
            case .close:
                if let close = Accessibility.element(record.element, kAXCloseButtonAttribute) {
                    success = AXUIElementPerformAction(close, kAXPressAction as CFString) == .success
                }
            case .minimize:
                let minimized = Accessibility.bool(record.element, kAXMinimizedAttribute)
                success = Accessibility.set(record.element, kAXMinimizedAttribute, minimized ? kCFBooleanFalse : kCFBooleanTrue)
            case .fullscreen:
                let fullscreen = Accessibility.bool(record.element, "AXFullScreen")
                success = Accessibility.set(record.element, "AXFullScreen", fullscreen ? kCFBooleanFalse : kCFBooleanTrue)
            case .quit: success = record.app.terminate()
            case .hide: success = record.app.isHidden ? record.app.unhide() : record.app.hide()
            }
            if !success { self.reportFailure() }
            self.requestRefresh()
        }
    }

    private func reportFailure() { DispatchQueue.main.async { [weak self] in self?.onActionFailure?() } }
}
