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
    var onCommand: ((ShortcutCommand) -> Void)?
    var mayBegin: (() -> Bool)?
    var onTapDisabled: (() -> Void)?
    var isRunning: Bool { tap != nil }

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
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        router.reset()
    }

    func resetSession() { router.reset() }

    fileprivate func receive(_ type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            router.reset()
            onTapDisabled?()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        var modifiers: KeyModifiers = []
        if event.flags.contains(.maskControl) { modifiers.insert(.control) }
        if event.flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if event.flags.contains(.maskShift) { modifiers.insert(.shift) }
        if event.flags.contains(.maskCommand) { modifiers.insert(.command) }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let result: ShortcutResult
        switch type {
        case .keyDown:
            if router.hold == nil, mayBegin?() == false { return false }
            result = router.keyDown(code, modifiers: modifiers,
                                    isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .keyUp: result = router.keyUp(code)
        case .flagsChanged: result = router.modifiersChanged(modifiers)
        default: return false
        }
        if let command = result.command { onCommand?(command) }
        return result.consume
    }
}
