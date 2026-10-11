import AppKit
import ApplicationServices
import KaleidoCore

private func windowObserverCallback(_ observer: AXObserver, _ element: AXUIElement,
                                    _ notification: CFString, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let repository = Unmanaged<WindowRepository>.fromOpaque(context).takeUnretainedValue()
    if notification as String == kAXUIElementDestroyedNotification { repository.windowDestroyed(element) }
    else { repository.requestRefresh() }
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
    private var iconCache: [Int32: NSImage] = [:]
    private var missingSince: [String: Date] = [:]
    private var observations: [pid_t: Observation] = [:]
    private var history = WindowHistory()
    private var lastFocusedID: String?
    private var focusGeneration: UInt64 = 0
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
            timer.schedule(deadline: .now(), repeating: 3, leeway: .milliseconds(200))
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

    fileprivate func windowDestroyed(_ element: AXUIElement) {
        queue.async { [weak self] in
            guard let self else { return }
            for (id, record) in self.records where CFEqual(record.element, element) {
                self.records.removeValue(forKey: id)
                self.missingSince.removeValue(forKey: id)
            }
            self.requestRefresh()
        }
    }

    private func refresh() {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy != .prohibited && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && $0.bundleIdentifier != "com.McAfee.McAfeeSafariHost"
        }
        let serverWindows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let order = Dictionary(serverWindows.enumerated().compactMap { index, value -> (CGWindowID, Int)? in
            guard let id = value[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return (id, index)
        }, uniquingKeysWith: { first, _ in first })
        let badges = dockBadges()
        let previousByPID = Dictionary(grouping: records.values, by: { $0.app.processIdentifier })
        var discovered: [Record] = []
        var icons: [Int32: NSImage] = [:]
        for app in apps {
            let pid = app.processIdentifier
            let root = AXUIElementCreateApplication(pid)
            let previousWindows = previousByPID[pid] ?? []
            if iconCache[pid] == nil { iconCache[pid] = app.icon }
            icons[pid] = iconCache[pid]
            // A busy AppKit animation can exceed the AX timeout. A failed read is not
            // an empty window list: keep the last snapshot until the app responds again.
            guard let elements = Accessibility.value(root, kAXWindowsAttribute) as? [AXUIElement] else {
                discovered += previousWindows
                continue
            }
            ensureObserver(pid: pid, root: root)
            for element in elements {
                let number = Accessibility.windowID(element)
                let stableID = number.map { "\(pid):\($0)" }
                let previous = stableID.flatMap { records[$0] }
                    ?? previousWindows.first { CFEqual($0.element, element) }
                guard let attributes = Accessibility.values(element, [kAXRoleAttribute, kAXSubroleAttribute,
                                                                       kAXTitleAttribute, kAXMinimizedAttribute, "AXFullScreen"]),
                      let role = attributes[kAXRoleAttribute] as? String,
                      let subrole = attributes[kAXSubroleAttribute] as? String else {
                    if let previous { discovered.append(previous) }
                    continue
                }
                guard role == kAXWindowRole,
                      subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
                let minimized = (attributes[kAXMinimizedAttribute] as? NSNumber)?.boolValue ?? previous?.descriptor.isMinimized ?? false
                let fullscreen = (attributes["AXFullScreen"] as? NSNumber)?.boolValue ?? previous?.descriptor.isFullscreen ?? false
                // Standard inactive tabs are not WindowServer windows. Off-Space windows are
                // included by optionAll; hidden/minimized windows remain eligible regardless.
                if let number, order[number] == nil, !app.isHidden, !minimized, !fullscreen { continue }
                let id = stableID ?? previous?.descriptor.id
                    ?? "\(pid):\(UUID().uuidString)"
                let descriptor = WindowDescriptor(
                    id: id, processID: pid, application: app.localizedName ?? "Application",
                    bundleIdentifier: app.bundleIdentifier ?? "",
                    title: attributes[kAXTitleAttribute] as? String ?? previous?.descriptor.title ?? "",
                    isMinimized: minimized, isHidden: app.isHidden, isFullscreen: fullscreen,
                    badge: badges[app.localizedName ?? ""]
                )
                discovered.append(Record(descriptor: descriptor, element: element, app: app, windowID: number))
                observeWindow(element, id: id, pid: pid)
            }
        }
        // Space transitions may successfully return a temporarily incomplete AXWindows
        // array. Confirm disappearance after a short grace period; destruction events and
        // terminated applications bypass the grace period so real closes remain prompt.
        let discoveredIDs = Set(discovered.map { $0.descriptor.id })
        let livePIDs = Set(apps.map(\.processIdentifier))
        iconCache = iconCache.filter { livePIDs.contains($0.key) }
        let now = Date()
        var retryMissing = false
        for (id, record) in records where !discoveredIDs.contains(id) && livePIDs.contains(record.app.processIdentifier) {
            let since = missingSince[id] ?? now
            missingSince[id] = since
            if now.timeIntervalSince(since) < 1.5 {
                discovered.append(record)
                retryMissing = true
            }
        }
        missingSince = missingSince.filter { !discoveredIDs.contains($0.key) && records[$0.key].map { livePIDs.contains($0.app.processIdentifier) } == true }
        if retryMissing { queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.requestRefresh() } }
        discovered.sort {
            let lhs = $0.windowID.flatMap { order[$0] } ?? Int.max
            let rhs = $1.windowID.flatMap { order[$0] } ?? Int.max
            return lhs == rhs ? $0.descriptor.id < $1.descriptor.id : lhs < rhs
        }
        var seen = Set<String>()
        discovered = discovered.filter { seen.insert($0.descriptor.id).inserted }
        records = Dictionary(uniqueKeysWithValues: discovered.map { ($0.descriptor.id, $0) })
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
        var result: [String: String] = [:]
        for list in Accessibility.elements(root, kAXChildrenAttribute) {
            for item in Accessibility.elements(list, kAXChildrenAttribute) {
                guard let attributes = Accessibility.values(item, [kAXTitleAttribute, "AXStatusLabel"]),
                      let title = attributes[kAXTitleAttribute] as? String,
                      let badge = attributes["AXStatusLabel"] as? String, !badge.isEmpty else { continue }
                result[title] = badge
            }
        }
        return result
    }

    func focus(_ id: String) {
        queue.async { [weak self] in
            guard let self, let record = self.records[id], !record.app.isTerminated else { return }
            self.focusGeneration &+= 1
            let generation = self.focusGeneration
            if record.app.isHidden { record.app.unhide() }
            if Accessibility.bool(record.element, kAXMinimizedAttribute) {
                Accessibility.set(record.element, kAXMinimizedAttribute, kCFBooleanFalse)
            }
            Accessibility.set(record.element, kAXMainAttribute, kCFBooleanTrue)
            let raised = Accessibility.perform(record.element, kAXRaiseAction)
            let activated = record.app.activate(options: [.activateIgnoringOtherApps])
            // A second raise after activation prevents another window of the same app winning.
            let retryDeadline = DispatchTime.now() + 0.25
            self.queue.asyncAfter(deadline: .now() + 0.08) {
                // A newer selection/action or an external app activation supersedes this retry.
                guard DispatchTime.now() < retryDeadline, generation == self.focusGeneration,
                      !record.app.isTerminated, !record.app.isHidden,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == record.app.processIdentifier,
                      let current = self.records[id], CFEqual(current.element, record.element) else {
                    self.requestRefresh()
                    return
                }
                Accessibility.perform(record.element, kAXRaiseAction)
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
            self.focusGeneration &+= 1
            var success = false
            switch action {
            case .close:
                if let close = Accessibility.element(record.element, kAXCloseButtonAttribute) {
                    success = Accessibility.perform(close, kAXPressAction)
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
