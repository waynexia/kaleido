import AppKit
import KaleidoCore

private func keyboardTap(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                         _ context: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let context else { return Unmanaged.passUnretained(event) }
    let shortcuts = Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue()
    return shortcuts.receive(type, event: event) ? nil : Unmanaged.passUnretained(event)
}

final class GlobalShortcuts {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var router = ShortcutRouter()
    private var releaseWatchdog: Timer?
    private var missingModifiersSince: Date?
    var onCommand: ((ShortcutCommand) -> Void)?
    var mayBegin: ((Bool) -> Bool)?
    var onTapDisabled: (() -> Void)?
    var isRunning: Bool { tap != nil }
    #if DEBUG
    var integrationEvents: [[String: String]] = []
    #endif

    func configure(profile: ShortcutProfile) {
        stop()
        router = ShortcutRouter(profile: profile)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: keyboardTap, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        releaseWatchdog?.invalidate()
        releaseWatchdog = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        router.reset(clearCapturedKeys: true)
    }

    func resetSession() {
        router.reset()
        releaseWatchdog?.invalidate()
        releaseWatchdog = nil
    }

    private static func modifiers(_ flags: CGEventFlags) -> KeyModifiers {
        var result: KeyModifiers = []
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        return result
    }

    private func watchForRelease() {
        releaseWatchdog?.invalidate()
        missingModifiersSince = nil
        // Remote input and input-source changes can omit flagsChanged. Reconcile with
        // the session's actual modifier state so a missed release cannot swallow typing.
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] timer in
            guard let self, let hold = self.router.hold else { timer.invalidate(); return }
            let flags = Self.modifiers(CGEventSource.flagsState(.combinedSessionState))
            if flags.contains(hold) {
                self.missingModifiersSince = nil
            } else if let since = self.missingModifiersSince, Date().timeIntervalSince(since) >= 0.1 {
                self.router.reset()
                timer.invalidate()
                self.onCommand?(.commit)
            } else if self.missingModifiersSince == nil {
                // Event taps can see a key before combined-session flags settle. Require
                // a sustained missing state; normal flagsChanged still commits immediately.
                self.missingModifiersSince = Date()
            }
        }
        releaseWatchdog = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    fileprivate func receive(_ type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            router.reset(clearCapturedKeys: true)
            releaseWatchdog?.invalidate()
            releaseWatchdog = nil
            onTapDisabled?()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let modifiers = Self.modifiers(event.flags)
        if let hold = router.hold, modifiers.contains(hold) { missingModifiersSince = nil }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let result: ShortcutResult
        switch type {
        case .keyDown:
            if let hold = router.hold, !modifiers.contains(hold) {
                resetSession()
                onCommand?(.commit)
            }
            result = router.keyDown(code, modifiers: modifiers,
                                    isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                                    mayBegin: { [weak self] in self?.mayBegin?($0) ?? false })
        case .keyUp: result = router.keyUp(code, modifiers: modifiers)
        case .flagsChanged: result = router.modifiersChanged(modifiers)
        default: return false
        }
        #if DEBUG
        if event.getIntegerValueField(.eventSourceUserData) == 0x4b414c45 {
            integrationEvents.append(["type": String(type.rawValue), "key": String(code),
                                      "flags": String(modifiers.rawValue), "command": String(describing: result.command),
                                      "hold": String(describing: router.hold?.rawValue)])
            if integrationEvents.count > 50 { integrationEvents.removeFirst() }
        }
        #endif
        if let command = result.command {
            if case .begin = command { watchForRelease() }
            onCommand?(command)
        }
        return result.consume
    }
}
